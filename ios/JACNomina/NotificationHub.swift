import SwiftUI
import UIKit
import UserNotifications

@MainActor
final class JACNotifications: ObservableObject {
    static let shared = JACNotifications()
    @Published var noticeID: String?
    @Published var message: String?
    private var client: PayrollClient?
    private var token: String?
    static var deviceID: String {
        if let id = UserDefaults.standard.string(forKey: "jac.push.device") { return id }
        let id = UUID().uuidString.lowercased(); UserDefaults.standard.set(id, forKey: "jac.push.device"); return id
    }
    func bind(_ client: PayrollClient) async {
        guard !client.baseURL.host!.hasSuffix(".invalid"), UserDefaults.standard.object(forKey: "jac.push.enabled") as? Bool != false else { return }
        self.client = client
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        if settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional { UIApplication.shared.registerForRemoteNotifications(); if let token { await register(token) } }
    }
    func enable(_ client: PayrollClient) async {
        self.client = client; message = nil; UserDefaults.standard.set(true, forKey: "jac.push.enabled")
        do {
            guard try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) else { message = "Activa las notificaciones de JAC en Ajustes del iPhone."; return }
            UIApplication.shared.registerForRemoteNotifications()
            if let token { await register(token) }
        } catch { message = "No se pudo solicitar el permiso. Revisa los ajustes del iPhone." }
    }
    func register(_ token: String) async {
        self.token = token; guard let client else { return }
        #if DEBUG
        let environment = "sandbox"
        #else
        let environment = "production"
        #endif
        do { try await client.noticeCommand(.object(["action": .string("register"), "id": .string(Self.deviceID), "platform": .string("ios"), "token": .string(token), "environment": .string(environment)])); message = "Notificaciones activadas en este iPhone." }
        catch { message = error.localizedDescription }
    }
    func disable(_ client: PayrollClient) async {
        do { try await client.noticeCommand(.object(["action": .string("unregister"), "id": .string(Self.deviceID)])); UserDefaults.standard.set(false, forKey: "jac.push.enabled"); stop(); message = "Notificaciones desactivadas en este iPhone." }
        catch { message = error.localizedDescription }
    }
    func stop() { client = nil; token = nil; noticeID = nil; UIApplication.shared.unregisterForRemoteNotifications() }
    func received(_ value: String?) { if let value, UUID(uuidString: value) != nil { noticeID = value.lowercased() } }
}

@MainActor
final class JACPushDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool { UNUserNotificationCenter.current().delegate = self; return true }
    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) { let value = deviceToken.map { String(format: "%02x", $0) }.joined(); Task { await JACNotifications.shared.register(value) } }
    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) { JACNotifications.shared.message = "No se pudo registrar el iPhone. Revisa Push Notifications y la firma de Apple Developer en Xcode." }
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) { completionHandler([.banner, .sound]) }
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) { let value = response.notification.request.content.userInfo["noticeId"] as? String; Task { @MainActor in JACNotifications.shared.received(value) }; completionHandler() }
}
