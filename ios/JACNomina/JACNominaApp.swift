import SwiftUI

private struct WorkspaceActiveKey: EnvironmentKey {
    static let defaultValue = true
}
extension EnvironmentValues {
    /// A mounted phone destination may retain its navigation and scroll state
    /// while another section, or the physical drawer, is visible.
    var isWorkspaceActive: Bool {
        get { self[WorkspaceActiveKey.self] }
        set { self[WorkspaceActiveKey.self] = newValue }
    }
}
struct JACWorkspaceRefreshID: Equatable {
    var location = ""
    var active: Bool
}

// Keep the iPhone's system picker; Mac dates open from a complete button.
#if os(macOS)
typealias JACDatePicker = MacDatePicker
#else
typealias JACDatePicker = SwiftUI.DatePicker<Text>
#endif
#if os(iOS)
import UIKit
#else
import AppKit
#endif

 #if os(iOS)
@main
@MainActor
struct JACNominaApp: App {
    @UIApplicationDelegateAdaptor(JACPushDelegate.self) private var pushDelegate
    @StateObject private var store = JACNominaApp.makeStore()
    @StateObject private var connectivity = AgendaConnectivity()
    @State private var incomingShare: MediaIncomingShare?
    @Environment(\.scenePhase) private var scenePhase
    init() { JACTheme.configure() }

    var body: some Scene {
        WindowGroup {
            ZStack {
                Group {
                    if Self.isUnitTestHost { Color(uiColor: .systemBackground) }
                    else if store.restoring { ProgressView("Conectando…") }
                    else if let overview = store.overview { PayrollHomeView(overview: overview, agendaOnly: store.isAgendaOnly) }
                    else if store.hasSavedSession { OfflineStartView() }
                    else { LoginView() }
                }
                .environmentObject(store)
                .tint(JACTheme.action)
                if scenePhase != .active {
                    Color(uiColor: .systemBackground).ignoresSafeArea()
                    BrandView().frame(width: 220).accessibilityIdentifier("privacy.cover")
                }
            }
            .background(WindowPrivacyShield())
            .modifier(JACWidgetLifecycle(store: store, enabled: Self.widgetIntegrationEnabled))
            #if DEBUG
            .overlay(alignment: .bottomTrailing) {
                if ProcessInfo.processInfo.arguments.contains("--uitest-scroll-performance") {
                    JACScrollDiagnosticsProbe().padding(.trailing, 6).padding(.bottom, 3)
                }
            }
            .transformEnvironment(\.dynamicTypeSize) { size in
                if ProcessInfo.processInfo.arguments.contains("--uitest-scroll-sidebar") { size = .accessibility5 }
            }
            #endif
            .onOpenURL { url in
                if url.isFileURL { store.receiveAudio(url); return }
                if JACWidgetNavigation.shared.receive(url) { return }
                if let share = MediaIncomingShare.parse(url) { incomingShare = share }
            }
            .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { activity in
                if let url = activity.webpageURL, let share = MediaIncomingShare.parse(url) { incomingShare = share }
            }
            .sheet(item: $incomingShare) { share in MediaSharedFolderBrowser(share: share).id(share.id) }
            .task {
                guard !Self.isUnitTestHost else { return }
                await store.restore()
                await store.resumeMediaUploads()
                store.prefetchMediaRoot()
                while !Task.isCancelled {
                    do { try await Task.sleep(for: .seconds(30)) } catch { return }
                    // Read the current scene state; a long-lived task must not
                    // keep the inactive value captured during cold startup.
                    if UIApplication.shared.applicationState == .active && store.hasSavedSession { try? await store.refreshAutomatically() }
                }
            }
            .onChange(of: scenePhase) { _, value in
                guard value == .active, !Self.isUnitTestHost, store.hasSavedSession || (try? store.client.hasSession()) == true else { return }
                Task {
                    if !store.hasSavedSession { await store.restore() }
                    else { try? await store.refreshAutomatically() }
                    await store.resumeMediaUploads()
                }
            }
            .onChange(of: connectivity.connected) { old, new in
                guard store.hasSavedSession && !Self.isUnitTestHost else { return }
                if new == false { store.client.beginOfflineRestore() }
                if old == false && new == true { Task { try? await store.refreshAutomatically(); await store.resumeMediaUploads() } }
            }
            .onChange(of: store.isOffline) { old, new in if old && !new && !Self.isUnitTestHost { store.prefetchMediaRoot() } }
            .onChange(of: store.overview?.user.id) { _, _ in if !Self.isUnitTestHost { store.prefetchMediaRoot() } }
        }
        .backgroundTask(.appRefresh(JACWidgetBridge.backgroundTaskIdentifier)) {
            guard await Self.widgetIntegrationEnabled else { return }
            await JACWidgetBridge.shared.refreshInBackground(client: store.client)
        }
    }
    private static var widgetIntegrationEnabled: Bool {
        #if DEBUG
        return !Self.isUnitTestHost && !ProcessInfo.processInfo.arguments.contains("--uitest-payroll")
        #else
        return true
        #endif
    }
    private static var isUnitTestHost: Bool {
        #if DEBUG
        return Bundle.allBundles.contains { $0.bundleURL.lastPathComponent == "JACNominaTests.xctest" }
        #else
        return false
        #endif
    }
    private static func makeStore() -> PayrollStore {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("--uitest-payroll") { return PayrollStore(client: UITestBackend.client(reader: arguments.contains("--uitest-reader"), conflict: arguments.contains("--uitest-conflict"), cancelledReads: arguments.contains("--uitest-cancelled-reads"), offline: arguments.contains("--uitest-offline"), slowAgenda: arguments.contains("--uitest-slow-agenda"), persistentAgenda: arguments.contains("--uitest-agenda-cache"), resetAgenda: arguments.contains("--uitest-reset-agenda"))) }
        #endif
        return PayrollStore()
    }
}

