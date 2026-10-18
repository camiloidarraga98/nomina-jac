import Foundation
import SwiftUI
#if os(iOS)
import UIKit
#else
import AppKit
#endif
import PhotosUI
import Vision
import ImageIO

enum ExpenseKind: String, CaseIterable, Codable {
    case food = "Alimentación", transport = "Transporte", lodging = "Hospedaje", fuel = "Combustible", other = "Otros"
}

struct ExpenseDraft: Codable, Hashable {
    struct File: Codable, Hashable { var filename: String; var data: Data }
    var id = UUID().uuidString.lowercased()
    var kind = ""
    var concept = ""
    var amount = ""
    var date = BoardingClock.today()
    var note = ""
    var receiptTime: String?
    var files: [File] = []
    // An uncertain submission must retry the identical UUID and payload.
    var attempted = false
    var submissionNote: String {
        ([kind.isEmpty ? nil : "Tipo de gasto: \(kind)", receiptTime.map { "Hora de factura: \($0)" }, note.isEmpty ? nil : note].compactMap { $0 }).joined(separator: "\n")
    }
    var isEmpty: Bool { concept.isEmpty && amount.isEmpty && note.isEmpty && kind.isEmpty && receiptTime == nil && files.isEmpty }
    func validateStorage() throws {
        guard UUID(uuidString: id) != nil, files.count <= 5, files.reduce(0, { $0 + $1.data.count }) <= 10 * 1024 * 1024,
              concept.utf16.count <= 120, amount.count <= 30, note.utf16.count <= 500,
              kind.isEmpty || ExpenseKind(rawValue: kind) != nil, ReceiptParser.civilDate(date) != nil,
              receiptTime.map(ReceiptParser.validTime) ?? true else {
            throw APIError.invalid("Revisa el tamaño de los campos y comprobantes del borrador.")
        }
        for file in files { _ = try NoticeUpload.mime(file.data) }
    }
}

extension PayrollClient {
    private var expenseDraftKey: String { "local-expense-draft-v1" }
    func expenseDraft() -> ExpenseDraft? {
        guard let scope = try? offlineScope(), let record = offlineCache.load(scope, key: expenseDraftKey),
              let draft = try? JSONDecoder().decode(ExpenseDraft.self, from: record.data), (try? draft.validateStorage()) != nil else { return nil }
        return draft
    }
    func saveExpenseDraft(_ draft: ExpenseDraft, scope: AgendaCacheScope) throws {
        guard scope.id == (try offlineScope())?.id else { throw APIError.unauthorized }
        try draft.validateStorage()
        try offlineCache.save(OfflineResponse(key: expenseDraftKey, url: baseURL.appendingPathComponent("local/expense-draft").absoluteString,
                                             headers: [:], data: JSONEncoder().encode(draft), receivedAt: Date(), revision: 1), scope: scope)
    }
    func removeExpenseDraft(scope: AgendaCacheScope) throws {
        guard scope.id == (try offlineScope())?.id else { throw APIError.unauthorized }
        offlineCache.remove(scope) { $0.key == expenseDraftKey }
    }
}

struct ReceiptSuggestion: Equatable {
    var kind: ExpenseKind?
    var concept: String?
    var amount: Int?
    var date: String?
    var time: String?
    var warnings: [String] = []
}

