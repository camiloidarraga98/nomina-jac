import SwiftUI

struct PayrollEditorView: View {
    @EnvironmentObject private var store: PayrollStore
    @Environment(\.dismiss) private var dismiss
    let session: PayrollEditorSession
    var onSaved: (String?) -> Void = { _ in }
    @State private var record: JSONValue
    @State private var month: Date
    @State private var half = 1
    @State private var preview: PeriodDetail?
    @State private var previewError: String?
    @State private var previewing = false

    init(session: PayrollEditorSession, onSaved: @escaping (String?) -> Void = { _ in }) {
        self.session = session; self.onSaved = onSaved
        _record = State(initialValue: session.record)
        _month = State(initialValue: session.kind == .period ? PayrollDates.parse(session.record["start"].text) : Date())
    }
    var body: some View {
        NavigationStack {
            Form {
                OperationStatusSection()
                fields
                if store.workspace?.version != session.version && !store.hasPending {
                    Section { Text("El servidor tiene una versión nueva. Vuelve a abrir el formulario para trabajar con ella.").foregroundStyle(.orange) }
                }
                if previewing { Section { ProgressView("Calculando en el servidor…") } }
                if let previewError { Section("Revisión del formulario") { InlineError(message: previewError) } }
                if let preview { PreviewCalculationSection(detail: preview) }
                Section {
                    Text(session.kind == .periodEmployee || session.kind == .periodSettings ? "Los ajustes se aplican únicamente a esta quincena en corrección." : "Los cambios se guardan para todo el equipo autorizado.").font(.footnote).foregroundStyle(.secondary)
                }
            }.navigationTitle(session.kind.title).navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) { Button("Cancelar") { dismiss() }.disabled(store.busy) }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            endEditing()
                            Task {
                                if await store.submit(session.command(record), label: session.kind.title, editorID: session.id) {
                                    onSaved(session.kind == .period ? record["id"].text : nil); dismiss()
                                }
                            }
                        } label: { if store.busy { ProgressView() } else { Text("Guardar").bold() } }
                            .disabled(store.busy || !hasRequiredFields || store.workspace?.version != session.version || (store.pending != nil && store.pending?.editorID != session.id))
                            .accessibilityIdentifier("editor.save")
                    }
                    ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("Listo", action: endEditing) }
                }
                .interactiveDismissDisabled(store.busy)
                .scrollDismissesKeyboard(.interactively)
                .environment(\.locale, Locale(identifier: "es_CO"))
                .environment(\.timeZone, TimeZone(identifier: "America/Bogota")!)
                .task(id: record) { await updatePreview() }
        }
    }
    @ViewBuilder private var fields: some View {
        switch session.kind {
        case .period: periodFields
        case .employee, .periodEmployee: EmployeeFields(record: $record)
        case .concept: conceptFields
        case .settings, .periodSettings: SettingsFields(record: $record)
        case .show: ShowFields(record: $record, session: session)
        case .movement: MovementFields(record: $record, session: session)
        case .hours: HoursFields(record: $record, session: session)
        case .route: RouteFields(record: $record, session: session)
        }
    }
    private var periodFields: some View {
        Section {
            DatePicker("Mes de la quincena", selection: $month, displayedComponents: .date).onChange(of: month) { _, _ in updatePeriodDates() }
            Picker("Quincena", selection: $half) { Text("Primera · 1 al 15").tag(1); Text("Segunda · 16 al fin de mes").tag(2) }.onChange(of: half) { _, _ in updatePeriodDates() }
            LabeledContent("Inicio", value: PayrollFormat.date(record["start"].text))
            LabeledContent("Fin", value: PayrollFormat.date(record["end"].text))
            Text("Se cargarán los salarios y condiciones vigentes. Shows, kilómetros, horas y novedades comienzan vacíos.").font(.footnote).foregroundStyle(.secondary)
        }
    }
    private var conceptFields: some View {
        Section {
            RecordTextField(title: "Nombre del concepto", record: $record, key: "name")
            RecordChoice(title: "Tratamiento", record: $record, key: "kind", options: PayrollChoices.kinds)
            RecordNumberField(title: "Valor por unidad", record: $record, key: "amount")
            Text("El nuevo valor se usará en futuras novedades. Las registradas conservan su importe.").font(.footnote).foregroundStyle(.secondary)
        }
    }
    private var hasRequiredFields: Bool {
        switch session.kind {
        case .employee, .periodEmployee: return record["name"].text.trimmingCharacters(in: .whitespacesAndNewlines).count >= 2
        case .concept, .show: return !record["name"].text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .movement: return !record["employeeId"].text.isEmpty && !record["concept"].text.isEmpty
        case .route: return !record["name"].text.isEmpty && (!record["drivers"].elements.isEmpty || !record["employeeId"].text.isEmpty)
        case .settings, .periodSettings: return !record["company"].text.isEmpty
        default: return true
        }
    }
    private func updatePeriodDates() { record = PayrollEditorSession.newPeriod(month: month, half: half, id: record["id"].text) }
    private func endEditing() { UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil) }
    private func updatePreview() async {
        guard session.periodID != nil || session.kind == .period else { return }
        guard hasRequiredFields else { preview = nil; previewError = nil; return }
        do {
            try await Task.sleep(for: .milliseconds(450)); try Task.checkCancellation()
            previewing = true
            let result = try await store.client.preview(session.command(record))
            try Task.checkCancellation(); preview = result.detail; previewError = nil; previewing = false
        } catch is CancellationError { }
        catch let error as URLError where error.code == .cancelled { }
        catch { if !Task.isCancelled { preview = nil; previewError = error.localizedDescription; previewing = false; store.report(error) } }
    }
}
struct EmployeeFields: View {
    @Binding var record: JSONValue
    var body: some View {
        Section("Datos personales") {
            RecordTextField(title: "Nombre completo", record: $record, key: "name")
            RecordTextField(title: "Correo para desprendibles", record: $record, key: "email").keyboardType(.emailAddress).textInputAutocapitalization(.never).autocorrectionDisabled()
            RecordTextField(title: "Documento", record: $record, key: "document")
            RecordTextField(title: "Cargo / instrumento", record: $record, key: "role")
            RecordChoice(title: "Grupo principal", record: $record, key: "category", options: PayrollChoices.categories)
            RecordToggle(title: "Persona activa", record: $record, key: "active")
        }
        Section("Servicios y shows") {
            RecordNumberField(title: "Tarifa habitual por show", record: $record, key: "showRate")
            RecordNumberField(title: "Tarifa por kilómetro", record: $record, key: "kmRate")
            RecordNumberField(title: "Honorario fijo por quincena", record: $record, key: "fixedService")
            RecordNumberField(title: "Retención de servicios (%)", record: $record, key: "withholding", scale: 100)
            RecordNumberField(title: "ReteICA (%)", record: $record, key: "ica", scale: 100)
        }
        Section("Nómina de dependientes") {
            RecordNumberField(title: "Salario mensual", record: $record, key: "salary")
            RecordNumberField(title: "Auxilio mensual de transporte", record: $record, key: "transport")
            RecordChoice(title: "Frecuencia de pago", record: $record, key: "cycle", options: [("quincenal", "Cada quincena"), ("mensual", "Una vez al mes")])
            if record["cycle"].text == "mensual" {
                Picker("Corte del pago mensual", selection: Binding(get: { Int(record["monthlyHalf"].number) }, set: { record["monthlyHalf"] = .number(Double($0)) })) {
                    Text("Primera quincena").tag(1); Text("Segunda quincena").tag(2)
                }
            }
            RecordNumberField(title: "Movilización no salarial por pago", record: $record, key: "nonSalary")
            RecordNumberField(title: "Base de aportes (%)", record: $record, key: "contributionBase", scale: 100)
            RecordNumberField(title: "Retención de nómina por pago", record: $record, key: "incomeTax")
            RecordNumberField(title: "Fondo de solidaridad por pago", record: $record, key: "solidarity")
            RecordToggle(title: "Descontar EPS (4%)", record: $record, key: "health")
            RecordToggle(title: "Descontar AFP (4%)", record: $record, key: "pension")
            Text("Un salario mensual de cero indica que esta persona no recibe nómina de dependientes.").font(.footnote).foregroundStyle(.secondary)
        }
    }
}
struct SettingsFields: View {
    @Binding var record: JSONValue
    var body: some View {
        Section("Empresa y cálculo") {
            RecordTextField(title: "Empresa", record: $record, key: "company"); RecordTextField(title: "NIT", record: $record, key: "nit")
            RecordNumberField(title: "Divisor mensual de horas", record: $record, key: "hourDivisor")
        }
        Section("Factores de horas") {
            ForEach(Array(PayrollFormat.hourNames.enumerated()), id: \.offset) { index, name in ArrayNumberField(title: name, record: $record, key: "hourFactors", index: index) }
            Text("Recargos: factor adicional (0,35 = 35 %). Extras: factor completo (1,25 = 125 %). Los cierres conservan sus parámetros.").font(.footnote).foregroundStyle(.secondary)
        }
    }
}
struct ArrayNumberField: View {
    let title: String
    @Binding var record: JSONValue
    let key: String
    let index: Int
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.subheadline).foregroundStyle(.secondary)
            TextField(title, value: Binding(get: {
                let values = record[key].elements; return index < values.count ? values[index].number : 0
            }, set: { value in
                var values = record[key].elements; while values.count <= index { values.append(.number(0)) }; values[index] = .number(value); record[key] = .array(values)
            }), format: .number.locale(Locale(identifier: "es_CO"))).keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                .textFieldStyle(.roundedBorder).frame(minHeight: 44).accessibilityLabel(title).accessibilityIdentifier("editor.\(key).\(index)")
        }
    }
}
struct PreviewCalculationSection: View {
    let detail: PeriodDetail
    var body: some View {
        Section("Liquidación calculada por el servidor") {
            AmountRow(title: "Neto de la quincena", value: detail.calculation.total)
            AmountRow(title: "Ingresos", value: detail.calculation.gross); AmountRow(title: "Descuentos", value: detail.calculation.deductions)
            ForEach(Array(detail.calculation.rows.enumerated()), id: \.offset) { _, row in AmountRow(title: row.name + " · " + PayrollFormat.category(row.category), value: row.net) }
        }
        if !detail.closeIssues.isEmpty { Section("Pendiente para el cierre") { ForEach(detail.closeIssues, id: \.self) { Text($0).font(.footnote) } } }
    }
}