#if DEBUG
private struct JACScrollDiagnosticsProbe: View {
    @State private var sample = 0
    @State private var value = "{}"
    var body: some View {
        Button {
            sample += 1
            let snapshot = JACPerformanceDiagnostics.snapshot()
            var fields = UITestBackend.scrollRequestSnapshot().reduce(into: [String: Int]()) { $0["requests." + $1.key] = $1.value }
            fields["sample"] = sample
            fields["main.expensive"] = snapshot.mainThreadExpensiveOperations
            for (name, operation) in [("diskRead", JACPerformanceDiagnostics.Operation.diskRead), ("diskWrite", .diskWrite), ("keyDerivation", .keyDerivation), ("jsonDecode", .jsonDecode), ("jsonEncode", .jsonEncode), ("sessionRead", .sessionRead)] {
                fields["main." + name] = snapshot.count(operation, mainThread: true)
            }
            if let bytes = try? JSONSerialization.data(withJSONObject: fields, options: [.sortedKeys]), let encoded = String(data: bytes, encoding: .utf8) { value = encoded }
        } label: {
            Image(systemName: "speedometer").font(.body).frame(width: 44, height: 44)
                .foregroundStyle(.white).background(.indigo, in: Circle())
        }.buttonStyle(.plain).accessibilityLabel("Capturar métricas de prueba")
            .accessibilityIdentifier("debug.scroll.snapshot").accessibilityValue(value)
    }
}
#endif

// A scene's window also contains presented sheets. The SwiftUI root cover sits
// below those sheets, so cover the window before the system takes its snapshot.
private struct WindowPrivacyShield: UIViewRepresentable {
    func makeUIView(context: Context) -> PrivacyShieldAnchor {
        let view = PrivacyShieldAnchor()
        view.isUserInteractionEnabled = false
        return view
    }
    func updateUIView(_ view: PrivacyShieldAnchor, context: Context) {}
    static func dismantleUIView(_ view: PrivacyShieldAnchor, coordinator: ()) { view.stop() }
}

private final class PrivacyShieldAnchor: UIView {
    private var observers: [NSObjectProtocol] = []
    private var cover: UIView?

