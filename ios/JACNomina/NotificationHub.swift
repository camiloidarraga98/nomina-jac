import SwiftUI
#if os(iOS)
import UIKit
#else
import AppKit
#endif
import UserNotifications

@MainActor
protocol NotificationPermissionProviding {
    func status() async -> UNAuthorizationStatus
    func request() async throws -> Bool
}
@MainActor
struct SystemNotificationPermission: NotificationPermissionProviding {
    func status() async -> UNAuthorizationStatus { await UNUserNotificationCenter.current().notificationSettings().authorizationStatus }
    func request() async throws -> Bool { try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) }
}

@MainActor
final class JACNotifications: ObservableObject {
    static let shared: JACNotifications = {
        #if DEBUG
        // Exercise the real, local iOS permission dialog without registering APNs.
        if ProcessInfo.processInfo.arguments.contains("--uitest-push-permission") {
            let defaults = UserDefaults(suiteName: "JACPushPermissionUITest")!
            defaults.removeObject(forKey: "jac.push.enabled")
            return JACNotifications(defaults: defaults, allowsFixture: true, pushAvailable: true, registerRemote: {}, unregisterRemote: {})
        }
        if ProcessInfo.processInfo.arguments.contains("--uitest-push-settings") {
            return JACNotifications(pushAvailable: true, registerRemote: {}, unregisterRemote: {})
        }
        #endif
        return JACNotifications()
    }()
    nonisolated static var buildSupportsPush: Bool { Bundle.main.object(forInfoDictionaryKey: "JACPushEnabled") as? String == "YES" }
    let pushAvailable: Bool
    static let suspensionMessage = "Notificaciones push suspendidas temporalmente mientras Apple aprueba la cuenta. Puedes consultar tus avisos dentro de JAC."
    @Published var noticeID: String?
    @Published var message: String?
    @Published private(set) var enabled: Bool
    @Published private(set) var busy = false
    private var client: PayrollClient?
    private var token: String?
    private let defaults: UserDefaults
    private let permission: any NotificationPermissionProviding
    private let registerRemote: @MainActor () -> Void
    private let unregisterRemote: @MainActor () -> Void
    private let allowsFixture: Bool
    private var generation = 0
    private var registration: Task<Void, Never>?
    init(defaults: UserDefaults = .standard, permission: (any NotificationPermissionProviding)? = nil, allowsFixture: Bool = false, pushAvailable: Bool = JACNotifications.buildSupportsPush, registerRemote: @escaping @MainActor () -> Void = { JACRemoteNotifications.register() }, unregisterRemote: @escaping @MainActor () -> Void = { JACRemoteNotifications.unregister() }) {
        self.pushAvailable = pushAvailable
        self.defaults = defaults; self.permission = permission ?? SystemNotificationPermission(); self.allowsFixture = allowsFixture; self.registerRemote = registerRemote; self.unregisterRemote = unregisterRemote
        enabled = pushAvailable && (defaults.object(forKey: "jac.push.enabled") as? Bool != false)
    }
    static var deviceID: String {
        if let id = UserDefaults.standard.string(forKey: "jac.push.device") { return id }
        let id = UUID().uuidString.lowercased(); UserDefaults.standard.set(id, forKey: "jac.push.device"); return id
    }
    private static func isAuthorized(_ status:UNAuthorizationStatus)->Bool {
        #if os(iOS)
        status == .authorized || status == .provisional || status == .ephemeral
        #else
        status == .authorized || status == .provisional
        #endif
    }
    func bind(_ client: PayrollClient) async {
        guard client.accessUser?.hasNotices != false else {stop();return}
        guard pushAvailable else { return }
        guard allowsFixture || !client.baseURL.host!.hasSuffix(".invalid"), !busy, defaults.object(forKey: "jac.push.enabled") as? Bool != false, let scope = try? client.agendaScope() else { return }
        busy = true; defer { busy = false }
        self.client = client
        let current = generation
        var status = await permission.status()
        guard current == generation, (try? client.agendaScope())?.id == scope.id else { return }
        if status == .notDetermined {
            do { status = try await permission.request() ? .authorized : .denied }
            catch { message = "No se pudo solicitar el permiso. Revisa los ajustes del \(JACDevice.name)."; return }
        }
        guard current == generation, enabled, (try? client.agendaScope())?.id == scope.id else { return }
        if Self.isAuthorized(status) {
            registerRemote(); if let token { await register(token) }
        } else { message = "Permiso desactivado. Puedes permitir las notificaciones de JAC en Ajustes del \(JACDevice.name)." }
    }
    func enable(_ client: PayrollClient) async {
        guard pushAvailable else { return }
        guard !busy else { return }
        defaults.set(true, forKey: "jac.push.enabled"); enabled = true; message = nil
        await bind(client)
    }
    func register(_ token: String) async {
        guard pushAvailable, enabled, defaults.object(forKey: "jac.push.enabled") as? Bool != false else { return }
        self.token = token; guard let client, let scope = try? client.agendaScope() else { return }
        #if DEBUG
        let environment = "sandbox"
        #else
        let environment = "production"
        #endif
        let current = generation, previous = registration
        let task = Task { @MainActor in
            await previous?.value
            guard current == self.generation, self.enabled, (try? client.agendaScope())?.id == scope.id else { return }
            do { try await client.noticeCommand(.object(["action": .string("register"), "id": .string(Self.deviceID), "platform": .string("ios"), "token": .string(token), "environment": .string(environment)])); if current == self.generation { self.message = "Notificaciones activadas en este \(JACDevice.name)." } }
            catch { if current == self.generation { self.message = error.localizedDescription } }
        }
        registration = task; await task.value
    }
    func disable(_ client: PayrollClient) async {
        guard pushAvailable else { return }
        guard !busy else { return }; busy = true; defer { busy = false }
        defaults.set(false, forKey: "jac.push.enabled"); enabled = false; generation += 1
        unregisterRemote(); await registration?.value
        do { try await client.noticeCommand(.object(["action": .string("unregister"), "id": .string(Self.deviceID)])); stop(); message = "Notificaciones desactivadas en este \(JACDevice.name)." }
        catch { message = error.localizedDescription }
    }
    func stop() { generation += 1; client = nil; token = nil; noticeID = nil; if pushAvailable { unregisterRemote() } }
    func received(_ value: String?) { if pushAvailable, let value, UUID(uuidString: value) != nil { noticeID = value.lowercased() } }
}

