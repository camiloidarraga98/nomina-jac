import Foundation
import Combine

enum APIError: LocalizedError {
    case unauthorized
    case message(String)
    case conflict(String)
    case invalid(String)
    case forbidden(String)
    var errorDescription: String? {
        switch self {
        case .unauthorized: return "Tu sesión venció o cambió tu acceso. Inicia sesión de nuevo."
        case .message(let message): return message
        case .conflict(let message): return message
        case .invalid(let message): return message
        case .forbidden(let message): return message
        }
    }
}

// These are display fields confirmed on the Wallet preparation screen. The
// airline's barcode remains a separate, immutable value from the source file.
extension BoardingWalletDetails {
    var validationMessage:String? {
        let fields:[(String,String,Int)]=[("Nombre",passenger,120),("Origen",origin,100),("Destino",destination,100),("Silla",seat,6)]
        for (label,value,limit) in fields {
            if value.trimmingCharacters(in:.whitespacesAndNewlines).utf16.count>limit || value.rangeOfCharacter(from:.controlCharacters) != nil {
                return "Revisa el campo \(label.lowercased())."
            }
        }
        for value in [departureTime,boardingTime] {
            let time=value.trimmingCharacters(in:.whitespacesAndNewlines)
            if !time.isEmpty && time.range(of:"^(?:[01][0-9]|2[0-3]):[0-5][0-9]$",options:.regularExpression) == nil {
                return "Escribe las horas en formato de 24 horas, por ejemplo 08:30."
            }
        }
        let selectedSeat=seat.trimmingCharacters(in:.whitespacesAndNewlines).uppercased()
        if !selectedSeat.isEmpty && selectedSeat.range(of:"^(?=.*[1-9A-Z])[A-Z0-9]{1,6}$",options:.regularExpression) == nil {
            return "Revisa la silla asignada, por ejemplo 12A."
        }
        return nil
    }
    func walletRequestFields() throws -> [String:JSONValue] {
        if let validationMessage {throw APIError.invalid(validationMessage)}
        let trim:(String)->String={$0.trimmingCharacters(in:.whitespacesAndNewlines)}
        // Explicit blanks are intentional omissions, not requests to restore a
        // suggestion that the user has removed.
        return ["passenger":.string(trim(passenger)),"origin":.string(trim(origin)),"destination":.string(trim(destination)),
                "departureTime":.string(trim(departureTime)),"boardingTime":.string(trim(boardingTime)),"seat":.string(trim(seat).uppercased())]
    }
}

struct MediaFileRemoved: LocalizedError {
    var errorDescription: String? { "Esta foto o video ya no está disponible. Actualiza la carpeta." }
}

private final class NoRedirects: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        // Never forward payroll credentials to a redirect destination.
        completionHandler(nil)
    }
}

@MainActor protocol MediaUploadTransporting: AnyObject {
    func send(_ request: URLRequest, body: Data, key: String, progress: @escaping @MainActor (Int64) -> Void) async throws -> (Data, URLResponse)
    func cancelAll()
}

private final class MediaUploadObserver: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    private let callback: @MainActor (Int64) -> Void
    private let lock=NSLock();private var active=true
    init(_ callback:@escaping @MainActor (Int64)->Void){self.callback=callback}
    func stop(){lock.lock();active=false;lock.unlock()}
    private var isActive:Bool{lock.lock();defer{lock.unlock()};return active}
    func urlSession(_ session:URLSession,task:URLSessionTask,didSendBodyData bytesSent:Int64,totalBytesSent:Int64,totalBytesExpectedToSend:Int64){
        Task {@MainActor [self] in if isActive {callback(totalBytesSent)}}
    }
    func urlSession(_ session:URLSession,task:URLSessionTask,willPerformHTTPRedirection response:HTTPURLResponse,newRequest request:URLRequest,completionHandler:@escaping(URLRequest?)->Void){completionHandler(nil)}
}

private struct MediaDownloadResponseFailure: Error { let response: URLResponse }

final class MediaDownloadProgressObserver: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let total: Int64
    private let callback: @MainActor (Int64, Int64) -> Void
    private let lock = NSLock()
    private var active = true
    private var started = false
    private var finished = false
    private var task: URLSessionDownloadTask?
    private var continuation: CheckedContinuation<(ExportedDocument, URLResponse), Error>?
    private var pendingDocument: ExportedDocument?
    private var pendingResponse: URLResponse?
    init(total: Int64, callback: @escaping @MainActor (Int64, Int64) -> Void) {
        self.total = total; self.callback = callback
    }
    func download(session: URLSession, request: URLRequest) async throws -> (ExportedDocument, URLResponse) {
        try Task.checkCancellation()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let task = session.downloadTask(with: request)
                task.delegate = self
                lock.lock()
                guard active, !started, !finished else {
                    lock.unlock(); task.cancel(); continuation.resume(throwing: CancellationError()); return
                }
                started = true; self.task = task; self.continuation = continuation
                lock.unlock()
                task.resume()
            }
        } onCancel: { self.stop() }
    }
    func stop() { finish(error: CancellationError()) }
    private var isActive: Bool { lock.lock(); defer { lock.unlock() }; return active }
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard isActive else { return }
        guard totalBytesWritten >= 0, totalBytesWritten <= total else {
            if let response = downloadTask.response as? HTTPURLResponse, !(200..<300).contains(response.statusCode) {
                finish(error: MediaDownloadResponseFailure(response: response))
            } else { finish(error: APIError.invalid("La descarga supera el tamaño esperado del archivo.")) }
            return
        }
        if let response = downloadTask.response as? HTTPURLResponse, !(200..<300).contains(response.statusCode) { return }
        Task { @MainActor [self] in if isActive { callback(totalBytesWritten, total) } }
    }
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        lock.lock()
        guard active, !finished, task === downloadTask else { lock.unlock(); return }
        do {
            // URLSession removes this URL when the callback returns. Claim it
            // now, then wait for didCompleteWithError before exposing a result.
            pendingDocument = try TemporaryDocuments.move(location, filename: "incoming.bin")
            pendingResponse = downloadTask.response
            lock.unlock()
        } catch { lock.unlock(); finish(error: error) }
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) { finish(error: error) }
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
    private func finish(error: Error?) {
        lock.lock()
        guard !finished else { lock.unlock(); return }
        finished = true; active = false
        let continuation = self.continuation, task = self.task
        let document = pendingDocument, response = pendingResponse
        self.continuation = nil; self.task = nil; pendingDocument = nil; pendingResponse = nil
        lock.unlock()
        if let error {
            task?.cancel()
            if let document { TemporaryDocuments.remove(document) }
            continuation?.resume(throwing: error)
        } else if let document, let response { continuation?.resume(returning: (document, response)) }
        else {
            if let document { TemporaryDocuments.remove(document) }
            continuation?.resume(throwing: APIError.message("La descarga no terminó correctamente."))
        }
    }
}

private struct CachedNoticeWrapper: Decodable { let item: JACNotice }
private struct OfflineSaveResult: @unchecked Sendable { let changed: Bool; let notices: [JACNotice]; let calendarDisconnected: Bool }

