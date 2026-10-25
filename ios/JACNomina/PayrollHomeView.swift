import SwiftUI
#if os(iOS)
import UIKit

struct PhoneSidebarMenu {
    let open: () -> Void
    let focus: AccessibilityFocusState<Bool>.Binding
}
private struct PhoneSidebarMenuKey: EnvironmentKey {
    static let defaultValue: PhoneSidebarMenu? = nil
}
extension EnvironmentValues {
    var phoneSidebarMenu: PhoneSidebarMenu? {
        get { self[PhoneSidebarMenuKey.self] }
        set { self[PhoneSidebarMenuKey.self] = newValue }
    }
}
struct PhoneSidebarToolbar: ViewModifier {
    var title: String? = nil
    @Environment(\.phoneSidebarMenu) private var menu
    @State private var insideModal = true
    @ViewBuilder
    func body(content: Content) -> some View {
        if let menu, !JACDevice.isPad {
            content.background(PhoneSidebarPresentationReader { value in
                if insideModal != value { insideModal = value }
            }).toolbar {
                if !insideModal {
                    if title != nil {
                        ToolbarItem(placement: .principal) {
                            Color.clear.frame(width: 1, height: 1).accessibilityHidden(true)
                        }
                    }
                    ToolbarItem(placement: .topBarLeading) {
                        HStack(spacing: 6) {
                            Button(action: menu.open) {
                                Image(systemName: "line.3.horizontal")
                                    .font(.system(size: 18, weight: .medium))
                                    .frame(width: 44, height: 44)
                            }.buttonStyle(.plain).foregroundStyle(JACTheme.ink)
                            .accessibilityLabel("Abrir menú").accessibilityHint("También puedes deslizar desde el borde izquierdo.")
                            .accessibilityIdentifier("phone.menu.open").accessibilityFocused(menu.focus)
                            if let title {
                                Text(title).font(.system(.title2, weight: .bold))
                                    .foregroundStyle(JACTheme.ink).lineLimit(1).minimumScaleFactor(0.8)
                                    .accessibilityAddTraits(.isHeader)
                            }
                        }
                    }
                }
            }
        } else { content }
    }
}

// SwiftUI's isPresented is also true for pushed destinations. Resolve only a
// UIKit modal ancestor so details retain the menu and sheets keep their own exit.
private struct PhoneSidebarPresentationReader: UIViewRepresentable {
    let changed: (Bool) -> Void
    func makeUIView(context: Context) -> PhoneSidebarPresentationAnchor { PhoneSidebarPresentationAnchor() }
    func updateUIView(_ view: PhoneSidebarPresentationAnchor, context: Context) {
        view.changed = changed; view.reportPresentation()
    }
}
private final class PhoneSidebarPresentationAnchor: UIView {
    var changed: ((Bool) -> Void)?
    override func didMoveToWindow() { super.didMoveToWindow(); isUserInteractionEnabled = false; reportPresentation() }
    func reportPresentation() {
        DispatchQueue.main.async { [weak self] in
            guard let self, window != nil else { return }
            var responder: UIResponder? = self
            while let current = responder, !(current is UIViewController) { responder = current.next }
            guard var controller = responder as? UIViewController else { return }
            while true {
                if controller.presentingViewController != nil { changed?(true); return }
                guard let parent = controller.parent else { changed?(false); return }
                controller = parent
            }
        }
    }
}

// A screen-edge recognizer leaves ordinary horizontal controls and vertical
// scrolling alone. A pushed navigation destination keeps the system back swipe.
private struct PhoneSidebarEdgeGesture: UIViewRepresentable {
    let enabled: Bool
    let open: () -> Void
    func makeUIView(context: Context) -> PhoneSidebarGestureAnchor { PhoneSidebarGestureAnchor() }
    func updateUIView(_ view: PhoneSidebarGestureAnchor, context: Context) {
        view.enabled = enabled; view.open = open
    }
    static func dismantleUIView(_ view: PhoneSidebarGestureAnchor, coordinator: ()) { view.detach() }
}
private final class PhoneSidebarGestureAnchor: UIView, UIGestureRecognizerDelegate {
    var enabled = false
    var open: (() -> Void)?
    private weak var gestureWindow: UIWindow?
    private lazy var edge: UIScreenEdgePanGestureRecognizer = {
        let value = UIScreenEdgePanGestureRecognizer(target: self, action: #selector(swiped(_:)))
        value.edges = .left; value.delegate = self
        value.cancelsTouchesInView = false; value.delaysTouchesBegan = false
        return value
    }()
    override func didMoveToWindow() {
        super.didMoveToWindow()
        detach()
        guard let window else { return }
        isUserInteractionEnabled = false
        gestureWindow = window; window.addGestureRecognizer(edge)
    }
    func detach() { gestureWindow?.removeGestureRecognizer(edge); gestureWindow = nil }
    override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard enabled, let window = gestureWindow, let root = window.rootViewController,
              bounds.contains(convert(gestureRecognizer.location(in: window), from: window)) else { return false }
        let velocity = edge.velocity(in: window)
        guard velocity.x > 0, velocity.x > abs(velocity.y) * 1.3 else { return false }
        guard root.presentedViewController == nil else { return false }
        // Hit-test the visible content instead of traversing all mounted stacks:
        // an inactive section can still retain a pushed destination.
        let point = convert(CGPoint(x: bounds.midX, y: bounds.midY), to: window)
        guard let navigation = Self.navigationController(from: window.hitTest(point, with: nil)) else { return false }
        return navigation.viewControllers.count == 1 && navigation.transitionCoordinator == nil && navigation.presentedViewController == nil
    }
    private static func navigationController(from view: UIView?) -> UINavigationController? {
        var responder: UIResponder? = view
        while let current = responder {
            if let navigation = current as? UINavigationController { return navigation }
            if let controller = current as? UIViewController, let navigation = controller.navigationController { return navigation }
            responder = current.next
        }
        return nil
    }
    @objc private func swiped(_ gesture: UIScreenEdgePanGestureRecognizer) {
        guard enabled, gesture.state == .ended else { return }
        let distance = gesture.translation(in: gestureWindow)
        if distance.x >= 60 && distance.x > abs(distance.y) * 1.3 { open?() }
    }
}
#endif