    override func didMoveToWindow() {
        super.didMoveToWindow()
        stop()
        guard let scene = window?.windowScene else { return }
        for name in [UIScene.willDeactivateNotification, UIScene.didEnterBackgroundNotification] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: scene, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.conceal() }
            })
        }
        observers.append(NotificationCenter.default.addObserver(forName: UIScene.didActivateNotification, object: scene, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.reveal() }
        })
        if scene.activationState != .foregroundActive { conceal() }
    }

    func stop() {
        observers.forEach { NotificationCenter.default.removeObserver($0) }
        observers.removeAll()
        reveal()
    }

    private func conceal() {
        guard let window else { return }
        // Remove keyboard suggestions from the snapshot without clearing any
        // field or dismissing its editor/navigation destination.
        UIView.performWithoutAnimation { _ = window.endEditing(true) }
        if let cover { window.bringSubviewToFront(cover); return }
        let shade = UIView(frame: window.bounds)
        shade.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        shade.backgroundColor = .systemBackground
        shade.accessibilityViewIsModal = true
        let brand = UIView()
        brand.backgroundColor = .white; brand.layer.cornerRadius = 14
        let logo = UIImageView(image: UIImage(named: "JACLogo"))
        logo.contentMode = .scaleAspectFit
        logo.isAccessibilityElement = true
        logo.accessibilityLabel = "JAC Music Estudios"
        logo.accessibilityIdentifier = "privacy.cover"
        brand.translatesAutoresizingMaskIntoConstraints = false
        logo.translatesAutoresizingMaskIntoConstraints = false
        shade.addSubview(brand); brand.addSubview(logo)
        let ratio = (logo.image?.size.height ?? 1) / (logo.image?.size.width ?? 1)
        NSLayoutConstraint.activate([
            brand.centerXAnchor.constraint(equalTo: shade.centerXAnchor), brand.centerYAnchor.constraint(equalTo: shade.centerYAnchor),
            brand.widthAnchor.constraint(equalToConstant: 220),
            logo.leadingAnchor.constraint(equalTo: brand.leadingAnchor, constant: 14), logo.trailingAnchor.constraint(equalTo: brand.trailingAnchor, constant: -14),
            logo.topAnchor.constraint(equalTo: brand.topAnchor, constant: 14), logo.bottomAnchor.constraint(equalTo: brand.bottomAnchor, constant: -14),
            logo.heightAnchor.constraint(equalTo: logo.widthAnchor, multiplier: ratio)
        ])
        cover = shade
        window.addSubview(shade)
    }

    private func reveal() { cover?.removeFromSuperview(); cover = nil }
}

#endif

struct OfflineStartView: View {
    @EnvironmentObject private var store: PayrollStore
    @State private var loading = false
    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                BrandView().frame(width: 180)
                ContentUnavailableView("Tu sesión sigue iniciada", systemImage: "wifi.slash", description: Text("Todavía no hay una copia descargada en este \(JACDevice.name). Conéctate una vez para guardar tu información."))
                Button("Reintentar conexión") { Task { loading = true; defer { loading = false }; await store.restore() } }.disabled(loading).accessibilityIdentifier("offline.retry")
                Button("Cerrar sesión", role: .destructive) { Task { await store.signOut() } }
            }.padding().jacSurface().navigationTitle("JAC")
        }
    }
}

struct BrandView: View {
    var body: some View {
        Image("JACLogo").resizable().scaledToFit()
            .padding(14)
            .background(.white, in: RoundedRectangle(cornerRadius: 14))
            .accessibilityLabel("JAC Music Estudios")
    }
}

struct InlineError: View {
    let message: String
    var body: some View { Label(message, systemImage: "exclamationmark.circle").font(.subheadline).foregroundStyle(.red).accessibilityIdentifier("error.inline") }
}