@MainActor
final class PayrollClient: ObservableObject {
    nonisolated static let productionURL = URL(string: "https://jhonalexcastano.com")!
    let baseURL: URL
    private let vault: SessionStoring
    private let session: URLSession
    private let mediaSession: URLSession
    private let mediaUploadTransport: MediaUploadTransporting?
    private let decoder = JSONDecoder()
    let offlineCache: OfflineResponseCache
    let mediaOffline: MediaOfflineCache
    let musicOffline: MediaOfflineCache
    lazy var photoPreviews = MediaPhotoPreviewPipeline(monitorNetwork: baseURL.host?.hasSuffix(".invalid") != true)
    @Published private(set) var usingOfflineCopy = false
    @Published private(set) var cacheRevision = 0
    @Published private(set) var offlineSyncMessage: String?
    @Published private(set) var syncingOffline = false
    var onSessionInvalidated: (() -> Void)?
    private var syncTask: Task<Void, Never>?
    private var storageFailures = 0
    private var lastOfflineSync: (generation: Int, version: Int, at: Date)?
    private var rememberedWorkspace: (scope: String, generation: Int, bytes: Data)?
    private var crmGeneration = 0
    private var deletedContractIDs = Set<String>()
    private var contractDocuments: [String: [ExportedDocument]] = [:]
    private var cacheGeneration = 0
    private var derivedOfflineScope: (token: String, scope: AgendaCacheScope)?
    private var derivedAgendaScope: (token: String, scope: AgendaCacheScope)?
    private struct DecodedEntry { let value: Any; let cost: Int }
    private var decodedResponses: [String: DecodedEntry] = [:]
    private var decodedOrder: [String] = []
    private var decodedMissing = Set<String>()
    private var decodedResourceKeys: [String: String] = [:]
    private var canonicalNoticeKeys: [String: (generation: Int, key: String)] = [:]
    private var derivedMusicScope: (token: String, scope: AgendaCacheScope)?
    private var decodedBytes = 0
    private var decodedEpoch: (scope: String, value: Int)?
    private var agendaWriteSequence = 0
    private var rememberedAgenda: (scope: String, generation: Int, record: AgendaOfflineRecord)?
    private var cachePersistence: Task<Void, Never>?
    private var derivedMediaScope: (token: String, scope: AgendaCacheScope)?
    // A cheap view identity, not authorization. Network/cache reads continue to
    // check Keychain and permissions before and after their asynchronous work.
    var mediaPresentationRevision: Int { cacheGeneration }
    private var noticeInvalidations: [String: Int] = [:]
    private var musicPlaybackToken: String?
    private var permissionUser: PayrollUser?
    private var mediaRootRead: (id: UUID, stamp: String, task: Task<MediaFeed, Error>)?
    var accessUser: PayrollUser? { permissionUser }
    private let automaticOfflineSync: Bool
    let agendaCache: AgendaOfflineCache
    private var cookieName: String { "__Host-jac_session" }
    private var origin: String { baseURL.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/")) }

    init(baseURL: URL = PayrollClient.productionURL, vault: SessionStoring? = nil, configuration: URLSessionConfiguration = .ephemeral, agendaCache: AgendaOfflineCache? = nil, offlineCache: OfflineResponseCache? = nil, mediaOffline: MediaOfflineCache? = nil, automaticallyDownloadOffline: Bool? = nil, mediaUploadTransport: MediaUploadTransporting? = nil) {
        precondition(baseURL.scheme == "https" && baseURL.host != nil && baseURL.path.isEmpty && baseURL.user == nil && baseURL.query == nil)
        self.baseURL = baseURL
        self.vault = vault ?? KeychainSessionStore(account: baseURL.host!)
        self.mediaUploadTransport = mediaUploadTransport
        self.musicOffline = MediaOfflineCache(root: baseURL.host!.hasSuffix(".invalid") ? FileManager.default.temporaryDirectory.appendingPathComponent("music-fixture-" + UUID().uuidString) : FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("JACMusicOffline", isDirectory: true))
        self.agendaCache = agendaCache ?? AgendaOfflineCache()
        self.automaticOfflineSync = automaticallyDownloadOffline ?? !baseURL.host!.hasSuffix(".invalid")
        self.offlineCache = offlineCache ?? OfflineResponseCache(root: baseURL.host!.hasSuffix(".invalid") ? FileManager.default.temporaryDirectory.appendingPathComponent("offline-fixture-" + UUID().uuidString) : nil)
        self.mediaOffline = mediaOffline ?? MediaOfflineCache(root: baseURL.host!.hasSuffix(".invalid") ? FileManager.default.temporaryDirectory.appendingPathComponent("media-fixture-" + UUID().uuidString) : nil)
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 60
        session = URLSession(configuration: configuration, delegate: NoRedirects(), delegateQueue: nil)
        let mediaConfiguration = configuration.copy() as! URLSessionConfiguration
        mediaConfiguration.timeoutIntervalForRequest = 120
        mediaConfiguration.timeoutIntervalForResource = 2 * 60 * 60
        mediaSession = URLSession(configuration: mediaConfiguration, delegate: NoRedirects(), delegateQueue: nil)
        if let token = try? self.checkedToken(), token.range(of: "^[A-Za-z0-9_-]{43}$", options: .regularExpression) != nil { self.offlineCache.removeOtherSessions(OfflineResponseCache.scope(origin: baseURL.absoluteString, token: token)) }
        permissionUser = rawCachedWorkspace()?.user ?? cachedAgenda()?.user
        if let scope = try? musicScope() { musicOffline.removeOtherSessions(scope) }
        // Prepare the checked presentation scope once during startup, including
        // a cold offline restore. Cells never derive keys or read Keychain.
        if let scope = try? mediaScope() { self.mediaOffline.removeOtherSessions(scope) }
    }

    private func invalidateWidgetSnapshot() {
        #if os(iOS)
        JACWidgetBridge.shared.invalidate()
        #endif
    }
    func hasSession() throws -> Bool { try checkedToken() != nil }
    private func clearDecodedResponses() { decodedResponses.removeAll(keepingCapacity: true); decodedOrder.removeAll(keepingCapacity: true); decodedMissing.removeAll(keepingCapacity: true); decodedResourceKeys.removeAll(keepingCapacity: true); canonicalNoticeKeys.removeAll(keepingCapacity: true); decodedBytes = 0 }
    // Revalidated at startup, foreground and before/after asynchronous work.
    // Display accessors use these snapshots, never Keychain from a SwiftUI body.
    private func checkedToken() throws -> String? {
        JACPerformanceDiagnostics.record(.sessionRead)
        let token: String?
        do { token = try vault.load() } catch { if !SessionStoreFailure.isProtectedDataUnavailable(error), derivedOfflineScope != nil || permissionUser != nil { invalidateWidgetSnapshot() }; clearDecodedResponses(); rememberedAgenda = nil; derivedOfflineScope = nil; derivedAgendaScope = nil; derivedMediaScope = nil; derivedMusicScope = nil; throw error }
        // A newly created secondary client has no widget ownership. The
        // primary lifecycle clears a missing cold-start session; a previously
        // known user still invalidates here, even after a temporary lock.
        if token == nil, derivedOfflineScope != nil || permissionUser != nil { invalidateWidgetSnapshot() }
        if derivedOfflineScope?.token != token {
            if derivedOfflineScope != nil, token != nil { invalidateWidgetSnapshot() }
            clearDecodedResponses(); rememberedWorkspace = nil; rememberedAgenda = nil
            derivedOfflineScope = nil; derivedAgendaScope = nil; derivedMediaScope = nil; derivedMusicScope = nil
        }
        return token
    }
    var agendaPresentationScopeID: String? { derivedAgendaScope?.scope.id }
    var mediaPresentationStamp: String? { derivedMediaScope.map { $0.scope.id + ":" + String(cacheGeneration) } }
    private func validateDecodedEpoch(_ scope: AgendaCacheScope) {
        let previous = decodedEpoch?.scope == scope.id ? decodedEpoch?.value : nil
        let changes = offlineCache.memoryChanges(scope, since: previous)
        if changes.invalidatesAll { clearDecodedResponses() }
        else if !changes.keys.isEmpty {
            let affected = Set(decodedResourceKeys.compactMap { changes.keys.contains($0.value) ? $0.key : nil })
            for key in affected {
                if let entry = decodedResponses.removeValue(forKey: key) { decodedBytes -= entry.cost }
                decodedMissing.remove(key); decodedResourceKeys.removeValue(forKey: key)
            }
            decodedOrder.removeAll { affected.contains($0) }
            canonicalNoticeKeys = canonicalNoticeKeys.filter { !affected.contains($0.value.key) }
        }
        decodedEpoch = (scope.id, changes.revision)
    }
    private func memoryKey(_ type: Any.Type, key: String, scope: AgendaCacheScope) -> String { scope.id + ":" + String(cacheGeneration) + ":" + String(reflecting: type) + ":" + key }
    private func rememberDecoded<T>(_ value: T, key: String, scope: AgendaCacheScope, cost: Int) {
        validateDecodedEpoch(scope)
        let resource = key
        let key = memoryKey(T.self, key: resource, scope: scope)
        decodedMissing.remove(key); decodedResourceKeys.removeValue(forKey: key)
        if let previous = decodedResponses.removeValue(forKey: key) { decodedBytes -= previous.cost; decodedOrder.removeAll { $0 == key } }
        guard cost <= 8 * 1024 * 1024 else { return }
        while decodedOrder.count >= 256 || decodedBytes + cost > 32 * 1024 * 1024 {
            guard !decodedOrder.isEmpty else { break }
            let oldest = decodedOrder.removeFirst(); decodedResourceKeys.removeValue(forKey: oldest); if let previous = decodedResponses.removeValue(forKey: oldest) { decodedBytes -= previous.cost }
        }
        decodedResponses[key] = DecodedEntry(value: value, cost: cost); decodedResourceKeys[key] = resource; decodedOrder.append(key); decodedBytes += cost
        if let wrapper = value as? CachedNoticeWrapper { canonicalNoticeKeys[wrapper.item.id] = (cacheGeneration, key) }
        if canonicalNoticeKeys.count > 256 { canonicalNoticeKeys = canonicalNoticeKeys.filter { decodedResponses[$0.value.key] != nil } }
    }
    // Only the active upload queue receives this separate Keychain store. The
    // ordinary login item keeps its existing WhenUnlocked protection.
    func makeMediaUploadClient(vault uploadVault: SessionStoring, transport: MediaUploadTransporting?) throws -> PayrollClient {
        guard permissionUser?.canUploadMedia == true, let token = try checkedToken(), token.range(of: "^[A-Za-z0-9_-]{43}$", options: .regularExpression) != nil else { throw APIError.unauthorized }
        try uploadVault.save(token)
        let client = PayrollClient(baseURL: baseURL, vault: uploadVault, automaticallyDownloadOffline: false, mediaUploadTransport: transport)
        client.permissionUser = permissionUser
        return client
    }
    func agendaScope() throws -> AgendaCacheScope? {
        guard let token = try checkedToken(), token.range(of: "^[A-Za-z0-9_-]{43}$", options: .regularExpression) != nil else { return nil }
        if let saved = derivedAgendaScope, saved.token == token { return saved.scope }
        let scope = AgendaCacheScope(origin: origin, token: token); derivedAgendaScope = (token, scope); return scope
    }
    func cachedAgenda() -> AgendaOfflineRecord? {
        guard permissionUser?.hasSection(.calendar) != false else { return nil }
        if let saved = rememberedAgenda, saved.generation == cacheGeneration, saved.scope == agendaPresentationScopeID { return saved.record }
        guard let scope = try? agendaScope(), let record = agendaCache.load(scope), record.user.hasSection(.calendar) else { return nil }
        rememberedAgenda = (scope.id, cacheGeneration, record); return record
    }
    func clearCachedAgenda() { agendaWriteSequence += 1; rememberedAgenda = nil; if let scope = try? agendaScope() { agendaCache.remove(scope) } }
    func saveAgenda(_ record: AgendaOfflineRecord, scope: AgendaCacheScope) throws {
        guard scope.id == (try agendaScope())?.id else { throw CancellationError() }
        agendaWriteSequence += 1
        agendaCache.invalidatePendingWrites(scope)
        try agendaCache.save(record, scope: scope); rememberedAgenda = (scope.id, cacheGeneration, record)
    }
    func saveAgendaInBackground(_ record: AgendaOfflineRecord, scope: AgendaCacheScope) async throws {
        guard scope.id == (try agendaScope())?.id else { throw CancellationError() }
        agendaWriteSequence += 1
        let sequence = agendaWriteSequence
        let generation = cacheGeneration, cache = agendaCache, epoch = agendaCache.epoch(scope), previous = cachePersistence
        let work = Task.detached(priority: .utility) {
            await previous?.value
            try Task.checkCancellation()
            try cache.save(record, scope: scope, expectedEpoch: epoch)
        }
        cachePersistence = Task { _ = try? await work.value }
        try await work.value
        guard generation == cacheGeneration, scope.id == (try agendaScope())?.id, epoch == cache.epoch(scope) else { throw CancellationError() }
        if sequence == agendaWriteSequence { rememberedAgenda = (scope.id, generation, record) }
    }
    func clearSession() throws {
        invalidateWidgetSnapshot()
        #if os(iOS)
        MediaGridThumbnailLoader.shared.clear()
        #endif
        deletedContractIDs=[];contractDocuments=[:]
        mediaRootRead?.task.cancel(); mediaRootRead = nil
        syncTask?.cancel(); syncTask = nil
        cacheGeneration += 1
        clearDecodedResponses(); rememberedWorkspace = nil; rememberedAgenda = nil
        if let scope = try musicScope() { musicOffline.clear(scope) }
        musicPlaybackToken = nil
        permissionUser = nil
        if let scope = try offlineScope() { offlineCache.clear(scope) }
        if let scope = try mediaScope() { mediaOffline.clear(scope) }
        clearCachedAgenda(); try vault.clear(); derivedMediaScope = nil; derivedOfflineScope = nil; derivedAgendaScope = nil; derivedMusicScope = nil; TemporaryDocuments.clear()
        usingOfflineCopy = false; syncingOffline = false; offlineSyncMessage = nil; cacheRevision += 1; onSessionInvalidated?()
    }
    func offlineScope() throws -> AgendaCacheScope? {
        guard let token = try checkedToken(), token.range(of: "^[A-Za-z0-9_-]{43}$", options: .regularExpression) != nil else { return nil }
        if let saved = derivedOfflineScope, saved.token == token { return saved.scope }
        let scope = OfflineResponseCache.scope(origin: origin, token: token); derivedOfflineScope = (token, scope); return scope
    }
    func mediaScope() throws -> AgendaCacheScope? {
        guard let token = try checkedToken() else { derivedMediaScope = nil; return nil }
        if let saved = derivedMediaScope, saved.token == token { return saved.scope }
        guard token.range(of: "^[A-Za-z0-9_-]{43}$", options: .regularExpression) != nil else { derivedMediaScope = nil; return nil }
        let scope = AgendaCacheScope(origin: origin + "/media-offline-v1", token: token)
        derivedMediaScope = (token, scope)
        return scope
    }
    func mediaAccessStamp() throws -> String? { try mediaScope().map { $0.id + ":" + String(cacheGeneration) } }
    func beginOfflineRestore() { usingOfflineCopy = true }
    private func resourceURL(path: String, query: [URLQueryItem]) -> URL {
        var parts = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty { parts.queryItems = query.sorted { ($0.name, $0.value ?? "") < ($1.name, $1.value ?? "") } }
        return parts.url!
    }
    private func resourceKey(_ url: URL, revision: Int = 0) -> String { url.absoluteString + "\nrevision=\(revision)" }
    private func allowsResource(_ path: String, query: [URLQueryItem], body: JSONValue? = nil) -> Bool { Self.allowsResource(permissionUser, path: path, query: query, body: body) }
    nonisolated private static func allowsResource(_ permissionUser: PayrollUser?, path: String, query: [URLQueryItem], body: JSONValue? = nil) -> Bool {
        guard let user=permissionUser else {return true}
        if path == "api/mobile/payroll" {return query.contains{$0.name == "workspace"} || user.hasSection(.payroll)}
        if path.hasPrefix("api/payroll/") || path == "api/mobile/gmail" {return user.hasSection(.payroll)}
        if path.hasPrefix("api/calendar") {return user.hasSection(.calendar)}
        if path.hasPrefix("api/crm") || path == "api/mobile/contracts" || path == "api/users" {return user.hasSection(.crm)}
        if path.hasPrefix("api/expenses") {return user.hasSection(.itineraries)}
        if path.hasPrefix("api/music") {return user.canReadMusic}
        if path.hasPrefix("api/media") {return user.canReadMedia}
        if path == "api/notices/recipients" {return user.isOwner && user.hasSection(.crm)}
        if path == "api/notices/wallet" {return user.hasSection(.boarding)}
        if path == "api/notices", let body, ["register", "unregister"].contains(body["action"].text) { return user.canReceiveNotifications }
        if path.hasPrefix("api/notices") {return query.contains{$0.name == "boarding"} ? user.hasSection(.boarding) : user.hasNotices}
        return true
    }
    private func authorizedNoticeData(_ data: Data, path: String) throws -> Data {
        guard path == "api/notices", let user = permissionUser else { return data }
        JACPerformanceDiagnostics.record(.jsonDecode)
        guard var json = try? decoder.decode(JSONValue.self, from: data) else { return data }
        if !json["item"].fields.isEmpty && !user.permitsNotice(json["item"]["kind"].text) {throw APIError.forbidden("Tu cuenta no tiene acceso a esta sección.")}
        if case .array = json["notices"] {json["notices"] = .array(json["notices"].elements.filter{user.permitsNotice($0["kind"].text)})}
        JACPerformanceDiagnostics.record(.jsonEncode)
        return try JSONEncoder().encode(json)
    }
    private func rawCachedWorkspace() -> PayrollWorkspace? {
        cached(PayrollWorkspace.self, path: "api/mobile/payroll", query: [URLQueryItem(name: "workspace", value: "1")])
    }
    func cached<T: Decodable>(_ type: T.Type, path: String, query: [URLQueryItem] = [], revision: Int = 0) -> T? {
        guard allowsResource(path, query: query) else { return nil }
        guard let scope = derivedOfflineScope?.scope ?? (try? offlineScope()) else { return nil }
        validateDecodedEpoch(scope)
        let key = resourceKey(resourceURL(path: path, query: query), revision: revision)
        let memoKey = memoryKey(type, key: key, scope: scope)
        if let value = decodedResponses[memoKey]?.value as? T { return value }
        if decodedMissing.contains(memoKey) { return nil }
        guard let record = offlineCache.load(scope, key: key), let data = try? authorizedNoticeData(record.data, path: path) else {
            if decodedMissing.count >= 256 {
                for missing in decodedMissing { decodedResourceKeys.removeValue(forKey: missing) }
                decodedMissing.removeAll(keepingCapacity: true)
            }
            decodedMissing.insert(memoKey); decodedResourceKeys[memoKey] = key; return nil
        }
        JACPerformanceDiagnostics.record(.jsonDecode)
        guard let value = try? decoder.decode(type, from: data) else { return nil }
        rememberDecoded(value, key: key, scope: scope, cost: data.count)
        return value
    }
    func cachedWorkspace() -> PayrollWorkspace? { rawCachedWorkspace()?.restrictedForSections }
    func cachedNotices(cursor: String = "", boarding: String? = nil) -> NoticeFeed? {
        guard let first = cached(NoticeFeed.self, path: "api/notices", query: (cursor.isEmpty ? [] : [URLQueryItem(name: "cursor", value: cursor)]) + (boarding.map { [URLQueryItem(name: "boarding", value: $0)] } ?? [])) else { return nil }
        var items = first.notices, next = first.nextCursor
        if usingOfflineCopy, let scope = try? offlineScope() {
            items = []
            for entry in offlineCache.entries(scope) {
                guard let parts = URLComponents(string: entry.url), parts.path == "/api/notices", parts.queryItems?.contains(where: { $0.name == "item" }) != true,
                      (parts.queryItems?.contains(where: { $0.name == "boarding" }) == true) == (boarding != nil),
                      let saved = offlineCache.load(scope, key: entry.key), let page = try? decoder.decode(NoticeFeed.self, from: saved.data) else { continue }
                items += page.notices.filter { permissionUser?.permitsNotice($0.kind) != false }
            }
            if let boarding { items = items.filter { boarding == "history" ? ($0.travelDate ?? "") < BoardingClock.today() : ($0.travelDate ?? "") >= BoardingClock.today() } }
            next = ""
        }
        var unique: [String: JACNotice] = [:], firstSeen: [String: Int] = [:]
        for item in items {
            if firstSeen[item.id] == nil { firstSeen[item.id] = firstSeen.count }
            let latest = cachedNotice(item.id) ?? item
            if (latest.revision ?? 1) >= (unique[item.id]?.revision ?? 0) { unique[item.id] = latest }
        }
        let sorted = unique.values.sorted { lhs, rhs in
            let left = boarding == nil ? lhs.createdAt : lhs.travelDate ?? "", right = boarding == nil ? rhs.createdAt : rhs.travelDate ?? ""
            if left == right { return firstSeen[lhs.id, default: .max] < firstSeen[rhs.id, default: .max] }
            return boarding == nil || boarding == "history" ? left > right : left < right
        }
        return NoticeFeed(notices: sorted, nextCursor: next, settings: first.settings, users: first.users, boardingUsers: first.boardingUsers, today: BoardingClock.today())
    }
    func cachedExpenses() -> TravelExpenseFeed? {
        guard let first = cached(TravelExpenseFeed.self, path: "api/expenses") else { return nil }
        guard usingOfflineCopy, let scope = try? offlineScope() else { return first }
        var items: [String: TravelExpense] = [:]
        for entry in offlineCache.entries(scope) where URL(string: entry.url)?.path == "/api/expenses" {
            guard let saved = offlineCache.load(scope, key: entry.key), let page = try? decoder.decode(TravelExpenseFeed.self, from: saved.data) else { continue }
            for item in page.expenses where item.version >= (items[item.id]?.version ?? 0) { items[item.id] = item }
        }
        return TravelExpenseFeed(expenses: items.values.sorted { $0.expenseDate > $1.expenseDate }, nextCursor: "", reviewer: first.reviewer, employees: first.employees, periods: first.periods)
    }
    func cachedNotice(_ id: String) -> JACNotice? {
        if let scope = derivedOfflineScope?.scope { validateDecodedEpoch(scope) }
        if let entry = canonicalNoticeKeys[id], entry.generation == cacheGeneration, let wrapper = decodedResponses[entry.key]?.value as? CachedNoticeWrapper {
            return permissionUser?.permitsNotice(wrapper.item.kind) == false ? nil : wrapper.item
        }
        return cached(CachedNoticeWrapper.self, path: "api/notices", query: [URLQueryItem(name: "item", value: id)])?.item
    }
    private func cacheable(_ path: String, query: [URLQueryItem]) -> Bool {
        if path == "api/music" { return query.isEmpty }
        if path == "api/calendar" { return !query.contains { $0.name == "action" } }
        return ["api/mobile/payroll", "api/notices", "api/notices/pdf", "api/notices/file", "api/payroll/export", "api/payroll/email", "api/users", "api/expenses", "api/expenses/file", "api/crm", "api/crm/file", "api/mobile/contracts", "api/media"].contains(path)
    }

    private func request(path: String, query: [URLQueryItem] = [], body: JSONValue? = nil, document: Bool = false, forceNetwork: Bool = false, cacheRevision: Int = 0, nativeBearer: Bool = false) async throws -> (Data, HTTPURLResponse) {
        let mediaThumbnailRead = path == "api/media/file" && query.contains { $0.name == "thumbnail" && $0.value == "1" }
        let mediaPreviewRead = path == "api/media/file" && query.contains { $0.name == "preview" && $0.value == "1" }
        guard allowsResource(path,query:query,body:body) else {throw APIError.forbidden("Tu cuenta no tiene acceso a esta sección.")}
        let url = resourceURL(path: path, query: query)
        let key = resourceKey(url, revision: cacheRevision)
        let scope = try offlineScope(), generation = cacheGeneration, crmReadGeneration = crmGeneration
        let canCache = body == nil && cacheable(path, query: query)
        let saved: OfflineResponse?
        if canCache, !forceNetwork, let scope {
            let cache = offlineCache
            saved = await Task.detached(priority: .utility) { cache.load(scope, key: key) }.value
            guard generation == cacheGeneration, scope.id == (try offlineScope())?.id else { throw CancellationError() }
        } else { saved = nil }
        if let saved, let response = saved.response, !forceNetwork, usingOfflineCopy { return (try authorizedNoticeData(saved.data,path:path), response) }
        if usingOfflineCopy, body == nil, !forceNetwork, saved == nil { throw APIError.message("Este contenido todavía no está descargado. Conéctate para guardarlo en este \(JACDevice.name).") }
        if let body, usingOfflineCopy, path != "api/auth" || !["logout", "login", "activate"].contains(body["action"].text) {
            throw APIError.invalid("Estás consultando una copia guardada. Conéctate antes de guardar cambios.")
        }
        var request = URLRequest(url: url)
        // Cache-backed reads can fail over quickly. An explicit revalidation
        // already displays that copy, so let a slow connection finish normally.
        request.timeoutInterval = saved != nil && !forceNetwork ? 5 : session.configuration.timeoutIntervalForRequest
        request.httpShouldHandleCookies = false
        request.setValue(document ? "*/*" : "application/json", forHTTPHeaderField: "Accept")
        request.setValue("JACNomina-\(JACDevice.name)/1.0", forHTTPHeaderField: "User-Agent")
        let sentToken = try checkedToken()
        if let token = sentToken {
            guard token.range(of: "^[A-Za-z0-9_-]{43}$", options: .regularExpression) != nil else { try clearSession(); throw APIError.unauthorized }
            if nativeBearer {
                guard path == "api/mobile/contracts" else {throw APIError.invalid("Ruta móvil no disponible.")}
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            } else { request.setValue("\(cookieName)=\(token)", forHTTPHeaderField: "Cookie") }
        }
        if let body {
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue(origin, forHTTPHeaderField: "Origin")
            request.httpBody = try JSONEncoder().encode(body)
        }
        let data: Data, rawResponse: URLResponse
        do { (data, rawResponse) = try await session.data(for: request) }
        catch {
            guard sentToken == (try checkedToken()), generation == cacheGeneration else { throw CancellationError() }
            if path.hasPrefix("api/crm") || path == "api/mobile/contracts",body == nil,crmReadGeneration != crmGeneration {throw CancellationError()}
            if AgendaOfflineCache.isUnavailable(error), !mediaThumbnailRead, !mediaPreviewRead {
                usingOfflineCopy = true
                if let saved, let response = saved.response, !forceNetwork { return (try authorizedNoticeData(saved.data,path:path), response) }
            }
            throw error
        }
        let response = rawResponse
        guard let response = response as? HTTPURLResponse else { throw APIError.message("El servidor no respondió correctamente.") }
        // A response from a previous login must not restore payroll data or
        // invalidate the session of a user who signed in while it was pending.
        guard sentToken == (try checkedToken()), generation == cacheGeneration else { throw CancellationError() }
        if response.statusCode == 401 || (300..<400).contains(response.statusCode) {
            if sentToken == (try checkedToken()) { try clearSession() }
            throw APIError.unauthorized
        }
        if path.hasPrefix("api/crm") || path == "api/mobile/contracts",body == nil,crmReadGeneration != crmGeneration,!(400..<500).contains(response.statusCode) {throw CancellationError()}
        if [500, 502, 503, 504].contains(response.statusCode), let saved, let result = saved.response, !forceNetwork {
            usingOfflineCopy = true; return (try authorizedNoticeData(saved.data,path:path), result)
        }
        guard (200..<300).contains(response.statusCode) else {
            // A pending/missing cover is not a revoked session or a deleted
            // original. Invalidating the global generation here used to cancel
            // every other thumbnail and collapse expanded folder contents.
            if mediaPreviewRead, [404, 429, 500, 502, 503, 504].contains(response.statusCode) {
                struct PreviewError: Decodable { let error: String?; let code: String? }
                let failure = try? decoder.decode(PreviewError.self, from: data)
                throw MediaPreviewUnavailable(message: failure?.error ?? "La vista previa no está disponible en este momento. Puedes reintentar.", preparing: failure?.code == "preview_preparing", retryAfter: min(5, max(0, Double(response.value(forHTTPHeaderField: "Retry-After") ?? "1") ?? 1)))
            }
            if mediaThumbnailRead, [404, 429, 500, 502, 503, 504].contains(response.statusCode) { throw MediaThumbnailUnavailable() }
            if path=="api/media",body==nil,response.statusCode==410,let folder=query.first(where:{$0.name=="folder"})?.value,let mediaScope=try mediaScope() {try mediaOffline.removeFolders([folder],scope:mediaScope);throw MediaFolderRemoved()}
            if path.hasPrefix("api/music"), response.statusCode == 403, let scope = try musicScope() { musicOffline.clear(scope) }
            if path.hasPrefix("api/media"), response.statusCode == 403, let mediaScope = try mediaScope() { invalidateWidgetSnapshot(); cacheGeneration += 1; mediaOffline.clear(mediaScope); TemporaryDocuments.clear() }
            if path == "api/mobile/payroll", query.contains(where: { $0.name == "workspace" }), response.statusCode == 403 { try clearSession(); throw APIError.unauthorized }
            if path == "api/notices/wallet", [403,404,410].contains(response.statusCode), let scope, let body,
               !body["id"].text.isEmpty { removeCachedNotice(body["id"].text,scope:scope) }
            if let scope, (body == nil || path == "api/crm" || path == "api/mobile/contracts"), [403, 404, 410].contains(response.statusCode) {
                if path.hasPrefix("api/notices"), let id = query.first(where: { ["id", "item"].contains($0.name) })?.value { removeCachedNotice(id, scope: scope) }
                else { let prefix=(path.hasPrefix("api/crm") || path == "api/mobile/contracts") && response.statusCode == 403 ? "/api/crm":"/"+path;offlineCache.remove(scope) { URL(string: $0.url)?.path.hasPrefix(prefix) == true || (prefix == "/api/crm" && URL(string:$0.url)?.path == "/api/mobile/contracts") } }
                invalidateWidgetSnapshot(); cacheGeneration += 1; syncTask?.cancel(); syncTask = nil; syncingOffline = false
                offlineSyncMessage = "Se conserva lo descargado. Quedan datos o adjuntos por actualizar."
                TemporaryDocuments.clear(); self.cacheRevision += 1
            }
            struct ServerError: Decodable { let error: String }
            let message = (try? decoder.decode(ServerError.self, from: data).error) ?? "No se pudo completar la operación. Intenta de nuevo."
            if path == "api/media/file", query.contains(where: { $0.name == "metadata" }), [404, 410].contains(response.statusCode) { throw MediaFileRemoved() }
            if response.statusCode == 409 { throw APIError.conflict(message) }
            if response.statusCode == 403 { if path == "api/calendar" { clearCachedAgenda() }; throw APIError.forbidden(message) }
            if response.statusCode == 400 || response.statusCode == 413 { throw APIError.invalid(message) }
            throw APIError.message(message)
        }
        if path == "api/auth" {
            let fields = Dictionary(uniqueKeysWithValues: response.allHeaderFields.map { (String(describing: $0.key), String(describing: $0.value)) })
            if let cookie = HTTPCookie.cookies(withResponseHeaderFields: fields, for: baseURL).first(where: { $0.name == cookieName }) {
                if cookie.value.isEmpty { try clearSession() }
                else if cookie.value.range(of: "^[A-Za-z0-9_-]{43}$", options: .regularExpression) != nil { if cookie.value != sentToken { if let scope { offlineCache.clear(scope) }; if let mediaScope = try mediaScope() { mediaOffline.clear(mediaScope) }; clearCachedAgenda(); TemporaryDocuments.clear() }; try vault.save(cookie.value); _ = try checkedToken(); if let currentScope = try offlineScope() { offlineCache.removeOtherSessions(currentScope) }; if let mediaScope = try mediaScope() { mediaOffline.removeOtherSessions(mediaScope) } }
            }
        }
        if path == "api/mobile/payroll", query.contains(where: { $0.name == "workspace" }), body == nil { usingOfflineCopy = false }
        if canCache, !(path == "api/mobile/payroll" && query.contains(where: { $0.name == "workspace" })), let scope {
            do { try await saveOffline(data, response: response, key: key, revision: cacheRevision, scope: scope) }
            catch is CancellationError { throw CancellationError() }
            catch {
                guard sentToken == (try checkedToken()), generation == cacheGeneration, allowsResource(path, query: query, body: body) else { throw CancellationError() }
                storageFailures += 1; offlineSyncMessage = "No se pudo guardar toda la copia local: " + error.localizedDescription
            }
            guard sentToken == (try checkedToken()), generation == cacheGeneration, allowsResource(path, query: query, body: body) else { throw CancellationError() }
        }
        return (body == nil ? try authorizedNoticeData(data,path:path) : data, response)
    }

    private func saveOffline(_ data: Data, response: HTTPURLResponse, key: String, revision: Int, scope: AgendaCacheScope) async throws {
        guard let url = response.url else { return }
        let cache = offlineCache, epoch = cache.epoch(scope), generation = cacheGeneration, previous = cachePersistence
        let work = Task.detached(priority: .utility) { () async throws -> OfflineSaveResult in
            await previous?.value
            try Task.checkCancellation()
            let mime = response.mimeType ?? "application/json", decoder = JSONDecoder(), encoder = JSONEncoder()
            encoder.outputFormatting = .sortedKeys
            let json: JSONValue?
            if (url.path == "/api/mobile/contracts" && mime == "application/pdf") || ["/api/notices/file", "/api/notices/pdf", "/api/expenses/file", "/api/crm/file"].contains(url.path) {
                guard data.count <= 10 * 1024 * 1024, (try? NoticeUpload.mime(data)) == mime else { throw APIError.message("No se recibió un adjunto válido para guardar.") }; json = nil
            } else {
                JACPerformanceDiagnostics.record(.jsonDecode); json = try? decoder.decode(JSONValue.self, from: data)
                if !url.path.hasSuffix("/export"), json == nil { throw APIError.message("No se recibió información válida para guardar.") }
            }
            var headers = ["Content-Type": response.value(forHTTPHeaderField: "Content-Type") ?? mime]
            if let disposition = response.value(forHTTPHeaderField: "Content-Disposition"), !disposition.isEmpty { headers["Content-Disposition"] = disposition }
            var records = [OfflineResponse(key: key, url: url.absoluteString, headers: headers, data: data, receivedAt: Date(), revision: revision)]
            var noticeRules: [String: (revision: Int, files: Set<String>)] = [:], notices: [JACNotice] = []
            if url.path == "/api/notices", let json {
                let items = json["item"].fields.isEmpty ? json["notices"].elements : [json["item"]]
                for item in items where !item["id"].text.isEmpty {
                    let id = item["id"].text, itemRevision = max(1, Int(item["revision"].number))
                    var parts = URLComponents(url: url, resolvingAgainstBaseURL: false)!; parts.queryItems = [URLQueryItem(name: "item", value: id)]
                    let itemURL = parts.url!, itemKey = itemURL.absoluteString + "\nrevision=0"
                    JACPerformanceDiagnostics.record(.jsonEncode)
                    let bytes = try encoder.encode(JSONValue.object(["item": item]))
                    // A late list must not overwrite a newer canonical item.
                    if let old = cache.load(scope, key: itemKey), old.revision > itemRevision { continue }
                    records.removeAll { $0.key == itemKey }
                    records.append(OfflineResponse(key: itemKey, url: itemURL.absoluteString, headers: ["Content-Type": "application/json"], data: bytes, receivedAt: Date(), revision: itemRevision))
                    JACPerformanceDiagnostics.record(.jsonDecode)
                    if let notice = try? decoder.decode(CachedNoticeWrapper.self, from: bytes).item { notices.append(notice) }
                    noticeRules[id] = (itemRevision, Set(item["attachments"].elements.map { $0["id"].text }))
                }
            }
            let expenseFeed = url.path == "/api/expenses" ? try? decoder.decode(TravelExpenseFeed.self, from: data) : nil
            let calendar = url.path == "/api/calendar" ? try? decoder.decode(AgendaData.self, from: data) : nil
            let disconnected = calendar.map { !$0.connection.connected || $0.connection.selected == nil } ?? false
            let changed = try cache.saveBatch(records, scope: scope, expectedEpoch: epoch) { entry in
                guard let parts = URLComponents(string: entry.url) else { return false }
                let id = parts.queryItems?.first(where: { $0.name == "id" })?.value ?? ""
                if ["/api/notices/file", "/api/notices/pdf"].contains(parts.path), let rule = noticeRules[id] {
                    return entry.revision != rule.revision || (parts.path.hasSuffix("/file") && !rule.files.contains(parts.queryItems?.first(where: { $0.name == "file" })?.value ?? ""))
                }
                if parts.path == "/api/expenses/file", let item = expenseFeed?.expenses.first(where: { $0.id == id }) {
                    return entry.revision != item.version || !item.attachments.contains { $0.id == parts.queryItems?.first(where: { $0.name == "file" })?.value }
                }
                if parts.path == "/api/calendar", let calendar, let saved = cache.load(scope, key: entry.key), let old = try? decoder.decode(AgendaData.self, from: saved.data) {
                    return disconnected || old.connection.revision != calendar.connection.revision || old.connection.selected?.id != calendar.connection.selected?.id
                }
                return false
            }
            return OfflineSaveResult(changed: changed, notices: notices, calendarDisconnected: disconnected)
        }
        cachePersistence = Task { _ = try? await work.value }
        let result = try await work.value
        try Task.checkCancellation()
        guard generation == cacheGeneration, scope.id == (try offlineScope())?.id, epoch == cache.epoch(scope) else { throw CancellationError() }
        if result.calendarDisconnected { clearCachedAgenda() }
        validateDecodedEpoch(scope)
        for notice in result.notices where permissionUser?.permitsNotice(notice.kind) != false {
            let itemKey = resourceKey(resourceURL(path: "api/notices", query: [URLQueryItem(name: "item", value: notice.id)]))
            rememberDecoded(CachedNoticeWrapper(item: notice), key: itemKey, scope: scope, cost: max(1024, data.count / max(1, result.notices.count)))
        }
        if result.changed { self.cacheRevision += 1 }
    }
    private func removeCachedNotice(_ id: String, scope: AgendaCacheScope) {
        noticeInvalidations[id, default: 0] += 1
        offlineCache.remove(scope) { entry in
            guard let parts = URLComponents(string: entry.url), parts.path.hasPrefix("/api/notices") else { return false }
            return parts.queryItems?.contains(where: { ["id", "item"].contains($0.name) && $0.value == id }) == true
        }
        for entry in offlineCache.entries(scope) where URL(string: entry.url)?.path == "/api/notices" {
            guard let saved = offlineCache.load(scope, key: entry.key), var json = try? decoder.decode(JSONValue.self, from: saved.data), !json["notices"].elements.isEmpty else { continue }
            json["notices"] = .array(json["notices"].elements.filter { $0["id"].text != id })
            if let bytes = try? JSONEncoder().encode(json) { _ = try? offlineCache.save(OfflineResponse(key: saved.key, url: saved.url, headers: saved.headers, data: bytes, receivedAt: Date(), revision: saved.revision), scope: scope) }
        }
        validateDecodedEpoch(scope)
        cacheRevision += 1
    }
    func rememberWorkspace(_ workspace: PayrollWorkspace) {
        if permissionUser == workspace.user, let scope = derivedOfflineScope?.scope,
           rememberedWorkspace?.scope == scope.id, rememberedWorkspace?.generation == cacheGeneration {
            let encoder = JSONEncoder(); encoder.outputFormatting = .sortedKeys
            if let bytes = try? encoder.encode(workspace.restrictedForSections), bytes == rememberedWorkspace?.bytes { return }
        }
        let userChanged = permissionUser.map{$0 != workspace.user} == true
        if let previous=permissionUser, ["itinerary","alert","boarding_pass"].contains(where:{previous.permitsNotice($0) != workspace.user.permitsNotice($0)}),let scope=try? offlineScope() {offlineCache.remove(scope){URL(string:$0.url)?.path.hasPrefix("/api/notices") == true}}
        if userChanged {clearDecodedResponses(); rememberedWorkspace = nil; rememberedAgenda = nil; invalidateWidgetSnapshot(); cacheGeneration += 1;syncTask?.cancel();syncTask=nil;syncingOffline=false;TemporaryDocuments.clear();clearCachedAgenda()}
        if !workspace.user.canReadMusic, let scope = try? musicScope() { musicOffline.clear(scope); musicPlaybackToken = nil }
        permissionUser=workspace.user
        if !workspace.user.hasSection(.calendar) {clearCachedAgenda()}
        if !workspace.user.canReadMedia, let mediaScope = try? mediaScope() { mediaOffline.clear(mediaScope) }
        guard let scope = try? offlineScope() else { return }
        offlineCache.remove(scope) { entry in guard let parts=URLComponents(string:entry.url) else{return true};return !self.allowsResource(String(parts.path.dropFirst()),query:parts.queryItems ?? []) }
        let url = resourceURL(path: "api/mobile/payroll", query: [URLQueryItem(name: "workspace", value: "1")])
        // Removal precedes the write: a revision-zero control workspace must
        // replace payroll, and a full disk must never resurrect the old role.
        if userChanged {offlineCache.remove(scope){$0.key == self.resourceKey(url)}}
        offlineCache.remove(scope) { URL(string: $0.url)?.path == "/api/payroll/export" && $0.revision != workspace.version }
        do {
            let encoder = JSONEncoder(); encoder.outputFormatting = .sortedKeys
            let bytes = try encoder.encode(workspace.restrictedForSections)
            if rememberedWorkspace?.scope == scope.id, rememberedWorkspace?.generation == cacheGeneration, rememberedWorkspace?.bytes == bytes { return }
            try offlineCache.save(OfflineResponse(key: resourceKey(url), url: url.absoluteString, headers: ["Content-Type": "application/json"], data: bytes, receivedAt: Date(), revision: workspace.version), scope: scope)
            rememberedWorkspace = (scope.id, cacheGeneration, bytes)
            rememberDecoded(workspace.restrictedForSections, key: resourceKey(url), scope: scope, cost: bytes.count)
        }
        catch { storageFailures += 1; offlineSyncMessage = "No se pudo guardar la copia local: " + error.localizedDescription }
    }
    private func rememberWorkspaceInBackground(_ workspace: PayrollWorkspace) async throws {
        // Permission transitions must invalidate old private copies immediately.
        // They are rare and use the existing fail-closed mutation path.
        if let previous = permissionUser, previous != workspace.user { rememberWorkspace(workspace); return }
        permissionUser = workspace.user
        guard let scope = try offlineScope() else { throw CancellationError() }
        let generation = cacheGeneration, cache = offlineCache, epoch = cache.epoch(scope), previous = cachePersistence
        let url = resourceURL(path: "api/mobile/payroll", query: [URLQueryItem(name: "workspace", value: "1")]), key: String
        key = resourceKey(url)
        let remembered = rememberedWorkspace?.scope == scope.id && rememberedWorkspace?.generation == generation ? rememberedWorkspace?.bytes : nil
        let work = Task.detached(priority: .utility) { () async throws -> Data in
            await previous?.value
            try Task.checkCancellation()
            if let current = cache.load(scope, key: key), current.revision > workspace.version { throw CancellationError() }
            let encoder = JSONEncoder(); encoder.outputFormatting = .sortedKeys; JACPerformanceDiagnostics.record(.jsonEncode)
            let bytes = try encoder.encode(workspace.restrictedForSections)
            if bytes == remembered { return bytes }
            try cache.saveBatch([OfflineResponse(key: key, url: url.absoluteString, headers: ["Content-Type": "application/json"], data: bytes, receivedAt: Date(), revision: workspace.version)], scope: scope, expectedEpoch: epoch) { entry in
                guard let parts = URLComponents(string: entry.url) else { return true }
                return !Self.allowsResource(workspace.user, path: String(parts.path.dropFirst()), query: parts.queryItems ?? []) || (parts.path == "/api/payroll/export" && entry.revision != workspace.version)
            }
            return bytes
        }
        cachePersistence = Task { _ = try? await work.value }
        do {
            let bytes = try await work.value
            guard generation == cacheGeneration, scope.id == (try offlineScope())?.id, epoch == cache.epoch(scope) else { throw CancellationError() }
            rememberedWorkspace = (scope.id, generation, bytes)
            rememberDecoded(workspace.restrictedForSections, key: key, scope: scope, cost: bytes.count)
        } catch is CancellationError { throw CancellationError() }
        catch {
            guard generation == cacheGeneration, scope.id == (try offlineScope())?.id, epoch == cache.epoch(scope) else { throw CancellationError() }
            storageFailures += 1; offlineSyncMessage = "No se pudo guardar la copia local: " + error.localizedDescription
        }
        guard generation == cacheGeneration, scope.id == (try offlineScope())?.id, epoch == cache.epoch(scope) else { throw CancellationError() }
    }
    func synchronizeOfflineContent(_ workspace: PayrollWorkspace) {
        guard automaticOfflineSync, !workspace.user.onlyMedia, syncTask == nil, !usingOfflineCopy else { return }
        if let lastOfflineSync, lastOfflineSync.generation == cacheGeneration,
           lastOfflineSync.version == workspace.version, Date().timeIntervalSince(lastOfflineSync.at) < 300 { return }
        syncTask = Task { [weak self] in
            guard let self, let token = try? self.checkedToken() else { return }
            let generation = self.cacheGeneration, failures = self.storageFailures
            self.syncingOffline = true; self.offlineSyncMessage = "Guardando información y adjuntos para consultar sin conexión…"
            defer { if generation == self.cacheGeneration { self.syncingOffline = false; self.syncTask = nil } }
            var partial = false
            @MainActor func validate() throws {
                try Task.checkCancellation()
                guard generation == self.cacheGeneration, token == (try self.checkedToken()), !self.usingOfflineCopy else { throw CancellationError() }
            }
            @MainActor func optionalRead(_ action: @MainActor () async throws -> Void) async throws {
                try validate()
                do { try await action() }
                catch { try validate(); partial = true }
            }
            do {
                var noticeIDs = Set<String>(), fetchedKeys = Set<String>()
                for boarding: String? in ["current", nil, "history"] where boarding == nil ? (workspace.user.hasSection(.itineraries) || workspace.user.hasSection(.alerts)) : workspace.user.hasSection(.boarding) {
                    var cursor = "", visited = Set<String>()
                    repeat {
                        try validate()
                        let query = (cursor.isEmpty ? [] : [URLQueryItem(name: "cursor", value: cursor)]) + (boarding.map { [URLQueryItem(name: "boarding", value: $0)] } ?? [])
                        let (bytes, _) = try await self.request(path: "api/notices", query: query, forceNetwork: true)
                        fetchedKeys.insert(self.resourceKey(self.resourceURL(path: "api/notices", query: query)))
                        let page = try self.decoder.decode(NoticeFeed.self, from: bytes)
                        for item in page.notices where workspace.user.permitsNotice(item.kind) {
                            try validate(); noticeIDs.insert(item.id)
                            for file in item.files {
                                let path = item.attachments == nil && item.kind == "itinerary" ? "api/notices/pdf" : "api/notices/file"
                                let query = [URLQueryItem(name: "id", value: item.id)] + (path.hasSuffix("/file") ? [URLQueryItem(name: "file", value: file.id)] : [])
                                let key = self.resourceKey(self.resourceURL(path: path, query: query), revision: item.revision ?? 1)
                                if let scope = try self.offlineScope(), self.offlineCache.load(scope, key: key) == nil { try await optionalRead { _ = try await self.request(path: path, query: query, document: true, forceNetwork: true, cacheRevision: item.revision ?? 1) } }
                            }
                        }
                        cursor = page.nextCursor
                        guard cursor.isEmpty || visited.insert(cursor).inserted else { throw APIError.message("No se pudo completar la copia de avisos.") }
                    } while !cursor.isEmpty
                }
                if let scope = try self.offlineScope() {
                    let obsolete = self.offlineCache.entries(scope).compactMap { entry -> String? in
                        guard let parts = URLComponents(string: entry.url), parts.path.hasPrefix("/api/notices") else { return nil }
                        return parts.queryItems?.first(where: { ["id", "item"].contains($0.name) })?.value
                    }.filter { !noticeIDs.contains($0) }
                    for id in Set(obsolete) { self.removeCachedNotice(id, scope: scope) }
                    self.offlineCache.remove(scope) { entry in
                        guard let parts = URLComponents(string: entry.url), parts.path == "/api/notices", parts.queryItems?.contains(where: { $0.name == "item" }) != true else { return false }
                        return !fetchedKeys.contains(entry.key)
                    }
                }
                for period in workspace.periods where workspace.user.hasSection(.payroll) {
                    let query = [URLQueryItem(name: "period", value: period.id)]
                    if self.cached(PeriodDetail.self, path: "api/mobile/payroll", query: query)?.version == workspace.version { continue }
                    try await optionalRead { _ = try await self.request(path: "api/mobile/payroll", query: query, forceNetwork: true) }
                }
                if workspace.user.hasSection(.calendar) {try await optionalRead { _ = try await self.agenda(month: CalendarClock.month(Date())) }}
                if workspace.user.hasSection(.itineraries) {
                var cursor = "", visited = Set<String>()
                repeat {
                    try validate()
                    let (bytes, _) = try await self.request(path: "api/expenses", query: cursor.isEmpty ? [] : [URLQueryItem(name: "cursor", value: cursor)], forceNetwork: true)
                    let page = try self.decoder.decode(TravelExpenseFeed.self, from: bytes)
                    for expense in page.expenses { for file in expense.attachments {
                        let query = [URLQueryItem(name: "id", value: expense.id), URLQueryItem(name: "file", value: file.id)]
                        if let scope = try self.offlineScope(), self.offlineCache.load(scope, key: self.resourceKey(self.resourceURL(path: "api/expenses/file", query: query), revision: expense.version)) == nil { try await optionalRead { _ = try await self.request(path: "api/expenses/file", query: query, document: true, forceNetwork: true, cacheRevision: expense.version) } }
                    } }
                    cursor = page.nextCursor; guard cursor.isEmpty || visited.insert(cursor).inserted else { throw APIError.message("No se pudo completar la copia de gastos.") }
                } while !cursor.isEmpty
                }
                if workspace.user.hasSection(.crm) { try await optionalRead { _ = try await self.users() };try await optionalRead {try await self.synchronizeCrmOffline()} }
                if workspace.user.hasSection(.payroll) {
                    try await optionalRead { _ = try await self.mail(periodID: nil) }
                    for period in workspace.periods where period.status == "cerrada" { try await optionalRead { _ = try await self.mail(periodID: period.id) } }
                }
                try validate()
                if !partial && failures == self.storageFailures { self.lastOfflineSync = (generation, workspace.version, Date()) }
                self.offlineSyncMessage = partial || failures != self.storageFailures ? "Se conserva lo descargado. Quedan datos o adjuntos por actualizar." : "La última información y sus adjuntos están guardados en este \(JACDevice.name)."
            } catch { if generation == self.cacheGeneration { self.offlineSyncMessage = "Se conserva lo descargado. Quedan datos o adjuntos por actualizar." } }
        }
    }

    func login(username: String, password: String, keepSignedIn: Bool = false) async throws {
        _ = try await request(path: "api/auth", body: .object(["action": .string("login"), "username": .string(username.trimmingCharacters(in: .whitespacesAndNewlines)), "password": .string(password), "keepSignedIn": .bool(keepSignedIn)]))
        guard try hasSession() else { throw APIError.message("No se pudo guardar la sesión. Intenta de nuevo.") }
    }
    func overview() async throws -> PayrollOverview {
        let (data, _) = try await request(path: "api/mobile/payroll")
        return try decoder.decode(PayrollOverview.self, from: data)
    }
    func detail(periodID: String) async throws -> PeriodDetail {
        let (data, _) = try await request(path: "api/mobile/payroll", query: [URLQueryItem(name: "period", value: periodID)])
        return try decoder.decode(PeriodDetail.self, from: data)
    }
    func changePassword(current: String, new: String) async throws {
        _ = try await request(path: "api/auth", body: .object(["action": .string("password"), "currentPassword": .string(current), "password": .string(new)]))
    }
    func logout() async throws {
        if usingOfflineCopy { try clearSession(); return }
        do { _ = try await request(path: "api/auth", body: .object(["action": .string("logout"), "notificationDeviceId": .string(JACNotifications.deviceID)])) }
        catch { try clearSession(); throw error }
        try clearSession()
    }
    func workspace(forceNetwork: Bool = false) async throws -> PayrollWorkspace {
        let (data, _) = try await request(path: "api/mobile/payroll", query: [URLQueryItem(name: "workspace", value: "1")], forceNetwork: forceNetwork)
        let result=try decoder.decode(PayrollWorkspace.self, from: data).restrictedForSections; try await rememberWorkspaceInBackground(result); return result
    }
    func notices(cursor: String = "", boarding: String? = nil) async throws -> NoticeFeed {
        let (data, _) = try await request(path: "api/notices", query: (cursor.isEmpty ? [] : [URLQueryItem(name: "cursor", value: cursor)]) + (boarding.map { [URLQueryItem(name:"boarding",value:$0)] } ?? []))
        return try decoder.decode(NoticeFeed.self, from: data)
    }
    func noticeRecipients() async throws -> NoticeRecipientRoster {
        guard !usingOfflineCopy else {throw APIError.invalid("Conéctate para actualizar los destinatarios antes de publicar.")}
        guard let user=permissionUser,user.isOwner,user.hasSection(.crm),let scope=try offlineScope() else {throw APIError.forbidden("Tu cuenta no puede administrar los destinatarios.")}
        let generation=cacheGeneration
        let (data,response)=try await request(path:"api/notices/recipients",forceNetwork:true)
        try Task.checkCancellation()
        guard generation == cacheGeneration,user == permissionUser,scope.id == (try offlineScope())?.id else {throw CancellationError()}
        guard response.mimeType == "application/json",data.count<=256*1024 else {throw APIError.invalid("No se pudo leer la lista actual de destinatarios.")}
        let roster=try decoder.decode(NoticeRecipientRoster.self,from:data)
        guard roster.users.count<=1000,roster.boardingUsers.count<=1000,
              Set(roster.users.map(\.id)).count == roster.users.count,Set(roster.boardingUsers.map(\.id)).count == roster.boardingUsers.count else {throw APIError.invalid("La lista de destinatarios no es válida.")}
        return roster
    }
    func noticeCommand(_ command: JSONValue) async throws { _ = try await request(path: "api/notices", body: command) }
    func notice(id: String) async throws -> JACNotice {
        struct Response: Decodable { let item: JACNotice }
        let (data, _) = try await request(path: "api/notices", query: [URLQueryItem(name: "item", value: id)])
        return try decoder.decode(Response.self, from: data).item
    }
    func itinerary(_ notice: JACNotice) async throws -> ExportedDocument {
        guard permissionUser?.permitsNotice(notice.kind) != false else {throw APIError.forbidden("Tu cuenta no tiene acceso a esta sección.")}
        let (data, response) = try await request(path: "api/notices/pdf", query: [URLQueryItem(name: "id", value: notice.id)], document: true, cacheRevision: notice.revision ?? 1)
        guard permissionUser?.permitsNotice(notice.kind) != false else { throw CancellationError() }
        guard response.mimeType == "application/pdf", data.count <= 10*1024*1024, data.starts(with: Data("%PDF-".utf8)) else { throw APIError.message("No se recibió un PDF válido.") }
        let name = (notice.filename as NSString).lastPathComponent
        return try TemporaryDocuments.save(data, filename: name.isEmpty ? "Itinerario.pdf" : name)
    }
    func publishNotice(id: String, kind: String, title: String, body: String, recipients: [String], files: [NoticeUpload], travelDate: String? = nil) async throws {
        guard files.count <= 5, files.reduce(0, { $0 + $1.data.count }) <= 10*1024*1024 else { throw APIError.message("Elige hasta 5 archivos que sumen como máximo 10 MB.") }
        for file in files { _ = try NoticeUpload.mime(file.data) }
        var payload: [String: JSONValue] = ["id": .string(id), "kind": .string(kind), "title": .string(title), "body": .string(body), "recipients": .array(recipients.sorted().map(JSONValue.string)), "files": .array(files.map { .object(["filename": .string($0.filename), "data": .string($0.data.base64EncodedString())]) })]
        if let travelDate { payload["travelDate"] = .string(travelDate) }; _ = try await request(path:"api/notices/publish",body:.object(payload))
    }
    func noticeFile(_ item: JACNotice, file: NoticeAttachment) async throws -> ExportedDocument {
        guard permissionUser?.permitsNotice(item.kind) != false else {throw APIError.forbidden("Tu cuenta no tiene acceso a esta sección.")}
        if let latest = cachedNotice(item.id), (latest.revision ?? 1) > (item.revision ?? 1) || !latest.files.contains(where: { $0.id == file.id }) { throw APIError.invalid("El documento cambió. Abre la versión más reciente.") }
        let (data, response) = try await request(path: "api/notices/file", query: [URLQueryItem(name: "id", value: item.id), URLQueryItem(name: "file", value: file.id)], document: true, cacheRevision: item.revision ?? 1)
        guard permissionUser?.permitsNotice(item.kind) != false else { throw CancellationError() }
        guard data.count <= 10*1024*1024, response.mimeType == file.mimeType, (try NoticeUpload.mime(data)) == file.mimeType else { throw APIError.message("No se recibió un archivo válido.") }
        let name = (file.filename as NSString).lastPathComponent
        return try TemporaryDocuments.save(data, filename: name.isEmpty ? "Adjunto" : name)
    }
    // A derived code belongs to the same private session, attachment and revision
    // as its PDF. Removal/denial invalidates even an in-memory, already decoded code.
    // Identity for a cached card's display/task key. This is deliberately not
    // authorization; opening a document/OCR/Wallet uses the checked accessor.
    func boardingCodePresentationStamp(_ item: JACNotice, file: NoticeAttachment) -> String? {
        guard item.kind == "boarding_pass", permissionUser?.permitsNotice(item.kind) != false,
              item.files.contains(where: { $0.id == file.id }), let scope = derivedOfflineScope?.scope else { return nil }
        if let latest = cachedNotice(item.id), (latest.revision ?? 1) != (item.revision ?? 1) || latest.boardingDetails != item.boardingDetails || !latest.files.contains(where: { $0.id == file.id }) { return nil }
        return "\(scope.id):\(cacheGeneration):\(noticeInvalidations[item.id, default: 0]):\(item.revision ?? 1)"
    }
    func boardingCodeAccessStamp(_ item: JACNotice, file: NoticeAttachment) throws -> String {
        guard item.kind == "boarding_pass", permissionUser?.permitsNotice(item.kind) != false,
              item.files.contains(where: { $0.id == file.id }), let scope = try offlineScope() else { throw APIError.unauthorized }
        if let latest = cachedNotice(item.id), (latest.revision ?? 1) != (item.revision ?? 1) || latest.boardingDetails != item.boardingDetails || !latest.files.contains(where: { $0.id == file.id }) {
            throw APIError.invalid("El pase cambió. Abre la versión más reciente.")
        }
        return "\(scope.id):\(cacheGeneration):\(noticeInvalidations[item.id, default: 0]):\(item.revision ?? 1)"
    }
    // Status and signed packages are always network-only. Wallet owns a copy
    // only after the user explicitly accepts Apple's add-pass interface.
    private func boardingWalletAccessStamp(_ item:JACNotice,file:NoticeAttachment) throws -> String {
        guard permissionUser?.hasSection(.boarding) == true, (item.revision ?? 1)>0 else {throw APIError.forbidden("Tu cuenta no tiene acceso a pases de abordar.")}
        return try boardingCodeAccessStamp(item,file:file)
    }
    func boardingWalletStatus(_ item:JACNotice,file:NoticeAttachment) async throws -> BoardingWalletStatus {
        let stamp=try boardingWalletAccessStamp(item,file:file)
        do {
            let (data,response)=try await request(path:"api/notices/wallet",forceNetwork:true)
            try Task.checkCancellation()
            guard stamp == (try boardingWalletAccessStamp(item,file:file)) else {throw CancellationError()}
            guard response.mimeType == "application/json", data.count<=16*1024 else {throw APIError.invalid("No se pudo consultar Apple Wallet.")}
            return try decoder.decode(BoardingWalletStatus.self,from:data)
        } catch APIError.forbidden(let message) {
            if let scope=try? offlineScope() {removeCachedNotice(item.id,scope:scope)}
            throw APIError.forbidden(message)
        }
    }
    func boardingWalletPass(_ item:JACNotice,file:NoticeAttachment,sourceSha256:String,barcode:BoardingWalletBarcode,legIndex:Int?=nil,details:BoardingWalletDetails?=nil) async throws -> Data {
        let stamp=try boardingWalletAccessStamp(item,file:file)
        guard sourceSha256.range(of:"^[a-f0-9]{64}$",options:.regularExpression) != nil else {throw APIError.invalid("Vuelve a abrir el documento original antes de añadirlo a Wallet.")}
        var fields:[String:JSONValue] = ["action":.string("create"),"id":.string(item.id),"file":.string(file.id),"revision":.number(Double(item.revision ?? 1)),"sourceSha256":.string(sourceSha256),"barcode":.object(["format":.string(barcode.format),"message":.string(barcode.message)])]
        if let legIndex {guard (0...3).contains(legIndex) else {throw APIError.invalid("Elige el tramo que corresponde a este pase.")};fields["legIndex"] = .number(Double(legIndex))}
        if let details {fields["details"] = .object(try details.walletRequestFields())}
        let payload:JSONValue = .object(fields)
        let (data,response)=try await request(path:"api/notices/wallet",body:payload,document:true,forceNetwork:true)
        try Task.checkCancellation()
        guard stamp == (try boardingWalletAccessStamp(item,file:file)) else {throw CancellationError()}
        guard response.mimeType == "application/vnd.apple.pkpass", (4...1024*1024).contains(data.count),data.starts(with:[0x50,0x4b,0x03,0x04]) else {
            throw APIError.invalid("No se recibió un pase válido para Apple Wallet. Conserva el documento original.")
        }
        return data
    }
    func confirmNotice(_ item: JACNotice) async throws {
        try await noticeCommand(.object(["action":.string("confirm"),"id":.string(item.id),"revision":.number(Double(item.revision ?? 1))]))
    }
    func updateItinerary(_ item: JACNotice, requestID: String, title: String, body: String, summary: String, files: [NoticeUpload]) async throws {
        _ = try await request(path:"api/notices/publish",query:[URLQueryItem(name:"update",value:"1")],body:.object(["id":.string(item.id),"requestId":.string(requestID),"revision":.number(Double(item.revision ?? 1)),"title":.string(title),"body":.string(body),"summary":.string(summary),"files":try travelUploads(files)]))
    }
    private func travelUploads(_ files:[NoticeUpload]) throws -> JSONValue {
        guard !files.isEmpty,files.count <= 5,files.reduce(0, { $0+$1.data.count }) <= 10*1024*1024 else { throw APIError.message("Adjunta de 1 a 5 archivos que sumen como máximo 10 MB.") }
        for f in files { _ = try NoticeUpload.mime(f.data) }
        return .array(files.map { .object(["filename":.string($0.filename),"data":.string($0.data.base64EncodedString())]) })
    }
    func expenses(cursor:String = "") async throws -> TravelExpenseFeed {
        let (data,_) = try await request(path:"api/expenses",query:cursor.isEmpty ? [] : [URLQueryItem(name:"cursor",value:cursor)])
        return try decoder.decode(TravelExpenseFeed.self,from:data)
    }
    func submitExpense(id:String,concept:String,amount:Double,date:String,note:String,files:[NoticeUpload]) async throws {
        _ = try await request(path:"api/expenses",body:.object(["id":.string(id),"concept":.string(concept),"amount":.number(amount),"expenseDate":.string(date),"note":.string(note),"files":try travelUploads(files)]))
    }
    func reviewExpense(_ expense:TravelExpense,approve:Bool,reason:String,employeeID:String,periodID:String) async throws {
        _ = try await request(path:"api/expenses",query:[URLQueryItem(name:"review",value:"1")],body:.object(["id":.string(expense.id),"version":.number(Double(expense.version)),"decision":.string(approve ? "approve" : "reject"),"reason":.string(reason),"employeeId":.string(employeeID),"periodId":.string(periodID)]))
    }
    func expenseFile(_ expense:TravelExpense,file:NoticeAttachment) async throws -> ExportedDocument {
        let (data,response) = try await request(path:"api/expenses/file",query:[URLQueryItem(name:"id",value:expense.id),URLQueryItem(name:"file",value:file.id)],document:true,cacheRevision:expense.version)
        guard data.count <= 10*1024*1024,response.mimeType == file.mimeType,(try NoticeUpload.mime(data)) == file.mimeType else { throw APIError.message("No se recibió un comprobante válido.") }
        return try TemporaryDocuments.save(data,filename:(file.filename as NSString).lastPathComponent)
    }
    func deleteNotice(_ item: JACNotice) async throws {
        try await noticeCommand(.object(["action": .string(item.kind == "boarding_pass" ? "deleteBoardingPass" : item.kind == "itinerary" ? "deleteItinerary" : "deleteAlert"), "id": .string(item.id), "confirmation": .string(item.id)]))
        if let scope = try offlineScope() { removeCachedNotice(item.id, scope: scope) }
    }
    func crm(query:[String:String] = [:],forceNetwork:Bool=false) async throws -> JSONValue {
        let(data,_)=try await request(path:"api/crm",query:query.map{URLQueryItem(name:$0.key,value:$0.value)},forceNetwork:forceNetwork)
        return try decoder.decode(JSONValue.self,from:data)
    }
    func crmCommand(_ action:String,record:JSONValue? = nil,month:String? = nil) async throws -> JSONValue {
        guard ["updateShow","createShow","addPayment","voidPayment","savePlan","linkPayroll","saveContact","addContactFiles","prepareDeleteShow","deleteShow","syncCalendar","syncSheets"].contains(action) else{throw APIError.invalid("Operación del CRM no disponible en este formulario.")}
        var command:JSONValue = .object(["action":.string(action)]);if let record{command["record"]=record};if let month{command["month"] = .string(month)}
        let(data,_)=try await request(path:"api/crm",body:command)
        if !["syncSheets","prepareDeleteShow"].contains(action){crmGeneration += 1}
        if !["syncCalendar","syncSheets","prepareDeleteShow"].contains(action),let scope=try offlineScope(){offlineCache.remove(scope){ URL(string:$0.url)?.path == "/api/crm" };cacheRevision += 1}
        return try decoder.decode(JSONValue.self,from:data)
    }
    func crmUploads(_ files:[NoticeUpload]) throws -> JSONValue { try travelUploads(files) }
    func createContract(_ input:ContractDraft,id:String? = nil,showId:String? = nil) async throws -> ExportedDocument {
        let fields=try input.payload()
        let payload:JSONValue = id.map { .object(["action":.string("save"),"id":.string($0),"showId":showId.map(JSONValue.string) ?? .null,"input":fields]) } ?? fields
        guard try hasSession() else {throw APIError.unauthorized}
        let (data,response)=try await request(path:"api/mobile/contracts",body:payload,document:true,forceNetwork:true,nativeBearer:true)
        guard !Task.isCancelled,permissionUser?.hasSection(.crm) != false,id.map({!deletedContractIDs.contains($0)}) ?? true else {throw CancellationError()}
        guard response.mimeType == "application/pdf",data.count <= 5*1024*1024,data.starts(with:Data("%PDF-".utf8)) else {throw APIError.invalid("No se recibió un contrato PDF válido.")}
        // Decode the UTF-8 filename supplied by the same generator as the web.
        // Neither a header nor a municipality may choose a filesystem path.
        let disposition=response.value(forHTTPHeaderField:"Content-Disposition") ?? ""
        let encoded=disposition.components(separatedBy:"filename*=UTF-8''").dropFirst().first?.components(separatedBy:";").first
        let received=encoded?.removingPercentEncoding
        let filename=received.flatMap { name in name == (name as NSString).lastPathComponent && !name.contains("\\") && !name.unicodeScalars.contains(where:{$0.value < 32 || $0.value == 127}) && name.hasSuffix(".pdf") ? name:nil } ?? input.filename
        let document=try TemporaryDocuments.save(data,filename:filename)
        if let id {contractDocuments[id,default:[]].append(document)}
        return document
    }
    func contractArchive(query:[String:String] = [:]) async throws -> JSONValue {
        let (data,_)=try await request(path:"api/mobile/contracts",query:query.map{URLQueryItem(name:$0.key,value:$0.value)},forceNetwork:!usingOfflineCopy,nativeBearer:true)
        return try decoder.decode(JSONValue.self,from:data)
    }
    func linkContract(id:String,showId:String?,version:Int) async throws {
        _ = try await request(path:"api/mobile/contracts",body:.object(["action":.string("link"),"id":.string(id),"showId":showId.map(JSONValue.string) ?? .null,"version":.number(Double(version))]),forceNetwork:true,nativeBearer:true)
    }
    func deleteArchivedContract(id:String,version:Int) async throws {
        _ = try await request(path:"api/mobile/contracts",body:.object(["action":.string("delete"),"id":.string(id),"confirmation":.string(id),"version":.number(Double(version))]),forceNetwork:true,nativeBearer:true)
        crmGeneration += 1;deletedContractIDs.insert(id)
        for document in contractDocuments.removeValue(forKey:id) ?? [] {TemporaryDocuments.remove(document)}
        if let scope=try offlineScope() {
            for entry in offlineCache.entries(scope) {
                guard let parts=URLComponents(string:entry.url),parts.path == "/api/mobile/contracts" else {continue}
                if parts.queryItems?.contains(where:{$0.name == "id" && $0.value == id}) == true {offlineCache.remove(scope){$0.key == entry.key};continue}
                guard let saved=offlineCache.load(scope,key:entry.key),var feed=try? decoder.decode(JSONValue.self,from:saved.data),case .array = feed["contracts"] else {continue}
                feed["contracts"] = .array(feed["contracts"].elements.filter{$0["id"].text != id})
                do {try offlineCache.save(OfflineResponse(key:saved.key,url:saved.url,headers:saved.headers,data:JSONEncoder().encode(feed),receivedAt:saved.receivedAt,revision:saved.revision),scope:scope)}
                catch {offlineCache.remove(scope){$0.key == entry.key}}
            }
        }
        cacheRevision += 1
    }
    func archivedContract(id:String,filename:String) async throws -> ExportedDocument {
        guard !deletedContractIDs.contains(id) else {throw APIError.message("Contrato no disponible.")}
        let (data,response)=try await request(path:"api/mobile/contracts",query:[URLQueryItem(name:"id",value:id)],document:true,forceNetwork:!usingOfflineCopy,nativeBearer:true)
        guard !Task.isCancelled,permissionUser?.hasSection(.crm) != false,!deletedContractIDs.contains(id) else {throw CancellationError()}
        guard response.mimeType == "application/pdf",data.count <= 5*1024*1024,data.starts(with:Data("%PDF-".utf8)) else {throw APIError.invalid("No se recibió un contrato PDF válido.")}
        let safe=(filename as NSString).lastPathComponent
        let document=try TemporaryDocuments.save(data,filename:safe.hasSuffix(".pdf") ? safe:"Contrato JAC.pdf")
        contractDocuments[id,default:[]].append(document);return document
    }
    func crmFile(owner:String,file:NoticeAttachment,version:Int,contact:Bool) async throws -> ExportedDocument {
        let query=[URLQueryItem(name:contact ? "contact":"id",value:owner),URLQueryItem(name:"file",value:file.id)]
        let(data,response)=try await request(path:"api/crm/file",query:query,document:true,cacheRevision:version)
        guard data.count<=10*1024*1024,response.mimeType==file.mimeType,(try NoticeUpload.mime(data))==file.mimeType else{throw APIError.invalid("No se recibió un documento válido.")}
        return try TemporaryDocuments.save(data,filename:(file.filename as NSString).lastPathComponent)
    }
    private func synchronizeCrmOffline() async throws {
        let feed=try await crm(query:["month":CalendarClock.month(Date())],forceNetwork:true)
        _ = try await crm(query:["view":"weekly","week":BoardingClock.today()],forceNetwork:true)
        func saveFiles(_ files:JSONValue,owner:String,version:Int,contact:Bool) async throws {
            for file in try files.decoded([NoticeAttachment].self) {
                try Task.checkCancellation()
                let query=[URLQueryItem(name:contact ? "contact":"id",value:owner),URLQueryItem(name:"file",value:file.id)]
                if let scope=try offlineScope(),offlineCache.load(scope,key:resourceKey(resourceURL(path:"api/crm/file",query:query),revision:version))==nil { _ = try await request(path:"api/crm/file",query:query,document:true,forceNetwork:true,cacheRevision:version) }
            }
        }
        for show in feed["shows"].elements {
            try Task.checkCancellation();let id=show["id"].text
            let d=try await crm(query:["id":id],forceNetwork:true)
            _ = try await crm(query:["view":"workspace","id":id],forceNetwork:true)
            for p in d["payments"].elements {try await saveFiles(p["files"],owner:p["id"].text,version:Int(p["version"].number),contact:false)}
        }
        let directory=try await crm(query:["view":"contacts"],forceNetwork:true)
        for c in directory["contacts"].elements {try Task.checkCancellation();let d=try await crm(query:["view":"contact","id":c["id"].text],forceNetwork:true);try await saveFiles(d["files"],owner:c["id"].text,version:Int(c["version"].number),contact:true)}
    }

    func payroll(_ command: JSONValue) async throws -> PayrollEnvelope {
        let (data, _) = try await request(path: "api/mobile/payroll", body: command)
        return try decoder.decode(PayrollEnvelope.self, from: data)
    }
    func preview(_ command: JSONValue) async throws -> PayrollPreview {
        var body = command; body["action"] = .string("previewEdit")
        let (data, _) = try await request(path: "api/mobile/payroll", body: body)
        return try decoder.decode(PayrollPreview.self, from: data)
    }
    func users() async throws -> UserDirectory {
        let (data, _) = try await request(path: "api/users")
        return try decoder.decode(UserDirectory.self, from: data)
    }
    func updateUser(_ user: ManagedUser) async throws -> OperationNotice {
        let record = try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(user))
        return try await notice(path: "api/users", body: .object(["action": .string(user.id.isEmpty ? "create" : "update"), "id": .string(user.id), "version": .number(Double(user.version)), "user": record]))
    }
    func invite(userID: String) async throws -> InvitationResult {
        let (data, _) = try await request(path: "api/users", body: .object(["action": .string("invite"), "id": .string(userID)]))
        return try decoder.decode(InvitationResult.self, from: data)
    }
    func activate(token: String, password: String) async throws {
        _ = try await request(path: "api/auth", body: .object(["action": .string("activate"), "token": .string(token), "password": .string(password)]))
        guard try hasSession() else { throw APIError.message("No se pudo guardar la sesión. Intenta de nuevo.") }
    }
    func mail(periodID: String?) async throws -> PayrollMail {
        let (data, _) = try await request(path: "api/payroll/email", query: periodID.map { [URLQueryItem(name: "period", value: $0)] } ?? [])
        return try decoder.decode(PayrollMail.self, from: data)
    }
    func mailOperation(_ body: JSONValue) async throws -> OperationNotice { try await notice(path: "api/payroll/email", body: body) }
    private func notice(path: String, body: JSONValue) async throws -> OperationNotice {
        let (data, _) = try await request(path: path, body: body)
        return try decoder.decode(OperationNotice.self, from: data)
    }
    func agenda(month: String) async throws -> AgendaData {
        let (data, _) = try await request(path: "api/calendar", query: [URLQueryItem(name: "month", value: month)])
        return try decoder.decode(AgendaData.self, from: data)
    }
    func agendaCalendars() async throws -> [AgendaCalendar] {
        let (data, _) = try await request(path: "api/calendar", query: [URLQueryItem(name: "action", value: "calendars")])
        return try decoder.decode(AgendaCalendars.self, from: data).calendars
    }
    func saveAgendaEvent(_ draft: AgendaEventDraft, revision: Int, event: AgendaEvent?, requestID: UUID) async throws -> AgendaEventMutation {
        var body: [String: JSONValue] = ["action": .string(event == nil ? "createEvent" : "updateEvent"), "revision": .number(Double(revision)), "event": draft.value]
        if let event { body["eventId"] = .string(event.id); body["etag"] = .string(event.etag ?? "") }
        else { body["requestId"] = .string(requestID.uuidString.lowercased()) }
        let (data, _) = try await request(path: "api/calendar", body: .object(body))
        return try decoder.decode(AgendaEventMutation.self, from: data)
    }
    func agendaOperation(action: String, revision: Int, calendarID: String? = nil) async throws -> AgendaMutation {
        var body: [String: JSONValue] = ["action": .string(action), "revision": .number(Double(revision))]
        if let calendarID { body["calendarId"] = .string(calendarID) }
        let (data, _) = try await request(path: "api/calendar", body: .object(body))
        return try decoder.decode(AgendaMutation.self, from: data)
    }
    func startAgenda() async throws -> AgendaStart {
        let (data, _) = try await request(path: "api/calendar", body: .object(["action": .string("connect"), "native": .bool(true)]))
        let start = try decoder.decode(AgendaStart.self, from: data)
        guard start.url.scheme == "https", start.url.host == baseURL.host, start.url.port == baseURL.port,
              start.url.path == "/api/calendar/connect", start.url.user == nil, start.url.password == nil, start.url.fragment == nil,
              start.nonce.range(of: "^[A-Za-z0-9_-]{43}$", options: .regularExpression) != nil else {
            throw APIError.message("La autorización de Agenda no es válida.")
        }
        return start
    }
    // Drive credentials stay on the server. Native transfers only use JAC's
    // authenticated origin, reject redirects and revalidate the session after I/O.
    // Pin status is presentation metadata. Actual download/pin/delete paths
    // retain their strict session checks before and after I/O.
    func mediaPinnedForPresentation(_ item: MediaItem) async -> Bool {
        guard !Task.isCancelled, permissionUser?.canReadMedia == true,
              let scope = derivedMediaScope?.scope, let stamp = mediaPresentationStamp else { return false }
        let cache = mediaOffline
        let pinned = await Task.detached(priority: .utility) { cache.isPinned(item, scope: scope) }.value
        return !Task.isCancelled && permissionUser?.canReadMedia == true && stamp == mediaPresentationStamp && pinned
    }
    func localMediaFoldersForPresentation() async -> Set<String> {
        guard !Task.isCancelled, permissionUser?.canReadMedia == true,
              let scope = derivedMediaScope?.scope, let stamp = mediaPresentationStamp else { return [] }
        let cache = mediaOffline
        let ids = await Task.detached(priority: .utility) { cache.localFolderIDs(scope: scope) }.value
        guard !Task.isCancelled, stamp == mediaPresentationStamp, permissionUser?.canReadMedia == true else { return [] }
        return ids
    }
    func removeLocalMediaFolder(_ id: String) async throws -> Int64 {
        let stamp = try mediaAccessStamp()
        guard permissionUser?.canReadMedia == true, let scope = try mediaScope() else { throw APIError.unauthorized }
        let cache = mediaOffline
        let work = Task.detached(priority: .userInitiated) { try cache.forgetLocalFolder(id, scope: scope) }
        let bytes = try await withTaskCancellationHandler { try await work.value } onCancel: { work.cancel() }
        guard !Task.isCancelled, stamp == (try mediaAccessStamp()) else { throw CancellationError() }
        cacheRevision += 1
        return bytes
    }
    func cachedMedia(folder: String = "") -> MediaFeed? {
        guard permissionUser?.canReadMedia != false, let scope = try? mediaScope() else { return nil }
        return mediaOffline.loadFeed(folder, scope: scope)
    }
    #if os(iOS)
    func widgetSessionMarker() throws -> String {
        guard let user = permissionUser, let scope = try offlineScope() else { throw APIError.unauthorized }
        return scope.id + ":" + user.id + ":" + String(cacheGeneration)
    }
    func widgetLatestPhotos() async throws -> WidgetRecentPhotos {
        guard permissionUser?.canReadMedia == true else { throw APIError.forbidden("Tu cuenta no tiene acceso a Fotografía.") }
        let marker = try widgetSessionMarker()
        let (data, _) = try await request(path: "api/media/recent", forceNetwork: true)
        try Task.checkCancellation()
        guard marker == (try widgetSessionMarker()), permissionUser?.canReadMedia == true else { throw CancellationError() }
        return try decoder.decode(WidgetRecentPhotos.self, from: data)
    }
    #endif
    func media(folder: String = "", pageToken: String = "", forceNetwork: Bool = false) async throws -> MediaFeed {
        // Startup prefetch and an already visible root gallery share one read.
        // Its scope includes the permission generation, not just the account.
        if forceNetwork, folder.isEmpty, pageToken.isEmpty, let stamp = try mediaAccessStamp() {
            if let read = mediaRootRead, read.stamp == stamp {
                let result = try await read.task.value
                try Task.checkCancellation()
                guard stamp == (try mediaAccessStamp()) else { throw CancellationError() }
                return result
            }
            let id = UUID(), task = Task { try await self.readMedia(folder: folder, pageToken: pageToken, forceNetwork: true) }
            mediaRootRead = (id, stamp, task)
            defer { if mediaRootRead?.id == id { mediaRootRead = nil } }
            let result = try await task.value
            try Task.checkCancellation()
            guard stamp == (try mediaAccessStamp()) else { throw CancellationError() }
            return result
        }
        return try await readMedia(folder: folder, pageToken: pageToken, forceNetwork: forceNetwork)
    }
    private func readMedia(folder: String, pageToken: String, forceNetwork: Bool) async throws -> MediaFeed {
        guard permissionUser?.canReadMedia != false else {throw APIError.forbidden("Tu cuenta no tiene acceso a Fotografía.")}
        var query: [URLQueryItem] = []
        if !folder.isEmpty { query.append(URLQueryItem(name: "folder", value: folder)) }
        if !pageToken.isEmpty { query.append(URLQueryItem(name: "pageToken", value: pageToken)) }
        guard let scope = try mediaScope() else { throw APIError.unauthorized }
        let generation = cacheGeneration
        if !forceNetwork, usingOfflineCopy, let saved = mediaOffline.loadFeed(folder, scope: scope) { return saved }
        do {
            let (data, response) = try await request(path: "api/media", query: query, forceNetwork: forceNetwork)
            if !forceNetwork, response.value(forHTTPHeaderField: "X-JAC-Offline") != nil, let saved = mediaOffline.loadFeed(folder, scope: scope) { return saved }
            var feed = try decoder.decode(MediaFeed.self, from: data)
            try Task.checkCancellation()
            guard generation == cacheGeneration, scope.id == (try mediaScope())?.id else { throw CancellationError() }
            if feed.connected && feed.canRead {
                mediaOffline.allow(scope)
                let cache = mediaOffline, incoming = feed
                feed = try await Task.detached(priority: .utility) {
                    try Task.checkCancellation()
                    return try cache.saveFeed(incoming, key: folder, append: !pageToken.isEmpty, scope: scope)
                }.value
                try Task.checkCancellation()
                guard generation == cacheGeneration, scope.id == (try mediaScope())?.id else { throw CancellationError() }
            }
            else { mediaOffline.clear(scope); TemporaryDocuments.clear() }
            if let deleted=feed.deletedFiles,!deleted.isEmpty {cacheRevision += 1}
            return feed
        } catch {
            if !forceNetwork, AgendaOfflineCache.isUnavailable(error), let saved = cachedMedia(folder: folder) { return saved }
            throw error
        }
    }
    func deleteMediaFolderStep(_ folder:MediaFolder) async throws -> MediaFolderDeletion {
        guard permissionUser?.canDeleteMedia != false else{throw APIError.forbidden("Tu cuenta no tiene permiso para eliminar carpetas de Fotografía.")}
        guard !usingOfflineCopy else{throw APIError.invalid("Conéctate para eliminar una carpeta.")}
        let (data,_)=try await request(path:"api/media",body:.object(["action":.string("deleteFolder"),"id":.string(folder.id)]))
        let result=try decoder.decode(MediaFolderDeletion.self,from:data)
        guard result.id==folder.id,result.complete != nil,result.removed>=0,!result.parentId.isEmpty else{throw APIError.invalid("No se pudo confirmar la carpeta eliminada.")}
        if let scope=try mediaScope(){try mediaOffline.removeFolders([folder.id],scope:scope)}
        return result
    }
    func deleteMediaFileStep(_ item:MediaItem) async throws -> MediaFolderDeletion {
        guard permissionUser?.canDeleteMedia != false else {throw APIError.forbidden("Tu cuenta no tiene permiso para eliminar archivos de Fotografía.")}
        guard !usingOfflineCopy else {throw APIError.invalid("Conéctate para eliminar una foto.")}
        var body:[String:JSONValue]=["action":.string("deleteFile"),"id":.string(item.id)]
        if !item.modifiedAt.isEmpty {body["revision"] = .string(item.modifiedAt)}
        let (data,_)=try await request(path:"api/media",body:.object(body))
        let result=try decoder.decode(MediaFolderDeletion.self,from:data)
        guard result.id==item.id,result.complete != nil,result.removed>=0,!result.parentId.isEmpty else {throw APIError.invalid("No se pudo confirmar la foto eliminada.")}
        if let scope=try mediaScope() {try mediaOffline.removeFile(item,scope:scope)}
        mediaRootRead?.task.cancel();mediaRootRead=nil;invalidateWidgetSnapshot(); cacheGeneration += 1;cacheRevision += 1
        return result
    }
    func createMediaFolder(id: String, parentID: String, name: String, date: String) async throws -> MediaFolder {
        guard permissionUser?.canUploadMedia != false else {throw APIError.forbidden("Tu cuenta no tiene permiso para subir contenido.")}
        let (data, _) = try await request(path: "api/media", body: .object(["action": .string("createFolder"), "id": .string(id), "parentId": .string(parentID), "name": .string(name), "date": .string(date)]))
        struct Result: Decodable { let folder: MediaFolder }
        return try decoder.decode(Result.self, from: data).folder
    }
    private func mediaUploadCommand(_ fields: [String: JSONValue]) async throws -> MediaUploadState {
        guard permissionUser?.canUploadMedia != false else {throw APIError.forbidden("Tu cuenta no tiene permiso para subir contenido.")}
        let data: Data
        if let mediaUploadTransport {
            let (base, token, generation) = try mediaRequest(path: "api/media/upload", query: [], method: "POST")
            var command = base; command.setValue("application/json", forHTTPHeaderField: "Content-Type")
            let encoder = JSONEncoder(); encoder.outputFormatting = .sortedKeys
            let payload = try encoder.encode(JSONValue.object(fields))
            let (bytes, raw) = try await mediaUploadTransport.send(command, body: payload, key: "control:" + (try mediaScope())!.id + ":" + (fields["id"]?.text ?? "") + ":" + (fields["action"]?.text ?? ""), progress: { _ in })
            _ = try validateMediaResponse(raw, data: bytes, token: token, generation: generation)
            data = bytes
        } else {
            (data, _) = try await request(path: "api/media/upload", body: .object(fields), forceNetwork: true)
        }
        return try decoder.decode(MediaUploadState.self, from: data)
    }
    private func mediaRequest(path: String, query: [URLQueryItem], method: String = "GET") throws -> (URLRequest, String, Int) {
        guard permissionUser?.canReadMedia != false,method != "PUT" || permissionUser?.canUploadMedia != false else {throw APIError.forbidden("Tu cuenta no tiene acceso a esta operación de Fotografía.")}
        guard let token = try checkedToken(), token.range(of: "^[A-Za-z0-9_-]{43}$", options: .regularExpression) != nil else { throw APIError.unauthorized }
        var req = URLRequest(url: resourceURL(path: path, query: query))
        req.httpMethod = method; req.httpShouldHandleCookies = false
        req.setValue("\(cookieName)=\(token)", forHTTPHeaderField: "Cookie")
        req.setValue(origin, forHTTPHeaderField: "Origin")
        req.setValue("no-store", forHTTPHeaderField: "Cache-Control")
        if method == "PUT" { req.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type") }
        return (req, token, cacheGeneration)
    }
    private func validateMediaResponse(_ raw: URLResponse, data: Data, token: String, generation: Int) throws -> HTTPURLResponse {
        guard token == (try checkedToken()), generation == cacheGeneration else { throw CancellationError() }
        guard let response = raw as? HTTPURLResponse else { throw APIError.message("No se recibió una respuesta válida.") }
        if response.statusCode == 401 || (300..<400).contains(response.statusCode) { try clearSession(); throw APIError.unauthorized }
        guard (200..<300).contains(response.statusCode) else {
            let error = (try? decoder.decode(JSONValue.self, from: data))?["error"].text
            let message = error?.isEmpty == false ? error! : "No se pudo completar la transferencia. Intenta de nuevo."
            if response.statusCode == 403 { invalidateWidgetSnapshot(); cacheGeneration += 1; if let scope = try mediaScope() { mediaOffline.clear(scope); TemporaryDocuments.clear() }; throw APIError.forbidden(message) }
            if [400, 413, 415, 422].contains(response.statusCode) { throw APIError.invalid(message) }
            if response.statusCode == 409 { throw APIError.conflict(message) }
            throw APIError.message(message)
        }
        return response
    }
    func uploadMedia(_ file: MediaLocalFile, parentID: String, transferred: @escaping (Int64) -> Void = {_ in}, progress: @escaping (Int64, Int64) -> Void) async throws {
        if try await uploadMediaOriginal(file, parentID: parentID, transferred: transferred, progress: progress) == "r2" { try await uploadMediaThumbnail(file) }
    }
    func uploadMediaOriginal(_ file: MediaLocalFile, parentID: String, transferred: @escaping (Int64) -> Void = {_ in}, progress: @escaping (Int64, Int64) -> Void) async throws -> String? {
        guard !usingOfflineCopy else { throw APIError.invalid("Conéctate para subir fotos y videos.") }
        let stamp = try mediaAccessStamp()
        var plan = try await mediaUploadCommand(["action": .string("start"), "transport": .string("direct"), "id": .string(file.id), "parentId": .string(parentID), "filename": .string(file.name), "mimeType": .string(file.mimeType), "size": .number(Double(file.size)), "imageLimit": .number(Double(file.imageLimit))])
        try plan.validate(for: file); progress(plan.offset, file.size)
        let handle = try FileHandle(forReadingFrom: file.url); defer { try? handle.close() }; var compatible = false, expiredRetries = 0
        while !plan.complete {
            try Task.checkCancellation()
            try handle.seek(toOffset: UInt64(plan.offset))
            let count = min(compatible ? 1024 * 1024 : plan.chunkSize, Int(file.size - plan.offset))
            guard count > 0, let chunk = try handle.read(upToCount: count), chunk.count == count else { throw APIError.invalid("El archivo local cambió. Vuelve a seleccionarlo.") }
            let (legacyRequest, token, generation) = try mediaRequest(path: "api/media/upload", query: [URLQueryItem(name: "id", value: file.id), URLQueryItem(name: "offset", value: String(plan.offset))] + (plan.uploadURL == nil ? [] : [URLQueryItem(name: "transport", value: "direct")]), method: "PUT")
            let previous = plan.offset
            var transmitted:Int64=0
            let onTransferred: @MainActor (Int64) -> Void = {sent in
                guard stamp == (try? self.mediaAccessStamp()),!Task.isCancelled else{return}
                let value=min(Int64(count),max(transmitted,sent));transferred(value-transmitted);transmitted=value
                progress(previous+value,file.size)
            }
            let observer=MediaUploadObserver(onTransferred)
            defer {observer.stop()}
            var expiredSignedPart = false
            do {
                guard stamp == (try mediaAccessStamp()) else { throw CancellationError() }
                if let url = plan.uploadURL, !compatible {
                    let direct = try Self.directMediaRequest(url, mime: file.mimeType, offset: previous, count: count, total: file.size)
                    let raw: URLResponse
                    if let mediaUploadTransport { (_, raw) = try await mediaUploadTransport.send(direct, body: chunk, key: "part:" + (try mediaScope())!.id + ":" + file.id + ":" + String(previous), progress: onTransferred) }
                    else { (_, raw) = try await mediaSession.upload(for: direct, from: chunk, delegate:observer) }
                    observer.stop()
                    expiredSignedPart = plan.provider == "r2" && (raw as? HTTPURLResponse)?.statusCode == 403
                    guard stamp == (try mediaAccessStamp()), !Task.isCancelled else { throw CancellationError() }
                    guard let response = raw as? HTTPURLResponse, (200..<300).contains(response.statusCode) || response.statusCode == 308 else { throw APIError.message("El almacenamiento no confirmó la transferencia. Reintenta para consultar su avance.") }
                    transferred(Int64(count)-transmitted)
                    var confirmation: [String: JSONValue] = ["action": .string("status"), "transport": .string("direct"), "id": .string(file.id)]
                    if plan.provider == "r2", previous == 0, Int64(count) == file.size,
                       let etag = response.value(forHTTPHeaderField: "ETag"), etag.range(of: "^\"[a-fA-F0-9]{32}\"$", options: .regularExpression) != nil {
                        confirmation["partReceipt"] = .object(["partNumber": .number(1), "etag": .string(etag), "size": .number(Double(count))])
                    }
                    plan = try await mediaUploadCommand(confirmation)
                } else {
                    let (data, raw) = try await mediaSession.upload(for: legacyRequest, from: chunk, delegate:observer)
                    observer.stop()
                    _ = try validateMediaResponse(raw, data: data, token: token, generation: generation)
                    transferred(Int64(count)-transmitted)
                    plan = try decoder.decode(MediaUploadState.self, from: data)
                }
            } catch {
                if error is CancellationError || (error as? URLError)?.code == .cancelled { throw error }
                if case APIError.unauthorized = error { throw error }
                if case APIError.forbidden = error { throw error }
                if case APIError.invalid = error { throw error }
                // A timed-out chunk may already be stored. Ask JAC for the
                // committed offset before retrying; never create a second file.
                plan = try await mediaUploadCommand(["action": .string("status"), "transport": .string("direct"), "id": .string(file.id)])
                try plan.validate(for: file)
                if plan.provider != "r2", plan.uploadURL != nil, !compatible, plan.offset == previous { compatible = true; continue }
                if expiredSignedPart, plan.provider == "r2", plan.offset == previous, expiredRetries < 2 { expiredRetries += 1; continue }
                guard plan.offset > previous else { throw error }
            }
            expiredRetries = 0
            try plan.validate(for: file)
            guard plan.offset > previous else { throw APIError.message("La subida no avanzó. Reintenta el mismo archivo.") }
            progress(plan.offset, file.size)
        }
        return plan.provider
    }
    func uploadMediaThumbnail(_ file: MediaLocalFile) async throws {
        let stamp = try mediaAccessStamp()
        for preview in file.mimeType.hasPrefix("image/") ? [false, true] : [false] {
            guard let bytes = await MediaThumbnail.jpeg(for: file, edge: preview ? 1600 : 360, quality: preview ? 0.76 : 0.60, limit: preview ? 2 * 1024 * 1024 : 512 * 1024) else {
                try Task.checkCancellation(); throw APIError.message("Original subido. Reintenta para completar sus vistas ligeras.")
            }
            guard stamp == (try mediaAccessStamp()), !Task.isCancelled else { throw CancellationError() }
            let kind = preview ? "preview" : "thumbnail"
            let (request, token, generation) = try mediaRequest(path: "api/media/upload", query: [URLQueryItem(name: kind, value: "1"), URLQueryItem(name: "id", value: file.id)], method: "PUT")
            var upload = request; upload.setValue("image/jpeg", forHTTPHeaderField: "Content-Type")
            let data: Data, response: URLResponse
            if let mediaUploadTransport { (data, response) = try await mediaUploadTransport.send(upload, body: bytes, key: kind + ":" + (try mediaScope())!.id + ":" + file.id, progress: { _ in }) }
            else { (data, response) = try await mediaSession.upload(for: upload, from: bytes) }
            _ = try validateMediaResponse(response, data: data, token: token, generation: generation)
        }
    }
    static func directMediaRequest(_ url: URL, mime: String, offset: Int64, count: Int, total: Int64) throws -> URLRequest {
        guard let parts = URLComponents(url: url, resolvingAgainstBaseURL: false), parts.scheme == "https", parts.port == nil, parts.user == nil, parts.password == nil, parts.fragment == nil,
              offset >= 0, count > 0, count <= 8 * 1024 * 1024, offset + Int64(count) <= total else { throw APIError.invalid("La autorización de subida no es válida.") }
        let r2 = parts.host?.range(of: "^[a-f0-9]{32}\\.r2\\.cloudflarestorage\\.com$", options: .regularExpression) != nil
        if r2 {
            let items = parts.queryItems ?? [], allowed: Set<String> = ["uploadId", "partNumber", "X-Amz-Algorithm", "X-Amz-Credential", "X-Amz-Date", "X-Amz-Expires", "X-Amz-SignedHeaders", "X-Amz-Signature"]
            let values = Dictionary(items.map { ($0.name, $0.value ?? "") }, uniquingKeysWith: { a, _ in a })
            guard items.count == allowed.count, Set(items.map(\.name)) == allowed,
                  parts.path.range(of: "^/jac-fotografia/originals/[a-f0-9-]{36}$", options: .regularExpression) != nil,
                  !(values["uploadId"] ?? "").isEmpty, Int64(values["partNumber"] ?? "") == offset / (8 * 1024 * 1024) + 1,
                  offset % (8 * 1024 * 1024) == 0, count == min(8 * 1024 * 1024, Int(total - offset)),
                  values["X-Amz-Algorithm"] == "AWS4-HMAC-SHA256", values["X-Amz-Expires"] == "300", values["X-Amz-SignedHeaders"] == "content-length;content-type;host",
                  values["X-Amz-Credential"]?.range(of: "^[a-fA-F0-9]{32}/[0-9]{8}/auto/s3/aws4_request$", options: .regularExpression) != nil,
                  values["X-Amz-Date"]?.range(of: "^[0-9]{8}T[0-9]{6}Z$", options: .regularExpression) != nil,
                  values["X-Amz-Signature"]?.range(of: "^[a-f0-9]{64}$", options: .regularExpression) != nil else { throw APIError.invalid("La autorización de subida no es válida.") }
        } else {
            guard parts.host == "www.googleapis.com", parts.path.range(of: "^/upload/drive/v3/files(/[A-Za-z0-9_-]+)?$", options: .regularExpression) != nil,
                  parts.queryItems?.filter({ $0.name == "upload_id" && !($0.value ?? "").isEmpty }).count == 1 else { throw APIError.invalid("La autorización de subida no es válida.") }
        }
        var request = URLRequest(url: url); request.httpMethod = "PUT"; request.httpShouldHandleCookies = false; request.cachePolicy = .reloadIgnoringLocalCacheData; request.timeoutInterval = 120
        request.setValue(mime, forHTTPHeaderField: "Content-Type")
        if r2 { request.setValue(String(count), forHTTPHeaderField: "Content-Length") }
        else { request.setValue("bytes \(offset)-\(offset + Int64(count) - 1)/\(total)", forHTTPHeaderField: "Content-Range") }
        // This request intentionally has no JAC cookie, owner OAuth token or
        // Authorization header. The URL only authorizes its reserved new file.
        return request
    }
    func mediaThumbnail(_ item: MediaItem, networkAllowed: Bool = true) async throws -> Data {
        guard let scope = try mediaScope(), permissionUser?.canReadMedia != false else { throw APIError.unauthorized }
        let stamp = try mediaAccessStamp(), cache = mediaOffline
        let saved = await Task.detached(priority: .utility) { cache.loadThumbnail(item, scope: scope) }.value
        guard stamp == (try mediaAccessStamp()), permissionUser?.canReadMedia != false else { throw CancellationError() }
        if let saved { return saved }
        guard networkAllowed, !usingOfflineCopy else { throw MediaThumbnailUnavailable() }
        let (data, response) = try await request(path: "api/media/file", query: [URLQueryItem(name: "id", value: item.id), URLQueryItem(name: "revision", value: item.modifiedAt), URLQueryItem(name: "thumbnail", value: "1")], document: true, forceNetwork: true)
        guard data.count <= 512 * 1024, ["image/jpeg", "image/png", "image/webp", "image/gif"].contains(response.mimeType ?? "") else { throw APIError.invalid("No se recibió una miniatura válida.") }
        guard stamp == (try mediaAccessStamp()) else { throw CancellationError() }
        _ = await Task.detached(priority: .utility) { try? cache.saveThumbnail(data, item: item, scope: scope) }.value
        guard stamp == (try mediaAccessStamp()) else { throw CancellationError() }
        return data
    }
    func mediaPlayback(_ item: MediaItem) async throws -> URL {
        struct Playback: Decodable { let ready: Bool; let url: String?; let message: String?; let status: String? }
        let (data, _) = try await request(path: "api/media/playback", query: [URLQueryItem(name: "id", value: item.id)], forceNetwork: true)
        let info = try decoder.decode(Playback.self, from: data)
        if !info.ready {
            let message = info.message ?? "Preparando la reproducción adaptativa."
            if !["error", "uncertain", "configuration", "unconfigured"].contains(info.status ?? "") { throw MediaPlaybackPending(message: message) }
            throw APIError.message(message)
        }
        guard let raw = info.url, let url = URL(string: raw), url.scheme == baseURL.scheme, url.host == baseURL.host,
              url.port == baseURL.port, url.path == "/api/media/playback", let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
              parts.queryItems?.contains(where: { $0.name == "lease" && !($0.value ?? "").isEmpty }) == true else { throw APIError.message(info.message ?? "Preparando la reproducción adaptativa. Vuelve a abrir el video en unos momentos.") }
        return url
    }
    func mediaPhotoPreview(_ item: MediaItem, quality: MediaPhotoPreviewQuality = .detail,
                           priority: MediaPhotoPreviewPipeline.Priority = .visible,
                           collectionID: String? = nil,
                           progress: @escaping (Int64, Int64) -> Void = { _, _ in }) async throws -> ExportedDocument {
        guard item.kind == "image", permissionUser?.canReadMedia != false, let scope = try mediaScope(),
              let stamp = try mediaAccessStamp() else { throw APIError.unauthorized }
        // Explicit offline downloads are useful even while the phone is online.
        // Reading them must never wait for a metadata request or a remote JPEG.
        let cache = mediaOffline, offline = usingOfflineCopy
        let cached = await Task.detached(priority: .userInitiated) {
            cache.photoPreviewSnapshot(item, quality: quality, allowBalanced: offline, scope: scope)
        }.value
        guard !Task.isCancelled, stamp == (try mediaAccessStamp()), cache.photoPreviewEpoch == cached.epoch,
              collectionID == nil || cached.collectionID == collectionID else { throw CancellationError() }
        if let bytes = cached.data {
            progress(Int64(bytes.count), Int64(bytes.count))
            return try await preparePhotoPreviewDocument(bytes, quality: cached.quality, stamp: stamp, epoch: cached.epoch)
        }
        if let saved = try await restoredMediaDocument(item, scope: scope) {
            progress(item.size, item.size); return saved
        }
        guard !usingOfflineCopy else { throw APIError.message("Esta foto todavía no está descargada en este dispositivo.") }
        let bytes = try await photoPreviewBytes(item, quality: quality, priority: priority, scope: scope, stamp: stamp, collectionID: cached.collectionID)
        guard !Task.isCancelled, stamp == (try mediaAccessStamp()) else { throw CancellationError() }
        progress(Int64(bytes.count), Int64(bytes.count))
        return try await preparePhotoPreviewDocument(bytes, quality: quality, stamp: stamp, epoch: cached.epoch)
    }

    private func preparePhotoPreviewDocument(_ data: Data, quality: MediaPhotoPreviewQuality, stamp: String, epoch: UInt64) async throws -> ExportedDocument {
        let work = Task.detached(priority: .userInitiated) {
            try Task.checkCancellation()
            return try TemporaryDocuments.save(data, filename: quality.filename)
        }
        let document: ExportedDocument
        do { document = try await withTaskCancellationHandler { try await work.value } onCancel: { work.cancel() } }
        catch {
            #if DEBUG
            if baseURL.host?.hasSuffix(".invalid") == true { print("JAC photo-preview temporary write failed: \((error as NSError).domain) \((error as NSError).code)") }
            #endif
            throw error
        }
        var accepted = false
        defer { if !accepted { TemporaryDocuments.remove(document) } }
        try Task.checkCancellation()
        guard stamp == (try mediaAccessStamp()), mediaOffline.photoPreviewEpoch == epoch else { throw CancellationError() }
        accepted = true; return document
    }

    func prefetchMediaPhotoPreview(_ item: MediaItem, collectionID: String? = nil) async throws {
        guard !usingOfflineCopy, let scope = try mediaScope(), let stamp = try mediaAccessStamp(),
              permissionUser?.canReadMedia != false else { throw CancellationError() }
        let cache = mediaOffline
        let saved = await Task.detached(priority: .utility) {
            (cache.hasFile(item, scope: scope) || cache.loadPhotoPreview(item, quality: .detail, scope: scope) != nil
                || cache.loadPhotoPreview(item, quality: .balanced, scope: scope) != nil, cache.photoPreviewCollection(scope: scope))
        }.value
        guard !Task.isCancelled, stamp == (try mediaAccessStamp()), collectionID == nil || saved.1 == collectionID else { throw CancellationError() }
        if !saved.0 { _ = try await photoPreviewBytes(item, quality: .balanced, priority: .prefetch, scope: scope, stamp: stamp, collectionID: saved.1) }
    }

    func improveMediaPhotoPreview(_ item: MediaItem, current: ExportedDocument) async throws -> ExportedDocument? {
        guard current.url.lastPathComponent == MediaPhotoPreviewQuality.balanced.filename,
              photoPreviews.connection.improvesQuality, !usingOfflineCopy else { return nil }
        return try await mediaPhotoPreview(item, quality: .detail)
    }

    private func photoPreviewBytes(_ item: MediaItem, quality: MediaPhotoPreviewQuality,
                                   priority: MediaPhotoPreviewPipeline.Priority, scope: AgendaCacheScope, stamp: String, collectionID: String?) async throws -> Data {
        let key = [stamp, collectionID ?? "", item.id, item.modifiedAt, String(item.size), item.mimeType, quality.rawValue].joined(separator: "|")
        return try await photoPreviews.data(key: key, priority: priority, authorized: { [weak self] in
            guard let self else { return false }
            return self.mediaPresentationStamp == stamp && self.accessUser?.canReadMedia != false
        }) { [self] in
            let cache = mediaOffline
            let state = await Task.detached(priority: .utility) {
                (cache.loadPhotoPreview(item, quality: quality, scope: scope), cache.photoPreviewCollection(scope: scope))
            }.value
            guard !Task.isCancelled, stamp == (try mediaAccessStamp()), state.1 == collectionID else { throw CancellationError() }
            if let bytes = state.0 { return bytes }
            let started = ProcessInfo.processInfo.systemUptime
            let bytes = try await downloadPhotoPreview(item, quality: quality, stamp: stamp)
            photoPreviews.measured(bytes: bytes.count, seconds: ProcessInfo.processInfo.systemUptime - started)
            let write = Task.detached(priority: .utility) {
                try cache.savePhotoPreview(bytes, item: item, quality: quality, scope: scope, collectionID: state.1)
            }
            do { try await withTaskCancellationHandler { try await write.value } onCancel: { write.cancel() } }
            catch {
                guard !Task.isCancelled, stamp == (try mediaAccessStamp()), !cache.isDeleted(item.id, scope: scope),
                      cache.photoPreviewCollection(scope: scope) == state.1 else { throw CancellationError() }
                // Disk full is allowed to keep the currently authorized preview.
            }
            guard !Task.isCancelled, stamp == (try mediaAccessStamp()) else { throw CancellationError() }
            return bytes
        }
    }

    private func downloadPhotoPreview(_ item: MediaItem, quality: MediaPhotoPreviewQuality, stamp: String) async throws -> Data {
        var retries = 0
        while true {
            do {
                var query = [URLQueryItem(name: "id", value: item.id), URLQueryItem(name: "preview", value: "1"), URLQueryItem(name: "revision", value: item.modifiedAt)]
                if quality == .balanced { query.append(URLQueryItem(name: "quality", value: "balanced")) }
                let (data, response) = try await request(path: "api/media/file", query: query, document: true, forceNetwork: true)
                guard !Task.isCancelled, stamp == (try mediaAccessStamp()) else { throw CancellationError() }
                guard !data.isEmpty, data.count <= quality.maximumBytes, response.mimeType == "image/jpeg" else { throw APIError.invalid("No se recibió una vista previa ligera.") }
                return data
            } catch let failure as MediaPreviewUnavailable {
                guard failure.preparing, retries < 2 else { throw failure }
                retries += 1
                try await Task.sleep(for: .seconds(failure.retryAfter))
                guard !Task.isCancelled, stamp == (try mediaAccessStamp()) else { throw CancellationError() }
            }
        }
    }

    private func restoredMediaDocument(_ item: MediaItem, scope: AgendaCacheScope) async throws -> ExportedDocument? {
        let generation = cacheGeneration
        let cache = mediaOffline, work = Task.detached(priority: .userInitiated) { try cache.document(item, scope: scope) }
        let document = try await withTaskCancellationHandler { try await work.value } onCancel: { work.cancel() }
        var accepted = false
        defer { if !accepted, let document { TemporaryDocuments.remove(document) } }
        try Task.checkCancellation()
        guard generation == cacheGeneration, scope.id == (try mediaScope())?.id else { throw CancellationError() }
        accepted = true
        return document
    }
    func mediaDocument(_ item: MediaItem, progress: @escaping (Int64, Int64) -> Void = { _, _ in }) async throws -> ExportedDocument {
        guard permissionUser?.canReadMedia != false else {throw APIError.forbidden("Tu cuenta no tiene acceso a Fotografía.")}
        guard let scope = try mediaScope() else { throw APIError.unauthorized }
        progress(0, item.size)
        if usingOfflineCopy {
            guard let saved = try await restoredMediaDocument(item, scope: scope) else { throw APIError.message("Este archivo todavía no está descargado. Conéctate y elige Disponible sin conexión.") }
            progress(item.size, item.size); return saved
        }
        let generation = cacheGeneration
        do {
            if mediaOffline.hasFile(item, scope: scope) {
                try await validateMediaItem(item)
                if let saved = try await restoredMediaDocument(item, scope: scope) { progress(item.size, item.size); return saved }
            }
            let document = try await downloadMediaDocument(item, progress: progress)
            if item.kind == "image", item.size <= 24 * 1024 * 1024, MediaStorageReview.freeBytes > item.size * 2 + 64 * 1024 * 1024 {
                let cache = mediaOffline, work = Task.detached(priority: .utility) { try cache.saveFile(document.url, item: item, scope: scope, preview: true) }
                do { try await withTaskCancellationHandler { try await work.value } onCancel: { work.cancel() } }
                catch { if scope.id != (try mediaScope())?.id { cache.clear(scope) } }
            }
            guard !Task.isCancelled, generation == cacheGeneration, scope.id == (try mediaScope())?.id else { TemporaryDocuments.remove(document); throw CancellationError() }
            progress(item.size, item.size); return document
        }
        catch {
            if AgendaOfflineCache.isUnavailable(error), let saved = try await restoredMediaDocument(item, scope: scope) { progress(item.size, item.size); return saved }
            throw error
        }
    }
    func validateMediaItem(_ item: MediaItem) async throws {
        let scope = try mediaScope()
        do {
            let (data, _) = try await request(path: "api/media/file", query: [URLQueryItem(name: "id", value: item.id), URLQueryItem(name: "metadata", value: "1")], forceNetwork: true)
            struct Result: Decodable { let item: MediaItem }
            let current = try decoder.decode(Result.self, from: data).item
            guard current.id == item.id, current.size == item.size, current.mimeType == item.mimeType, current.modifiedAt == item.modifiedAt else { throw APIError.conflict("El archivo cambió. Actualiza la carpeta.") }
        } catch is MediaFileRemoved {
            if let scope, scope.id == (try mediaScope())?.id { try mediaOffline.removeFile(item, scope: scope) }
            throw MediaFileRemoved()
        }
    }
    func mediaRange(_ item: MediaItem, offset: Int64, count: Int) async throws -> Data {
        guard count > 0, count <= 1024 * 1024, offset >= 0, offset < item.size, offset + Int64(count) <= item.size else { throw APIError.invalid("El tramo de video no es válido.") }
        var (req, token, generation) = try mediaRequest(path: "api/media/file", query: [URLQueryItem(name: "id", value: item.id), URLQueryItem(name: "revision", value: item.modifiedAt)])
        req.setValue("bytes=\(offset)-\(offset + Int64(count) - 1)", forHTTPHeaderField: "Range")
        let (data, raw) = try await mediaSession.data(for: req)
        let response = try validateMediaResponse(raw, data: data, token: token, generation: generation)
        guard response.statusCode == 206, response.mimeType == item.mimeType, data.count == count,
              response.value(forHTTPHeaderField: "Content-Range") == "bytes \(offset)-\(offset + Int64(count) - 1)/\(item.size)" else { throw APIError.invalid("El video cambió o llegó incompleto. Actualiza la carpeta.") }
        return data
    }
    private func downloadMediaDocument(_ item: MediaItem, progress: @escaping (Int64, Int64) -> Void = { _, _ in }) async throws -> ExportedDocument {
        guard item.kind != "folder", item.size > 0, item.size <= MediaLocalFile.maximumSize else { throw APIError.invalid("El archivo no está disponible para abrirse.") }
        let free = (try? FileManager.default.attributesOfFileSystem(forPath: TemporaryDocuments.root.deletingLastPathComponent().path)[.systemFreeSize] as? NSNumber)?.int64Value ?? Int64.max
        guard free > item.size + 64 * 1024 * 1024 else { throw APIError.invalid("No hay espacio suficiente para abrir este archivo en el dispositivo.") }
        let (req, token, generation) = try mediaRequest(path: "api/media/file", query: [URLQueryItem(name: "id", value: item.id), URLQueryItem(name: "revision", value: item.modifiedAt)])
        let stamp = try mediaAccessStamp()
        let observer = MediaDownloadProgressObserver(total: item.size) { [weak self] received, total in
            guard let self, stamp == (try? self.mediaAccessStamp()) else { return }
            progress(received, total)
        }
        defer { observer.stop() }
        let incoming: ExportedDocument, raw: URLResponse
        do { (incoming, raw) = try await observer.download(session: mediaSession, request: req) }
        catch let failure as MediaDownloadResponseFailure {
            _ = try validateMediaResponse(failure.response, data: Data(), token: token, generation: generation)
            throw APIError.invalid("La respuesta de descarga no es válida.")
        }
        defer { TemporaryDocuments.remove(incoming) }
        let temporary = incoming.url
        try FileManager.default.setAttributes(JACFileSecurity.fileAttributes, ofItemAtPath: temporary.path)
        let handle = try FileHandle(forReadingFrom: temporary); defer { try? handle.close() }
        let prefix = try handle.read(upToCount: 64 * 1024) ?? Data()
        let response = try validateMediaResponse(raw, data: prefix, token: token, generation: generation)
        let count = (try temporary.resourceValues(forKeys: [.fileSizeKey])).fileSize ?? 0
        guard count > 0, Int64(count) == item.size, response.mimeType == item.mimeType else { throw APIError.invalid("No se recibió una foto o video válido.") }
        try Task.checkCancellation()
        if let scope=try mediaScope(),mediaOffline.isDeleted(item.id,scope:scope) {throw MediaFileRemoved()}
        return try TemporaryDocuments.move(temporary, filename: MediaLocalFile.safeName(item.name))
    }

    #if os(iOS)
    func mediaFolderShares(_ folder: String) async throws -> [MediaSharedLink] {
        let (data, _) = try await request(path: "api/media/shares", query: [URLQueryItem(name: "folder", value: folder)], forceNetwork: true)
        struct Response: Decodable { let links: [MediaSharedLink] }
        return try decoder.decode(Response.self, from: data).links
    }
    func createMediaFolderShare(_ folder: String, id: String, days: Int) async throws -> MediaSharedLink {
        let (data, _) = try await request(path: "api/media/shares", body: .object([
            "action": .string("create"), "folderId": .string(folder), "id": .string(id), "days": .number(Double(days))]), forceNetwork: true)
        struct Response: Decodable { let link: MediaSharedLink }
        return try decoder.decode(Response.self, from: data).link
    }
    func revokeMediaFolderShare(_ folder: String, id: String) async throws {
        _ = try await request(path: "api/media/shares", body: .object([
            "action": .string("revoke"), "folderId": .string(folder), "id": .string(id)]), forceNetwork: true)
    }
    #endif

    func mediaDownloadPlan(folder: String = "", imagesOnly: Bool = false) async throws -> MediaDownloadPlan {
        var pending = [folder], seenFolders = Set<String>(), seenFiles = Set<String>(), files: [MediaItem] = [], root: MediaFolder?
        let stamp=try mediaAccessStamp();var firstFeed:MediaFeed?
        while !pending.isEmpty {
            try Task.checkCancellation()
            let current = pending.removeFirst(); guard seenFolders.insert(current).inserted else { continue }
            var cursor = "", seenPages = Set<String>(), folderItems: [MediaItem] = [], lastFeed: MediaFeed?
            repeat {
                let feed = try await media(folder: current, pageToken: cursor)
                guard stamp == (try mediaAccessStamp()) else {throw CancellationError()}
                if let firstFeed {guard firstFeed.collectionID == feed.collectionID,firstFeed.root?.id == feed.root?.id else {throw APIError.invalid("La colección cambió. Actualiza Fotografía e inténtalo de nuevo.")}}else {firstFeed=feed}
                guard feed.connected, feed.canRead else { throw APIError.forbidden("La carpeta ya no está disponible para tu cuenta.") }
                if root == nil { root = feed.folder ?? feed.root }
                folderItems += feed.items; lastFeed = feed
                for item in feed.items {
                    if item.kind == "folder" { if !seenFolders.contains(item.id) { pending.append(item.id) } }
                    else if (!imagesOnly || item.kind == "image"), seenFiles.insert(item.id).inserted { files.append(item) }
                }
                cursor = feed.nextPageToken ?? ""
                guard cursor.isEmpty || seenPages.insert(cursor).inserted else { throw APIError.message("No se pudo completar el listado. Actualiza la carpeta.") }
            } while !cursor.isEmpty
            if let feed = lastFeed, let scope = try mediaScope() {
                let complete = MediaFeed(connected: feed.connected, canRead: feed.canRead, canUpload: feed.canUpload, canConnect: feed.canConnect, root: feed.root, folder: feed.folder, breadcrumbs: feed.breadcrumbs, items: folderItems, nextPageToken: nil,provider:feed.provider,collectionID:feed.collectionID,canDelete:feed.canDelete,pendingDeletions:feed.pendingDeletions,deletedFolders:feed.deletedFolders,deletedFiles:feed.deletedFiles,pendingFileDeletions:feed.pendingFileDeletions)
                try mediaOffline.pinFeed(complete, key: current, scope: scope)
            }
        }
        guard let root else { throw APIError.invalid("No se encontró la carpeta.") }
        return MediaDownloadPlan(folder: root, files: files)
    }
    func saveMediaOffline(_ item: MediaItem) async throws {
        guard permissionUser?.canReadMedia != false else {throw APIError.forbidden("Tu cuenta no tiene acceso a Fotografía.")}
        guard let scope = try mediaScope() else { throw APIError.unauthorized }
        if mediaOffline.hasFile(item, scope: scope) {if !usingOfflineCopy {try await validateMediaItem(item)};try mediaOffline.pinFile(item,scope:scope);cacheRevision += 1;return}
        let generation = cacheGeneration, localEpoch = mediaOffline.localDownloadEpoch
        guard MediaStorageReview.freeBytes > item.size * 2 + 64 * 1024 * 1024 else { throw APIError.invalid("No hay espacio suficiente para descargar y cifrar este archivo. Libera espacio e inténtalo de nuevo.") }
        let document = try await downloadMediaDocument(item); defer { TemporaryDocuments.remove(document) }
        guard !Task.isCancelled, generation == cacheGeneration, scope.id == (try mediaScope())?.id else { throw CancellationError() }
        let cache = mediaOffline, work = Task.detached(priority: .utility) { try cache.saveFile(document.url, item: item, scope: scope, expectedLocalEpoch: localEpoch) }
        do { try await withTaskCancellationHandler { try await work.value } onCancel: { work.cancel() } }
        catch { if scope.id != (try mediaScope())?.id { cache.clear(scope) }; throw error }
        guard !Task.isCancelled, generation == cacheGeneration, scope.id == (try mediaScope())?.id else { cache.clear(scope); throw CancellationError() }
        try mediaOffline.pinFile(item,scope:scope);cacheRevision += 1
    }

    func startGmail() async throws -> GmailStart {
        let (data, _) = try await request(path: "api/mobile/gmail", body: .object([:]))
        let start = try decoder.decode(GmailStart.self, from: data)
        guard start.url.scheme == "https", start.url.host == baseURL.host, start.url.port == baseURL.port,
              start.url.path == "/api/mobile/gmail", start.url.user == nil, start.url.password == nil,
              start.nonce.range(of: "^[A-Za-z0-9_-]{43}$", options: .regularExpression) != nil else {
            throw APIError.message("La autorización recibida no es válida.")
        }
        return start
    }
    func download(periodID: String, format: DocumentFormat, employeeID: String? = nil) async throws -> ExportedDocument {
        var query = [URLQueryItem(name: "period", value: periodID), URLQueryItem(name: "format", value: format.rawValue)]
        if let employeeID { query.append(URLQueryItem(name: "employee", value: employeeID)) }
        let (data, response) = try await request(path: "api/payroll/export", query: query, document: true, cacheRevision: cachedWorkspace()?.version ?? 0)
        guard !data.isEmpty else { throw APIError.message("El documento llegó vacío. Intenta de nuevo.") }
        let expectedType = format == .xlsx ? "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet" : format == .zip ? "application/zip" : "application/pdf"
        guard response.mimeType == expectedType else { throw APIError.message("No se recibió un documento válido.") }
        let fallback = "nomina-\(UUID().uuidString).\(format.fileExtension)"
        let filename = response.value(forHTTPHeaderField: "Content-Disposition")?.components(separatedBy: "filename=\"").last?.components(separatedBy: "\"").first
        let safeName = filename.map { ($0 as NSString).lastPathComponent } ?? fallback
        return try TemporaryDocuments.save(data, filename: safeName.isEmpty ? fallback : safeName)
    }
}

struct ExportedDocument: Identifiable {
    let id: UUID
    let url: URL
}

enum TemporaryDocuments {
    private static let lock = NSRecursiveLock()
    static var root: URL { FileManager.default.temporaryDirectory.appendingPathComponent("JACPayrollDocuments", isDirectory: true) }
    static func save(_ data: Data, filename: String) throws -> ExportedDocument {
        lock.lock(); defer { lock.unlock() }
        JACPerformanceDiagnostics.record(.diskWrite)
        let id = UUID()
        let folder = root.appendingPathComponent(id.uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true, attributes: JACFileSecurity.directoryAttributes)
        try FileManager.default.setAttributes(JACFileSecurity.directoryAttributes, ofItemAtPath: root.path)
        let url = folder.appendingPathComponent(filename)
        try data.write(to: url, options: JACFileSecurity.writeOptions)
        try FileManager.default.setAttributes(JACFileSecurity.fileAttributes, ofItemAtPath: url.path)
        return ExportedDocument(id: id, url: url)
    }
    static func move(_ source: URL, filename: String) throws -> ExportedDocument {
        lock.lock(); defer { lock.unlock() }
        let id = UUID()
        // Use the document UUID for deterministic cleanup on dismiss/logout.
        let targetFolder = root.appendingPathComponent(id.uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: targetFolder, withIntermediateDirectories: true, attributes: JACFileSecurity.directoryAttributes)
        try FileManager.default.setAttributes(JACFileSecurity.directoryAttributes, ofItemAtPath: root.path)
        let url = targetFolder.appendingPathComponent(filename)
        do {
            try FileManager.default.moveItem(at: source, to: url)
            try FileManager.default.setAttributes(JACFileSecurity.fileAttributes, ofItemAtPath: url.path)
            return ExportedDocument(id: id, url: url)
        } catch { try? FileManager.default.removeItem(at: targetFolder); throw error }
    }
    static func remove(_ document: ExportedDocument) { lock.lock(); defer { lock.unlock() }; try? FileManager.default.removeItem(at: root.appendingPathComponent(document.id.uuidString)) }
    static func clear() { lock.lock(); defer { lock.unlock() }; try? FileManager.default.removeItem(at: root) }
}

// Música has its own namespace, permission checks and encrypted download cache.
extension PayrollClient {
    func beginMusicPlayback() throws {
        guard permissionUser?.canReadMusic == true else { throw APIError.forbidden("Tu cuenta no tiene acceso a Música.") }
        if musicPlaybackToken == nil { musicPlaybackToken = try checkedToken() }
    }
    func endMusicPlayback() { musicPlaybackToken = nil }
    func musicScope() throws -> AgendaCacheScope? {
        guard let token = try musicPlaybackToken ?? checkedToken(), token.range(of: "^[A-Za-z0-9_-]{43}$", options: .regularExpression) != nil else { return nil }
        if let saved = derivedMusicScope, saved.token == token { return saved.scope }
        let scope = AgendaCacheScope(origin: origin + "/music-offline-v1", token: token)
        derivedMusicScope = (token, scope); return scope
    }
    func cachedMusic() -> MusicLibrary? { cached(MusicLibrary.self, path: "api/music") }
    func musicLibrary(forceNetwork: Bool = false) async throws -> MusicLibrary {
        let previous = cachedMusic()
        let (data, _) = try await request(path: "api/music", forceNetwork: forceNetwork)
        let result = try decoder.decode(MusicLibrary.self, from: data)
        if let scope = try musicScope() {
            let cache = musicOffline, fresh = Dictionary(uniqueKeysWithValues: result.tracks.map { ($0.id, $0) })
            if let previous { for old in previous.tracks where fresh[old.id]?.revision != old.revision { try cache.forgetLocalFile(old.mediaItem, scope: scope) } }
            try? cache.allowBackgroundAudio(scope)
        }
        return result
    }
    func musicPlayback(_ track: MusicTrack) async throws -> (URL, ExportedDocument?) {
        guard permissionUser?.canReadMusic == true, let scope = try musicScope() else { throw APIError.unauthorized }
        let cache = musicOffline
        if cache.hasFile(track.mediaItem, scope: scope) {
            let document = try await Task.detached(priority: .userInitiated) { try cache.document(track.mediaItem, scope: scope, backgroundAudio: true) }.value
            guard scope.id == (try musicScope())?.id, permissionUser?.canReadMusic == true else { if let document {MusicPlaybackDocuments.remove(document)}; throw CancellationError() }
            if let document { return (document.url, document) }
        }
        guard let token = musicPlaybackToken else { throw APIError.unauthorized }
        var req = URLRequest(url: resourceURL(path: "api/music", query: [URLQueryItem(name:"play",value:"1"),URLQueryItem(name:"id",value:track.id),URLQueryItem(name:"revision",value:track.revision)]))
        req.httpShouldHandleCookies = false; req.setValue("\(cookieName)=\(token)", forHTTPHeaderField: "Cookie")
        let (data, raw) = try await session.data(for: req)
        guard musicPlaybackToken == token, permissionUser?.canReadMusic == true else { throw CancellationError() }
        guard let response = raw as? HTTPURLResponse else {throw APIError.message("No se recibió una respuesta.")}
        if response.statusCode == 401 {try clearSession(); throw APIError.unauthorized}
        if response.statusCode == 403 {musicOffline.clear(scope);musicPlaybackToken=nil;throw APIError.forbidden("Tu cuenta ya no tiene acceso a Música.")}
        guard response.statusCode == 200 else {throw APIError.message("No se pudo abrir el audio. Revisa la conexión.")}
        struct Playback: Decodable { let url: String }
        let reply = try decoder.decode(Playback.self, from: data)
        guard reply.url.hasPrefix("/api/music/file?"), let url = URL(string: reply.url, relativeTo: baseURL)?.absoluteURL, url.host == baseURL.host, url.scheme == "https", url.port == baseURL.port, url.user == nil else { throw APIError.invalid("La dirección del audio no es válida.") }
        return (url, nil)
    }
    func musicHasDownload(_ track: MusicTrack) -> Bool {
        guard permissionUser?.canReadMusic == true, let scope = try? musicScope() else { return false }
        return musicOffline.hasFile(track.mediaItem, scope: scope)
    }
    func forgetMusic(_ track: MusicTrack) throws {
        guard let scope = try musicScope() else { return }
        try musicOffline.forgetLocalFile(track.mediaItem, scope: scope)
        try? musicOffline.allowBackgroundAudio(scope)
    }
    func downloadMusic(_ track: MusicTrack, progress: @escaping @MainActor (Double) -> Void) async throws {
        guard permissionUser?.canReadMusic == true, let scope = try musicScope(), let token = try checkedToken() else { throw APIError.unauthorized }
        if musicHasDownload(track) { return }
        var req = URLRequest(url: resourceURL(path: "api/music/file", query: [URLQueryItem(name:"id",value:track.id),URLQueryItem(name:"revision",value:track.revision)]))
        req.httpShouldHandleCookies = false; req.setValue("\(cookieName)=\(token)", forHTTPHeaderField:"Cookie")
        let transfer = MediaDownloadProgressObserver(total: track.size, callback: { received, total in progress(total > 0 ? Double(received)/Double(total) : 0) })
        let (document, raw) = try await transfer.download(session: mediaSession, request: req)
        defer { TemporaryDocuments.remove(document) }
        guard token == (try checkedToken()), permissionUser?.canReadMusic == true, scope.id == (try musicScope())?.id else { throw CancellationError() }
        guard let response = raw as? HTTPURLResponse else { throw APIError.message("No se recibió el audio.") }
        if response.statusCode == 401 { try clearSession(); throw APIError.unauthorized }
        if response.statusCode == 403 { musicOffline.clear(scope); throw APIError.forbidden("Tu cuenta ya no tiene acceso a Música.") }
        guard response.statusCode == 200, response.mimeType == track.mimeType, (try document.url.resourceValues(forKeys:[.fileSizeKey])).fileSize == Int(track.size) else { throw APIError.message("El audio cambió o llegó incompleto. Actualiza Música.") }
        let cache = musicOffline
        try await Task.detached(priority: .utility) { try cache.saveFile(document.url, item: track.mediaItem, scope: scope); try cache.pinFile(track.mediaItem, scope: scope); try cache.allowBackgroundAudio(scope) }.value
        guard token == (try checkedToken()), permissionUser?.canReadMusic == true else { cache.clear(scope); throw CancellationError() }
        progress(1)
    }
    func deleteMusic(_ track: MusicTrack) async throws {
        _ = try await request(path:"api/music",body:.object(["action":.string("delete"),"id":.string(track.id),"revision":.string(track.revision)]))
        try forgetMusic(track)
    }
    func uploadMusic(_ file: MusicImportFile, section: MusicSection, progress: @escaping @MainActor (Double) -> Void) async throws {
        guard permissionUser?.canUploadMusic == true, let token = try checkedToken(), let scope = try musicScope() else { throw APIError.forbidden("Tu cuenta no puede subir audios.") }
        struct Plan: Decodable { let offset: Int64; let ready: Bool; let chunkSize: Int }
        let (data, _) = try await request(path:"api/music/upload",body:.object(["action":.string("start"),"id":.string(file.id),"section":.string(section.rawValue),"filename":.string(file.name),"size":.number(Double(file.size))]))
        var plan = try decoder.decode(Plan.self, from:data)
        guard plan.chunkSize == 8*1024*1024 else { throw APIError.invalid("Actualiza la app antes de subir audio.") }
        let input = try FileHandle(forReadingFrom:file.url); defer {try? input.close()}
        while !plan.ready && plan.offset < file.size {
            try Task.checkCancellation()
            guard token == (try checkedToken()), permissionUser?.canUploadMusic == true else {throw CancellationError()}
            try input.seek(toOffset: UInt64(plan.offset))
            guard let bytes = try input.read(upToCount:plan.chunkSize), !bytes.isEmpty else {throw APIError.invalid("El audio está incompleto.")}
            var req = URLRequest(url:resourceURL(path:"api/music/upload",query:[URLQueryItem(name:"id",value:file.id),URLQueryItem(name:"offset",value:String(plan.offset))]))
            req.httpMethod="PUT";req.httpShouldHandleCookies=false;req.setValue("\(cookieName)=\(token)",forHTTPHeaderField:"Cookie");req.setValue(origin,forHTTPHeaderField:"Origin");req.setValue("application/octet-stream",forHTTPHeaderField:"Content-Type")
            let (reply, raw) = try await mediaSession.upload(for:req,from:bytes)
            guard token == (try checkedToken()),scope.id == (try musicScope())?.id,permissionUser?.canUploadMusic == true else {throw CancellationError()}
            guard let response=raw as? HTTPURLResponse else {throw APIError.message("No se recibió una respuesta.")}
            if response.statusCode == 401 {try clearSession();throw APIError.unauthorized}
            guard response.statusCode == 200 else {throw APIError.message((try? decoder.decode(JSONValue.self,from:reply))?["error"].text ?? "No se pudo subir el bloque. Reintenta la subida.")}
            let updated=try decoder.decode(Plan.self,from:reply)
            guard updated.offset > plan.offset,updated.offset <= file.size else {throw APIError.invalid("El progreso de la subida no es válido.")}
            plan=updated;progress(Double(plan.offset)/Double(file.size))
        }
        if !plan.ready {_ = try await request(path:"api/music/upload",body:.object(["action":.string("complete"),"id":.string(file.id)]))}
        progress(1)
    }
}

struct MediaPlaybackPending: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}
