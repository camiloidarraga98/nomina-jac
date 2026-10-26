import Foundation
import Network

enum MediaPhotoPreviewQuality: String, CaseIterable, Sendable {
    case balanced, detail
    var maximumBytes: Int { self == .balanced ? 512 * 1024 : 2 * 1024 * 1024 }
    var filename: String { self == .balanced ? "jac-preview-balanced.jpg" : "jac-preview-detail.jpg" }
}

struct MediaPhotoConnection: Equatable, Sendable {
    var available = true
    var expensive = false
    var constrained = false
    var wifi = false
    var bytesPerSecond: Double?
    var improvesQuality: Bool {
        available && !expensive && !constrained && wifi && (bytesPerSecond.map { $0 >= 180_000 } ?? true)
    }
    var prefetchCount: Int { !available || constrained ? 0 : (improvesQuality ? Int.max : 6) }
}

/// One queue per authenticated client, shared by visible photos and folder
/// prefetch. Only JPEG bytes are shared; each reader owns its temporary file.
@MainActor
final class MediaPhotoPreviewPipeline {
    enum Priority { case visible, prefetch }
    private final class Flight {
        var priority: Priority
        var readers: [UUID: CheckedContinuation<Data, Error>] = [:]
        var task: Task<Void, Never>?
        var runningInBackground = false
        init(_ priority: Priority) { self.priority = priority }
    }
    private var flights: [String: Flight] = [:]
    private var waiting: [(UUID, Flight, CheckedContinuation<Void, Error>)] = []
    private var running = 0
    private var backgroundRunning = 0
    private let limit: Int
    private var monitor: NWPathMonitor?
    private(set) var connection = MediaPhotoConnection()

    init(limit: Int = 2, monitorNetwork: Bool = true) {
        self.limit = max(1, limit)
        if monitorNetwork {
            let monitor = NWPathMonitor(); self.monitor = monitor
            monitor.pathUpdateHandler = { [weak self] path in
                let state = MediaPhotoConnection(available: path.status == .satisfied, expensive: path.isExpensive,
                                                constrained: path.isConstrained, wifi: path.usesInterfaceType(.wifi))
                Task { @MainActor [weak self] in self?.updateConnection(state) }
            }
            monitor.start(queue: DispatchQueue(label: "co.jacmusic.nomina.photo-network"))
        }
    }
    deinit { monitor?.cancel() }
    func updateConnection(_ state: MediaPhotoConnection) { connection = state }
    func measured(bytes: Int, seconds: TimeInterval) {
        guard seconds >= 0.15, bytes >= 16 * 1024 else { return }
        let rate = Double(bytes) / seconds
        connection.bytesPerSecond = connection.bytesPerSecond.map { $0 * 0.5 + rate * 0.5 } ?? rate
    }

    func data(key: String, priority: Priority, authorized: @escaping () -> Bool,
              load: @escaping () async throws -> Data) async throws -> Data {
        try Task.checkCancellation()
        guard authorized() else { throw CancellationError() }
        let reader = UUID()
        let result: Data = try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                if let flight = flights[key] {
                    flight.readers[reader] = continuation
                    if priority == .visible { flight.priority = .visible; drain() }
                    return
                }
                let flight = Flight(priority); flight.readers[reader] = continuation; flights[key] = flight
                flight.task = Task {
                    do {
                        try await acquire(flight)
                        defer { release(flight) }
                        try Task.checkCancellation()
                        guard authorized() else { throw CancellationError() }
                        let bytes = try await load()
                        try Task.checkCancellation()
                        guard authorized() else { throw CancellationError() }
                        finish(key, flight, .success(bytes))
                    } catch { finish(key, flight, .failure(error)) }
                }
            }
        } onCancel: {
            Task { @MainActor in
                guard let flight = self.flights[key], let waiter = flight.readers.removeValue(forKey: reader) else { return }
                waiter.resume(throwing: CancellationError())
                if flight.readers.isEmpty { self.flights.removeValue(forKey: key); flight.task?.cancel() }
            }
        }
        try Task.checkCancellation()
        guard authorized() else { throw CancellationError() }
        return result
    }
    private func finish(_ key: String, _ flight: Flight, _ result: Result<Data, Error>) {
        guard flights[key] === flight else { return }
        flights.removeValue(forKey: key)
        for reader in flight.readers.values { reader.resume(with: result) }
        flight.readers.removeAll(); flight.task = nil
    }
    private func acquire(_ flight: Flight) async throws {
        let id = UUID()
        try await withTaskCancellationHandler {
            try Task.checkCancellation()
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                if running < limit && canStart(flight) { reserve(flight); continuation.resume() }
                else { waiting.append((id, flight, continuation)) }
            }
        } onCancel: {
            Task { @MainActor in
                if let index = self.waiting.firstIndex(where: { $0.0 == id }) {
                    self.waiting.remove(at: index).2.resume(throwing: CancellationError())
                }
            }
        }
    }
    private func canStart(_ flight: Flight) -> Bool {
        flight.priority == .visible || backgroundRunning < max(1, limit - 1)
    }
    private func reserve(_ flight: Flight) {
        running += 1; flight.runningInBackground = flight.priority == .prefetch
        if flight.runningInBackground { backgroundRunning += 1 }
    }
    private func drain() {
        while running < limit {
            guard let index = waiting.firstIndex(where: { $0.1.priority == .visible }) ?? waiting.firstIndex(where: { canStart($0.1) }) else { return }
            let next = waiting.remove(at: index); reserve(next.1); next.2.resume()
        }
    }
    private func release(_ flight: Flight) {
        running -= 1
        if flight.runningInBackground { backgroundRunning -= 1 }
        drain()
    }
}