enum JACTheme {
    // JAC logo palette. Keep status colours semantic and text readable in both appearances.
    static let navy = Color(red: 6/255, green: 47/255, blue: 70/255)
    static let highlight = Color(red: 98/255, green: 206/255, blue: 255/255)
    static let primary = Color(red: 0/255, green: 111/255, blue: 189/255)
    #if os(iOS)
    static let pageTopSpacing: CGFloat = 8
    static let card = Color(uiColor: .secondarySystemGroupedBackground)
    static let canvas = Color(UIColor { $0.userInterfaceStyle == .dark ? UIColor(red: 11/255, green: 25/255, blue: 37/255, alpha: 1) : UIColor(red: 245/255, green: 247/255, blue: 250/255, alpha: 1) })
    static let action = Color(UIColor { $0.userInterfaceStyle == .dark ? UIColor(red: 98/255, green: 206/255, blue: 255/255, alpha: 1) : UIColor(red: 0/255, green: 111/255, blue: 189/255, alpha: 1) })
    static let ink = Color(UIColor { $0.userInterfaceStyle == .dark ? UIColor(red: 232/255, green: 241/255, blue: 246/255, alpha: 1) : UIColor(red: 18/255, green: 47/255, blue: 66/255, alpha: 1) })
    static let border = Color(UIColor { $0.userInterfaceStyle == .dark ? UIColor(red: 42/255, green: 61/255, blue: 75/255, alpha: 1) : UIColor(red: 225/255, green: 231/255, blue: 238/255, alpha: 1) })
    static let muted = Color(UIColor { $0.userInterfaceStyle == .dark ? UIColor(red: 167/255, green: 183/255, blue: 197/255, alpha: 1) : UIColor(red: 98/255, green: 111/255, blue: 126/255, alpha: 1) })
    @MainActor static func configure() {
        let tabs = UITabBarAppearance(); tabs.configureWithOpaqueBackground(); tabs.backgroundColor = .systemBackground
        for item in [tabs.stackedLayoutAppearance, tabs.inlineLayoutAppearance, tabs.compactInlineLayoutAppearance] {
            item.normal.iconColor = .secondaryLabel
            item.normal.titleTextAttributes = [.foregroundColor: item.normal.iconColor!]
            item.selected.iconColor = UIColor(action); item.selected.titleTextAttributes = [.foregroundColor: UIColor(action)]
        }
        UITabBar.appearance().standardAppearance = tabs; UITabBar.appearance().scrollEdgeAppearance = tabs
        let navigation = UINavigationBarAppearance()
        navigation.configureWithOpaqueBackground()
        navigation.backgroundColor = UIColor(canvas)
        navigation.shadowColor = .clear
        navigation.titleTextAttributes = [.foregroundColor: UIColor(ink)]
        UINavigationBar.appearance().standardAppearance = navigation
        UINavigationBar.appearance().scrollEdgeAppearance = navigation
        UINavigationBar.appearance().compactAppearance = navigation
    }
    #else
    static let pageTopSpacing: CGFloat = 18
    static let card = Color(nsColor: .controlBackgroundColor)
    static let canvas = JACAdaptiveColor(light: (0.953,0.969,0.984), dark: (0.043,0.094,0.137))
    static let action = JACAdaptiveColor(light: (0,0.435,0.741), dark: (0.384,0.808,1))
    static let ink = JACAdaptiveColor(light: (0.086,0.204,0.286), dark: (0.906,0.945,0.980))
    static let border = JACAdaptiveColor(light: (0.88,0.91,0.94), dark: (0.16,0.24,0.29))
    static let muted = Color.secondary
    @MainActor static func configure() {}
    #endif
}
#if os(macOS)
struct JACPrimaryButtonStyle: PrimitiveButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button(configuration).buttonStyle(.borderedProminent).controlSize(.large).tint(JACTheme.primary).fixedSize(horizontal:true,vertical:false)
    }
}
#else
struct JACPrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.fontWeight(.semibold).padding(.horizontal, 16).padding(.vertical, 12)
            .foregroundStyle(.white).background(JACTheme.primary, in: RoundedRectangle(cornerRadius: 12))
            .contentShape(RoundedRectangle(cornerRadius: 12))
            .opacity(enabled ? (configuration.isPressed ? 0.8 : 1) : 0.45)
    }
}
#endif

