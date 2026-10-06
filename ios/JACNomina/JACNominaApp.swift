import SwiftUI

@main
@MainActor
struct JACNominaApp: App {
    @StateObject private var store = JACNominaApp.makeStore()
    @Environment(\.scenePhase) private var scenePhase

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
                .tint(Color(red: 0, green: 0.48, blue: 0.85))
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