// Conservative suggestions only: never treat subtotal, IVA, cash or change as the total.
enum ReceiptParser {
    static func normalize(_ value: String) -> String {
        value.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "es_CO")).uppercased()
    }
    private static func matches(_ pattern: String, _ text: String) -> [String] {
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return [] }
        return expression.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap { Range($0.range, in: text).map { String(text[$0]) } }
    }
    static func civilDate(_ iso: String) -> Date? {
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.timeZone = CalendarClock.calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"; formatter.isLenient = false
        guard let value = formatter.date(from: iso), formatter.string(from: value) == iso else { return nil }
        return value
    }
    private static func iso(_ day: String, _ month: String, _ year: String) -> String? {
        guard let d = Int(day), let m = Int(month), let y = Int(year), (2000...2100).contains(y) else { return nil }
        let value = String(format: "%04d-%02d-%02d", y, m, d)
        return civilDate(value) == nil ? nil : value
    }
    static func money(_ raw: String) -> Int? {
        var value = raw.replacingOccurrences(of: " ", with: "")
        // Decimal cents must be zero: the expense API stores whole Colombian pesos.
        if let decimal = value.range(of: "[.,][0-9]{2}$", options: .regularExpression) {
            guard value[decimal].dropFirst() == "00" else { return nil }
            guard let separator = value[decimal].first, !value[..<decimal.lowerBound].contains(separator) else { return nil }
            value.removeSubrange(decimal)
        }
        if value.contains(".") || value.contains(",") {
            guard value.range(of: "^[0-9]{1,3}([.,][0-9]{3})+$", options: .regularExpression) != nil,
                  !(value.contains(".") && value.contains(",")) else { return nil }
            value = value.replacingOccurrences(of: ".", with: "").replacingOccurrences(of: ",", with: "")
        }
        guard let amount = Int(value), amount > 0, amount <= 1_000_000_000 else { return nil }
        return amount
    }
    static func parse(_ lines: [String]) -> ReceiptSuggestion {
        let original = lines.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        let rows = original.map(normalize), text = rows.joined(separator: "\n")
        var result = ReceiptSuggestion()
        let foreign = text.range(of: "\\b(USD|EUR|MXN|ARS|CLP|PEN|BRL|GBP|CAD|AUD|CHF|JPY|DOLARES|EUROS|SOLES|REALES)\\b|US\\s*\\$|€", options: .regularExpression) != nil
        var totals: [(Int, Int)] = []
        let exclude = "SUB\\s*TOTAL|IVA|IMPUEST|EFECTIVO|CAMBIO|RECIBIDO|AHORRO|DESCUENTO|PROPINA|TARJETA|CUOTAS"
        for (index, row) in rows.enumerated() {
            guard row.contains("TOTAL") || row.contains("A PAGAR"), row.range(of: exclude, options: .regularExpression) == nil else { continue }
            let priority = row.contains("A PAGAR") || row.contains("VALOR TOTAL") || row.contains("TOTAL FACTURA") ? 2 : 1
            let label = row.range(of: "A PAGAR|TOTAL(?:\\s+(?:FACTURA|NETO|VENTA))?", options: .regularExpression)!
            var tail = String(row[label.upperBound...])
            if tail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, index + 1 < rows.count { tail = rows[index + 1] }
            if tail.contains("-"), tail.range(of: "-\\s*[0-9]", options: .regularExpression) != nil { continue }
            let tokens = matches("(?<![A-Z0-9])\\d+(?:[., ]\\d+)*(?![A-Z0-9])", tail)
            if tokens.count == 1, let amount = money(tokens[0]) { totals.append((priority, amount)) }
        }
        if !foreign, let priority = totals.map({ $0.0 }).max() {
            let amounts = Set(totals.filter { $0.0 == priority }.map { $0.1 })
            if amounts.count == 1 { result.amount = amounts.first }
        }
        if result.amount == nil { result.warnings.append(foreign ? "La factura indica otra moneda. Introduce el valor en COP; no se convierte automáticamente." : "No hay un total inequívoco en pesos enteros. Revisa el valor en COP.") }

        if let first = firstDateAndTime(rows) { result.date = first.date; result.time = first.time }
        if result.date == nil { result.warnings.append("No se pudo leer una fecha válida. Revisa la fecha del gasto.") }
        result.kind = suggestedKind(rows)
        if result.kind == nil { result.warnings.append("Selecciona el tipo de gasto; no se pudo clasificar con certeza.") }
        result.concept = merchantName(original)
        if result.concept == nil { result.warnings.append("Completa el concepto del gasto.") }
        return result
    }
    // Only names actually read in the heading may become the concept.
    static func merchantCandidate(_ line: String) -> String? {
        var value = line.trimmingCharacters(in: .whitespacesAndNewlines)
        let label = "^(?:NOMBRE COMERCIAL|RAZ[OÓ]N SOCIAL|EMISOR|ESTABLECIMIENTO)\\s*[:：-]\\s*"
        if let range = value.range(of: label, options: [.regularExpression, .caseInsensitive]) { value.removeSubrange(range) }
        if let tax = value.range(of: "\\s+NIT\\b.*$", options: [.regularExpression, .caseInsensitive]) { value.removeSubrange(tax) }
        let upper = normalize(value)
        let metadata = "^(?:FACTURA|DOCUMENTO|RECIBO|TIQUETE|NOTA (?:CREDITO|DEBITO)|BIENVENID|GRACIAS|NIT|CUFE|DIAN|FECHA|HORA|TOTAL|SUBTOTAL|IVA|CLIENTE|ADQUIRIENTE|CONSUMIDOR|VENDEDOR|CAJERO|CAJA|MESA|PEDIDO|ORDEN|DESCRIPCION|CANTIDAD|ARTICULO|PRODUCTO|PRECIO|VALOR|EFECTIVO|CAMBIO|RESOLUCION|AUTORIZACION|RESPONSABILIDAD|REGIMEN|IMPUESTO|TELEFONO|TEL[ .:]|CELULAR|DIRECCION|CALLE|CARRERA|CRA[ .]|CL[ .]|AVENIDA|SUCURSAL|SEDE|PUNTO DE VENTA)"
        guard upper.range(of: metadata, options: .regularExpression) == nil,
              upper.range(of: "@|WWW[.]|HTTPS?://|\\b(?:NIT|CUFE|CIIU)\\b|[0-9]{3,}|[$]", options: .regularExpression) == nil,
              value.filter({ $0.isLetter }).count >= 3, value.utf16.count <= 120,
              value.first?.isNumber != true else { return nil }
        // Spaced logo lettering is normalized only when it spells the complete name.
        let letters = upper.filter { $0.isLetter }
        if letters == "FRISBY" || letters == "FRISBYSAS" { return "Frisby" }
        return value
    }
    static func merchantName(_ lines: [String]) -> String? {
        let heading = Array(lines.prefix(12).prefix { dates(normalize($0)).isEmpty && normalize($0).range(of: "^(?:FECHA|HORA|DESCRIPCION|CANTIDAD|ARTICULO|PRODUCTO|SUBTOTAL|TOTAL)\\b", options: .regularExpression) == nil })
        for label in ["NOMBRE COMERCIAL", "RAZON SOCIAL", "EMISOR", "ESTABLECIMIENTO"] {
            if let line = heading.first(where: { normalize($0).range(of: "^" + label + "\\s*[:：-]", options: .regularExpression) != nil }), let name = merchantCandidate(line) { return name }
        }
        return heading.compactMap(merchantCandidate).first
    }
    private static let monthNames = ["ENE": 1, "ENERO": 1, "FEB": 2, "FEBRERO": 2, "MAR": 3, "MARZO": 3,
        "ABR": 4, "ABRIL": 4, "MAY": 5, "MAYO": 5, "JUN": 6, "JUNIO": 6, "JUL": 7, "JULIO": 7,
        "AGO": 8, "AGOSTO": 8, "SEP": 9, "SEPT": 9, "SEPTIEMBRE": 9, "SETIEMBRE": 9,
        "OCT": 10, "OCTUBRE": 10, "NOV": 11, "NOVIEMBRE": 11, "DIC": 12, "DICIEMBRE": 12]
    private static func dates(_ row: String) -> [(range: NSRange, date: String)] {
        let patterns = [
            "(?<![0-9])([0-9]{4})\\s*[-/.]\\s*([0-9]{1,2})\\s*[-/.]\\s*([0-9]{1,2})(?![0-9])",
            "(?<![0-9])([0-9]{1,2})\\s*[-/.]\\s*([0-9]{1,2})\\s*[-/.]\\s*([0-9]{4}|[0-9]{2})(?![0-9])",
            "(?<![0-9])([0-9]{1,2})[ /-]+(?:DE\\s+)?([A-Z]+)\\.?[ /-]+(?:DE\\s+)?([0-9]{4}|[0-9]{2})(?![0-9])"]
        var found: [(range: NSRange, date: String)] = []
        for (index, pattern) in patterns.enumerated() {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            for match in regex.matches(in: row, range: NSRange(row.startIndex..., in: row)) {
                let parts = (1...3).map { (row as NSString).substring(with: match.range(at: $0)) }
                let day = index == 0 ? parts[2] : parts[0]
                let month = index == 2 ? monthNames[parts[1]].map(String.init) ?? "" : parts[1]
                var year = index == 0 ? parts[0] : parts[2]
                if year.count == 2 { year = "20" + year }
                if let date = iso(day, month, year) { found.append((match.range, date)) }
            }
        }
        return found.sorted { $0.range.location < $1.range.location }
    }
    private static func times(_ row: String) -> [(range: NSRange, time: String)] {
        let pattern = "(?<![0-9:])([0-9]{1,2}):([0-9]{2})(?::([0-9]{2}))?\\s*([AP]\\s*\\.?\\s*M\\.?)?(?![A-Z0-9:])"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        return regex.matches(in: row, range: NSRange(row.startIndex..., in: row)).compactMap { match in
            func part(_ index: Int) -> String? { let range = match.range(at: index);return range.location == NSNotFound ? nil : (row as NSString).substring(with: range) }
            guard var hour = Int(part(1) ?? ""), let minute = Int(part(2) ?? ""), minute < 60 else { return nil }
            let seconds = part(3).flatMap(Int.init)
            if let seconds, seconds >= 60 { return nil }
            if let marker = part(4) { guard (1...12).contains(hour) else { return nil }; hour = hour % 12 + (marker.hasPrefix("P") ? 12 : 0) }
            guard (0...23).contains(hour) else { return nil }
            return (match.range, String(format: "%02d:%02d", hour, minute) + (seconds.map { String(format: ":%02d", $0) } ?? ""))
        }
    }
    static func validTime(_ time: String) -> Bool { times(time).contains { $0.time == time && $0.range.location == 0 && NSMaxRange($0.range) == time.utf16.count } }
    private static func firstDateAndTime(_ rows: [String]) -> (date: String, time: String?)? {
        for (index, row) in rows.enumerated() {
            let candidates = dates(row)
            guard let first = candidates.first else { continue }
            // Never borrow the time belonging to another date farther along the receipt.
            let end = candidates.dropFirst().first?.range.location ?? row.utf16.count
            let sameLine = times(row).filter { $0.range.location >= NSMaxRange(first.range) && NSMaxRange($0.range) <= end }.first
                ?? times(row).last(where: { NSMaxRange($0.range) <= first.range.location })
            var time = sameLine?.time
            if time == nil, candidates.count == 1, index + 1 < rows.count {
                let next = rows[index + 1]
                if dates(next).isEmpty, let adjacent = times(next).first,
                   next.contains("HORA") || next.trimmingCharacters(in: .whitespaces).hasPrefix((next as NSString).substring(with: adjacent.range).trimmingCharacters(in: .whitespaces)) { time = adjacent.time }
            }
            return (first.date, time)
        }
        return nil
    }
    private static func suggestedKind(_ rows: [String]) -> ExpenseKind? {
        let content = rows.filter { $0.range(of: "\\b(NIT|CUFE|CIIU|DIAN|DIRECCION|RESOLUCION)\\b|ACTIVIDAD ECONOMICA|RESPONSABILIDAD FISCAL", options: .regularExpression) == nil }.joined(separator: "\n")
        let rules: [(ExpenseKind, [(String, Int)])] = [
            (.fuel, [("GASOLINA|DIESEL|ACPM|COMBUSTIBLE|TERPEL|BIOMAX|ESTACION DE SERVICIO|GNV", 6), ("GALONES|GALON|SURTIDOR", 3)]),
            (.lodging, [("HOTEL|HOSTAL|HOSPEDAJE|ALOJAMIENTO", 3), ("HABITACION|PERNOCTA|NOCHES|TARIFA POR NOCHE", 5)]),
            (.transport, [("TAXI|UBER|DIDI|PEAJE|PEAJES|PARQUEADERO|AVIANCA|LATAM|WINGO|COPETRAN", 6), ("TRANSPORTE|TIQUETE|TIQUETES|PASAJE|PASAJES|TARIFA DE VIAJE|ESTACIONAMIENTO", 4)]),
            (.food, [("RESTAURANTE|CAFETERIA|PANADERIA|ALIMENTACION|COMIDAS", 3), ("ALMUERZO|DESAYUNO|CENA|POLLO|ARROZ|CARNE|CERDO|FRIJOLES|PESCADO|PASTA|HAMBURGUESA|PIZZA|ENSALADA|SANDWICH|EMPANADA|SOPA|AREPA|CAFE|TINTO|JUGO|GASEOSA", 3)])]
        let scores = rules.map { kind, terms -> (ExpenseKind, Int) in
            (kind, terms.reduce(0) { score, rule in score + Set(matches("\\b(?:" + rule.0 + ")\\b", content)).count * rule.1 })
        }.sorted { $0.1 > $1.1 }
        guard let best = scores.first, best.1 > 0, best.1 > scores[1].1 else { return nil }
        return best.0
    }

}