extension View {
    // Mark the content, not the NavigationStack/TabView that owns it. On iOS 27
    // redacting the whole navigation hierarchy for a background snapshot can
    // attach its UINavigationItem to a second bar while the keyboard resigns.
    func jacSurface() -> some View {
        scrollContentBackground(.hidden).background(JACCanvas()).foregroundStyle(JACTheme.ink)
            .tint(JACTheme.action).jacListSpacing().privacySensitive()
    }
    func jacStandaloneRow() -> some View {
        listRowBackground(Color.clear).listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: 5, leading: 0, bottom: 5, trailing: 0))
    }
}


// Presentation only. Navigation, permissions and actions remain owned by each screen.
enum JACTone {
    case blue, teal, violet, amber
    var color: Color {
        switch self {
        case .blue: return JACTheme.action
        case .teal: return JACAdaptiveColor(light:(0.02,0.43,0.43),dark:(0.36,0.86,0.79))
        case .violet: return JACAdaptiveColor(light:(0.34,0.30,0.66),dark:(0.74,0.71,1))
        case .amber: return JACAdaptiveColor(light:(0.56,0.34,0.08),dark:(1,0.77,0.38))
        }
    }
    var deep: Color {
        switch self {
        case .blue: return Color(red: 0.02, green: 0.28, blue: 0.46)
        case .teal: return Color(red: 0.02, green: 0.31, blue: 0.34)
        case .violet: return Color(red: 0.22, green: 0.23, blue: 0.46)
        case .amber: return Color(red: 0.38, green: 0.24, blue: 0.13)
        }
    }
}
struct JACCanvas: View {
    var body: some View {
        #if os(iOS)
        JACTheme.canvas.ignoresSafeArea()
        #else
        LinearGradient(colors: [JACTheme.action.opacity(0.055), JACTheme.canvas, JACTheme.canvas], startPoint: .topLeading, endPoint: .bottomTrailing).ignoresSafeArea()
        #endif
    }
}
struct JACFeatureBanner: View {
    let eyebrow: String
    let title: String
    let subtitle: String
    var symbol = "waveform"
    var tone: JACTone = .blue
    var body: some View {
        #if os(macOS)
        MacPageHeader(title:macTitle,subtitle:subtitle,symbol:symbol)
        #else
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: symbol).font(.subheadline.bold()).frame(width: 32, height: 32)
                    .background(.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
                Text(eyebrow.uppercased()).font(.caption2.weight(.bold)).tracking(1.8)
                Spacer(minLength: 0)
                HStack(alignment: .center, spacing: 3) {
                    ForEach(Array([10.0, 22.0, 15.0, 29.0, 19.0].enumerated()), id: \.offset) { _, height in
                        Capsule().fill(JACTheme.highlight.opacity(0.85)).frame(width: 3, height: height)
                    }
                }.accessibilityHidden(true)
            }.foregroundStyle(.white.opacity(0.9))
            Text(title).font(.system(.title2, design: .rounded, weight: .bold)).foregroundStyle(.white).fixedSize(horizontal: false, vertical: true)
            Text(subtitle).font(.subheadline).foregroundStyle(Color(red: 0.80, green: 0.89, blue: 0.96)).fixedSize(horizontal: false, vertical: true)
        }.frame(maxWidth: .infinity, alignment: .leading).padding(22)
            .background {
                ZStack(alignment: .trailing) {
                    LinearGradient(colors: [JACTheme.navy, tone.deep], startPoint: .topLeading, endPoint: .bottomTrailing)
                    Circle().stroke(.white.opacity(0.07), lineWidth: 28).frame(width: 180, height: 180).offset(x: 72, y: 28)
                }.allowsHitTesting(false).accessibilityHidden(true)
            }
            .clipShape(RoundedRectangle(cornerRadius: 24))
            .overlay(RoundedRectangle(cornerRadius: 24).stroke(.white.opacity(0.08), lineWidth: 1))
        #endif
    }
    #if os(macOS)
    private var macTitle:String {
        switch symbol {
        case "wallet.pass": "Quincenas"
        case "archivebox": "Archivo de quincenas"
        case "briefcase": "CRM · Shows y abonos"
        case "slider.horizontal.3": "Configuración general"
        default: title
        }
    }
    #endif

}
struct JACIcon: View {
    let symbol: String
    var tone: JACTone = .blue
    var body: some View {
        Image(systemName: symbol).font(.system(size: 20, weight: .semibold))
            .foregroundStyle(tone.color).frame(width: 46, height: 46)
            .background(tone.color.opacity(0.10), in: RoundedRectangle(cornerRadius: 15))
            .accessibilityHidden(true)
    }
}
struct JACBadge: View {
    let title: String
    var tone: JACTone = .blue
    var body: some View {
        Text(title).font(.caption2.weight(.semibold)).foregroundStyle(tone.color)
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(tone.color.opacity(0.09), in: Capsule())
    }
}
struct JACAccessCard: View {
    let title: String
    let subtitle: String
    let symbol: String
    var tone: JACTone = .blue
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack { JACIcon(symbol: symbol, tone: tone); Spacer(minLength: 0); Image(systemName: "arrow.up.right").font(.caption.bold()).foregroundStyle(tone.color) }
            Text(title).font(.system(.subheadline, design: .rounded, weight: .bold)).foregroundStyle(JACTheme.ink).fixedSize(horizontal: false, vertical: true)
            Text(subtitle).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }.frame(maxWidth: .infinity, minHeight: 126, alignment: .topLeading).padding(16)
            .background(JACTheme.card, in: RoundedRectangle(cornerRadius: 22))
            .overlay(RoundedRectangle(cornerRadius: 22).stroke(tone.color.opacity(0.12), lineWidth: 1))
            .contentShape(RoundedRectangle(cornerRadius: 22))
            .accessibilityElement(children: .ignore).accessibilityLabel(title)
    }
}
#if os(macOS)
struct JACSecondaryButtonStyle: PrimitiveButtonStyle {
    var tone:JACTone = .blue
    func makeBody(configuration:Configuration)->some View {
        Button(configuration).buttonStyle(.bordered).controlSize(.regular).fixedSize(horizontal:true,vertical:false)
    }
}
#else
struct JACSecondaryButtonStyle: ButtonStyle {
    var tone: JACTone = .blue
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.subheadline.weight(.semibold)).padding(.horizontal, 15).padding(.vertical, 12)
            .foregroundStyle(tone.color).background(tone.color.opacity(configuration.isPressed ? 0.18 : 0.09), in: RoundedRectangle(cornerRadius: 15))
            .opacity(enabled ? 1 : 0.45)
    }
}
#endif

