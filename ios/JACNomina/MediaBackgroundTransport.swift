#if os(iOS)
import Foundation
import CryptoKit
import UIKit

// A background session owns the bytes, not the gallery view. Its task
// descriptions contain only a digest; capabilities remain in URLSession.
@MainActor final class MediaBackgroundTransport: NSObject, MediaUploadTransporting {
    nonisolated static let sessionIdentifier = "co.jacmusic.nomina.media-upload.v1"
    private static var instances: [String: MediaBackgroundTransport] = [:]
    private static var completions: [String: () -> Void] = [:]
    private let identifier: String
    private let root: URL
    private let origin: URL
    private let injectedConfiguration: URLSessionConfiguration?
    private var recovery: Task<Void, Never>?
    private var records: [String: Record] = [:]
    private var finished: [String: Result<(Data, URLResponse), Error>] = [:]
    private var processingLease: UIBackgroundTaskIdentifier = .invalid
    private var epoch = 0
    private lazy var session: URLSession = {
        let config = injectedConfiguration ?? URLSessionConfiguration.background(withIdentifier: identifier)
        config.httpCookieStorage = nil; config.httpShouldSetCookies = false
        config.urlCache = nil; config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.timeoutIntervalForRequest = 120; config.timeoutIntervalForResource = 24 * 60 * 60
        config.httpMaximumConnectionsPerHost = 3
        if injectedConfiguration == nil { config.isDiscretionary = false; config.sessionSendsLaunchEvents = true; config.waitsForConnectivity = true }
        return URLSession(configuration: config, delegate: forwardingDelegate, delegateQueue: nil)
    }()
    private lazy var forwardingDelegate = MediaBackgroundDelegate(owner: self)
    private final class Record {
        let task: URLSessionUploadTask
        let body: URL
        var data = Data()
        var failure: Error?
        var continuation: CheckedContinuation<(Data, URLResponse), Error>?
        var progress: (@MainActor (Int64) -> Void)?
        init(task: URLSessionUploadTask, body: URL) { self.task = task; self.body = body }
    }
    init(identifier: String = MediaBackgroundTransport.sessionIdentifier, root: URL, origin: URL = PayrollClient.productionURL, configuration: URLSessionConfiguration? = nil) {
        self.identifier = identifier; self.root = root; self.origin = origin; self.injectedConfiguration = configuration
        super.init()
        Self.instances[identifier] = self
    }
    static func handleEvents(identifier: String, completion: @escaping () -> Void) {
        guard identifier == sessionIdentifier else { completion(); return }
        completions[identifier] = completion
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("JACMediaUploadOutbox/transport", isDirectory: true)
        let transport = shared(root: root, origin: PayrollClient.productionURL)
        Task { await transport.reconnect() }
    }
    static func shared(root: URL, origin: URL) -> MediaBackgroundTransport {
        if let existing = instances[sessionIdentifier], existing.root == root, existing.origin == origin { return existing }
        return MediaBackgroundTransport(root: root, origin: origin)
    }
    static func finishUnclaimedEvents() async {
        guard completions[sessionIdentifier] != nil, let transport = instances[sessionIdentifier] else { return }
        transport.cancelAll()
        await transport.reconnect()
        finishEvents(sessionIdentifier)
    }
    func reconnect() async {
        if let recovery { await recovery.value; return }
        let generation = epoch
        let task = Task { [self] in
            let tasks = await session.allTasks
            for task in tasks {
                guard generation == epoch else { return }
                guard let upload = task as? URLSessionUploadTask, let key = upload.taskDescription,
                      key.range(of: "^[a-f0-9]{64}$", options: .regularExpression) != nil,
                      let request = upload.originalRequest, Self.allowed(request, origin: origin),
                      FileManager.default.fileExists(atPath: bodyURL(key).path) else { task.cancel(); continue }
                if records[key] == nil { records[key] = Record(task: upload, body: bodyURL(key)) }
            }
        }
        recovery = task
        await task.value
    }
    private func bodyURL(_ key: String) -> URL { root.appendingPathComponent(key + ".body") }
    static func allowed(_ request: URLRequest, origin: URL) -> Bool {
        guard let url = request.url, let p = URLComponents(url: url, resolvingAgainstBaseURL: false), p.scheme == "https", p.port == nil,
              p.user == nil, p.password == nil, p.fragment == nil, ["POST", "PUT"].contains(request.httpMethod ?? "") else { return false }
        if p.host == origin.host {
            guard p.path == "/api/media/upload", request.value(forHTTPHeaderField: "Origin") == origin.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/")),
                  request.value(forHTTPHeaderField: "Cookie")?.range(of: "^__Host-jac_session=[A-Za-z0-9_-]{43}$", options: .regularExpression) != nil,
                  request.value(forHTTPHeaderField: "Authorization") == nil else { return false }
            return true
        }
        guard request.httpMethod == "PUT", p.host?.range(of: "^[a-f0-9]{32}\\.r2\\.cloudflarestorage\\.com$", options: .regularExpression) != nil,
              p.path.range(of: "^/jac-fotografia/originals/[a-f0-9-]{36}$", options: .regularExpression) != nil,
              ["Cookie", "Authorization", "Origin", "Referer"].allSatisfy({ request.value(forHTTPHeaderField: $0) == nil }) else { return false }
        return true // PayrollClient additionally validates every signed field.
    }
    func send(_ request: URLRequest, body: Data, key: String, progress: @escaping @MainActor (Int64) -> Void) async throws -> (Data, URLResponse) {
        guard Self.allowed(request, origin: origin), !body.isEmpty, body.count <= 8 * 1024 * 1024 else { throw APIError.invalid("La transferencia en segundo plano no es válida.") }
        await reconnect()
        try Task.checkCancellation()
        let generation = epoch
        let digest = SHA256.hash(data: Data(key.utf8) + body).map { String(format: "%02x", $0) }.joined()
        if let result = finished.removeValue(forKey: digest) { return try result.get() }
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                guard generation == epoch, !Task.isCancelled else { continuation.resume(throwing: CancellationError()); return }
                do {
                    let record: Record
                    if let existing = records[digest] { record = existing }
                    else {
                        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true, attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
                        var directory = root; var values = URLResourceValues(); values.isExcludedFromBackup = true; try directory.setResourceValues(values)
                        let file = bodyURL(digest)
                        try body.write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
                        var upload = request; upload.httpBody = nil; upload.httpShouldHandleCookies = false
                        let task = session.uploadTask(with: upload, fromFile: file)
                        task.taskDescription = digest
                        task.countOfBytesClientExpectsToSend = Int64(body.count)
                        record = Record(task: task, body: file); records[digest] = record
                    }
                    guard record.continuation == nil else { throw APIError.conflict("Esta transferencia ya está en curso.") }
                    record.continuation = continuation; record.progress = progress
                    record.task.resume()
                    finishProcessing()
                } catch { continuation.resume(throwing: error) }
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                guard let self, generation == self.epoch else { return }
                self.cancel(digest)
            }
        }
    }
    private func cancel(_ key: String) {
        guard let record = records.removeValue(forKey: key) else { return }
        record.task.cancel(); record.progress = nil
        record.continuation?.resume(throwing: CancellationError()); record.continuation = nil
        try? FileManager.default.removeItem(at: record.body)
    }
    func cancelAll() {
        epoch += 1; recovery?.cancel(); recovery = nil
        Array(records.keys).forEach(cancel); finished = [:]
        // A later enqueue must wait for this snapshot/cancellation to finish;
        // otherwise getAllTasks could inadvertently cancel the new batch.
        recovery = Task { [self] in
            let tasks = await session.allTasks
            tasks.forEach { $0.cancel() }
        }
        try? FileManager.default.removeItem(at: root)
        finishProcessing()
    }
    fileprivate func report(_ task: URLSessionTask, sent: Int64) {
        guard let key = task.taskDescription, let record = records[key], record.task.taskIdentifier == task.taskIdentifier else { return }; record.progress?(sent)
    }
    fileprivate static func finishEvents(_ identifier: String) { completions.removeValue(forKey: identifier)?() }
    func finishProcessing() {
        if processingLease != .invalid { UIApplication.shared.endBackgroundTask(processingLease); processingLease = .invalid }
    }
    fileprivate func complete(_ task: URLSessionTask, data: Data, error: Error?) {
        guard let key = task.taskDescription, key.range(of: "^[a-f0-9]{64}$", options: .regularExpression) != nil else { return }
        if let existing = records[key], existing.task.taskIdentifier != task.taskIdentifier { return }
        if records[key] == nil, (error as? URLError)?.code == .cancelled { return }
        let record = records.removeValue(forKey: key)
        guard record != nil || FileManager.default.fileExists(atPath: bodyURL(key).path) else { return }
        // Give the delegate's consumer time to confirm and enqueue its next
        // background request. This is finite processing time, not a fake daemon.
        if processingLease == .invalid {
            processingLease = UIApplication.shared.beginBackgroundTask(withName: "Confirmar subida JAC") { [weak self] in Task { @MainActor in self?.finishProcessing() } }
        }
        record?.progress = nil; try? FileManager.default.removeItem(at: record?.body ?? bodyURL(key))
        let result: Result<(Data, URLResponse), Error>
        if let failure = error { result = .failure(failure) }
        else if let response = task.response { result = .success((data, response)) }
        else { result = .failure(URLError(.badServerResponse)) }
        if let continuation = record?.continuation { continuation.resume(with: result) }
        else { finished[key] = result }
    }
}

