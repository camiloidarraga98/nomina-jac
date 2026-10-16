import SwiftUI

struct PayrollHomeView: View {
    let overview: PayrollOverview
    @EnvironmentObject private var store: PayrollStore
    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject private var push = JACNotifications.shared
    @State private var selected: String
    init(overview: PayrollOverview, agendaOnly: Bool = false) {
        self.overview = overview; _selected = State(initialValue: agendaOnly && overview.user.hasSection(.calendar) ? "agenda" : overview.user.firstDestination)
    }
    private var user: PayrollUser { overview.user }
    private var showsMediaTab: Bool { user.canReadMedia }
    var body: some View {
        Group {
            #if os(iOS)
            if JACDevice.isPad { tabletWorkspace }
            else { phoneTabs }
            #else
            phoneTabs
            #endif
        }.tint(JACTheme.action)
            .task(id: store.isAgendaOnly) { if !store.isAgendaOnly && user.hasNotices { await push.bind(store.client) } }
            .onChange(of: scenePhase) { _, value in if value == .active && !store.isAgendaOnly && user.hasNotices { Task { await push.bind(store.client) } } }
            .onChange(of: user) { _, value in selected = value.firstDestination; if !value.hasNotices { push.stop() } }
            .sheet(isPresented: Binding(get: { user.hasNotices && push.noticeID != nil }, set: { if !$0 { push.noticeID = nil } })) { NavigationStack { NoticesView(user: user, kind: user.hasSection(.itineraries) ? "itinerary" : user.hasSection(.alerts) ? "alert" : "boarding_pass", initialNotice: push.noticeID).id(push.noticeID).toolbar { ToolbarItem(placement: .cancellationAction) { Button("Listo") { push.noticeID = nil } } } } }
    }
    private var phoneTabs: some View {
        TabView(selection: $selected) {
            if user.hasSection(.payroll) { Group { if store.isAgendaOnly { ConnectionRequiredView(title: "Quincenas") } else { PeriodsView(overview: overview) } }.tabItem { Label("Quincena", systemImage: "wallet.pass") }.tag("payroll") }
            if user.hasSection(.calendar) { CalendarView(user: user, initialMonth: store.preferredAgendaMonth).tabItem { Label("Agenda", systemImage: "calendar.badge.clock") }.tag("agenda") }
            if user.hasSection(.itineraries) || user.hasSection(.boarding) {
                NavigationStack { NoticesView(user: user, kind: user.hasSection(.itineraries) ? "itinerary" : "boarding_pass") }.tabItem { Label(user.hasSection(.itineraries) ? "Itinerarios" : "Pases", systemImage: "doc.text") }.tag("itineraries")
            } else if user.hasSection(.alerts) {
                NavigationStack { NoticesView(user: user, kind: "alert") }.tabItem { Label("Alertas", systemImage: "bell.badge") }.tag("alerts")
            }
            if showsMediaTab { NavigationStack { MediaGalleryView(user: user) }.tabItem { Label("Fotografía", systemImage: "photo.on.rectangle.angled") }.tag("media") }
            ManagementView(user:user).tabItem { Label("Gestión",systemImage:"slider.horizontal.3") }.tag("management")
        }
    }
    #if os(iOS)
    @State private var sidebarVisibility: NavigationSplitViewVisibility = .all
    @State private var compactColumn: NavigationSplitViewColumn = .detail
    private var tabletDestinations: [(id: String, title: String, symbol: String)] {
        var items: [(String, String, String)] = []
        if user.hasSection(.crm) { items.append(("crm", "CRM", "briefcase")) }
        if user.hasSection(.payroll) { items.append(("payroll", "Quincena", "wallet.pass")) }
        if user.hasSection(.calendar) { items.append(("agenda", "Agenda", "calendar.badge.clock")) }
        if user.hasSection(.itineraries) || user.hasSection(.boarding) { items.append(("itineraries", user.hasSection(.itineraries) ? "Itinerarios" : "Pases", "doc.text")) }
        else if user.hasSection(.alerts) { items.append(("alerts", "Alertas", "bell.badge")) }
        if user.canReadMedia { items.append(("media", "Fotografía", "photo.on.rectangle.angled")) }
        items.append(("management", "Gestión", "slider.horizontal.3"))
        return items
    }
    private var tabletWorkspace: some View {
        NavigationSplitView(columnVisibility: $sidebarVisibility, preferredCompactColumn: $compactColumn) {
            List {
                Section {
                    BrandView().frame(maxWidth: 166).padding(.vertical, 12).frame(maxWidth: .infinity)
                        .listRowBackground(Color.clear).accessibilityHidden(true)
                }
                Section("Tu espacio") {
                    ForEach(tabletDestinations, id: \.id) { item in
                        Button {
                            selected = item.id; compactColumn = .detail
                        } label: {
                            Label(item.title, systemImage: item.symbol).font(.body.weight(selected == item.id ? .semibold : .regular))
                                .frame(maxWidth: .infinity, minHeight: 36, alignment: .leading).contentShape(Rectangle())
                        }.buttonStyle(.plain).foregroundStyle(selected == item.id ? JACTheme.action : JACTheme.ink)
                            .listRowBackground(selected == item.id ? JACTheme.action.opacity(0.12) : Color.clear)
                            .accessibilityAddTraits(selected == item.id ? [.isSelected] : [])
                            .accessibilityIdentifier("ipad.section." + item.id)
                    }
                }
            }.listStyle(.sidebar).navigationTitle("JAC Music")
                .navigationSplitViewColumnWidth(min: 220, ideal: 248, max: 290)
                .safeAreaInset(edge: .bottom) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(user.displayName).font(.subheadline.weight(.semibold)).lineLimit(2)
                        Label(store.isOffline ? "Copia sin conexión" : "Tu equipo, conectado", systemImage: store.isOffline ? "wifi.slash" : "person.2")
                            .font(.caption).foregroundStyle(.secondary)
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(18).background(.bar).privacySensitive()
                }
        } detail: {
            tabletContent.id(selected)
        }
        // The split view owns the navigation hosts above each section's stack.
        // Recreate those hosts when changing sections so a pushed CRM/management
        // detail cannot remain on screen over a different section's root.
        .id(selected).navigationSplitViewStyle(.balanced).tint(JACTheme.action)
    }
    @ViewBuilder private var tabletContent: some View {
        switch selected {
        case "crm" where user.hasSection(.crm): NavigationStack { CRMHomeView(client: store.client) }
        case "payroll" where user.hasSection(.payroll):
            if store.isAgendaOnly { NavigationStack { ConnectionRequiredView(title: "Quincenas") } }
            else { PeriodsView(overview: overview) }
        case "agenda" where user.hasSection(.calendar): CalendarView(user: user, initialMonth: store.preferredAgendaMonth)
        case "itineraries" where user.hasSection(.itineraries) || user.hasSection(.boarding):
            NavigationStack { NoticesView(user: user, kind: user.hasSection(.itineraries) ? "itinerary" : "boarding_pass") }
        case "alerts" where user.hasSection(.alerts): NavigationStack { NoticesView(user: user, kind: "alert") }
        case "media" where user.canReadMedia: NavigationStack { MediaGalleryView(user: user) }
        default: ManagementView(user: user)
        }
    }
    #endif
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