// Platform presentation adapters. The domain model and all server commands are shared.
#if os(iOS)
typealias JACPlatformImage = UIImage
#else
typealias JACPlatformImage = NSImage
#endif
func JACAdaptiveColor(light:(Double,Double,Double),dark:(Double,Double,Double)) -> Color {
    #if os(iOS)
    return Color(UIColor { traits in let c = traits.userInterfaceStyle == .dark ? dark:light;return UIColor(red:c.0,green:c.1,blue:c.2,alpha:1) })
    #else
    return Color(nsColor:NSColor(name:nil) { appearance in let c = appearance.bestMatch(from:[.darkAqua,.aqua]) == .darkAqua ? dark:light;return NSColor(srgbRed:c.0,green:c.1,blue:c.2,alpha:1) })
    #endif
}
extension View {
    @ViewBuilder func jacSearchable(text: Binding<String>, prompt: String) -> some View {
        #if os(iOS)
        searchable(text: text, placement: .navigationBarDrawer(displayMode: .always), prompt: prompt)
        #else
        searchable(text: text, prompt: prompt)
        #endif
    }

    @ViewBuilder func jacInlineTitle() -> some View {
        #if os(iOS)
        navigationBarTitleDisplayMode(.inline).modifier(PhoneSidebarToolbar())
        #else
        self
        #endif
    }
    // One root heading beside the drawer button; details keep their native back
    // button and sheets keep the system title/close controls. Preserve the
    // navigation title as the bar's identity for VoiceOver and state restoration.
    @ViewBuilder func jacWorkspaceTitle(_ title: String) -> some View {
        #if os(iOS)
        navigationTitle(title).navigationBarTitleDisplayMode(.inline)
            .modifier(PhoneSidebarToolbar(title: title))
        #else
        navigationTitle(title)
        #endif
    }
    @ViewBuilder func jacListSpacing() -> some View {
        #if os(iOS)
        listSectionSpacing(18).contentMargins(.top, 0, for: .scrollContent)
        #else
        formStyle(.grouped).frame(minWidth:620,minHeight:440)
        #endif
    }
}
extension ToolbarItemPlacement {
    static var jacLeading: Self {
        #if os(iOS)
        .topBarLeading
        #else
        .cancellationAction
        #endif
    }
    static var jacTrailing: Self {
        #if os(iOS)
        .topBarTrailing
        #else
        .primaryAction
        #endif
    }
}
extension Image {
    init(jacImage:JACPlatformImage) {
        #if os(iOS)
        self.init(uiImage:jacImage)
        #else
        self.init(nsImage:jacImage)
        #endif
    }
}
enum JACPlatform {
    @MainActor static func endEditing() {
        #if os(iOS)
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder),to:nil,from:nil,for:nil)
        #else
        NSApp.keyWindow?.makeFirstResponder(nil)
        #endif
    }
    static var keyboardShown: Notification.Name {
        #if os(iOS)
        UIResponder.keyboardDidShowNotification
        #else
        Notification.Name("JACMacNoSoftwareKeyboard")
        #endif
    }
    @MainActor static func printDocument(_ url:URL) {
        #if os(iOS)
        let printer=UIPrintInteractionController.shared;printer.printingItem=url;printer.present(animated:true,completionHandler:nil)
        #else
        MacDocumentActions.printDocument(url)
        #endif
    }
    static func fixturePDF() -> Data {
        #if os(iOS)
        return UIGraphicsPDFRenderer(bounds:CGRect(x:0,y:0,width:300,height:300)).pdfData { c in c.beginPage();("PRUEBA JAC SIN DATOS REALES" as NSString).draw(at:CGPoint(x:20,y:20),withAttributes:nil) }
        #else
        let output=NSMutableData();var bounds=CGRect(x:0,y:0,width:300,height:300)
        let consumer=CGDataConsumer(data:output as CFMutableData)!
        let context=CGContext(consumer:consumer,mediaBox:&bounds,nil)!;context.beginPDFPage(nil);context.endPDFPage();context.closePDF();return output as Data
        #endif
    }
}

@MainActor var JACCameraAvailable:Bool {
    #if os(iOS)
    UIImagePickerController.isSourceTypeAvailable(.camera)
    #else
    true
    #endif
}

enum JACDevice {
    static var isPad: Bool {
        #if os(iOS)
        UIDevice.current.userInterfaceIdiom == .pad
        #else
        false
        #endif
    }
    static var name:String {
        #if os(iOS)
        isPad ? "iPad" : "iPhone"
        #else
        "Mac"
        #endif
    }
}

extension View {
    @ViewBuilder func jacFileDrop(enabled:Bool=true, receive:@escaping ([URL])->Void) -> some View {
        #if os(macOS)
        dropDestination(for:URL.self) {urls,_ in guard enabled,!urls.isEmpty else{return false};receive(urls);return true}
        #else
        self
        #endif
    }
}

extension View {
    @ViewBuilder func jacRefreshCommand(_ action:@escaping ()->Void)->some View {
        #if os(macOS)
        focusedSceneValue(\.macRefresh,action)
        #else
        self
        #endif
    }
}