enum ReceiptOCR {
    static func orderedLines(_ fragments: [(text: String, bounds: CGRect)]) -> [String] {
        groupedLines(fragments).map(\.text)
    }
    private static func groupedLines(_ fragments: [(text: String, bounds: CGRect)]) -> [(text: String, bounds: CGRect)] {
        // Receipts often put the label and price in separate OCR observations.
        // Merge only fragments on the same baseline, then read left to right.
        var rows: [[(text: String, bounds: CGRect)]] = []
        for fragment in fragments.sorted(by: { $0.bounds.midY > $1.bounds.midY }) {
            if let index = rows.firstIndex(where: { row in
                guard let anchor = row.first else { return false }
                return abs(anchor.bounds.midY - fragment.bounds.midY) < min(anchor.bounds.height, fragment.bounds.height) * 0.45
            }) { rows[index].append(fragment) } else { rows.append([fragment]) }
        }
        return rows.map { row in
            (row.sorted { $0.bounds.minX < $1.bounds.minX }.map(\.text).joined(separator: " "), row.dropFirst().reduce(row[0].bounds) { $0.union($1.bounds) })
        }
    }
    struct Fragment {
        var text: String
        var bounds: CGRect
        var confidence: Float = 1
    }
    static func merchant(in fragments: [Fragment]) -> String? {
        let reliable = fragments.filter { $0.confidence >= 0.35 }
        guard let top = reliable.map({ $0.bounds.maxY }).max() else { return nil }
        // Ignore the body/footer even if an item or the total has a larger font.
        let boundary = reliable.filter { ReceiptParser.normalize($0.text).range(of: "^(?:NIT|FECHA|CUFE|DESCRIPCION|CANTIDAD|SUBTOTAL|TOTAL)\\b", options: .regularExpression) != nil }.map { $0.bounds.maxY }.max() ?? 0
        let heading = reliable.filter { $0.bounds.midY >= max(0.5, top - 0.35) && $0.bounds.midY > boundary }
        let rows = groupedLines(heading.map { ($0.text, $0.bounds) })
        return rows.compactMap { row -> (String, Double)? in
            guard let name = ReceiptParser.merchantCandidate(row.text) else { return nil }
            let explicit = ReceiptParser.normalize(row.text).range(of: "^NOMBRE COMERCIAL\\s*[:：-]", options: .regularExpression) != nil
            return (name, (explicit ? 1 : 0) + row.bounds.height + row.bounds.midY * 0.005)
        }.sorted { $0.1 > $1.1 }.first?.0
    }
    private static func observations(_ data: Data, header: Bool = false) throws -> [Fragment] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate; request.usesLanguageCorrection = true
        request.customWords = ["Frisby"]
        let supported = try request.supportedRecognitionLanguages()
        request.recognitionLanguages = ["es-ES", "en-US"].filter { supported.contains($0) }
        if header {
            guard let source = CGImageSourceCreateWithData(data as CFData, nil), let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
                  let crop = image.cropping(to: CGRect(x: 0, y: 0, width: image.width, height: Int(Double(image.height) * 0.45))) else { return [] }
            try VNImageRequestHandler(cgImage: crop).perform([request])
        } else { try VNImageRequestHandler(data: data).perform([request]) }
        try Task.checkCancellation()
        return (request.results ?? []).compactMap { observation in
            guard let text = observation.topCandidates(1).first else { return nil }
            var bounds = observation.boundingBox
            if header { bounds = CGRect(x: bounds.minX, y: 0.55 + bounds.minY * 0.45, width: bounds.width, height: bounds.height * 0.45) }
            return Fragment(text: text.string, bounds: bounds, confidence: text.confidence)
        }
    }
    static func recognize(_ data: Data) async throws -> [String] {
        try await Task.detached(priority: .userInitiated) { orderedLines(try observations(data).map { ($0.text, $0.bounds) }) }.value
    }
    static func readReceipt(_ data: Data) async throws -> ReceiptSuggestion {
        try await Task.detached(priority: .userInitiated) {
            let full = try observations(data), lines = orderedLines(full.map { ($0.text, $0.bounds) })
            guard !lines.isEmpty else { throw APIError.invalid("No se pudo leer texto. Intenta otra foto o completa el gasto manualmente.") }
            var value = ReceiptParser.parse(lines)
            // A heading-only retry helps large stylized lettering without changing date/total order.
            let header: [Fragment]
            do { header = try observations(data, header: true) }
            catch { try Task.checkCancellation(); header = [] }
            let reliableLines = orderedLines(full.filter { $0.confidence >= 0.35 }.map { ($0.text, $0.bounds) })
            value.concept = merchant(in: header) ?? merchant(in: full) ?? ReceiptParser.merchantName(reliableLines)
            value.warnings.removeAll { $0 == "Completa el concepto del gasto." }
            if value.concept == nil { value.warnings.append("Completa el concepto del gasto.") }
            return value
        }.value
    }
    @MainActor static func photograph(_ image: JACPlatformImage) throws -> Data {
        #if os(iOS)
        // Bound camera resolution and normalize orientation before text recognition.
        let scale = min(1, 4096 / max(image.size.width, image.size.height))
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let picture = UIGraphicsImageRenderer(size: size, format: format).image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
        guard let data = picture.jpegData(compressionQuality: 0.9), data.count <= 10 * 1024 * 1024 else { throw APIError.invalid("La foto supera los 10 MB. Intenta acercarte a la factura.") }
        return data
        #else
        return try MacReceiptImages.photograph(image)
        #endif
    }
    #if DEBUG
    @MainActor static func fixture(logo: Bool = false) -> JACPlatformImage {
        #if os(iOS)
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: 1100, height: 1350), format: format).image { context in
            UIColor.white.setFill(); context.fill(CGRect(x: 0, y: 0, width: 1100, height: 1350))
            let lines = ["RESTAURANTE FICTICIO JAC", "FACTURA DE PRUEBA", "FECHA: 08/10/2026 13:45:20", "Almuerzo de prueba", "SUBTOTAL 40.000", "IVA 7.600", "TOTAL A PAGAR COP 47.600", "EFECTIVO 50.000", "CAMBIO 2.400", "VENCIMIENTO: 10/10/2026 09:00"]
            for (index, line) in lines.enumerated() {
                if index == 0, logo {
                    ("Frisby" as NSString).draw(at: CGPoint(x: 320, y: 20), withAttributes: [.font: UIFont(name: "Georgia-BoldItalic", size: 100) ?? UIFont.boldSystemFont(ofSize: 100), .kern: 2, .foregroundColor: UIColor.systemRed])
                } else { (line as NSString).draw(at: CGPoint(x: 60, y: 60 + index * 125), withAttributes: [.font: UIFont.monospacedSystemFont(ofSize: 44, weight: .medium), .foregroundColor: UIColor.black]) }
            }
        }
        #else
        return MacReceiptImages.fixture(logo:logo)
        #endif
    }
    #endif
}