#if os(iOS)
/// Warms compressed previews, never originals or a folder full of bitmaps.
/// One background reader leaves capacity for the photo under the user's finger.
@MainActor
final class MediaFolderPhotoPrefetch {
    private var task: Task<Void, Never>?
    private var identity: String?
    private var generation = UUID()
    func stop() { generation = UUID(); task?.cancel(); task = nil; identity = nil }
    func start(_ feed: MediaFeed, client: PayrollClient, selectedID: String? = nil, denied: @escaping (Error) -> Void) {
        guard feed.connected, feed.canRead, !client.usingOfflineCopy,
              let stamp = client.mediaPresentationStamp else { stop(); return }
        let signature = stamp + "|" + String(client.photoPreviews.connection.prefetchCount) + "|" + (feed.collectionID ?? "") + "|" + (feed.folder?.id ?? "") + "|" + (selectedID ?? "")
            + "|" + (feed.nextPageToken ?? "") + "|" + feed.items.map { $0.id + ":" + $0.modifiedAt }.joined(separator: "|")
        guard identity != signature else { return }
        stop(); identity = signature
        let expected = generation
        task = Task(priority: .utility) {
            defer { if expected == generation { task = nil } }
            do {
                var page = feed, seen = Set<String>(), cursors = Set<String>(), warmed = 0
                while true {
                    try Task.checkCancellation()
                    guard generation == expected, stamp == client.mediaPresentationStamp, !client.usingOfflineCopy,
                          page.connected, page.canRead, page.collectionID == feed.collectionID,
                          page.folder?.id == feed.folder?.id else { throw CancellationError() }
                    var photos = page.items.filter { $0.kind == "image" && seen.insert($0.id).inserted }
                    if let selectedID, let index = photos.firstIndex(where: { $0.id == selectedID }) {
                        photos = Array(photos[index...]) + Array(photos[..<index])
                    }
                    for photo in photos {
                        try Task.checkCancellation()
                        guard warmed < client.photoPreviews.connection.prefetchCount else { return }
                        do { try await client.prefetchMediaPhotoPreview(photo, collectionID: feed.collectionID) }
                        catch {
                            if error is CancellationError || (error as? URLError)?.code == .cancelled { throw error }
                            if case APIError.unauthorized = error { throw error }
                            if case APIError.forbidden = error { throw error }
                            if AgendaOfflineCache.isUnavailable(error) { throw error }
                            // An unavailable derivative must not block the folder.
                        }
                        warmed += 1
                    }
                    guard let cursor = page.nextPageToken, !cursor.isEmpty else { break }
                    guard warmed < client.photoPreviews.connection.prefetchCount, cursors.insert(cursor).inserted, cursors.count <= 1000 else { break }
                    page = try await client.media(folder: feed.folder?.id ?? "", pageToken: cursor, forceNetwork: true)
                }
            } catch {
                guard expected == generation, !Task.isCancelled else { return }
                identity = nil
                if case APIError.unauthorized = error { stop(); denied(error) }
                if case APIError.forbidden = error { stop(); denied(error) }
            }
        }
    }
}
#endif
