import Foundation
import SwiftUI
import UIKit
import PhotosUI
import Vision

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
        for (index, row) in rows.prefix(8).enumerated() where row.range(of: "FACTURA|ELECTRONIC|DOCUMENTO|NIT|CUFE|DIAN|FECHA|TOTAL|RECIBO|TELEFONO|DIRECCION|RESOLUCION|^[0-9$]", options: .regularExpression) == nil {
            if row.filter({ $0.isLetter }).count >= 3, row.count <= 120 { result.concept = original[index]; break }
        }
        if result.concept == nil { result.warnings.append("Completa el concepto del gasto.") }
        return result
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
        // Receipts often put the label and price in separate OCR observations.
        // Merge only fragments on the same baseline, then read left to right.
        var rows: [[(text: String, bounds: CGRect)]] = []
        for fragment in fragments.sorted(by: { $0.bounds.midY > $1.bounds.midY }) {
            if let index = rows.firstIndex(where: { row in
                guard let anchor = row.first else { return false }
                return abs(anchor.bounds.midY - fragment.bounds.midY) < min(anchor.bounds.height, fragment.bounds.height) * 0.45
            }) { rows[index].append(fragment) } else { rows.append([fragment]) }
        }
        return rows.map { $0.sorted { $0.bounds.minX < $1.bounds.minX }.map(\.text).joined(separator: " ") }
    }
    static func recognize(_ data: Data) async throws -> [String] {
        try await Task.detached(priority: .userInitiated) {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate; request.usesLanguageCorrection = true
            let supported = try request.supportedRecognitionLanguages()
            request.recognitionLanguages = ["es-ES", "en-US"].filter { supported.contains($0) }
            try VNImageRequestHandler(data: data).perform([request])
            try Task.checkCancellation()
            let fragments = (request.results ?? []).compactMap { observation -> (text: String, bounds: CGRect)? in
                guard let text = observation.topCandidates(1).first?.string else { return nil }
                return (text, observation.boundingBox)
            }
            return orderedLines(fragments)
        }.value
    }
    @MainActor static func photograph(_ image: UIImage) throws -> Data {
        // Bound camera resolution and normalize orientation before text recognition.
        let scale = min(1, 4096 / max(image.size.width, image.size.height))
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let picture = UIGraphicsImageRenderer(size: size, format: format).image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
        guard let data = picture.jpegData(compressionQuality: 0.9), data.count <= 10 * 1024 * 1024 else { throw APIError.invalid("La foto supera los 10 MB. Intenta acercarte a la factura.") }
        return data
    }
    #if DEBUG
    @MainActor static func fixture() -> UIImage {
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: 1100, height: 1350), format: format).image { context in
            UIColor.white.setFill(); context.fill(CGRect(x: 0, y: 0, width: 1100, height: 1350))
            let lines = ["RESTAURANTE FICTICIO JAC", "FACTURA DE PRUEBA", "FECHA: 08/10/2026 13:45:20", "Almuerzo de prueba", "SUBTOTAL 40.000", "IVA 7.600", "TOTAL A PAGAR COP 47.600", "EFECTIVO 50.000", "CAMBIO 2.400", "VENCIMIENTO: 10/10/2026 09:00"]
            for (index, line) in lines.enumerated() { (line as NSString).draw(at: CGPoint(x: 60, y: 60 + index * 125), withAttributes: [.font: UIFont.monospacedSystemFont(ofSize: 44, weight: .medium), .foregroundColor: UIColor.black]) }
        }
    }
    #endif
}

struct ReceiptScannerView: View {
    @EnvironmentObject private var store: PayrollStore
    @Environment(\.dismiss) private var dismiss
    let onApply: (ReceiptSuggestion, NoticeUpload) -> Void
    @State private var camera = false
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
                    Text("Fotografía la factura completa, bien iluminada. La lectura se hace en este iPhone; revisa los datos antes de usarlos.").font(.subheadline).foregroundStyle(.secondary)
                    if UIImagePickerController.isSourceTypeAvailable(.camera) { Button { camera = true } label: { Label("Tomar foto de la factura", systemImage: "camera") } }
                    PhotosPicker(selection: $photo, matching: .images) { Label("Leer una foto guardada", systemImage: "photo") }.accessibilityIdentifier("receipt.photos")
                    #if DEBUG
                    if store.client.baseURL.host?.hasSuffix(".invalid") == true { Button("Leer factura ficticia") { Task { await read(ReceiptOCR.fixture()) } }.accessibilityIdentifier("receipt.fixture") }
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
                if let imageData, let image = UIImage(data: imageData) { Section("Comprobante") { Image(uiImage: image).resizable().scaledToFit().frame(maxHeight: 260).accessibilityLabel("Foto de la factura") } }
            }.jacSurface().navigationTitle("Escanear factura").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } } }
                .sheet(isPresented: $camera) { TravelReceiptCamera { image in camera = false; if let image { Task { await read(image) } } } }
                .onChange(of: photo) { _, value in Task {
                    guard let value else { return }; reading = true
                    do { guard let data = try await value.loadTransferable(type: Data.self), data.count <= 20 * 1024 * 1024, let image = UIImage(data: data) else { throw APIError.invalid("No se pudo abrir esa foto.") }; await read(image) }
                    catch { if active { self.error = error.localizedDescription; reading = false } }
                    photo = nil
                } }
                .onAppear { active = true }
                .onDisappear { active = false }
        }.privacySensitive()
    }
    @MainActor private func read(_ image: UIImage) async {
        guard active else { return }; reading = true; error = nil; suggestion = nil
        defer { reading = false }
        do {
            let data = try ReceiptOCR.photograph(image), lines = try await ReceiptOCR.recognize(data)
            guard active else { return }; imageData = data
            guard !lines.isEmpty else { throw APIError.invalid("No se pudo leer texto. Intenta otra foto o completa el gasto manualmente.") }
            suggestion = ReceiptParser.parse(lines)
        } catch { if active { self.error = error.localizedDescription } }
    }
}
