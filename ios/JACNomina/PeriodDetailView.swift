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
        if detail == nil { detail = store.client.cached(PeriodDetail.self, path: "api/mobile/payroll", query: [URLQueryItem(name: "period", value: id)]) }
        loading = true; error = nil
        defer { loading = false }
        repeat {
            reloadRequested = false
            do { detail = try await store.client.detail(periodID: id); error = nil }
            catch { self.error = store.reportReadFailure(error); return }
        } while reloadRequested && !store.hasPending
    }
}

struct PeriodDetailView: View {
    @EnvironmentObject private var store: PayrollStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize
    let periodID: String
    let user: PayrollUser
    @StateObject private var period = PeriodWorkspace()
    @State private var section = PeriodDetailView.initialSection
    @State private var search = ""
    @State private var category = ""
    @State private var action: String?
    @State private var editor: PayrollEditorSession?
    @State private var selectedActivity: ActivityKind?
    private static var initialSection: String {
        #if os(iOS)
        JACDevice.isPad ? "pagos" : "actividad"
        #else
        "pagos"
        #endif
    }
    var body: some View {
        List {
            if store.hasOperationStatus { OperationStatusSection() }
            if let error = period.error { Section { InlineError(message: error); Button("Volver a intentar") { Task { await load() } } } }
            if let d = period.detail {
                Section {
                    periodSummary(d)
                }.jacStandaloneRow()
                if d.record["ownerOnly"].flag || d.calculation.closedAt != nil || !d.record["revisions"].elements.isEmpty || !d.record["snapshot"]["closedBy"].text.isEmpty {
                    Section("Datos del cierre") {
                        if d.record["ownerOnly"].flag { Text("Corrección con condiciones históricas").font(.caption).foregroundStyle(.orange) }
                        if let closedAt = d.calculation.closedAt { LabeledContent("Fecha de cierre",value:PayrollFormat.timestamp(closedAt)) }
                        if !d.record["snapshot"]["closedBy"].text.isEmpty { LabeledContent("Cerrado por",value:d.record["snapshot"]["closedBy"].text) }
                        if !d.record["revisions"].elements.isEmpty { LabeledContent("Versiones de cierre conservadas",value:"\(d.record["revisions"].elements.count)") }
                    }
                }
                Section {
                    Picker("Vista de la quincena", selection: $section) {
                        Text("Pagos").tag("pagos"); Text("Actividad").tag("actividad"); Text("Documentos").tag("documentos")
                    }.pickerStyle(.segmented)
                }.listRowBackground(Color.clear).listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                if section == "pagos" { payments(d) }
                else if section == "actividad" {
                    activitySections(d)
                } else { DocumentsSection(detail: d, user: user) }
                operations(d)
            } else if period.loading { Section { ProgressView("Consultando quincena…") } }
        }.jacSurface().navigationTitle(period.detail?.period.title ?? "Quincena").jacInlineTitle()
            .task { await load() }
            .onChange(of: store.workspace?.version) { _, _ in Task { await load() } }
            .refreshable { await load() }
            .sheet(item: $editor) { PayrollEditorView(session: $0) }
            .navigationDestination(item:$selectedActivity) { kind in ActivityView(kind:kind,user:user).environmentObject(period) }
            .confirmationDialog(confirmationTitle, isPresented: Binding(get: { action != nil }, set: { if !$0 { action = nil } }), titleVisibility: .visible) {
                if let selected = action {
                    Button(selected == "close" ? "Cerrar quincena" : selected == "reopen" ? "Reabrir para corregir" : "Eliminar definitivamente", role: selected == "deletePeriod" ? .destructive : nil) {
                        let version = period.detail?.version
                        Task { if await store.action(selected, periodID: periodID, version: version), selected == "deletePeriod" { dismiss() } }; action = nil
                    }
                }
            } message: { Text(confirmationMessage) }
    }
    private func generalAmount(_ calculation: PayrollCalculation) -> String {
        guard let general = calculation.general else { return PayrollFormat.money(calculation.total) }
        guard let total = general.total else { return "Pendiente de revisión" }
        return PayrollFormat.money(total)
    }
    @ViewBuilder private func periodSummary(_ d: PeriodDetail) -> some View {
        #if os(iOS)
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(d.calculation.general == nil ? "Neto del equipo" : "Total general de nómina")
                    .font(.caption).foregroundStyle(JACTheme.muted)
                Spacer(minLength: 0)
                Text(d.period.isClosed ? "Cerrada" : "En curso")
                    .font(.caption2.weight(.semibold)).foregroundStyle(JACTheme.action)
                    .padding(.horizontal, 9).padding(.vertical, 6)
                    .background(JACTheme.action.opacity(0.08), in: RoundedRectangle(cornerRadius: 7))
            }
            Text(generalAmount(d.calculation))
                .font(.system(.largeTitle, weight: .semibold)).monospacedDigit()
                .minimumScaleFactor(0.65).lineLimit(1)
                .accessibilityIdentifier("period.net")
            Divider()
            if let general=d.calculation.general {
                AmountRow(title:"Neto del equipo",value:general.team)
                if let camilo=general.camilo {AmountRow(title:"Camilo · comisión del 5%",value:camilo)}
                else {Text("Comisión de Camilo pendiente de revisión").font(.caption).foregroundStyle(.secondary)}
            }
            ViewThatFits(in: .horizontal) {
                HStack {
                    Text("\(Set(d.calculation.rows.map(\.employeeId)).count) personas")
                    Spacer(minLength: 10)
                    Text("\(d.period.shows.count) shows · COP")
                }
                VStack(alignment: .leading, spacing: 5) {
                    Text("\(Set(d.calculation.rows.map(\.employeeId)).count) personas")
                    Text("\(d.period.shows.count) shows · COP")
                }
            }.font(.caption).foregroundStyle(JACTheme.muted)
        }.padding(18).frame(maxWidth: .infinity, alignment: .leading)
            .background(JACTheme.card, in: RoundedRectangle(cornerRadius: 20))
            .overlay(RoundedRectangle(cornerRadius: 20).stroke(JACTheme.border, lineWidth: 1).allowsHitTesting(false))
        #else
        VStack(alignment:.leading,spacing:16) {
            HStack { Label("JAC · NÓMINA",systemImage:"waveform").font(.caption2.weight(.bold)).tracking(1.5);Spacer();Image(systemName:d.period.isClosed ? "lock.shield":"wallet.pass").font(.title3) }.foregroundStyle(JACTheme.highlight)
            Text(d.calculation.general == nil ? "Neto del equipo" : "Total general de nómina").font(.subheadline).foregroundStyle(.white.opacity(0.8))
            Text(generalAmount(d.calculation)).font(.system(.largeTitle,design:.rounded,weight:.bold)).minimumScaleFactor(0.6).lineLimit(1).monospacedDigit()
            if let general=d.calculation.general {
                AmountRow(title:"Neto del equipo",value:general.team)
                if let camilo=general.camilo {AmountRow(title:"Camilo · comisión del 5%",value:camilo)}
                else {Text("Comisión de Camilo pendiente de revisión").font(.caption)}
            }
            Label(d.period.isClosed ? "Quincena cerrada" : "Quincena abierta",systemImage:d.period.isClosed ? "lock.fill":"pencil").font(.caption.weight(.semibold))
                .padding(.horizontal,12).padding(.vertical,7).background(.white.opacity(0.12),in:Capsule())
        }.padding(24).foregroundStyle(.white).frame(maxWidth:.infinity,alignment:.leading)
            .background(LinearGradient(colors:[JACTheme.navy,JACTone.blue.deep],startPoint:.topLeading,endPoint:.bottomTrailing),in:RoundedRectangle(cornerRadius:24))
        #endif
    }
    @ViewBuilder private func activitySections(_ d: PeriodDetail) -> some View {
        #if os(iOS)
        Section("Actividad del periodo") {
            ForEach([ActivityKind.shows, .movements, .routes, .expenses, .hours]) { kind in
                Button { selectedActivity = kind } label: {
                    HStack(spacing: 12) {
                        Image(systemName: kind.symbol).font(.system(size: 18)).foregroundStyle(JACTheme.muted)
                            .frame(width: 23).accessibilityHidden(true)
                        Text(activityTitle(kind)).font(.subheadline.weight(.medium)).foregroundStyle(JACTheme.ink)
                        Spacer(minLength: 8)
                        if let count = activityCount(kind, detail: d) {
                            Text(count.formatted()).font(.caption).foregroundStyle(JACTheme.muted)
                        }
                        Image(systemName: "chevron.right").font(.caption2.weight(.semibold))
                            .foregroundStyle(JACTheme.muted).accessibilityHidden(true)
                    }.frame(minHeight: 44).contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityIdentifier("activity.\(kind.rawValue)")
            }
        }
        if !JACDevice.isPad {
            Section {
                Button { section = "pagos" } label: {
                    HStack(spacing: 8) {
                        Text("Ver liquidación")
                        Image(systemName: "arrow.right").accessibilityHidden(true)
                    }.frame(maxWidth: .infinity, minHeight: 22)
                }.buttonStyle(JACPrimaryButtonStyle()).accessibilityIdentifier("period.liquidation")
            }.jacStandaloneRow()
        }
        #else
        Section {
            LazyVGrid(columns:Array(repeating:GridItem(.flexible(),spacing:12),count:typeSize.isAccessibilitySize ? 1:2),spacing:12) {
                ForEach(ActivityKind.allCases) { kind in
                    Button { selectedActivity = kind } label:{ JACAccessCard(title:kind.title,subtitle:"Consultar y gestionar",symbol:kind.symbol,tone:kind == .shows ? .blue:.teal) }
                        .accessibilityIdentifier("activity.\(kind.rawValue)")
                }
            }.buttonStyle(.plain)
        }.jacStandaloneRow()
        #endif
    }
    private func activityTitle(_ kind: ActivityKind) -> String {
        switch kind {
        case .shows: "Shows"
        case .movements: "Novedades"
        case .routes: "Recorridos"
        case .expenses: "Gastos"
        case .hours: "Horas y salarios"
        }
    }
    private func activityCount(_ kind: ActivityKind, detail: PeriodDetail) -> Int? {
        switch kind {
        case .shows: detail.period.shows.count
        case .movements: detail.period.movements.count
        case .routes: detail.period.routes.count
        case .expenses: detail.record["showExpenses"].elements.count
        case .hours: nil
        }
    }
    private var confirmationTitle: String { action == "close" ? "¿Cerrar esta quincena?" : action == "reopen" ? "¿Reabrir este cierre?" : "¿Eliminar esta quincena y todos sus registros de correo?" }
    private var confirmationMessage: String {
        action == "close" ? "Se guardará la liquidación definitiva. Podrás descargar sus documentos y enviar los desprendibles manualmente desde Correos."
        : action == "reopen" ? "El cierre anterior se conserva. La corrección utiliza las condiciones históricas y requiere permiso para modificar cierres."
        : "No se puede deshacer. No retira correos ya enviados ni archivos descargados. Las demás quincenas se conservan."
    }
    @ViewBuilder private func operations(_ d: PeriodDetail) -> some View {
        Section("Acciones de la quincena") {
            if !d.period.isClosed && user.can("export") {
                Button("Preliquidación") { section = "documentos" }.accessibilityIdentifier("period.preliquidation")
            }
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
        if let commission = d.calculation.camiloCommission { CamiloCommissionSection(value: commission) }
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
            if store.hasOperationStatus { OperationStatusSection() }
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
        }.jacSurface().navigationTitle("Condiciones del corte").jacInlineTitle().sheet(item: $editor) { PayrollEditorView(session: $0) }
    }
}
struct AmountRow: View {
    let title: String
    let value: Double
    var body: some View { LabeledContent { Text(PayrollFormat.money(value)).monospacedDigit().multilineTextAlignment(.trailing) } label: { Text(title) } }
}