struct NotificationSettingsView: View {
    @EnvironmentObject private var store: PayrollStore
    @ObservedObject private var push = JACNotifications.shared
    var body: some View {
        List {
            Section("Avisos en este \(JACDevice.name)") {
                if push.pushAvailable {
                    Text("Recibe los itinerarios nuevos y las alertas dirigidas a ti. Las alertas muestran su título y mensaje.")
                    Text(push.enabled ? "Los avisos están permitidos en JAC; también requieren autorización en Ajustes del \(JACDevice.name)." : "Notificaciones desactivadas en este \(JACDevice.name).").font(.footnote).foregroundStyle(.secondary)
                    if let message = push.message { Text(message).font(.footnote).accessibilityIdentifier("notifications.status") }
                    Button("Permitir notificaciones") { Task { await push.enable(store.client) } }.accessibilityIdentifier("notices.enable").disabled(push.busy)
                    Button("Desactivar en este \(JACDevice.name)", role: .destructive) { Task { await push.disable(store.client) } }.accessibilityIdentifier("notices.disable").disabled(push.busy)
                    Button("Abrir Ajustes del \(JACDevice.name)") { JACRemoteNotifications.openSettings() }
                } else {
                    Text(JACNotifications.suspensionMessage).accessibilityIdentifier("notifications.suspended")
                }
            }
        }.jacSurface().navigationTitle("Notificaciones").jacInlineTitle()
    }
}

#if os(iOS)
@MainActor
final class JACPushDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool { if JACNotifications.shared.pushAvailable { UNUserNotificationCenter.current().delegate = self }; return true }
    func application(_ application: UIApplication, handleEventsForBackgroundURLSession identifier: String, completionHandler: @escaping () -> Void) {
        MediaBackgroundTransport.handleEvents(identifier: identifier, completion: completionHandler)
        Task { await MediaUploadQueue.shared.restore(background: true) }
    }
    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) { let value = deviceToken.map { String(format: "%02x", $0) }.joined(); Task { await JACNotifications.shared.register(value) } }
    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) { guard JACNotifications.shared.pushAvailable else { return }; JACNotifications.shared.message = "No se pudo registrar el iPhone. Revisa Push Notifications y la firma de Apple Developer en Xcode." }
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) { completionHandler([.banner, .sound]) }
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) { let value = response.notification.request.content.userInfo["noticeId"] as? String; Task { @MainActor in JACNotifications.shared.received(value) }; completionHandler() }
}

#endif

enum JACRemoteNotifications {
 @MainActor static func register() {
 #if os(iOS)
 UIApplication.shared.registerForRemoteNotifications()
 #endif
 }
 @MainActor static func unregister() {
 #if os(iOS)
 UIApplication.shared.unregisterForRemoteNotifications()
 #endif
 }
 @MainActor static func openSettings() {
 #if os(iOS)
 if let url=URL(string:UIApplication.openSettingsURLString) {UIApplication.shared.open(url)}
 #else
 if let url=URL(string:"x-apple.systempreferences:com.apple.Notifications-Settings.extension") {NSWorkspace.shared.open(url)}
 #endif
 }
}
