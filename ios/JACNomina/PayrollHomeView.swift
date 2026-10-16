import SwiftUI

struct PayrollHomeView: View {
    let overview: PayrollOverview
    @EnvironmentObject private var store: PayrollStore
    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject private var push = JACNotifications.shared
    @State private var selected: String
    init(overview: PayrollOverview, agendaOnly: Bool = false) {
        self.overview = overview; _selected = State(initialValue: agendaOnly ? "agenda" : overview.user.itinerariesOnly == true ? "itineraries" : "payroll")
    }
    var body: some View {
        TabView(selection: $selected) {
            if overview.user.itinerariesOnly != true { Group { if store.isAgendaOnly { ConnectionRequiredView(title: "Quincenas") } else { PeriodsView(overview: overview) } }.tabItem { Label("Quincena", systemImage: "wallet.pass") }.tag("payroll") }
            CalendarView(user: overview.user, initialMonth: store.preferredAgendaMonth).tabItem { Label("Agenda", systemImage: "calendar.badge.clock") }.tag("agenda")
            NavigationStack { if store.isAgendaOnly { ConnectionRequiredView(title: "Itinerarios") } else { NoticesView(user: overview.user) } }.tabItem { Label("Itinerarios", systemImage: "doc.text") }.tag("itineraries")
            NavigationStack { AccountView(user: overview.user) }.tabItem { Label("Mi cuenta", systemImage: "person.crop.circle") }.tag("account")
            Group { if store.isAgendaOnly { ConnectionRequiredView(title: "Gestión") } else { ManagementView(user: overview.user) } }.tabItem { Label("Gestión", systemImage: "slider.horizontal.3") }.tag("management")
        }.tint(JACTheme.action)
            .task(id: store.isAgendaOnly) { if !store.isAgendaOnly { await push.bind(store.client) } }
            .onChange(of: scenePhase) { _, value in if value == .active && !store.isAgendaOnly { Task { await push.bind(store.client) } } }
            .sheet(isPresented: Binding(get: { push.noticeID != nil }, set: { if !$0 { push.noticeID = nil } })) { NavigationStack { NoticesView(user: overview.user, initialNotice: push.noticeID).id(push.noticeID).toolbar { ToolbarItem(placement: .cancellationAction) { Button("Listo") { push.noticeID = nil } } } } }
    }
}
private struct ConnectionRequiredView: View {
    @EnvironmentObject private var store: PayrollStore
    let title: String
    @State private var loading = false
    var body: some View {
        VStack(spacing: 20) {
            ContentUnavailableView("Necesitas conexión", systemImage: "wifi.slash", description: Text("La última agenda descargada está disponible en Agenda. Conéctate para consultar las demás secciones."))
            Button("Volver a conectar") { Task { loading = true; defer { loading = false }; try? await store.refresh() } }.disabled(loading)
        }.padding().jacSurface().navigationTitle(title)
    }
}
struct PeriodsView: View {
    @EnvironmentObject private var store: PayrollStore
    let overview: PayrollOverview
    var archive = false
    var embedded = false
    @State private var search = ""
    @State private var editor: PayrollEditorSession?
    @State private var path: [String] = []
    @State private var createdPeriod: String?
    private var periods: [PeriodSummary] {
        overview.periods.sorted { $0.start > $1.start }.filter {
            (!archive || $0.isClosed) && (search.isEmpty || $0.title.localizedCaseInsensitiveContains(search) || ($0.isClosed ? "cerrada" : "abierta").localizedCaseInsensitiveContains(search))
        }
    }
    var body: some View {
        Group {
            if embedded { content }
            else { NavigationStack(path: $path) { content.navigationDestination(for: String.self) { PeriodDetailView(periodID: $0, user: overview.user) } } }
        }
    }
    private var content: some View {
            List {
                OperationStatusSection()
                Section {
                    JACFeatureBanner(eyebrow: archive ? "JAC · Archivo" : "JAC · Nómina", title: archive ? "Cada cierre, a mano." : "Tu equipo. Todo al día.", subtitle: archive ? "Consulta tus quincenas y documentos conservados." : "\(overview.periods.filter { !$0.isClosed }.count) en preparación · \(overview.periods.filter(\.isClosed).count) cerradas", symbol: archive ? "archivebox" : "wallet.pass")
                    if !archive && overview.user.can("payroll") {
                        Button {
                            if let w = store.workspace { editor = PayrollEditorSession(kind: .period, workspace: w, detail: nil, record: PayrollEditorSession.newRecord(.period, workspace: w)) }
                        } label: { Label("Nueva quincena", systemImage: "plus").frame(maxWidth: .infinity) }
                            .buttonStyle(JACPrimaryButtonStyle()).accessibilityLabel("Crear quincena").accessibilityIdentifier("period.create").disabled(!store.canWrite)
                            .padding(.top, 5)
                    }
                }.jacStandaloneRow()
                if periods.isEmpty {
                    ContentUnavailableView(search.isEmpty ? (archive ? "Archivo vacío" : "Sin quincenas") : "Sin resultados", systemImage: archive ? "archivebox" : "calendar", description: Text(archive ? "Consulta los cierres y sus documentos." : "Crea una quincena para comenzar."))
                }
                ForEach([false, true], id: \.self) { closed in
                    let group = periods.filter { $0.isClosed == closed }
                    if !group.isEmpty {
                        Section(closed ? "Quincenas cerradas" : "En preparación") {
                            ForEach(group) { period in
                                Group {
                                    if embedded { NavigationLink { PeriodDetailView(periodID: period.id, user: overview.user) } label: { periodRow(period) } }
                                    else { NavigationLink(value: period.id) { periodRow(period) } }
                                }.accessibilityIdentifier("period.\(period.id)")
                            }
                        }
                    }
                }
            }.jacSurface().navigationTitle(archive ? "Archivo" : "Quincenas").jacInlineTitle()
                .searchable(text: $search, prompt: "Buscar mes o estado")
                .refreshable { try? await store.refresh() }
                .sheet(item: $editor, onDismiss: { if let id = createdPeriod { path.append(id); createdPeriod = nil } }) { session in PayrollEditorView(session: session) { createdPeriod = $0 } }
    }
    private func periodRow(_ period: PeriodSummary) -> some View {
        HStack(alignment: .top, spacing: 14) {
            JACIcon(symbol: period.isClosed ? "checkmark.seal" : "wallet.pass", tone: period.isClosed ? .violet : .blue)
            VStack(alignment: .leading, spacing: 10) {
                Text(period.title).font(.system(.headline, design: .rounded)).fixedSize(horizontal: false, vertical: true)
                ViewThatFits(in: .horizontal) {
                    HStack { JACBadge(title: period.isClosed ? "Cerrada" : "En preparación", tone: period.isClosed ? .violet : .blue); Spacer(); Text("\(period.showCount) shows").font(.caption).foregroundStyle(.secondary) }
                    VStack(alignment: .leading, spacing: 6) { JACBadge(title: period.isClosed ? "Cerrada" : "En preparación", tone: period.isClosed ? .violet : .blue); Text("\(period.showCount) shows").font(.caption).foregroundStyle(.secondary) }
                }
                if period.ownerOnly { Text("Corrección de cierre").font(.caption).foregroundStyle(.orange) }
            }
        }.padding(.vertical, 10)
    }
}