// Accumulate response bytes on the serial delegate queue before hopping to
// MainActor. This preserves data/completion ordering even during relaunch.
private final class MediaBackgroundDelegate: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    weak var owner: MediaBackgroundTransport?
    private var data: [Int: Data] = [:]
    private var failures: [Int: Error] = [:]
    init(owner: MediaBackgroundTransport) { self.owner = owner }
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive bytes: Data) {
        let id = dataTask.taskIdentifier
        guard (data[id]?.count ?? 0) + bytes.count <= 1024 * 1024 else {
            failures[id] = APIError.invalid("La respuesta de subida es demasiado grande."); dataTask.cancel(); return
        }
        data[id, default: Data()].append(bytes)
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, didSendBodyData bytesSent: Int64, totalBytesSent: Int64, totalBytesExpectedToSend: Int64) {
        Task { @MainActor [weak owner] in owner?.report(task, sent: totalBytesSent) }
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        let bytes = data.removeValue(forKey: task.taskIdentifier) ?? Data()
        let failure = failures.removeValue(forKey: task.taskIdentifier) ?? error
        Task { @MainActor [weak owner] in owner?.complete(task, data: bytes, error: failure) }
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        Task { @MainActor in MediaBackgroundTransport.finishEvents(session.configuration.identifier ?? "") }
    }
}
#endif
