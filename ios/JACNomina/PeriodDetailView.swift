import SwiftUI
import Combine

@MainActor
final class PeriodWorkspace: ObservableObject {
    @Published var detail: PeriodDetail?
    @Published var error: String?
    @Published var loading = false
    private var reloadRequested = false
    func load(_ id: String, store: PayrollStore) async {
        guard !store.hasPending else { return }
        if loading { reloadRequested = true; return }
        loading = true; error = nil
        defer { loading = false }
        repeat {
            reloadRequested = false
            do { detail = try await store.client.detail(periodID: id); error = nil }
            catch is CancellationError { return }
            catch { self.error = error.localizedDescription; store.report(error); return }
        } while reloadRequested && !store.hasPending
    }
}

struct PeriodDetailView: View {
    @EnvironmentObject private var store: PayrollStore
    @Environment(\.dismiss) private var dismiss
    let periodID: String
    let user: PayrollUser
    @StateObject private var period = PeriodWorkspace()
    @State private var section = "pagos"
    @State private var search = ""
    @State private var category = ""
    @State private var action: String?
    @State private var editor: PayrollEditorSession?
    var body: some View {
        List {
            OperationStatusSection()
            if let error = period.error { Section { InlineError(message: error); Button("Volver a intentar") { Task { await load() } } } }
            if let d = period.detail {
                Section {
                    Text(d.period.isClosed ? "Neto del cierre" : "Neto en preparación").font(.subheadline).foregroundStyle(.secondary)
                    Text(PayrollFormat.money(d.calculation.total)).font(.largeTitle.weight(.bold)).minimumScaleFactor(0.6).lineLimit(1)
                    Label(d.period.isClosed ? "Quincena cerrada" : "Quincena abierta", systemImage: d.period.isClosed ? "lock.fill" : "pencil")
                    if d.record["ownerOnly"].flag { Text("Corrección con condiciones históricas").font(.caption).foregroundStyle(.orange) }
                    if let closedAt = d.calculation.closedAt { LabeledContent("Fecha de cierre", value: PayrollFormat.timestamp(closedAt)) }
                    if !d.record["snapshot"]["closedBy"].text.isEmpty { LabeledContent("Cerrado por", value: d.record["snapshot"]["closedBy"].text) }
                    if !d.record["revisions"].elements.isEmpty { LabeledContent("Versiones de cierre conservadas", value: "\(d.record["revisions"].elements.count)") }
                }
                Section {
                    Picker("Vista de la quincena", selection: $section) {
                        Text("Pagos").tag("pagos"); Text("Actividad").tag("actividad"); Text("Documentos").tag("documentos")
                    }.pickerStyle(.segmented)
                }.listRowBackground(Color.clear).listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                if section == "pagos" { payments(d) }
                else if section == "actividad" {
                    Section {
                        ForEach(ActivityKind.allCases) { kind in
                            NavigationLink { ActivityView(kind: kind, user: user).environmentObject(period) } label: { Label(kind.title, systemImage: kind.symbol) }
                                .accessibilityIdentifier("activity.\(kind.rawValue)")
                        }
                    }
                } else { DocumentsSection(detail: d, user: user) }
                operations(d)
            } else if period.loading { Section { ProgressView("Consultando quincena…") } }
        }.navigationTitle(period.detail?.period.title ?? "Quincena").navigationBarTitleDisplayMode(.inline)
            .task { await load() }
            .onChange(of: store.workspace?.version) { _, _ in Task { await load() } }
            .refreshable { await load() }
            .sheet(item: $editor) { PayrollEditorView(session: $0) }
            .confirmationDialog(confirmationTitle, isPresented: Binding(get: { action != nil }, set: { if !$0 { action = nil } }), titleVisibility: .visible) {
                if let selected = action {
                    Button(selected == "close" ? "Cerrar quincena" : selected == "reopen" ? "Reabrir para corregir" : "Eliminar definitivamente", role: selected == "deletePeriod" ? .destructive : nil) {
                        let version = period.detail?.version
                        Task { if await store.action(selected, periodID: periodID, version: version), selected == "deletePeriod" { dismiss() } }; action = nil
                    }
                }
            } message: { Text(confirmationMessage) }
    }
    private var confirmationTitle: String { action == "close" ? "¿Cerrar esta quincena?" : action == "reopen" ? "¿Reabrir este cierre?" : "¿Eliminar esta quincena y todos sus registros de correo?" }
    private var confirmationMessage: String {
        action == "close" ? "Se conservará una instantánea. Si Gmail está conectado, se enviarán automáticamente los desprendibles a las personas con correo registrado."
        : action == "reopen" ? "El cierre anterior se conserva. La corrección utiliza las condiciones históricas y requiere permiso para modificar cierres."
        : "No se puede deshacer. No retira correos ya enviados ni archivos descargados. Las demás quincenas se conservan."
    }
    @ViewBuilder private func operations(_ d: PeriodDetail) -> some View {
        Section("Acciones de la quincena") {
            if d.period.isClosed {
                if user.can("modifyClosed") { Button("Reabrir para corregir") { action = "reopen" }.disabled(!store.canWrite).accessibilityIdentifier("period.reopen") }
            } else if user.can(d.record["ownerOnly"].flag ? "modifyClosed" : "close") {
                Button("Cerrar quincena") { action = "close" }.disabled(!store.canWrite || !d.closeIssues.isEmpty).accessibilityIdentifier("period.close")
            }
            if !d.period.isClosed && d.record["ownerOnly"].flag && user.can("modifyClosed") {
                Button("Corregir parámetros de este corte") {
                    if let w = store.workspace, let settings = d.editing?["settings"] { editor = PayrollEditorSession(kind: .periodSettings, workspace: w, detail: d, record: settings) }
                }.disabled(!store.canWrite)
                NavigationLink("Corregir condiciones de una persona") { HistoricalConditionsView(user: user).environmentObject(period) }
            }
            NavigationLink("Correos y envíos de este corte") { MailView(user: user, initialPeriodID: periodID) }
            if user.isOwner { Button("Eliminar quincena", role: .destructive) { action = "deletePeriod" }.disabled(!store.canWrite).accessibilityIdentifier("period.delete") }
        }
    }
    @ViewBuilder private func payments(_ d: PeriodDetail) -> some View {
        Section("Resumen") {
            AmountRow(title: "Ingresos", value: d.calculation.gross); AmountRow(title: "Descuentos", value: d.calculation.deductions)
            AmountRow(title: "Reintegros", value: d.calculation.reimbursements); AmountRow(title: "Ventas de shows", value: d.calculation.sale)
        }
        Section("Pagos del equipo") {
            TextField("Buscar persona o cargo", text: $search).accessibilityIdentifier("payments.search")
            Picker("Grupo", selection: $category) { Text("Todos").tag(""); ForEach(PayrollChoices.categories, id: \.0) { Text($0.1).tag($0.0) } }
            let rows = d.calculation.rows.filter { (category.isEmpty || $0.category == category) && (search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) || $0.role.localizedCaseInsensitiveContains(search)) }
            if rows.isEmpty { Text("Sin pagos para esta selección.").foregroundStyle(.secondary) }
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                NavigationLink { PaymentDetailView(rows: d.calculation.rows.filter { $0.employeeId == row.employeeId }, period: d.period, user: user, conditions: employeeRecord(d, id: row.employeeId)) } label: {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(row.name).font(.headline)
                        HStack { Text(PayrollFormat.category(row.category)); Spacer(); Text(PayrollFormat.money(row.net)).fontWeight(.semibold) }.font(.subheadline)
                    }.padding(.vertical, 4)
                }
            }
        }
        if !d.closeIssues.isEmpty { Section("Pendiente para el cierre") { ForEach(d.closeIssues, id: \.self) { Text($0).font(.subheadline) } } }
    }
    private func employeeRecord(_ d: PeriodDetail, id: String) -> JSONValue? {
        let historical = d.record["snapshot"]["employees"].elements + d.record["calculationBase"]["employees"].elements
        return historical.first { $0["id"].text == id } ?? store.workspace?.record("employees", id: id)
    }
    private func load() async { await period.load(periodID, store: store) }
}
struct HistoricalConditionsView: View {
    @EnvironmentObject private var store: PayrollStore
    @EnvironmentObject private var period: PeriodWorkspace
    let user: PayrollUser
    @State private var editor: PayrollEditorSession?
    var body: some View {
        List {
            OperationStatusSection()
            Section { Text("Estas condiciones pertenecen a la quincena reabierta. No modifican el personal vigente ni otros cierres.").font(.footnote) }
            if let d = period.detail {
                ForEach(d.employees.sorted { $0.name < $1.name }) { employee in
                    Button(employee.name) {
                        if let w = store.workspace, let record = d.record["calculationBase"]["employees"].elements.first(where: { $0["id"].text == employee.id }) {
                            editor = PayrollEditorSession(kind: .periodEmployee, workspace: w, detail: d, record: record)
                        }
                    }.disabled(!store.canWrite || d.period.isClosed || !user.can("modifyClosed"))
                }
            }
        }.navigationTitle("Condiciones del corte").sheet(item: $editor) { PayrollEditorView(session: $0) }
    }
}
struct AmountRow: View {
    let title: String
    let value: Double
    var body: some View { LabeledContent { Text(PayrollFormat.money(value)).monospacedDigit().multilineTextAlignment(.trailing) } label: { Text(title) } }
}