struct CamiloCommissionSection: View {
    let value: PayrollCamiloCommission
    var body: some View {
        Section("Comisión de Camilo · 5%") {
            AmountRow(title: "Ventas de todos los shows", value: value.sales)
            AmountRow(title: "Costos descontados", value: value.costs)
            AmountRow(title: "Costos promocionales excluidos", value: value.promotionalCosts)
            AmountRow(title: "Base de comisión", value: value.base)
            if let amount = value.amount { AmountRow(title: "Comisión para revisión", value: amount).accessibilityIdentifier("commission.amount") }
            else { Text("Pendiente de revisión de recorridos").foregroundStyle(.orange) }
            if value.balance < 0 { Text("Los costos superan las ventas: comisión en cero, sin saldo al próximo corte.").font(.footnote) }
            Text("Calculada por el servidor e incluida en el total general de nómina, en una línea independiente. Excluye salarios, honorarios fijos, novedades, reintegros y recorridos extra.").font(.footnote).foregroundStyle(.secondary)
            ForEach(value.issues, id: \.self) { Text($0).font(.footnote).foregroundStyle(.orange) }
            if value.unlinkedKilometers > 0 { AmountRow(title: "Kilómetros sin show, no descontados", value: value.unlinkedKilometers) }
            DisclosureGroup("Costos por show") {
                ForEach(value.shows) { show in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(show.name + (show.promotional ? " · Promocional" : "")).font(.headline)
                        Text(PayrollFormat.date(show.date)).font(.caption).foregroundStyle(.secondary)
                        AmountRow(title: "Ventas", value: show.sale)
                        AmountRow(title: "Músicos", value: show.musicians); AmountRow(title: "Técnica", value: show.technical)
                        AmountRow(title: "Conductores / km", value: show.drivers); AmountRow(title: "Gastos", value: show.expenses)
                        AmountRow(title: "Costo total", value: show.cost); AmountRow(title: "Resultado del show", value: show.sale - show.cost)
                        AmountRow(title: "Costo descontado", value: show.deductible)
                    }.padding(.vertical, 6)
                }
            }
        }
    }
}
