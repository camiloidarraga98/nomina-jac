#if os(iOS)
import Foundation
import Combine
import CryptoKit
import Security

struct MediaUploadJob: Identifiable, Codable {
    let id: String
    let name: String
    let mimeType: String
    let size: Int64
    let imageLimit: Int64
    let destination: MediaFolder
    var progress: Double = 0
    var completed = false
    var error: String?
    fileprivate var phase = MediaUploadJobPhase.pending
    fileprivate var sourceName: String
    fileprivate var attempts = 0
    fileprivate var retryAt: Date?
    fileprivate var retryable = false
}

private enum MediaUploadJobPhase: String, Codable { case pending, original, thumbnail, done }

/// The outbox belongs to the signed-in session, never to a gallery view. Its
/// files are intentionally separate from preview/offline TemporaryDocuments.
@MainActor
final class MediaUploadQueue: ObservableObject {
    static let shared = MediaUploadQueue()
    typealias Original = (PayrollClient, MediaLocalFile, String, @escaping (Int64) -> Void, @escaping (Int64, Int64) -> Void) async throws -> String?
    typealias Thumbnail = (PayrollClient, MediaLocalFile) async throws -> Void
    typealias TransportFactory = (URL, URL) -> (any MediaUploadTransporting)?

    @Published private(set) var jobs: [MediaUploadJob] = []
    @Published private(set) var uploading = false
    @Published private(set) var notice: String?
    @Published private(set) var revision = 0
    @Published private(set) var meter = MediaUploadRate()
    var destination: MediaFolder? { jobs.first(where: { $0.phase != .done })?.destination ?? jobs.last?.destination }

    private struct Manifest: Codable {
        let schema: Int
        let origin: String
        let scope: String
        let actor: String?
        let paused: Bool
        let jobs: [MediaUploadJob]
    }
    private let configuredRoot: URL
    private let usesDefaultStorage: Bool
    private var root: URL
    private var vault: SessionStoring
    private var encryptionKeyStore: SessionStoring
    private let transportFactory: TransportFactory
    private let original: Original
    private let thumbnail: Thumbnail
    private let automaticallyStart: Bool
    private let retryDelays: [TimeInterval]
    private weak var mainClient: PayrollClient?
    private var workerClient: PayrollClient?
    private var transport: (any MediaUploadTransporting)?
    private var scope: String?
    private var origin: URL?
    private var actor: String?
    private var boundScope: String?
    private var boundScopeKnown = false
    private var fixture = false
    private var fixtureClientIdentity: ObjectIdentifier?
    private var loaded = false
    private var paused = false
    private var backgroundAllowed = false
    private var enqueuing = false
    private var epoch = UUID()
    private var originals: [String: Task<Void, Never>] = [:]
    private var thumbnails: [String: Task<Void, Never>] = [:]
    private var retryWake: Task<Void, Never>?

    init(root: URL? = nil, vault: SessionStoring? = nil, encryptionKeyStore: SessionStoring? = nil,
         transportFactory: TransportFactory? = nil, automaticallyStart: Bool = true,
         retryDelays: [TimeInterval] = [1, 3, 8], original: Original? = nil, thumbnail: Thumbnail? = nil) {
        let location = root ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("JACMediaUploadOutbox", isDirectory: true)
        configuredRoot = location
        self.root = location
        usesDefaultStorage = root == nil && vault == nil && encryptionKeyStore == nil
        self.vault = vault ?? MediaUploadKeychain(account: "session")
        self.encryptionKeyStore = encryptionKeyStore ?? MediaUploadKeychain(account: "manifest-key")
        self.transportFactory = transportFactory ?? { origin, root in MediaBackgroundTransport.shared(root: root, origin: origin) }
        self.automaticallyStart = automaticallyStart
        self.retryDelays = retryDelays
        self.original = original ?? { client, file, destination, transferred, progress in
            try await client.uploadMediaOriginal(file, parentID: destination, transferred: transferred, progress: progress)
        }
        self.thumbnail = thumbnail ?? { client, file in try await client.uploadMediaThumbnail(file) }
    }

    deinit {
        originals.values.forEach { $0.cancel() }
        thumbnails.values.forEach { $0.cancel() }
        retryWake?.cancel()
    }