struct ReceiptScannerView: View {
    @EnvironmentObject private var store: PayrollStore
    @Environment(\.dismiss) private var dismiss
    let onApply: (ReceiptSuggestion, NoticeUpload) -> Void
    @State private var camera = false
    @State private var pickingFile=false
    @State private var photo: PhotosPickerItem?
    @State private var imageData: Data?
    @State private var suggestion: ReceiptSuggestion?
    @State private var error: String?
    @State private var reading = false
    @State private var active = true
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Fotografía la factura completa, bien iluminada. La lectura se hace en este \(JACDevice.name); revisa los datos antes de usarlos.").font(.subheadline).foregroundStyle(.secondary)
                    if JACCameraAvailable { Button { camera = true } label: { Label("Tomar foto de la factura", systemImage: "camera") } }
                    #if os(macOS)
                    Button("Leer una imagen o PDF de Archivos") {pickingFile=true}.accessibilityIdentifier("receipt.file")
                    #endif
                    PhotosPicker(selection: $photo, matching: .images) { Label("Leer una foto guardada", systemImage: "photo") }.accessibilityIdentifier("receipt.photos")
                    #if DEBUG
                    if store.client.baseURL.host?.hasSuffix(".invalid") == true {
                        Button("Leer factura ficticia") { Task { await read(ReceiptOCR.fixture()) } }.accessibilityIdentifier("receipt.fixture")
                        Button("Leer encabezado estilizado ficticio") { Task { await read(ReceiptOCR.fixture(logo: true)) } }.accessibilityIdentifier("receipt.logoFixture")
                    }
                    #endif
                }.disabled(reading)
                if reading { Section { ProgressView("Leyendo factura…").accessibilityIdentifier("receipt.reading") } }
                if let error { InlineError(message: error) }
                if let suggestion {
                    Section("Datos sugeridos") {
                        LabeledContent("Tipo", value: suggestion.kind?.rawValue ?? "Por revisar")
                        LabeledContent("Concepto", value: suggestion.concept ?? "Por completar").accessibilityElement(children: .combine).accessibilityIdentifier("receipt.concept")
                        LabeledContent("Valor COP", value: suggestion.amount.map { PayrollFormat.money(Double($0)) } ?? "Por completar")
                        LabeledContent("Fecha", value: suggestion.date ?? "Por revisar").accessibilityIdentifier("receipt.date")
                        if let time = suggestion.time { LabeledContent("Hora", value: time).accessibilityIdentifier("receipt.time") }
                        Text("Se toma la primera fecha válida de arriba hacia abajo. Revisa que corresponda al gasto.").font(.footnote).foregroundStyle(.secondary)
                        ForEach(suggestion.warnings, id: \.self) { Text($0).font(.footnote).foregroundStyle(.secondary) }
                        Text("Podrás corregir todos los campos en el formulario. La foto se adjuntará al gasto.").font(.footnote)
                        Button("Usar foto y datos sugeridos") {
                            guard let imageData else { return }
                            onApply(suggestion, NoticeUpload(filename: "Factura.jpg", data: imageData)); dismiss()
                        }.accessibilityIdentifier("receipt.apply")
                    }
                }
                if let imageData, let image = JACPlatformImage(data: imageData) { Section("Comprobante") { Image(jacImage: image).resizable().scaledToFit().frame(maxHeight: 260).accessibilityLabel("Foto de la factura") } }
            }.jacSurface().navigationTitle("Escanear factura").jacInlineTitle()
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } } }
                .sheet(isPresented: $camera) { TravelReceiptCamera { image in camera = false; if let image { Task { await read(image) } } } }
                #if os(macOS)
                .fileImporter(isPresented:$pickingFile,allowedContentTypes:[.pdf,.jpeg,.png]) {result in
                    do{let url=try result.get();let image=try MacReceiptImages.file(url);Task{await read(image)}}catch{if (error as? CocoaError)?.code != .userCancelled{self.error=error.localizedDescription}}
                }
                #endif
                .onChange(of: photo) { _, value in Task {
                    guard let value else { return }; reading = true
                    do { guard let data = try await value.loadTransferable(type: Data.self), data.count <= 20 * 1024 * 1024, let image = JACPlatformImage(data: data) else { throw APIError.invalid("No se pudo abrir esa foto.") }; await read(image) }
                    catch { if active { self.error = error.localizedDescription; reading = false } }
                    photo = nil
                } }
                .onAppear { active = true }
                .onDisappear { active = false }
        }.privacySensitive()
    }
    @MainActor private func read(_ image: JACPlatformImage) async {
        guard active else { return }; reading = true; error = nil; suggestion = nil
        defer { reading = false }
        do {
            let data = try ReceiptOCR.photograph(image), value = try await ReceiptOCR.readReceipt(data)
            guard active else { return }; imageData = data
            suggestion = value
        } catch { if active { self.error = error.localizedDescription } }
    }
}
