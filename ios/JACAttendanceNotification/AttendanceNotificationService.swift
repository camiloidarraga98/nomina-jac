import Foundation
import UserNotifications

private final class SameHostSession: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

final class AttendanceNotificationService: UNNotificationServiceExtension {
    private struct Delivery {
        let content: UNMutableNotificationContent
        let deliver: (UNNotificationContent) -> Void
    }
    private let state = DispatchQueue(label: "co.jacmusic.attendance.notification")
    private var pending = [UUID: Delivery]()
    private let configuration: URLSessionConfiguration

    override convenience init() { self.init(configuration: .ephemeral) }

    init(configuration: URLSessionConfiguration) {
        configuration.httpShouldSetCookies = false
        configuration.urlCache = nil
        configuration.urlCredentialStorage = nil
        configuration.timeoutIntervalForResource = 10
        self.configuration = configuration
        super.init()
    }

    override func didReceive(_ request: UNNotificationRequest,
                             withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void) {
        guard let content = request.content.mutableCopy() as? UNMutableNotificationContent else {
            contentHandler(request.content)
            return
        }
        let grant = content.userInfo.removeValue(forKey: "photoGrant") as? String
        guard content.userInfo["kind"] as? String == "alert",
              let rawID = content.userInfo["noticeId"] as? String, let id = UUID(uuidString: rawID),
              let grant, grant.range(of: #"^[A-Fa-f0-9-]{36}\.[0-9]{10}\.[A-Za-z0-9_-]{43}$"#, options: .regularExpression) != nil,
              let url = URL(string: "https://jhonalexcastano.com/api/team-attendance/notification-photo?id=" + id.uuidString.lowercased())
        else { contentHandler(content); return }

        let deliveryID = UUID()
        state.sync { pending[deliveryID] = Delivery(content: content, deliver: contentHandler) }
        var photo = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 8)
        photo.setValue("JAC-Photo " + grant, forHTTPHeaderField: "Authorization")
        let session = URLSession(configuration: configuration, delegate: SameHostSession(), delegateQueue: nil)
        session.dataTask(with: photo) { data, response, error in
            let http = response as? HTTPURLResponse
            let valid = error == nil && http?.statusCode == 200 && http?.mimeType == "image/jpeg"
            self.finish(deliveryID, portrait: valid ? data : nil)
        }.resume()
        session.finishTasksAndInvalidate()
    }

    private func finish(_ id: UUID, portrait: Data?) {
        state.sync {
            guard let item = pending.removeValue(forKey: id) else { return }
            if let data = portrait, (4...96 * 1024).contains(data.count),
               data.starts(with: [0xff, 0xd8]), data.suffix(2).elementsEqual([0xff, 0xd9]) {
                let url = FileManager.default.temporaryDirectory.appendingPathComponent(id.uuidString + ".jpg")
                do {
                    try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
                    item.content.attachments = [try UNNotificationAttachment(identifier: "marcacion", url: url, options: nil)]
                } catch {
                    try? FileManager.default.removeItem(at: url)
                }
            }
            item.deliver(item.content)
        }
    }

    override func serviceExtensionTimeWillExpire() {
        state.sync {
            for item in pending.values { item.deliver(item.content) }
            pending.removeAll()
        }
    }
}