    func bind(_ client: PayrollClient) {
        let isFixture = client.baseURL.host?.hasSuffix(".invalid") == true
        if usesDefaultStorage, isFixture, !fixture {
            // UI fixtures must never open, cancel or remove a real outbox.
            fixture = true
            root = FileManager.default.temporaryDirectory.appendingPathComponent("JACMediaUploadFixture-" + UUID().uuidString, isDirectory: true)
            vault = MediaUploadMemoryStore()
            encryptionKeyStore = MediaUploadMemoryStore()
            loaded = false
        } else if usesDefaultStorage, isFixture, let previous = fixtureClientIdentity, previous != ObjectIdentifier(client) {
            revoke()
        }
        if isFixture { fixtureClientIdentity = ObjectIdentifier(client) }
        mainClient = client
        if client.accessUser?.canUploadMedia == false { revoke(); return }
        do {
            let nextScope = try client.mediaScope()?.id
            boundScopeKnown = true
            boundScope = nextScope
            if let scope, scope != nextScope { revoke() }
            else if nextScope == nil, !jobs.isEmpty { revoke() }
        } catch {
            // The ordinary login item is WhenUnlocked. Its temporary lock is
            // not logout and cannot revoke an already authorized AFU transfer.
            boundScopeKnown = false
        }
    }

    func restore(background: Bool = false) async {
        backgroundAllowed = backgroundAllowed || background
        do {
            if !loaded { try readManifest() }
            if let scope, boundScopeKnown, scope != boundScope { revoke(); return }
            guard jobs.contains(where: { $0.phase != .done }) else {
                finishIfEmpty()
                if background, usesDefaultStorage, !fixture { await MediaBackgroundTransport.finishUnclaimedEvents() }
                return
            }
            if mainClient?.accessUser?.canUploadMedia == false { revoke(); return }
            if workerClient == nil { try prepareRestoredClient() }
            if !paused, originals.isEmpty, thumbnails.isEmpty {
                for index in jobs.indices where jobs[index].retryable {
                    jobs[index].error = nil; jobs[index].retryAt = nil; jobs[index].attempts = 0
                }
            }
            pump()
        } catch {
            // A locked Keychain/network interruption preserves the durable
            // files and credentials for the next permitted attempt.
            if background, usesDefaultStorage, !fixture {
                do {
                    let credential = try vault.load()
                    let encryptionKey = try encryptionKeyStore.load()
                    if credential == nil || encryptionKey == nil {
                        revoke()
                        await MediaBackgroundTransport.finishUnclaimedEvents()
                    }
                } catch {
                    // A thrown read can mean protected data is unavailable;
                    // only an actual missing credential abandons the event.
                }
            }
            notice = "La subida pendiente se retomará cuando haya conexión y el iPhone esté disponible."
        }
    }

