#if os(iOS)
import SwiftUI
import WebKit
import CryptoKit

struct AttendanceIdentity: Codable, Equatable {
    let id: String
    let role: String
    let name: String
}

private enum AttendanceFailure: LocalizedError {
    case invalid
    var errorDescription: String? { "La sesión o la operación de Asistencia no es válida." }
}

/// The bundle ships exactly the web interface tested against the JAC Worker.
/// WebKit has no session cookie or remote navigation. Only this bridge talks to JAC.
struct AttendanceView: UIViewRepresentable {
    @EnvironmentObject var store: PayrollStore
    let account: String

    func makeCoordinator() -> Coordinator { Coordinator(store: store, account: account) }
    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        config.userContentController.addScriptMessageHandler(context.coordinator, contentWorld: .page, name: "attendance")
        let view = WKWebView(frame: .zero, configuration: config)
        view.navigationDelegate = context.coordinator
        if let file = Bundle.main.url(forResource: "index", withExtension: "html", subdirectory: "attendance") {
            view.loadFileURL(file, allowingReadAccessTo: file.deletingLastPathComponent())
        }
        return view
    }
    func updateUIView(_ view: WKWebView, context: Context) {}
    static func dismantleUIView(_ view: WKWebView, coordinator: Coordinator) {
        view.stopLoading()
        view.configuration.userContentController.removeScriptMessageHandler(forName: "attendance", contentWorld: .page)
    }

    @MainActor final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandlerWithReply {
        let store: PayrollStore
        let account: String
        private let local: AttendanceStorage
        init(store: PayrollStore, account: String) {
            self.store = store
            self.account = account
            self.local = AttendanceStorage(origin: store.client.baseURL.absoluteString, account: account)
        }
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            let index = Bundle.main.url(forResource: "index", withExtension: "html", subdirectory: "attendance")
            decisionHandler(index != nil && navigationAction.request.url?.standardizedFileURL == index?.standardizedFileURL ? .allow : .cancel)
        }
        private var allowed: Bool {
            guard (try? store.client.hasSession()) == true else { return false }
            return store.attendanceKiosk?.id == account
        }
        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage,
                                   replyHandler: @escaping (Any?, String?) -> Void) {
            guard allowed, message.frameInfo.isMainFrame, message.frameInfo.request.url?.isFileURL == true,
                  let body = message.body as? [String: Any] else { replyHandler(nil, "Acceso no disponible."); return }
            Task { @MainActor in
                do {
                    switch body["action"] as? String {
                    case "account": replyHandler(account, nil)
                    case "logout": await store.signOut(); replyHandler(true, nil)
                    case "storage":
                        guard body["account"] as? String == account, let op = body["op"] as? String,
                              let key = body["key"] as? String, key.utf8.count < 160 else { throw AttendanceFailure.invalid }
                        // Encode before crossing queues. The queue serializes writes from every scene.
                        let input = try JSONSerialization.data(withJSONObject: body["value"] ?? NSNull(), options: [.fragmentsAllowed])
                        let output = try await local.access(op: op, key: key, input: input)
                        guard allowed else { throw AttendanceFailure.invalid }
                        replyHandler(try JSONSerialization.jsonObject(with: output, options: [.fragmentsAllowed]), nil)
                    case "api":
                        guard let command = body["command"] as? String else { throw AttendanceFailure.invalid }
                        let data: Data?
                        if command == "session" {
                            guard body["body"] == nil || body["body"] is NSNull else { throw AttendanceFailure.invalid }
                            data = nil
                        } else {
                            guard let payload = body["body"] as? [String: Any] else { throw AttendanceFailure.invalid }
                            data = try JSONSerialization.data(withJSONObject: payload)
                        }
                        let (response, status) = try await store.client.attendanceRequest(command: command, data: data, ticket: body["ticket"] as? String)
                        guard allowed else { throw AttendanceFailure.invalid }
                        let result = try JSONSerialization.jsonObject(with: response)
                        replyHandler(["status": status, "data": result], nil)
                        if status == 401 { await store.signOut() }
                    default: throw AttendanceFailure.invalid
                    }
                } catch { replyHandler(nil, error.localizedDescription) }
            }
        }
    }
}

private struct AttendanceStorage: Sendable {
    private static let queue = DispatchQueue(label: "co.jacmusic.asistencia.storage", qos: .utility)
    private let partition: String
    init(origin: String, account: String) {
        partition = SHA256.hash(data: Data((origin + "/" + account).utf8)).map { String(format: "%02x", $0) }.joined()
    }
    func access(op: String, key: String, input: Data) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            Self.queue.async {
                do { continuation.resume(returning: try transact(op: op, key: key, input: input)) }
                catch { continuation.resume(throwing: error) }
            }
        }
    }
    private func transact(op: String, key: String, input: Data) throws -> Data {
        let fm = FileManager.default
        var directory = try fm.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true).appendingPathComponent("JACAsistencia", isDirectory: true)
        try fm.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.protectionKey: FileProtectionType.complete])
        var protection = URLResourceValues()
        protection.isExcludedFromBackup = true
        try directory.setResourceValues(protection)
        let file = directory.appendingPathComponent(partition + ".json")
        var records: [String: Any] = [:]
        if fm.fileExists(atPath: file.path) {
            guard let decoded = try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any] else { throw AttendanceFailure.invalid }
            records = decoded
        }
        let value = try JSONSerialization.jsonObject(with: input, options: [.fragmentsAllowed])
        var result: Any = NSNull()
        switch op {
        case "read": result = records[key] ?? NSNull()
        case "list": result = records.filter { $0.key.hasPrefix(key) }.map(\.value)
        case "device":
            result = records[key] ?? value
            records[key] = result
        case "write": records[key] = value
        case "delete": records.removeValue(forKey: key)
        case "enqueue":
            guard let row = value as? [String: Any], let employee = row["employee"] as? String,
                  let movement = row["movement"] as? String, let time = row["device_time"] as? String else { throw AttendanceFailure.invalid }
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            guard let now = formatter.date(from: time) else { throw AttendanceFailure.invalid }
            let previous = "last/" + employee + "/" + movement
            if let old = records[previous] as? String, let date = formatter.date(from: old), abs(now.timeIntervalSince(date)) < 3 {
                result = false
            } else {
                guard records[key] == nil else { throw AttendanceFailure.invalid }
                records[key] = value; records[previous] = time; result = true
            }
        default: throw AttendanceFailure.invalid
        }
        if op != "read" && op != "list" {
            try JSONSerialization.data(withJSONObject: records).write(to: file, options: [.atomic, .completeFileProtection])
        }
        return try JSONSerialization.data(withJSONObject: result, options: [.fragmentsAllowed])
    }
}
#endif
