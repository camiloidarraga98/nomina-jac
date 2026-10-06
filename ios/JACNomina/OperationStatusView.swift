import SwiftUI

struct OperationStatusSection: View {
    @EnvironmentObject private var store: PayrollStore
    @State private var confirmDiscard = false
    @State private var backup: ExportedDocument?
    @State private var heldBackup: ExportedDocument?
    var body: some View {
        if let error = store.error { Section { InlineError(message: error) } }
        if let notice = store.notice { Section { Label(notice, systemImage: "checkmark.circle").foregroundStyle(.green) } }
        if let pending = store.pending {
            Section("Cambios pendientes · \(pending.label)") {
                Text("Tu formulario se conserva en memoria. Si otra persona guardó cambios, descarga tu copia y actualiza para revisarlos.").font(.footnote)
                Button("Reintentar guardado") { Task { await store.retryPending() } }.disabled(store.busy)
                Button("Guardar copia de mis cambios") {
                    do { let file = try store.backupPending(); heldBackup = file; backup = file }
                    catch { store.report(error) }
                }.disabled(store.busy)
                Button("Descartar y actualizar", role: .destructive) { confirmDiscard = true }.disabled(store.busy)
            }
            .confirmationDialog("¿Descartar los cambios pendientes y cargar la versión del servidor?", isPresented: $confirmDiscard, titleVisibility: .visible) {
                Button("Descartar y actualizar", role: .destructive) { Task { await store.discardAndRefresh() } }
            }
            .sheet(item: $backup, onDismiss: { if let heldBackup { TemporaryDocuments.remove(heldBackup); self.heldBackup = nil } }) { file in
                NavigationStack {
                    VStack(spacing: 24) {
                        Image(systemName: "doc.text").font(.largeTitle)
                        Text("Copia de tus cambios pendientes").font(.headline)
                        ShareLink("Guardar o compartir copia", item: file.url)
                    }.padding().jacSurface().navigationTitle("Copia de cambios")
                        .toolbar { ToolbarItem(placement: .topBarLeading) { Button("Listo") { backup = nil } } }
                }
            }
        }
    }
}

struct RecordTextField: View {
    let title: String
    @Binding var record: JSONValue
    let key: String
    var multiline = false
    var body: some View {
        let value = Binding(get: { record[key].text }, set: { record[key] = .string($0) })
        if multiline { TextField(title, text: value, axis: .vertical).lineLimit(2...5).accessibilityIdentifier("editor.\(key)") }
        else { TextField(title, text: value).accessibilityIdentifier("editor.\(key)") }
    }
}

struct RecordNumberField: View {
    let title: String
    @Binding var record: JSONValue
    let key: String
    var scale: Double = 1
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.subheadline).foregroundStyle(.secondary)
            TextField(title, value: Binding(get: { record[key].number * scale }, set: { record[key] = .number($0 / scale) }), format: .number.locale(Locale(identifier: "es_CO")))
                .keyboardType(.decimalPad).multilineTextAlignment(.trailing).monospacedDigit()
                .textFieldStyle(.roundedBorder).frame(minHeight: 44)
                .accessibilityLabel(title).accessibilityIdentifier("editor.\(key)")
        }
    }
}

struct RecordToggle: View {
    let title: String
    @Binding var record: JSONValue
    let key: String
    var body: some View { Toggle(title, isOn: Binding(get: { record[key].flag }, set: { record[key] = .bool($0) })) }
}

struct RecordChoice: View {
    let title: String
    @Binding var record: JSONValue
    let key: String
    let options: [(String, String)]
    var body: some View {
        Picker(title, selection: Binding(get: { record[key].text }, set: { record[key] = .string($0) })) {
            ForEach(options, id: \.0) { option in Text(option.1).tag(option.0) }
        }.accessibilityIdentifier("editor.\(key)")
    }
}

struct RecordDateField: View {
    let title: String
    @Binding var record: JSONValue
    let key: String
    let start: String
    let end: String
    var body: some View {
        DatePicker(title, selection: Binding(get: { PayrollDates.parse(record[key].text) }, set: { record[key] = .string(PayrollDates.iso($0)) }), in: PayrollDates.parse(start)...PayrollDates.parse(end), displayedComponents: .date)
    }
}

enum PayrollDates {
    static func parse(_ value: String) -> Date {
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.timeZone = TimeZone(identifier: "America/Bogota"); formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: value) ?? Date()
    }
    static func iso(_ date: Date) -> String {
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.timeZone = TimeZone(identifier: "America/Bogota"); formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}

enum PayrollChoices {
    static let categories = ["musicos", "tecnica", "conductores", "administracion", "comision"].map { ($0, PayrollFormat.category($0)) }
    static let kinds = [("servicio", "Honorario / actividad"), ("reintegro", "Pasaje / reintegro no salarial"), ("salarial", "Adición salarial"), ("descuento", "Descuento")]
}
