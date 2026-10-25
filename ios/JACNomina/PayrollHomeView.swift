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
            if JACDevice.isPad {
                tabletWorkspace.safeAreaInset(edge: .bottom, spacing: 0) { MusicMiniPlayer(player: store.music) }
            } else { phoneDrawerWorkspace }
            #else
            phoneTabs.safeAreaInset(edge: .bottom, spacing: 0) { MusicMiniPlayer(player: store.music) }
            #endif
        }.tint(JACTheme.action)
            .sheet(item: $store.incomingAudio) { incoming in MusicImportView(incoming: incoming, initialSection: .warmup).environmentObject(store) }
            .task(id: store.isAgendaOnly) { if !store.isAgendaOnly && user.canReceiveNotifications { await push.bind(store.client) } }
            .onChange(of: scenePhase) { _, value in if value == .active && !store.isAgendaOnly && user.canReceiveNotifications { Task { await push.bind(store.client) } } }
            .onChange(of: user) { _, value in
                selected = value.firstDestination
                #if os(iOS)
                phoneVisited = []; phoneMenuOpen = false
                #endif
                if !value.canReceiveNotifications { push.stop() }
                else if !store.isAgendaOnly { Task { await push.bind(store.client) } }
            }
            .sheet(isPresented: Binding(get: { user.hasNotices && push.noticeID != nil }, set: { if !$0 { push.noticeID = nil } })) { NavigationStack { NoticesView(user: user, kind: user.hasSection(.itineraries) ? "itinerary" : user.hasSection(.alerts) ? "alert" : "boarding_pass", initialNotice: push.noticeID).id(push.noticeID).toolbar { ToolbarItem(placement: .cancellationAction) { Button("Listo") { push.noticeID = nil } } } } }
            .modifier(MediaNotificationPresenter(opened: {
                selected = "media"
                #if os(iOS)
                phoneMenuOpen = false; compactColumn = .detail
                #endif
            }))
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
            if user.canReadMusic { NavigationStack { MusicLibraryView(user: user) }.tabItem { Label("Música", systemImage: "music.note.list") }.tag("music") }
            ManagementView(user:user).tabItem { Label("Gestión",systemImage:"slider.horizontal.3") }.tag("management")
        }
    }
    #if os(iOS)
    @State private var phoneMenuOpen = false
    @State private var phoneVisited: Set<String> = []
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AccessibilityFocusState private var menuCloseFocused: Bool
    @AccessibilityFocusState private var menuOpenFocused: Bool
    private var phoneDestinations: [(id: String, title: String, symbol: String)] {
        var items: [(String, String, String)] = []
        if user.hasSection(.crm) { items.append(("crm", "CRM", "briefcase")) }
        if user.hasSection(.payroll) { items.append(("payroll", "Quincena", "wallet.pass")) }
        if user.hasSection(.calendar) { items.append(("agenda", "Agenda", "calendar.badge.clock")) }
        if user.hasSection(.itineraries) || user.hasSection(.boarding) { items.append(("itineraries", user.hasSection(.itineraries) ? "Itinerarios" : "Pases", "doc.text")) }
        if user.hasSection(.alerts) { items.append(("alerts", "Alertas", "bell.badge")) }
        if user.hasSection(.itineraries) && user.hasSection(.boarding) { items.append(("boarding", "Pases", "airplane")) }
        if user.canReadMedia { items.append(("media", "Fotografía", "photo.on.rectangle.angled")) }
        if user.canReadMusic { items.append(("music", "Música", "music.note.list")) }
        items.append(("management", "Gestión", "slider.horizontal.3"))
        return items
    }
    private func setPhoneMenu(_ visible: Bool) {
        if visible { JACPlatform.endEditing() }
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.26)) { phoneMenuOpen = visible }
        menuCloseFocused = visible
        menuOpenFocused = !visible
    }
    private var phoneDrawerWorkspace: some View {
        GeometryReader { geometry in
            let width = min(330, geometry.size.width * 0.86)
            // One rigid translation moves the persistent panel and the entire
            // screen together. Its full width keeps navigation/scroll layout stable.
            HStack(spacing: 0) {
                phoneSidebar
                    .frame(width: width, height: geometry.size.height)
                    .allowsHitTesting(phoneMenuOpen).accessibilityHidden(!phoneMenuOpen)
                phoneWorkspace
                    .safeAreaInset(edge: .bottom, spacing: 0) { MusicMiniPlayer(player: store.music) }
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .background(JACTheme.canvas)
                    .allowsHitTesting(!phoneMenuOpen).accessibilityHidden(phoneMenuOpen)
                    .overlay {
                        Color.clear.contentShape(Rectangle())
                            .onTapGesture { setPhoneMenu(false) }
                            .simultaneousGesture(DragGesture(minimumDistance: 30).onEnded { closePhoneMenuOnSwipe($0) })
                            .allowsHitTesting(phoneMenuOpen).accessibilityHidden(true)
                    }
            }
            .frame(width: geometry.size.width + width, height: geometry.size.height, alignment: .leading)
            .offset(x: phoneMenuOpen ? 0 : -width)
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .leading)
            .clipped()
        }.background(JACTheme.canvas.ignoresSafeArea())
    }
    private func closePhoneMenuOnSwipe(_ value: DragGesture.Value) {
        if value.translation.width < -60 && abs(value.translation.width) > abs(value.translation.height) { setPhoneMenu(false) }
    }
    private var phoneWorkspace: some View {
        // Keep only visited sections mounted, preserving their routes, calendar
        // selection and gallery scroll without loading every module at launch.
        VStack(spacing: 0) {
            phoneMenuBar.zIndex(1)
            ZStack {
                ForEach(phoneDestinations.filter { $0.id == selected || phoneVisited.contains($0.id) }, id: \.id) { item in
                    phoneContent(item.id)
                        .opacity(selected == item.id ? 1 : 0)
                        .allowsHitTesting(selected == item.id && !phoneMenuOpen)
                        .accessibilityHidden(selected != item.id || phoneMenuOpen)
                }
            }.frame(maxWidth: .infinity, maxHeight: .infinity).clipped().animation(nil, value: selected)
        }
        .onChange(of: selected) { old, new in phoneVisited.insert(old); phoneVisited.insert(new) }
    }
    private var phoneMenuBar: some View {
        HStack(spacing: 8) {
            Button { setPhoneMenu(true) } label: { Image(systemName: "line.3.horizontal").font(.title3.weight(.semibold)).frame(width: 44, height: 44) }
                .buttonStyle(.plain).frame(width: 44, height: 44).contentShape(Rectangle())
                .accessibilityLabel("Abrir menú").accessibilityIdentifier("phone.menu.open").accessibilityFocused($menuOpenFocused)
            Text(phoneDestinations.first(where: { $0.id == selected })?.title ?? "JAC Music").font(.subheadline.weight(.semibold)).lineLimit(1)
            Spacer(minLength: 8)
            Text("JAC Music").font(.caption.weight(.medium)).foregroundStyle(.secondary).padding(.trailing, 16)
        }.foregroundStyle(JACTheme.ink).background(JACTheme.card)
            .overlay(alignment: .bottom) { Divider() }
            .accessibilityHidden(phoneMenuOpen)
    }
    @ViewBuilder private func phoneContent(_ destination: String) -> some View {
        switch destination {
        case "crm" where user.hasSection(.crm): NavigationStack { CRMHomeView(client: store.client) }
        case "payroll" where user.hasSection(.payroll):
            if store.isAgendaOnly { NavigationStack { ConnectionRequiredView(title: "Quincenas") } }
            else { PeriodsView(overview: overview) }
        case "agenda" where user.hasSection(.calendar): CalendarView(user: user, initialMonth: store.preferredAgendaMonth)
        case "itineraries" where user.hasSection(.itineraries) || user.hasSection(.boarding):
            NavigationStack { NoticesView(user: user, kind: user.hasSection(.itineraries) ? "itinerary" : "boarding_pass") }
        case "alerts" where user.hasSection(.alerts): NavigationStack { NoticesView(user: user, kind: "alert") }
        case "boarding" where user.hasSection(.boarding): NavigationStack { NoticesView(user: user, kind: "boarding_pass") }
        case "media" where user.canReadMedia: NavigationStack { MediaGalleryView(user: user) }
        case "music" where user.canReadMusic: NavigationStack { MusicLibraryView(user: user) }
        default: ManagementView(user: user)
        }
    }
    private var phoneSidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                BrandView().frame(maxWidth: 150).accessibilityHidden(true)
                Spacer()
                Button { setPhoneMenu(false) } label: { Image(systemName: "xmark").frame(width: 44, height: 44) }
                    .accessibilityLabel("Cerrar menú").accessibilityIdentifier("phone.menu.close").accessibilityFocused($menuCloseFocused)
            }.padding(.horizontal, 18).padding(.top, 12).padding(.bottom, 18)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    Text("TU ESPACIO").font(.caption.weight(.semibold)).foregroundStyle(.secondary).padding(.horizontal, 14).padding(.vertical, 10)
                    ForEach(phoneDestinations, id: \.id) { item in
                        Button {
                            phoneVisited.insert(selected); phoneVisited.insert(item.id); selected = item.id; setPhoneMenu(false)
                        } label: {
                            HStack(spacing: 14) {
                                Image(systemName: item.symbol).font(.body).frame(width: 25)
                                Text(item.title).font(.body.weight(selected == item.id ? .semibold : .regular))
                                Spacer(minLength: 4)
                                if selected == item.id { Image(systemName: "checkmark").font(.caption.weight(.semibold)) }
                            }.padding(.horizontal, 14).frame(minHeight: 50).contentShape(Rectangle())
                        }.buttonStyle(.plain)
                            .foregroundStyle(selected == item.id ? JACTheme.action : JACTheme.ink)
                            .background(selected == item.id ? JACTheme.action.opacity(0.12) : Color.clear, in: RoundedRectangle(cornerRadius: 14))
                            .accessibilityAddTraits(selected == item.id ? [.isSelected] : [])
                            .accessibilityIdentifier("phone.section." + item.id)
                    }
                }.padding(12)
            }.accessibilityIdentifier("phone.sidebar.scroll")
            Divider()
            VStack(alignment: .leading, spacing: 4) {
                Text(user.displayName).font(.subheadline.weight(.semibold)).lineLimit(2)
                Text("Tu equipo, en un solo lugar.").font(.caption).foregroundStyle(.secondary)
            }.frame(maxWidth: .infinity, alignment: .leading).padding(22).privacySensitive()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(JACTheme.card)
        .overlay(alignment: .trailing) { Rectangle().fill(JACTheme.ink.opacity(0.1)).frame(width: 1) }
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(phoneMenuOpen ? [.isModal] : [])
        .simultaneousGesture(DragGesture(minimumDistance: 30).onEnded { closePhoneMenuOnSwipe($0) })
    }
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
        if user.canReadMusic { items.append(("music", "Música", "music.note.list")) }
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
                        Label("JAC Music", systemImage:"person.2")
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
        case "music" where user.canReadMusic: NavigationStack { MusicLibraryView(user: user) }
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
                if store.hasOperationStatus { OperationStatusSection() }
                if archive {
                    Section {
                        JACFeatureBanner(eyebrow: "JAC · Archivo", title: "Cada cierre, a mano.", subtitle: "Consulta tus quincenas y documentos conservados.", symbol: "archivebox")
                    }.jacStandaloneRow()
                } else if overview.user.can("payroll") {
                    Section {
                        Button {
                            if let w = store.workspace { editor = PayrollEditorSession(kind: .period, workspace: w, detail: nil, record: PayrollEditorSession.newRecord(.period, workspace: w)) }
                        } label: { Label("Nueva quincena", systemImage: "plus").frame(maxWidth: .infinity) }
                            .buttonStyle(JACPrimaryButtonStyle()).accessibilityLabel("Crear quincena").accessibilityIdentifier("period.create").disabled(!store.canWrite)
                    }.jacStandaloneRow()
                }
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
                .jacSearchable(text: $search, prompt: "Buscar mes o estado")
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