    func enqueue(_ files: [MediaLocalFile], destination: MediaFolder, client: PayrollClient) async throws {
        guard !enqueuing, !files.isEmpty, !destination.id.isEmpty, client.accessUser?.canUploadMedia == true,
              !client.usingOfflineCopy, let nextScope = try client.mediaScope()?.id else {
            throw APIError.invalid("Conéctate y selecciona los archivos que quieres subir.")
        }
        guard files.count <= 1000 else { throw APIError.invalid("Selecciona como máximo1.000 archivos por lote.") }
        enqueuing = true
        defer { enqueuing = false }
        bind(client)
        if !loaded { try readManifest() }
        if let scope, scope != nextScope { revoke() }
        let oldJobs = jobs, oldScope = scope, oldOrigin = origin, oldActor = actor
        if jobs.allSatisfy({ $0.phase == .done }) { jobs = [] }
        guard jobs.count + files.count <= 2000 else { jobs = oldJobs; throw APIError.invalid("Termina o retira algunos archivos pendientes antes de agregar más.") }
        let origin = client.baseURL
        if scope == nil {
            scope = nextScope; self.origin = origin; actor = client.accessUser?.id
        }
        do {
            try prepareDirectory(root)
            if transport == nil, !isFixture(client) { transport = transportFactory(origin, root.appendingPathComponent("transport", isDirectory: true)) }
            // Factory copies only to the separate AFU Keychain account.
            let clone = try client.makeMediaUploadClient(vault: vault, transport: isFixture(client) ? nil : transport)
            workerClient = isFixture(client) ? client : clone
            _ = try key(create: true)
        } catch {
            jobs = oldJobs; scope = oldScope; self.origin = oldOrigin; actor = oldActor
            if !oldJobs.contains(where: { $0.phase != .done }) { try? vault.clear(); try? encryptionKeyStore.clear(); workerClient = nil }
            throw error
        }

        var moved: [(file: MediaLocalFile, url: URL)] = []
        do {
            var ids = Set(jobs.map(\.id))
            for file in files {
                guard !file.mimeType.hasPrefix("video/") || file.videoPrepared else {
                    throw APIError.invalid("El video debe terminar de comprimirse antes de subirlo. Vuelve a seleccionarlo.")
                }
                guard UUID(uuidString: file.id)?.uuidString.lowercased() == file.id,
                      ids.insert(file.id).inserted, file.url.isFileURL, file.size > 0, file.size <= MediaLocalFile.maximumSize else {
                    throw APIError.invalid("Uno de los archivos seleccionados no es válido.")
                }
                let attributes = try file.url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
                guard attributes.isRegularFile == true, attributes.isSymbolicLink != true, attributes.fileSize == Int(file.size) else {
                    throw APIError.invalid("El archivo local cambió. Vuelve a seleccionarlo.")
                }
                let ext = file.url.pathExtension.lowercased().filter { $0.isASCII && ($0.isLetter || $0.isNumber) }
                let leaf = "original." + (ext.isEmpty ? "bin" : String(ext.prefix(10)))
                let job = MediaUploadJob(id: file.id, name: file.name, mimeType: file.mimeType, size: file.size, imageLimit: file.imageLimit, destination: destination, sourceName: leaf)
                guard valid(job) else { throw APIError.invalid("Los datos del archivo o de su carpeta no son válidos.") }
                let directory = jobDirectory(file.id)
                try prepareDirectory(directory)
                let target = directory.appendingPathComponent(leaf)
                guard !FileManager.default.fileExists(atPath: target.path) else { throw APIError.conflict("Este archivo ya está en la cola.") }
                try FileManager.default.moveItem(at: file.url, to: target)
                moved.append((file, target))
                try protect(target)
                jobs.append(job)
            }
            paused = false
            loaded = true
            try persist()
            moved.forEach { $0.file.remove() }
            notice = nil
            revision += 1
            pump()
        } catch {
            for pair in moved.reversed() {
                try? FileManager.default.createDirectory(at: pair.file.url.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: JACFileSecurity.directoryAttributes)
                try? FileManager.default.moveItem(at: pair.url, to: pair.file.url)
                try? FileManager.default.setAttributes(JACFileSecurity.fileAttributes, ofItemAtPath: pair.file.url.path)
                try? FileManager.default.removeItem(at: jobDirectory(pair.file.id))
            }
            jobs = oldJobs; scope = oldScope; self.origin = oldOrigin; actor = oldActor
            if oldJobs.isEmpty { try? vault.clear(); try? encryptionKeyStore.clear(); workerClient = nil }
            throw error
        }
    }

    func stop() {
        paused = true
        cancelWorkers()
        for index in jobs.indices where jobs[index].phase == .original { jobs[index].phase = .pending }
        notice = "Subida en pausa."
        saveOrPause()
    }

    func retry() {
        guard !jobs.isEmpty else { return }
        paused = false
        for index in jobs.indices where jobs[index].phase != .done {
            jobs[index].error = nil; jobs[index].retryAt = nil; jobs[index].attempts = 0
            if jobs[index].phase == .original { jobs[index].phase = .pending }
        }
        notice = nil
        do {
            if workerClient == nil { try prepareRestoredClient() }
            try persist()
            pump()
        } catch { notice = error.localizedDescription }
    }

