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
    var files: [File] = []
    // An uncertain submission must retry the identical UUID and payload.
    var attempted = false
    var submissionNote: String { (kind.isEmpty ? "" : "Tipo de gasto: \(kind)" + (note.isEmpty ? "" : "\n")) + note }
    var isEmpty: Bool { concept.isEmpty && amount.isEmpty && note.isEmpty && kind.isEmpty && files.isEmpty }
    func validateStorage() throws {
        guard UUID(uuidString: id) != nil, files.count <= 5, files.reduce(0, { $0 + $1.data.count }) <= 10 * 1024 * 1024,
              concept.utf16.count <= 120, amount.count <= 30, note.utf16.count <= 500,
              kind.isEmpty || ExpenseKind(rawValue: kind) != nil, ReceiptParser.civilDate(date) != nil else {
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

        var dates: [(Int, String)] = []
        let months = ["ENERO", "FEBRERO", "MARZO", "ABRIL", "MAYO", "JUNIO", "JULIO", "AGOSTO", "SEPTIEMBRE", "OCTUBRE", "NOVIEMBRE", "DICIEMBRE"]
        for row in rows where row.range(of: "VENC|LIMITE|RESOLUCION|AUTORIZACION|HABILITACION", options: .regularExpression) == nil {
            let priority = row.contains("FECHA") || row.contains("EMISION") ? 2 : 1
            for value in matches("\\b[0-9]{4}-[0-9]{2}-[0-9]{2}\\b", row) { if civilDate(value) != nil { dates.append((priority, value)) } }
            for value in matches("\\b[0-9]{1,2}[/.-][0-9]{1,2}[/.-][0-9]{4}\\b", row) {
                let parts = value.components(separatedBy: CharacterSet(charactersIn: "/.-"))
                if let date = iso(parts[0], parts[1], parts[2]) { dates.append((priority, date)) }
            }
            for value in matches("\\b[0-9]{1,2}\\s+(?:DE\\s+)?(?:" + months.joined(separator: "|") + ")\\s+(?:DE\\s+)?[0-9]{4}\\b", row) {
                let parts = value.components(separatedBy: " ").filter { !$0.isEmpty && $0 != "DE" }
                if let month = months.firstIndex(of: parts[1]), let date = iso(parts[0], String(month + 1), parts[2]) { dates.append((priority, date)) }
            }
        }
        if let priority = dates.map({ $0.0 }).max() { let values = Set(dates.filter { $0.0 == priority }.map { $0.1 }); if values.count == 1 { result.date = values.first } }
        if result.date == nil { result.warnings.append("No se pudo identificar una fecha única. Revisa la fecha del gasto.") }

        let rules: [(ExpenseKind, String)] = [(.fuel, "\\b(GASOLINA|DIESEL|COMBUSTIBLE|ESTACION DE SERVICIO|TERPEL|BIOMAX)\\b"),
            (.lodging, "\\b(HOTEL|HOSTAL|HOSPEDAJE|ALOJAMIENTO)\\b"), (.transport, "\\b(TAXI|UBER|DIDI|TRANSPORTE|PEAJE|PARQUEADERO|TIQUETE|PASAJES)\\b"),
            (.food, "\\b(RESTAURANTE|CAFETERIA|ALMUERZO|DESAYUNO|CENA|ALIMENTACION|COMIDAS)\\b")]
        let kinds = rules.filter { text.range(of: $0.1, options: .regularExpression) != nil }.map { $0.0 }
        if kinds.count == 1 { result.kind = kinds[0] }
        if result.kind == nil { result.warnings.append("Selecciona el tipo de gasto; no se pudo clasificar con certeza.") }
        for (index, row) in rows.prefix(8).enumerated() where row.range(of: "FACTURA|ELECTRONIC|DOCUMENTO|NIT|CUFE|DIAN|FECHA|TOTAL|RECIBO|TELEFONO|DIRECCION|RESOLUCION|^[0-9$]", options: .regularExpression) == nil {
            if row.filter({ $0.isLetter }).count >= 3, row.count <= 120 { result.concept = original[index]; break }
        }
        if result.concept == nil { result.warnings.append("Completa el concepto del gasto.") }
        return result
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
            let lines = ["RESTAURANTE FICTICIO JAC", "FACTURA DE PRUEBA", "FECHA: 08/10/2026", "Almuerzo de prueba", "SUBTOTAL 40.000", "IVA 7.600", "TOTAL A PAGAR COP 47.600", "EFECTIVO 50.000", "CAMBIO 2.400"]
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
                        LabeledContent("Fecha", value: suggestion.date ?? "Por revisar")
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