struct PayrollHomeView: View {
    let overview: PayrollOverview
    @EnvironmentObject private var store: PayrollStore
    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject private var push = JACNotifications.shared
    @State private var selected: String
    init(overview: PayrollOverview, agendaOnly: Bool = false) {
        self.overview = overview; _selected = State(initialValue: overview.user.initialMobileDestination)
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
                selected = value.initialMobileDestination
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
        if user.hasSection(.calendar) { items.append(("agenda", "Agenda", "calendar.badge.clock")) }
        if user.hasSection(.crm) { items.append(("crm", "CRM", "briefcase")) }
        if user.hasSection(.payroll) { items.append(("payroll", "Quincenas", "list.clipboard")) }
        if user.hasSection(.itineraries) || user.hasSection(.boarding) { items.append(("itineraries", user.hasSection(.itineraries) ? "Itinerarios" : "Pases", "doc.text")) }
        if user.hasSection(.itineraries) && user.hasSection(.boarding) { items.append(("boarding", "Pases", "airplane")) }
        if user.hasSection(.alerts) { items.append(("alerts", "Alertas", "bell")) }
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
            let width = min(314, geometry.size.width * 0.86)
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
        ZStack {
            ForEach(phoneDestinations.filter { $0.id == selected || phoneVisited.contains($0.id) }, id: \.id) { item in
                phoneContent(item.id)
                    .opacity(selected == item.id ? 1 : 0)
                    .allowsHitTesting(selected == item.id && !phoneMenuOpen)
                    .accessibilityHidden(selected != item.id || phoneMenuOpen)
            }
        }.frame(maxWidth: .infinity, maxHeight: .infinity).clipped().animation(nil, value: selected)
        .environment(\.phoneSidebarMenu, PhoneSidebarMenu(open: { setPhoneMenu(true) }, focus: $menuOpenFocused))
        .background(PhoneSidebarEdgeGesture(enabled: !phoneMenuOpen) { setPhoneMenu(true) })
        .onChange(of: selected) { old, new in phoneVisited.insert(old); phoneVisited.insert(new) }
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
                Image("JACLogo").resizable().scaledToFit().frame(width: 114)
                    .padding(8).background(.white, in: RoundedRectangle(cornerRadius: 10)).accessibilityHidden(true)
                Spacer()
                Button { setPhoneMenu(false) } label: { Image(systemName: "xmark").frame(width: 44, height: 44) }
                    .accessibilityLabel("Cerrar menú").accessibilityIdentifier("phone.menu.close").accessibilityFocused($menuCloseFocused)
            }.padding(.horizontal, 18).padding(.top, 10).padding(.bottom, 12)
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    let operations = phoneDestinations.filter { !["media", "music", "management"].contains($0.id) }
                    if !operations.isEmpty {
                        phoneSidebarHeading("OPERACIÓN")
                        ForEach(operations, id: \.id) { phoneSidebarItem($0) }
                    }
                    let library = phoneDestinations.filter { ["media", "music"].contains($0.id) }
                    if !library.isEmpty {
                        phoneSidebarHeading("BIBLIOTECA").padding(.top, 10)
                        ForEach(library, id: \.id) { phoneSidebarItem($0) }
                    }
                    if let management = phoneDestinations.first(where: { $0.id == "management" }) {
                        phoneSidebarItem(management).padding(.top, 12)
                    }
                }.padding(.horizontal, 16).padding(.bottom, 12)
            }.accessibilityIdentifier("phone.sidebar.scroll")
            Divider().padding(.horizontal, 20)
            HStack(spacing: 10) {
                Text(user.displayName.split(separator: " ").prefix(2).map { String($0.prefix(1)) }.joined().uppercased())
                    .font(.caption.weight(.semibold)).foregroundStyle(JACTheme.action)
                    .frame(width: 34, height: 34).background(JACTheme.action.opacity(0.09), in: Circle())
                VStack(alignment: .leading, spacing: 4) {
                    Text(user.displayName).font(.subheadline.weight(.semibold)).lineLimit(2)
                    Text(user.isOwner ? "Administración" : "Mi espacio").font(.caption).foregroundStyle(JACTheme.muted)
                }
            }.frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 24).padding(.vertical, 16).privacySensitive()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(JACTheme.card)
        .overlay(alignment: .trailing) { Rectangle().fill(JACTheme.ink.opacity(0.1)).frame(width: 1) }
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(phoneMenuOpen ? [.isModal] : [])
        .simultaneousGesture(DragGesture(minimumDistance: 30).onEnded { closePhoneMenuOnSwipe($0) })
    }
    private func phoneSidebarHeading(_ title: String) -> some View {
        Text(title).font(.caption2.weight(.semibold)).tracking(1.2).foregroundStyle(JACTheme.muted)
            .padding(.horizontal, 12).padding(.top, 12).padding(.bottom, 6)
    }
    private func phoneSidebarItem(_ item: (id: String, title: String, symbol: String)) -> some View {
        Button {
            phoneVisited.insert(selected); phoneVisited.insert(item.id); selected = item.id; setPhoneMenu(false)
        } label: {
            HStack(spacing: 13) {
                Image(systemName: item.symbol).font(.system(size: 18, weight: .regular)).frame(width: 22)
                    .foregroundStyle(selected == item.id ? JACTheme.action : JACTheme.muted)
                Text(item.title).font(.subheadline.weight(selected == item.id ? .semibold : .regular))
                Spacer(minLength: 4)
                if selected == item.id { Circle().fill(JACTheme.action).frame(width: 5, height: 5).accessibilityHidden(true) }
            }.padding(.horizontal, 13).frame(minHeight: 49).contentShape(Rectangle())
        }.buttonStyle(.plain).foregroundStyle(selected == item.id ? JACTheme.action : JACTheme.ink)
            .background(selected == item.id ? JACTheme.action.opacity(0.09) : Color.clear, in: RoundedRectangle(cornerRadius: 12))
            .accessibilityAddTraits(selected == item.id ? [.isSelected] : [])
            .accessibilityIdentifier("phone.section." + item.id)
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
        }.padding().jacSurface().navigationTitle(title).jacInlineTitle()
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
                #if os(macOS)
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
                #endif
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
            }.jacSurface().jacWorkspaceTitle(archive ? "Archivo" : "Quincenas")
                .jacSearchable(text: $search, prompt: "Buscar mes o estado")
                #if os(iOS)
                .toolbar {
                    if !archive && overview.user.can("payroll") {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button {
                                if let w = store.workspace { editor = PayrollEditorSession(kind: .period, workspace: w, detail: nil, record: PayrollEditorSession.newRecord(.period, workspace: w)) }
                            } label: {
                                Image(systemName: "plus").font(.title3.weight(.medium)).foregroundStyle(.white)
                                    .frame(width: 44, height: 44).background(JACTheme.primary, in: RoundedRectangle(cornerRadius: 14))
                            }.buttonStyle(.plain).accessibilityLabel("Crear quincena").accessibilityIdentifier("period.create").disabled(!store.canWrite)
                        }
                    }
                }
                #endif
                .refreshable { try? await store.refresh() }
                .sheet(item: $editor, onDismiss: { if let id = createdPeriod { path.append(id); createdPeriod = nil } }) { session in PayrollEditorView(session: session) { createdPeriod = $0 } }
    }
    @ViewBuilder private func periodRow(_ period: PeriodSummary) -> some View {
        #if os(iOS)
        if !JACDevice.isPad {
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: period.isClosed ? "checkmark.seal" : "calendar")
                    .font(.body).foregroundStyle(JACTheme.action).frame(width: 38, height: 38)
                    .background(JACTheme.action.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                VStack(alignment: .leading, spacing: 7) {
                    Text(period.title).font(.subheadline.weight(.semibold)).fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 8) {
                        Text(period.isClosed ? "Cerrada" : "En curso").foregroundStyle(JACTheme.action)
                        Text("· \(period.showCount) shows").foregroundStyle(JACTheme.muted)
                    }.font(.caption)
                    if period.ownerOnly { Text("Corrección de cierre").font(.caption).foregroundStyle(.orange) }
                }
            }.padding(.vertical, 8)
        } else { legacyPeriodRow(period) }
        #else
        legacyPeriodRow(period)
        #endif
    }
    private func legacyPeriodRow(_ period: PeriodSummary) -> some View {
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