    func remove(id: String) {
        guard UUID(uuidString: id)?.uuidString.lowercased() == id, jobs.contains(where: { $0.id == id }) else { return }
        originals.removeValue(forKey: id)?.cancel()
        thumbnails.removeValue(forKey: id)?.cancel()
        jobs.removeAll { $0.id == id }
        try? FileManager.default.removeItem(at: jobDirectory(id))
        revision += 1
        saveOrPause()
        finishIfEmpty()
        pump()
    }

    func revoke() {
        cancelWorkers()
        jobs = []
        try? FileManager.default.removeItem(at: root)
        try? vault.clear()
        try? encryptionKeyStore.clear()
        workerClient = nil
        scope = nil; origin = nil; actor = nil
        loaded = true; paused = false; backgroundAllowed = false
        notice = nil
        meter = MediaUploadRate()
        revision += 1
    }

    private func isFixture(_ client: PayrollClient) -> Bool { client.baseURL.host?.hasSuffix(".invalid") == true }
    private func jobDirectory(_ id: String) -> URL { root.appendingPathComponent("files", isDirectory: true).appendingPathComponent(id, isDirectory: true) }
    private var manifestURL: URL { root.appendingPathComponent("manifest.sealed") }
    private func file(for job: MediaUploadJob) -> MediaLocalFile {
        MediaLocalFile(id: job.id, url: jobDirectory(job.id).appendingPathComponent(job.sourceName), name: job.name, mimeType: job.mimeType, size: job.size, imageLimit: job.imageLimit)
    }

    private func prepareRestoredClient() throws {
        guard let origin, let scope, let token = try vault.load(), token.range(of: "^[A-Za-z0-9_-]{43}$", options: .regularExpression) != nil else {
            throw APIError.unauthorized
        }
        if let mainClient, isFixture(mainClient) {
            guard try mainClient.mediaScope()?.id == scope else { throw APIError.unauthorized }
            workerClient = mainClient
        } else {
            if transport == nil { transport = transportFactory(origin, root.appendingPathComponent("transport", isDirectory: true)) }
            let restored = PayrollClient(baseURL: origin, vault: vault, automaticallyDownloadOffline: false, mediaUploadTransport: transport)
            guard try restored.mediaScope()?.id == scope else { throw APIError.unauthorized }
            workerClient = restored
        }
    }

    private func pump() {
        guard automaticallyStart, !paused, let workerClient, scope != nil,
              backgroundAllowed || mainClient?.usingOfflineCopy != true else { updateUploading(); return }
        if boundScopeKnown, boundScope != scope { revoke(); return }
        if mainClient?.accessUser?.canUploadMedia == false { revoke(); return }
        if thumbnails.isEmpty, let job = jobs.first(where: { $0.phase == .thumbnail && available($0) }) { startThumbnail(job, client: workerClient) }
        var capacity = 2 - originals.count
        // Reserve one future thumbnail slot for every active original, so a
        // slow thumbnail cannot accumulate unbounded retained video originals.
        var thumbnailReservations = jobs.filter { $0.phase == .thumbnail }.count + originals.count
        for job in jobs where capacity > 0 && thumbnailReservations < 4 && job.phase == .pending && available(job) {
            startOriginal(job, client: workerClient)
            capacity -= 1; thumbnailReservations += 1
        }
        updateUploading()
        scheduleRetry()
        finishIfEmpty()
    }

    private func available(_ job: MediaUploadJob) -> Bool {
        job.error == nil || job.retryAt.map { $0 <= Date() } == true
    }

