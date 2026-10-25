#if os(iOS)
import SwiftUI
import Combine

/// A widget link selects an existing, authorised destination after login. It
/// carries no session or document capability, and never grants a module.
@MainActor
final class JACWidgetNavigation: ObservableObject {
    struct Pending: Identifiable {
        let id = UUID()
        let route: JACWidgetRoute
    }
    static let shared = JACWidgetNavigation()
    @Published private(set) var pending: Pending?

    @discardableResult func receive(_ url: URL) -> Bool {
        guard let route = JACWidgetRoute(url: url) else { return false }
        pending = Pending(route: route)
        return true
    }
    func finish(_ id: UUID) {
        if pending?.id == id { pending = nil }
    }
}

/// Observes only lifecycle changes. Snapshot encoding, images and disk writes
/// belong to the bridge's utility actor, never to a SwiftUI render or scroll.
struct JACWidgetLifecycle: ViewModifier {
    @ObservedObject var store: PayrollStore
    let enabled: Bool
    @Environment(\.scenePhase) private var phase
    @State private var synchronization: Task<Void, Never>?

    func body(content: Content) -> some View {
        content
            .task(id: store.overview?.user) { await synchronize() }
            .onChange(of: store.hasSavedSession) { _, value in
                guard enabled else { return }
                if value { requestSynchronization() }
                else { JACWidgetBridge.shared.invalidate() }
            }
            .onChange(of: store.savedAgenda?.latest?.receivedAt) { _, _ in
                guard enabled else { return }
                Task { await publishCalendar() }
            }
            // Ordinary feed/cache writes must not start another authenticated
            // widget read. This is a cheap session/permission generation only.
            .onChange(of: store.client.mediaPresentationStamp) { _, _ in requestSynchronization() }
            .onReceive(MediaUploadQueue.shared.$uploading.removeDuplicates().dropFirst()) { uploading in
                if !uploading, store.overview?.user.canReadMedia == true { requestSynchronization(force: true) }
            }
            .onChange(of: phase) { _, value in
                guard enabled else { return }
                if value == .active { requestSynchronization() }
                else { synchronization?.cancel(); synchronization = nil }
                if value == .background, store.hasSavedSession,
                   let user = store.overview?.user,
                   user.hasSection(.calendar) || user.canReadMedia {
                    JACWidgetBridge.shared.scheduleBackgroundRefresh()
                }
            }
            .onDisappear { synchronization?.cancel(); synchronization = nil }
    }

    private func requestSynchronization(force: Bool = false) {
        guard enabled, phase == .active else { return }
        synchronization?.cancel()
        synchronization = Task {
            do { try await Task.sleep(for: .milliseconds(750)) } catch { return }
            await synchronize(force: force)
        }
    }
    private func synchronize(force: Bool = false) async {
        guard enabled, phase == .active, !Task.isCancelled else { return }
        guard store.hasSavedSession else { JACWidgetBridge.shared.invalidate(); return }
        guard let user = store.overview?.user else { return }
        let agenda = store.savedAgenda?.month(CalendarClock.month(Date()))?.data
        await JACWidgetBridge.shared.refresh(client: store.client, user: user, agenda: agenda, force: force)
    }
    private func publishCalendar() async {
        guard enabled, store.hasSavedSession, let user = store.overview?.user,
              user.hasSection(.calendar), let data = store.savedAgenda?.latest?.data else {
            if enabled { await JACWidgetBridge.shared.clearCalendar() }
            return
        }
        await JACWidgetBridge.shared.publishCalendar(client: store.client, user: user, data: data)
    }
}
#endif
