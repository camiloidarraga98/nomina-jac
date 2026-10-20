import SwiftUI

enum ActivityKind: String, CaseIterable, Identifiable {
    case shows, movements, expenses, routes, hours
    var id: String { rawValue }
    var title: String { ["shows": "Shows y honorarios", "movements": "Novedades y descuentos", "expenses": "Gastos por show", "routes": "Recorridos y kilómetros", "hours": "Horas y salarios"][rawValue]! }
    var symbol: String { ["shows": "music.mic", "movements": "plusminus.circle", "expenses": "receipt", "routes": "car", "hours": "clock"][rawValue]! }
    var editorKind: PayrollEditorKind { switch self { case .shows: return .show; case .movements: return .movement; case .expenses: return .showExpense; case .routes: return .route; case .hours: return .hours } }
}
struct ActivityView: View {
    @EnvironmentObject private var store: PayrollStore
    @EnvironmentObject private var period: PeriodWorkspace
    let kind: ActivityKind
    let user: PayrollUser
    @State private var editor: PayrollEditorSession?
    @State private var removal: String?
    var body: some View {
        List {
            if store.hasOperationStatus { OperationStatusSection() }
            if let d = period.detail {
                if let error = period.error { Section { InlineError(message: error) } }
                if d.period.isClosed { Section { Label("Consulta de un cierre", systemImage: "lock.fill") } }
                switch kind { case .shows: shows(d); case .movements: movements(d); case .expenses: expenses(d); case .routes: routes(d); case .hours: hours(d) }
            }
        }.jacSurface().navigationTitle(kind.title).jacInlineTitle()
            .toolbar {
                if let d = period.detail, canEdit(d), kind != .hours {
                    ToolbarItem(placement: .jacTrailing) {
                        Button { edit(nil, detail: d) } label: { Image(systemName: "plus") }
                            .accessibilityLabel(kind == .routes ? "Agregar kilometraje extra" : "Agregar registro")
                            .accessibilityIdentifier("activity.add").disabled(!store.canWrite || (kind == .expenses && d.period.shows.isEmpty))
                    }
                }
            }.refreshable { await reload() }
            .onChange(of: store.workspace?.version) { _, _ in Task { await reload() } }
            .sheet(item: $editor) { PayrollEditorView(session: $0) }
            .confirmationDialog(kind == .shows ? "¿Eliminar el show, su recorrido y sus gastos vinculados?" : "¿Eliminar este registro?", isPresented: Binding(get: { removal != nil }, set: { if !$0 { removal = nil } }), titleVisibility: .visible) {
                if let id = removal, let d = period.detail {
                    Button("Eliminar", role: .destructive) { Task { _ = await store.remove(kind: kind.editorKind.rawValue, id: id, detail: d) }; removal = nil }
                }
            }
    }
    private func reload() async { if let id = period.detail?.period.id { await period.load(id, store: store) } }
    private func canEdit(_ d: PeriodDetail) -> Bool { !d.period.isClosed && user.can(d.record["ownerOnly"].flag ? "modifyClosed" : "payroll") }
    private func edit(_ record: JSONValue?, detail: PeriodDetail, employeeID: String? = nil) {
        guard let w = store.workspace else { return }
        editor = PayrollEditorSession(kind: kind.editorKind, workspace: w, detail: detail, record: record ?? PayrollEditorSession.newRecord(kind.editorKind, workspace: w, detail: detail, employeeID: employeeID))
    }
    @ViewBuilder private func recordActions(_ record: JSONValue, detail: PeriodDetail, allowRemove: Bool = true) -> some View {
        if canEdit(detail) {
            HStack {
                Button("Editar") { edit(record, detail: detail) }.buttonStyle(.borderless).disabled(!store.canWrite)
                Spacer()
                if allowRemove { Button("Eliminar", role: .destructive) { removal = record["id"].text }.buttonStyle(.borderless).disabled(!store.canWrite) }
            }
        }
    }
    @ViewBuilder private func shows(_ d: PeriodDetail) -> some View {
        if d.period.shows.isEmpty { Section { Text("Sin shows registrados.").foregroundStyle(.secondary) } }
        ForEach(d.period.shows) { show in
            Section(show.name) {
                LabeledContent("Fecha", value: PayrollFormat.date(show.date)); AmountRow(title: "Venta", value: show.sale)
                if show.promotional == true { Label("Promocional", systemImage: "tag") }
                ForEach(show.participants, id: \.employeeId) { AmountRow(title: d.employeeName($0.employeeId), value: $0.amount) }
                if let record = d.record["shows"].elements.first(where: { $0["id"].text == show.id }) { recordActions(record, detail: d) }
            }
        }
    }
    @ViewBuilder private func expenses(_ d: PeriodDetail) -> some View {
        let records = d.record["showExpenses"].elements
        if records.isEmpty { Section { Text(d.period.shows.isEmpty ? "Agrega un show antes de registrar sus gastos." : "Sin gastos de show registrados.").foregroundStyle(.secondary) } }
        ForEach(Array(records.enumerated()), id: \.offset) { _, record in
            Section(record["concept"].text) {
                LabeledContent("Show", value: d.period.shows.first { $0.id == record["showId"].text }?.name ?? "").accessibilityElement(children: .combine).accessibilityIdentifier("expense.linkedShow")
                LabeledContent("Tipo", value: ["tiquetes":"Tiquetes","hoteles":"Hoteles","alimentacion":"Alimentación","otros":"Otros gastos"][record["category"].text] ?? record["category"].text)
                LabeledContent("Fecha", value: PayrollFormat.date(record["date"].text)); AmountRow(title: "Valor", value: record["amount"].number)
                if !record["note"].text.isEmpty { Text(record["note"].text).font(.footnote) }
                recordActions(record, detail: d)
            }
        }
        if let commission = d.calculation.camiloCommission { CamiloCommissionSection(value: commission) }
    }
    @ViewBuilder private func movements(_ d: PeriodDetail) -> some View {
        if d.period.movements.isEmpty { Section { Text("Sin novedades registradas.").foregroundStyle(.secondary) } }
        ForEach(d.period.movements) { movement in
            Section(movement.concept) {
                LabeledContent("Persona", value: d.employeeName(movement.employeeId))
                LabeledContent("Tratamiento", value: PayrollChoices.kinds.first { $0.0 == movement.kind }?.1 ?? movement.kind)
                LabeledContent("Cantidad", value: PayrollFormat.number(movement.quantity)); AmountRow(title: "Valor por unidad", value: movement.amount)
                if !movement.note.isEmpty { Text(movement.note).font(.footnote) }
                if let record = d.record["movements"].elements.first(where: { $0["id"].text == movement.id }) { recordActions(record, detail: d) }
            }
        }
    }
    @ViewBuilder private func routes(_ d: PeriodDetail) -> some View {
        Section { Text("Registra el recorrido total de ida y regreso una sola vez por show. Los pagos usan las tarifas registradas de cada conductor.").font(.footnote).foregroundStyle(.secondary) }
        let templates = d.editing?["showRoutes"].elements ?? []
        ForEach(Array(templates.enumerated()), id: \.offset) { _, record in
            Section(record["name"].text) {
                LabeledContent("Fecha", value: PayrollFormat.date(record["date"].text)); LabeledContent("Distancia", value: "\(PayrollFormat.number(record["km"].number)) km")
                driverRates(record, detail: d)
                if record["legacyCount"].number > 0 { Text("Los registros anteriores se conservan hasta guardar el recorrido compartido.").font(.footnote).foregroundStyle(.secondary) }
                recordActions(record, detail: d, allowRemove: d.period.routes.contains { $0.id == record["id"].text })
            }
        }
        let unshared = d.record["routes"].elements.filter { $0["showId"].text.isEmpty }
        ForEach(Array(unshared.enumerated()), id: \.offset) { _, record in
            Section((record["kind"].text == "extra" ? "Extra · " : "Registro anterior · ") + record["name"].text) {
                LabeledContent("Fecha", value: PayrollFormat.date(record["date"].text)); LabeledContent("Distancia", value: "\(PayrollFormat.number(record["km"].number)) km")
                if !record["employeeId"].text.isEmpty { AmountRow(title: d.employeeName(record["employeeId"].text) + " / km", value: record["rate"].number) }
                else { driverRates(record, detail: d) }
                recordActions(record, detail: d)
            }
        }
        if templates.isEmpty && unshared.isEmpty { Section { Text("Sin recorridos registrados.").foregroundStyle(.secondary) } }
    }
    @ViewBuilder private func driverRates(_ record: JSONValue, detail: PeriodDetail) -> some View {
        ForEach(Array(record["drivers"].elements.enumerated()), id: \.offset) { _, driver in AmountRow(title: detail.employeeName(driver["employeeId"].text) + " / km", value: driver["rate"].number) }
    }
    @ViewBuilder private func hours(_ d: PeriodDetail) -> some View {
        let people = d.employees.filter { $0.active && $0.deleted != true && $0.salary > 0 && !d.record["excludedEmployees"].elements.map(\.text).contains($0.id) }
        if people.isEmpty { Section { Text("No hay dependientes con salario en este corte.").foregroundStyle(.secondary) } }
        ForEach(people) { employee in
            let record = d.record["hours"].elements.first { $0["employeeId"].text == employee.id }
            Section(employee.name) {
                AmountRow(title: "Salario mensual", value: employee.salary)
                LabeledContent("Frecuencia", value: employee.cycle == "mensual" ? "Mensual" : "Quincenal")
                if let record {
                    LabeledContent("Días trabajados", value: PayrollFormat.number(record["days"].number)); AmountRow(title: "Vacaciones", value: record["vacations"].number)
                    ForEach(Array(record["counts"].elements.enumerated()), id: \.offset) { index, value in LabeledContent(index < PayrollFormat.hourNames.count ? PayrollFormat.hourNames[index] : "Horas", value: PayrollFormat.number(value.number)) }
                    if !record["note"].text.isEmpty { Text(record["note"].text).font(.footnote) }
                } else { Text("Sin novedades; se aplica la base habitual del servidor.").font(.footnote).foregroundStyle(.secondary) }
                if canEdit(d) { Button(record == nil ? "Registrar horas y novedades" : "Editar horas y novedades") { edit(record, detail: d, employeeID: employee.id) }.disabled(!store.canWrite) }
            }
        }
    }
}