    private func startOriginal(_ job: MediaUploadJob, client: PayrollClient) {
        guard !paused, let index = jobs.firstIndex(where: { $0.id == job.id }), originals[job.id] == nil else { return }
        let current = epoch
        jobs[index].phase = .original; jobs[index].error = nil; jobs[index].retryAt = nil
        guard saveOrPause() else { return }
        let local = file(for: job)
        originals[job.id] = Task { [weak self] in
            guard let self else { return }
            do {
                let provider = try await self.original(client, local, job.destination.id, { [weak self] bytes in
                    guard let self, self.epoch == current, self.originals[job.id] != nil else { return }
                    self.meter.record(bytes)
                }, { [weak self] sent, total in
                    guard let self, self.epoch == current, self.originals[job.id] != nil,
                          let index = self.jobs.firstIndex(where: { $0.id == job.id }) else { return }
                    self.jobs[index].progress = total > 0 ? min(0.99, max(0, Double(sent) / Double(total))) : 0
                })
                guard self.epoch == current, !Task.isCancelled, let index = self.jobs.firstIndex(where: { $0.id == job.id }) else { return }
                self.originals[job.id] = nil
                self.jobs[index].completed = provider != "r2"; self.jobs[index].progress = provider == "r2" ? 0.99 : 1
                self.jobs[index].attempts = 0; self.jobs[index].error = nil; self.jobs[index].retryable = false
                self.jobs[index].phase = provider == "r2" ? .thumbnail : .done
                self.revision += 1
                guard self.saveOrPause() else {
                    if provider != "r2", let index = self.jobs.firstIndex(where: { $0.id == job.id }) {
                        self.jobs[index].phase = .pending; self.jobs[index].completed = false; self.jobs[index].progress = 0.99
                    }
                    return
                }
                if provider != "r2" { try? FileManager.default.removeItem(at: self.jobDirectory(job.id)) }
                self.pump()
            } catch {
                guard self.epoch == current, !Task.isCancelled else { return }
                self.originals[job.id] = nil
                self.failed(error, id: job.id, phase: .pending)
            }
        }
    }

    private func startThumbnail(_ job: MediaUploadJob, client: PayrollClient) {
        guard !paused, let index = jobs.firstIndex(where: { $0.id == job.id }) else { return }
        jobs[index].error = nil; jobs[index].retryAt = nil
        guard saveOrPause() else { return }
        let current = epoch
        let local = file(for: job)
        thumbnails[job.id] = Task { [weak self] in
            guard let self else { return }
            do {
                try await self.thumbnail(client, local)
                guard self.epoch == current, !Task.isCancelled, let index = self.jobs.firstIndex(where: { $0.id == job.id }) else { return }
                self.thumbnails[job.id] = nil
                self.jobs[index].phase = .done; self.jobs[index].error = nil
                self.jobs[index].completed = true; self.jobs[index].progress = 1
                self.jobs[index].retryAt = nil; self.jobs[index].attempts = 0; self.jobs[index].retryable = false
                self.revision += 1
                guard self.saveOrPause() else {
                    if let index = self.jobs.firstIndex(where: { $0.id == job.id }) {
                        self.jobs[index].phase = .thumbnail; self.jobs[index].completed = false; self.jobs[index].progress = 0.99
                    }
                    return
                }
                try? FileManager.default.removeItem(at: self.jobDirectory(job.id))
                self.pump()
            } catch {
                guard self.epoch == current, !Task.isCancelled else { return }
                self.thumbnails[job.id] = nil
                self.failed(error, id: job.id, phase: .thumbnail)
            }
        }
    }

    private func failed(_ error: Error, id: String, phase: MediaUploadJobPhase) {
        if case APIError.unauthorized = error {
            let primary = mainClient
            revoke()
            try? primary?.clearSession()
            // Even if WhenUnlocked blocked deletion, known401 must retire the
            // in-memory UI immediately. The foreground retry rechecks Keychain.
            primary?.onSessionInvalidated?()
            notice = error.localizedDescription
            return
        }
        if case APIError.forbidden = error { revoke(); notice = error.localizedDescription; return }
        guard let index = jobs.firstIndex(where: { $0.id == id }) else { return }
        jobs[index].phase = phase
        if error is CancellationError || (error as? URLError)?.code == .cancelled { updateUploading(); return }
        jobs[index].error = error.localizedDescription
        jobs[index].retryable = AgendaOfflineCache.isUnavailable(error) || isRetryable(error)
        if jobs[index].retryable {
            let attempt = jobs[index].attempts
            jobs[index].attempts += 1
            jobs[index].retryAt = attempt < retryDelays.count ? Date().addingTimeInterval(retryDelays[attempt]) : nil
        } else { jobs[index].retryAt = nil }
        saveOrPause()
        pump()
    }

    private func isRetryable(_ error: Error) -> Bool {
        if error is URLError { return true }
        if case APIError.message = error { return true }
        if case APIError.conflict = error { return true }
        return false
    }

