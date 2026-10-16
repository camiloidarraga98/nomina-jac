import SwiftUI
import UIKit

@main
@MainActor
struct JACNominaApp: App {
    @UIApplicationDelegateAdaptor(JACPushDelegate.self) private var pushDelegate
    @StateObject private var store = JACNominaApp.makeStore()
    @StateObject private var connectivity = AgendaConnectivity()
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
            .task {
                guard !Self.isUnitTestHost else { return }
                await store.restore()
                while !Task.isCancelled {
                    do { try await Task.sleep(for: .seconds(30)) } catch { return }
                    // Read the current scene state; a long-lived task must not
                    // keep the inactive value captured during cold startup.
                    if UIApplication.shared.applicationState == .active && store.hasSavedSession { try? await store.refreshAutomatically() }
                }
            }
            .onChange(of: scenePhase) { _, value in if value == .active && store.hasSavedSession && !Self.isUnitTestHost { Task { try? await store.refreshAutomatically() } } }
            .onChange(of: connectivity.connected) { old, new in
                guard store.hasSavedSession && !Self.isUnitTestHost else { return }
                if new == false { store.client.beginOfflineRestore() }
                if old == false && new == true { Task { try? await store.refreshAutomatically() } }
            }
        }
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

struct OfflineStartView: View {
    @EnvironmentObject private var store: PayrollStore
    @State private var loading = false
    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                BrandView().frame(width: 180)
                ContentUnavailableView("Tu sesión sigue iniciada", systemImage: "wifi.slash", description: Text("Todavía no hay una copia descargada en este iPhone. Conéctate una vez para guardar tu información."))
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
    static let card = Color(uiColor: .secondarySystemGroupedBackground)
    static let canvas = Color(UIColor { $0.userInterfaceStyle == .dark ? UIColor(red: 11/255, green: 24/255, blue: 35/255, alpha: 1) : UIColor(red: 243/255, green: 247/255, blue: 251/255, alpha: 1) })
    static let action = Color(UIColor { $0.userInterfaceStyle == .dark ? UIColor(red: 98/255, green: 206/255, blue: 255/255, alpha: 1) : UIColor(red: 0/255, green: 111/255, blue: 189/255, alpha: 1) })
    static let ink = Color(UIColor { $0.userInterfaceStyle == .dark ? UIColor(red: 231/255, green: 241/255, blue: 250/255, alpha: 1) : UIColor(red: 22/255, green: 52/255, blue: 73/255, alpha: 1) })
    @MainActor static func configure() {
        let tabs = UITabBarAppearance(); tabs.configureWithOpaqueBackground(); tabs.backgroundColor = .systemBackground
        for item in [tabs.stackedLayoutAppearance, tabs.inlineLayoutAppearance, tabs.compactInlineLayoutAppearance] {
            item.normal.iconColor = .secondaryLabel
            item.normal.titleTextAttributes = [.foregroundColor: item.normal.iconColor!]
            item.selected.iconColor = UIColor(action); item.selected.titleTextAttributes = [.foregroundColor: UIColor(action)]
        }
        UITabBar.appearance().standardAppearance = tabs; UITabBar.appearance().scrollEdgeAppearance = tabs
    }
}
struct JACPrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.fontWeight(.semibold).padding(.horizontal, 16).padding(.vertical, 12)
            .foregroundStyle(.white).background(LinearGradient(colors: [JACTheme.primary, Color(red: 0.02, green: 0.33, blue: 0.59)], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 16))
            .contentShape(RoundedRectangle(cornerRadius: 16))
            .opacity(enabled ? (configuration.isPressed ? 0.8 : 1) : 0.45)
    }
}
extension View {
    // Mark the content, not the NavigationStack/TabView that owns it. On iOS 27
    // redacting the whole navigation hierarchy for a background snapshot can
    // attach its UINavigationItem to a second bar while the keyboard resigns.
    func jacSurface() -> some View {
        scrollContentBackground(.hidden).background(JACCanvas()).foregroundStyle(JACTheme.ink)
            .tint(JACTheme.action).listSectionSpacing(18).privacySensitive()
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
        case .teal: return Color(UIColor { $0.userInterfaceStyle == .dark ? UIColor(red: 0.36, green: 0.86, blue: 0.79, alpha: 1) : UIColor(red: 0.02, green: 0.43, blue: 0.43, alpha: 1) })
        case .violet: return Color(UIColor { $0.userInterfaceStyle == .dark ? UIColor(red: 0.74, green: 0.71, blue: 1, alpha: 1) : UIColor(red: 0.34, green: 0.30, blue: 0.66, alpha: 1) })
        case .amber: return Color(UIColor { $0.userInterfaceStyle == .dark ? UIColor(red: 1, green: 0.77, blue: 0.38, alpha: 1) : UIColor(red: 0.56, green: 0.34, blue: 0.08, alpha: 1) })
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
        LinearGradient(colors: [JACTheme.action.opacity(0.055), JACTheme.canvas, JACTheme.canvas], startPoint: .topLeading, endPoint: .bottomTrailing).ignoresSafeArea()
    }
}
struct JACFeatureBanner: View {
    let eyebrow: String
    let title: String
    let subtitle: String
    var symbol = "waveform"
    var tone: JACTone = .blue
    var body: some View {
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
    }
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
struct JACSecondaryButtonStyle: ButtonStyle {
    var tone: JACTone = .blue
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.subheadline.weight(.semibold)).padding(.horizontal, 15).padding(.vertical, 12)
            .foregroundStyle(tone.color).background(tone.color.opacity(configuration.isPressed ? 0.18 : 0.09), in: RoundedRectangle(cornerRadius: 15))
            .opacity(enabled ? 1 : 0.45)
    }
}
