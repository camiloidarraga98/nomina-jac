import SwiftUI
import UIKit

@main
@MainActor
struct JACNominaApp: App {
    @UIApplicationDelegateAdaptor(JACPushDelegate.self) private var pushDelegate
    @StateObject private var store = JACNominaApp.makeStore()
    @Environment(\.scenePhase) private var scenePhase
    init() { JACTheme.configure() }

    var body: some Scene {
        WindowGroup {
            ZStack {
                Group {
                    if Self.isUnitTestHost { Color(uiColor: .systemBackground) }
                    else if store.restoring { ProgressView("Conectando…") }
                    else if let overview = store.overview { PayrollHomeView(overview: overview) }
                    else { LoginView() }
                }
                .environmentObject(store)
                .tint(JACTheme.action)
                .privacySensitive()
                if scenePhase != .active {
                    Color(uiColor: .systemBackground).ignoresSafeArea()
                    BrandView().frame(width: 220)
                }
            }
            .task { if !Self.isUnitTestHost { await store.restore() } }
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
        if arguments.contains("--uitest-payroll") { return PayrollStore(client: UITestBackend.client(reader: arguments.contains("--uitest-reader"), conflict: arguments.contains("--uitest-conflict"))) }
        #endif
        return PayrollStore()
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
    var body: some View { Label(message, systemImage: "exclamationmark.circle").font(.subheadline).foregroundStyle(.red) }
}

enum JACTheme {
    static let forest = Color(red: 23/255, green: 44/255, blue: 36/255)
    static let lime = Color(red: 196/255, green: 244/255, blue: 100/255)
    static let canvas = Color(UIColor { $0.userInterfaceStyle == .dark ? UIColor(red: 16/255, green: 28/255, blue: 22/255, alpha: 1) : UIColor(red: 243/255, green: 246/255, blue: 243/255, alpha: 1) })
    static let action = Color(UIColor { $0.userInterfaceStyle == .dark ? UIColor(red: 196/255, green: 244/255, blue: 100/255, alpha: 1) : UIColor(red: 53/255, green: 100/255, blue: 61/255, alpha: 1) })
    static let ink = Color(UIColor { $0.userInterfaceStyle == .dark ? UIColor(red: 237/255, green: 246/255, blue: 239/255, alpha: 1) : UIColor(red: 24/255, green: 34/255, blue: 30/255, alpha: 1) })
    @MainActor static func configure() {
        let tabs = UITabBarAppearance(); tabs.configureWithOpaqueBackground(); tabs.backgroundColor = UIColor(forest)
        for item in [tabs.stackedLayoutAppearance, tabs.inlineLayoutAppearance, tabs.compactInlineLayoutAppearance] {
            item.normal.iconColor = UIColor(red: 172/255, green: 192/255, blue: 178/255, alpha: 1)
            item.normal.titleTextAttributes = [.foregroundColor: item.normal.iconColor!]
            item.selected.iconColor = UIColor(lime); item.selected.titleTextAttributes = [.foregroundColor: UIColor(lime)]
        }
        UITabBar.appearance().standardAppearance = tabs; UITabBar.appearance().scrollEdgeAppearance = tabs
    }
}
struct JACPrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.fontWeight(.semibold).padding(.horizontal, 16).padding(.vertical, 12)
            .foregroundStyle(JACTheme.forest).background(JACTheme.lime, in: RoundedRectangle(cornerRadius: 10))
            .opacity(enabled ? (configuration.isPressed ? 0.8 : 1) : 0.45)
    }
}
extension View {
    func jacSurface() -> some View { scrollContentBackground(.hidden).background(JACTheme.canvas).foregroundStyle(JACTheme.ink).tint(JACTheme.action) }
}