    private func scheduleRetry() {
        retryWake?.cancel(); retryWake = nil
        guard !paused, let next = jobs.compactMap(\.retryAt).filter({ $0 > Date() }).min() else { return }
        let current = epoch
        retryWake = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(max(0.01, next.timeIntervalSinceNow))) } catch { return }
            guard let self, self.epoch == current else { return }
            self.retryWake = nil
            self.pump()
        }
    }

    private func updateUploading() { uploading = !originals.isEmpty || !thumbnails.isEmpty }

    private func finishIfEmpty() {
        guard !jobs.contains(where: { $0.phase != .done }), originals.isEmpty, thumbnails.isEmpty else { return }
        if scope != nil { transport?.cancelAll() }
        // A crash may occur after persisting done but before removing its
        // payload. No outbox file is needed when every durable job is done.
        try? FileManager.default.removeItem(at: root.appendingPathComponent("files", isDirectory: true))
        try? FileManager.default.removeItem(at: manifestURL)
        try? vault.clear(); try? encryptionKeyStore.clear()
        workerClient = nil
        scope = nil; origin = nil; actor = nil
        (transport as? MediaBackgroundTransport)?.finishProcessing()
        if !jobs.isEmpty { notice = "\(jobs.count) archivos subidos." }
    }

    private func cancelWorkers() {
        epoch = UUID()
        originals.values.forEach { $0.cancel() }; originals = [:]
        thumbnails.values.forEach { $0.cancel() }; thumbnails = [:]
        retryWake?.cancel(); retryWake = nil
        transport?.cancelAll()
        (transport as? MediaBackgroundTransport)?.finishProcessing()
        uploading = false
    }

    @discardableResult private func saveOrPause() -> Bool {
        do { try persist(); return true }
        catch { paused = true; cancelWorkers(); notice = "No se pudo guardar la cola de subida. Libera espacio y reintenta."; return false }
    }

    private func key(create: Bool) throws -> SymmetricKey? {
        if let encoded = try encryptionKeyStore.load() {
            guard let bytes = Data(base64Encoded: encoded), bytes.count == 32 else { throw APIError.invalid("La cola guardada no es válida.") }
            return SymmetricKey(data: bytes)
        }
        guard create else { return nil }
        let key = SymmetricKey(size: .bits256)
        try encryptionKeyStore.save(key.withUnsafeBytes { Data($0).base64EncodedString() })
        return key
    }

    private func persist() throws {
        guard let scope, let origin else { return }
        try prepareDirectory(root)
        let manifest = Manifest(schema: 1, origin: origin.absoluteString, scope: scope, actor: actor, paused: paused, jobs: jobs)
        let bytes = try JSONEncoder().encode(manifest)
        guard bytes.count <= 1024 * 1024, let key = try key(create: true), let sealed = try AES.GCM.seal(bytes, using: key).combined else {
            throw APIError.invalid("La cola de subida supera el tamaño permitido.")
        }
        try sealed.write(to: manifestURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        try protect(manifestURL)
    }

    private func readManifest() throws {
        guard !loaded else { return }
        guard FileManager.default.fileExists(atPath: manifestURL.path) else { loaded = true; return }
        guard let key = try key(create: false) else { throw APIError.invalid("La cola pendiente no está disponible en este iPhone.") }
        let bytes = try Data(contentsOf: manifestURL)
        guard bytes.count <= 1024 * 1024 + 64 else { throw APIError.invalid("La cola guardada supera el tamaño permitido.") }
        let manifest = try JSONDecoder().decode(Manifest.self, from: AES.GCM.open(AES.GCM.SealedBox(combined: bytes), using: key))
        guard manifest.schema == 1, manifest.scope.range(of: "^[a-f0-9]{64}$", options: .regularExpression) != nil,
              let origin = URL(string: manifest.origin), origin.scheme == "https", origin.host != nil, origin.path.isEmpty,
              origin.user == nil, origin.password == nil, origin.port == nil, origin.query == nil, origin.fragment == nil,
              (origin == PayrollClient.productionURL || ((!usesDefaultStorage || fixture) && origin.host?.hasSuffix(".invalid") == true)),
              manifest.jobs.count <= 2000, Set(manifest.jobs.map(\.id)).count == manifest.jobs.count,
              manifest.jobs.allSatisfy({ valid($0) }) else {
            throw APIError.invalid("La cola guardada no es válida.")
        }
        if boundScopeKnown, boundScope != manifest.scope { revoke(); return }
        guard let token = try vault.load(), token.range(of: "^[A-Za-z0-9_-]{43}$", options: .regularExpression) != nil,
              AgendaCacheScope(origin: origin.absoluteString + "/media-offline-v1", token: token).id == manifest.scope else {
            throw APIError.unauthorized
        }
        self.origin = origin; scope = manifest.scope; actor = manifest.actor
        paused = manifest.paused
        jobs = manifest.jobs
        for index in jobs.indices {
            if jobs[index].phase == .original { jobs[index].phase = .pending }
            jobs[index].completed = jobs[index].phase == .done
            jobs[index].progress = jobs[index].completed ? 1 : min(0.99, jobs[index].progress)
            let path = file(for: jobs[index]).url
            let attributes = try? path.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
            if jobs[index].phase != .done, attributes?.isRegularFile != true || attributes?.isSymbolicLink == true || attributes?.fileSize != Int(jobs[index].size) {
                jobs[index].error = "El archivo pendiente ya no está disponible en este iPhone."
                jobs[index].retryAt = nil; jobs[index].retryable = false
            }
        }
        loaded = true
        revision += 1
    }

    private func valid(_ job: MediaUploadJob) -> Bool {
        let types = Set(["image/jpeg", "image/png", "image/gif", "image/webp", "image/heic", "image/heif", "image/tiff", "video/mp4", "video/quicktime", "video/webm", "video/x-m4v"])
        return UUID(uuidString: job.id)?.uuidString.lowercased() == job.id
            && job.sourceName.range(of: "^original\\.[a-z0-9]{1,10}$", options: .regularExpression) != nil
            && job.destination.id.range(of: "^[A-Za-z0-9_-]{1,200}$", options: .regularExpression) != nil
            && job.name == MediaLocalFile.safeName(job.name) && types.contains(job.mimeType)
            && job.size > 0 && job.size <= MediaLocalFile.maximumSize
            && [Int64(0), 2_000_000, 4_000_000, 6_000_000].contains(job.imageLimit)
            && (job.mimeType.hasPrefix("image/") ? job.imageLimit == 0 || job.size <= job.imageLimit : job.imageLimit == 0)
            && job.progress.isFinite && (0...1).contains(job.progress) && (0...100).contains(job.attempts)
    }

    private func prepareDirectory(_ url: URL) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true, attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
        try protect(url)
    }

    private func protect(_ url: URL) throws {
        try FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: url.path)
        var target = url
        var values = URLResourceValues(); values.isExcludedFromBackup = true
        try target.setResourceValues(values)
    }
}

private final class MediaUploadMemoryStore: SessionStoring {
    private var value: String?
    func load() throws -> String? { value }
    func save(_ token: String) throws { value = token }
    func clear() throws { value = nil }
}

/// A narrowly scoped copy for pending uploads. It never replaces or changes
/// the ordinary login's WhenUnlocked Keychain item.
private final class MediaUploadKeychain: SessionStoring {
    private let account: String
    init(account: String) { self.account = account }
    private var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "co.jacmusic.nomina.media-upload", kSecAttrAccount as String: account]
    }
    func load() throws -> String? {
        var q = query; q[kSecReturnData as String] = true; q[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(q as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data, let value = String(data: data, encoding: .utf8) else { throw APIError.message("Desbloquea el iPhone para retomar la subida pendiente.") }
        return value
    }
    func save(_ token: String) throws {
        let attributes: [String: Any] = [kSecValueData as String: Data(token.utf8), kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var q = query; attributes.forEach { q[$0.key] = $0.value }
            guard SecItemAdd(q as CFDictionary, nil) == errSecSuccess else { throw APIError.message("No se pudo guardar la cola de subida de forma segura.") }
        } else if status != errSecSuccess { throw APIError.message("No se pudo actualizar la cola de subida segura.") }
    }
    func clear() throws {
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw APIError.message("No se pudo retirar la cola segura.") }
    }
}
#endif
