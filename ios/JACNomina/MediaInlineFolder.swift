#if os(iOS)
import SwiftUI
import UIKit

/// Bounded decoded memory. Visible cells and folder prefetch share each request;
/// leaving a cell cancels only its subscription, never another reader's work.
@MainActor
final class MediaGridThumbnailLoader {
    static let shared = MediaGridThumbnailLoader()
    enum Priority { case visible, prefetch }
    private final class Entry: NSObject {
        let image: UIImage
        init(_ image: UIImage) { self.image = image }
    }
    private let cache = NSCache<NSString, Entry>()
    private let limit: Int
    private var running = 0
    private var generation = 0
    private final class Flight {
        var priority: Priority
        var readers: [UUID: CheckedContinuation<UIImage?, Error>] = [:]
        var task: Task<Void, Never>?
        init(priority: Priority) { self.priority = priority }
    }
    private var flights: [String: Flight] = [:]
    private var waiting: [(UUID, Flight, CheckedContinuation<Void, Error>)] = []
    init(limit: Int = 4) {
        self.limit = max(1, limit)
        cache.countLimit = 256
        cache.totalCostLimit = 64 * 1024 * 1024
    }
    func clear() {
        generation += 1; cache.removeAllObjects()
        let old = Array(flights.values); flights.removeAll()
        for flight in old {
            flight.task?.cancel()
            for reader in flight.readers.values { reader.resume(throwing: CancellationError()) }
            flight.readers.removeAll()
        }
    }

    func load(key: String, authorized: @escaping () -> Bool, allowNetwork: Bool = true,
              priority: Priority = .visible, bytes: @escaping () async throws -> Data) async throws -> UIImage? {
        try Task.checkCancellation()
        guard authorized() else { clear(); throw CancellationError() }
        if let entry = cache.object(forKey: key as NSString) { return entry.image }
        guard allowNetwork else { return nil }
        let reader = UUID()
        let result: UIImage? = try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                if let flight = flights[key] {
                    flight.readers[reader] = continuation
                    if priority == .visible { flight.priority = .visible }
                } else {
                    let flight = Flight(priority: priority), expected = generation
                    flight.readers[reader] = continuation; flights[key] = flight
                    flight.task = Task {
                        do {
                            let value = try await perform(key: key, flight: flight, expected: expected, authorized: authorized, bytes: bytes)
                            finish(key, flight: flight, result: .success(value))
                        } catch {
                            finish(key, flight: flight, result: .failure(error))
                            if case APIError.unauthorized = error { clear() }
                            if case APIError.forbidden = error { clear() }
                        }
                    }
                }
            }
        } onCancel: {
            Task { @MainActor in
                guard let flight = self.flights[key], let continuation = flight.readers.removeValue(forKey: reader) else { return }
                continuation.resume(throwing: CancellationError())
                if flight.readers.isEmpty { self.flights.removeValue(forKey: key); flight.task?.cancel() }
            }
        }
        try Task.checkCancellation()
        guard authorized() else { clear(); throw CancellationError() }
        return result
    }

    private func finish(_ key: String, flight: Flight, result: Result<UIImage?, Error>) {
        guard flights[key] === flight else { return }
        flights.removeValue(forKey: key)
        for reader in flight.readers.values { reader.resume(with: result) }
        flight.readers.removeAll(); flight.task = nil
    }

    private func perform(key: String, flight: Flight, expected: Int, authorized: () -> Bool,
                         bytes: () async throws -> Data) async throws -> UIImage? {
        try await acquire(flight)
        defer { release() }
        try Task.checkCancellation()
        guard expected == generation else { throw CancellationError() }
        guard authorized() else { clear(); throw CancellationError() }
        if let entry = cache.object(forKey: key as NSString) { return entry.image }
        let data = try await bytes()
        try Task.checkCancellation()
        let decoder = Task.detached(priority: .utility) { MediaThumbnail.image(data, decodeImmediately: true) }
        let image = await withTaskCancellationHandler { await decoder.value } onCancel: { decoder.cancel() }
        try Task.checkCancellation()
        guard expected == generation else { throw CancellationError() }
        guard authorized() else { clear(); throw CancellationError() }
        if let image {
            cache.setObject(Entry(image), forKey: key as NSString, cost: Int(image.size.width * image.size.height * 4))
        }
        return image
    }

    private func key(_ item: MediaItem, client: PayrollClient, stamp: String) -> String {
        "\(ObjectIdentifier(client))|\(stamp)|\(item.id)|\(item.modifiedAt)|\(item.size)|\(item.mimeType)"
    }
    func cachedImage(_ item: MediaItem, client: PayrollClient, stamp: String) -> UIImage? {
        cache.object(forKey: key(item, client: client, stamp: stamp) as NSString)?.image
    }
    func image(_ item: MediaItem, client: PayrollClient, networkAllowed: Bool = true, priority: Priority = .visible) async throws -> UIImage? {
        try Task.checkCancellation()
        // Decoded, session-scoped pixels are the same presentation snapshot
        // used by visible tiles. Reusing them starts no file or network read.
        if item.thumbnailAvailable, client.accessUser?.canReadMedia == true,
           let stamp = client.mediaPresentationStamp,
           let image = cachedImage(item, client: client, stamp: stamp) { return image }
        guard let stamp = try client.mediaAccessStamp(), client.accessUser?.canReadMedia != false else { throw CancellationError() }
        guard item.thumbnailAvailable else { return nil }
        return try await load(key: key(item, client: client, stamp: stamp), authorized: { stamp == (try? client.mediaAccessStamp()) && client.accessUser?.canReadMedia != false }, priority: priority, bytes: { try await client.mediaThumbnail(item, networkAllowed: networkAllowed && !client.usingOfflineCopy) })
    }

    private func acquire(_ flight: Flight) async throws {
        let id = UUID()
        try await withTaskCancellationHandler {
            try Task.checkCancellation()
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                if running < limit { running += 1; continuation.resume() }
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
    private func release() {
        if waiting.isEmpty { running -= 1 }
        else {
            let index = waiting.firstIndex { $0.1.priority == .visible } ?? 0
            waiting.remove(at: index).2.resume()
        }
    }
}

/// The viewport owns the request, not the cached image. Explicit appearance
/// restarts a cancelled cell even when SwiftUI reuses the same task identity.
@MainActor
final class MediaTileThumbnail: ObservableObject {
    @Published private(set) var image: UIImage?
    private(set) var visible = false
    private var key: String?
    private var generation = UUID()
    private var task: Task<Void, Never>?

    func show(key: String, authorized: @escaping () -> Bool, cached: UIImage? = nil,
              load: @escaping () async throws -> UIImage?, denied: @escaping (Error) -> Void) {
        visible = true
        guard authorized() else { cancel(); return }
        if self.key == key, image != nil || task != nil { return }
        cancel(); self.key = key
        if let cached { image = cached; return }
        let expected = generation
        task = Task {
            defer { if expected == generation { task = nil } }
            // A temporary failure retries only while this cell is visible.
            // A known missing thumbnail is skipped by the loader instead.
            for attempt in 0..<3 {
                do {
                    let value = try await load()
                    try Task.checkCancellation()
                    guard expected == generation, visible, authorized() else { return }
                    image = value; return
                } catch {
                    guard expected == generation, visible, !Task.isCancelled else { return }
                    if case APIError.unauthorized = error { cancel(); denied(error); return }
                    if case APIError.forbidden = error { cancel(); denied(error); return }
                    guard authorized(), attempt < 2,
                          error is MediaThumbnailUnavailable || AgendaOfflineCache.isUnavailable(error) else { return }
                    do { try await Task.sleep(for: .milliseconds(attempt == 0 ? 600 : 1800)) }
                    catch { return }
                }
            }
        }
    }
    func hide() { visible = false; cancel() }
    func pause() {
        // A retained section may be hidden by the drawer without leaving the
        // viewport. Cancel the read, retaining the decoded image and identity.
        visible = false; generation = UUID(); task?.cancel(); task = nil
    }
    private func cancel() {
        generation = UUID(); task?.cancel(); task = nil; key = nil; image = nil
    }
}

/// Starts at folder opening, independently of the lazy grid's viewport. Only
/// two background readers run, leaving capacity for visible thumbnails. The
/// encrypted disk cache remains bounded; no originals or unopened folders load.
@MainActor
final class MediaFolderThumbnailPrefetch: ObservableObject {
    private let loader: MediaGridThumbnailLoader
    private let photoPreviews = MediaFolderPhotoPrefetch()
    private var identity: String?
    private var generation = UUID()
    private(set) var task: Task<Void, Never>?
    init(loader: MediaGridThumbnailLoader? = nil) { self.loader = loader ?? .shared }

    func stop() { generation = UUID(); task?.cancel(); task = nil; identity = nil; photoPreviews.stop() }

    func start(_ feed: MediaFeed, client: PayrollClient, networkAllowed: Bool, denied: @escaping (Error) -> Void) {
        guard networkAllowed, !client.usingOfflineCopy, feed.connected, feed.canRead,
              let stamp = try? client.mediaAccessStamp() else { stop(); return }
        let signature = stamp + "|" + (feed.collectionID ?? "") + "|" + (feed.folder?.id ?? "") + "|" + (feed.nextPageToken ?? "") + "|" + feed.items.map { "\($0.id):\($0.modifiedAt):\($0.size):\($0.thumbnailAvailable)" }.joined(separator: "|")
        guard identity != signature else { return }
        stop(); identity = signature
        photoPreviews.start(feed, client: client, denied: denied)
        let expected = generation
        task = Task(priority: .utility) {
            defer { if expected == generation { task = nil } }
            do {
                var page = feed, seenItems = Set<String>(), cursors = Set<String>()
                while true {
                    try Task.checkCancellation()
                    guard expected == generation, stamp == (try client.mediaAccessStamp()), !client.usingOfflineCopy,
                          page.connected, page.canRead, page.collectionID == feed.collectionID, page.folder?.id == feed.folder?.id else { throw CancellationError() }
                    let files = page.items.filter { $0.kind != "folder" && $0.thumbnailAvailable && seenItems.insert($0.id).inserted }
                    try await withThrowingTaskGroup(of: Void.self) { group in
                        var iterator = files.makeIterator()
                        for _ in 0..<2 {
                            if let item = iterator.next() { group.addTask { try await self.warm(item, client: client) } }
                        }
                        while try await group.next() != nil {
                            try Task.checkCancellation()
                            if let item = iterator.next() { group.addTask { try await self.warm(item, client: client) } }
                        }
                    }
                    guard let cursor = page.nextPageToken, !cursor.isEmpty else { break }
                    guard cursors.insert(cursor).inserted, cursors.count <= 1000 else { throw APIError.invalid("La paginación de la carpeta cambió.") }
                    try Task.checkCancellation()
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
    private func warm(_ item: MediaItem, client: PayrollClient) async throws {
        do { _ = try await loader.image(item, client: client, priority: .prefetch) }
        catch {
            if error is CancellationError || (error as? URLError)?.code == .cancelled { throw error }
            if case APIError.unauthorized = error { throw error }
            if case APIError.forbidden = error { throw error }
            if AgendaOfflineCache.isUnavailable(error) { throw error }
            // A missing cover must not stop the rest of the folder.
        }
    }
}

/// One selection spans the expanded folders, but never another session or
/// collection. Keep the observed revision until the user explicitly reselects.
@MainActor
final class MediaBatchSelection: ObservableObject {
    private struct Entry {
        let item: MediaItem
        let ancestors: Set<String>
        let canDelete: Bool
    }
    @Published private(set) var active = false
    @Published private var entries: [Entry] = []
    @Published private(set) var deleting = false
    @Published private(set) var completed = 0
    @Published private(set) var total = 0
    @Published private(set) var failures: [String] = []
    @Published private(set) var message: String?
    private var stamp: String?
    private var collectionID: String?
    private var operation = UUID()
    private var task: Task<Void, Never>?

    var items: [MediaItem] { entries.map(\.item) }
    var count: Int { entries.count }
    var canDelete: Bool { !entries.isEmpty && entries.allSatisfy(\.canDelete) }
    func contains(_ id: String) -> Bool { entries.contains { $0.item.id == id } }

    func select(_ item: MediaItem, in feed: MediaFeed, client: PayrollClient) {
        guard !deleting, item.kind == "image" || item.kind == "video",
              feed.connected, feed.canRead, let current = try? client.mediaAccessStamp() else { return }
        if active && (stamp != current || collectionID != feed.collectionID) { reset() }
        if !active { stamp = current; collectionID = feed.collectionID; active = true }
        guard !contains(item.id) else { return }
        entries.append(Entry(item: item, ancestors: Set(feed.breadcrumbs.map(\.id)).union([feed.folder?.id ?? ""]), canDelete: feed.canDelete == true))
    }

    func toggle(_ item: MediaItem, in feed: MediaFeed, client: PayrollClient) {
        guard !deleting else { return }
        if contains(item.id) { entries.removeAll { $0.item.id == item.id } }
        else { select(item, in: feed, client: client) }
    }

    func synchronize(client: PayrollClient) {
        if active, stamp != (try? client.mediaAccessStamp()) { reset() }
    }

    func reconcile(_ feed: MediaFeed) {
        guard active else { return }
        guard feed.connected, feed.canRead, collectionID == feed.collectionID else { reset(); return }
        let files = Set(feed.deletedFiles ?? []), folders = Set(feed.deletedFolders ?? [])
        let current = Dictionary(feed.items.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        entries.removeAll { entry in
            files.contains(entry.item.id) || !entry.ancestors.isDisjoint(with: folders)
                || current[entry.item.id].map { $0 != entry.item } == true
        }
        // Cached feeds omit write permissions. Only a confirmed denial changes
        // the permission already observed in an authorized network listing.
        if feed.canDelete == false {
            entries = entries.map { Entry(item: $0.item, ancestors: $0.ancestors, canDelete: false) }
        }
    }

    func reset() {
        operation = UUID(); task?.cancel(); task = nil
        active = false; entries = []; stamp = nil; collectionID = nil
        deleting = false; completed = 0; total = 0; failures = []; message = nil
    }

    func cancelDeletion() { task?.cancel() }

    func delete(_ targets: [MediaItem], client: PayrollClient, denied: @escaping (Error) -> Void) {
        synchronize(client: client)
        guard active, !deleting, canDelete, !targets.isEmpty,
              client.accessUser?.canDeleteMedia == true, !client.usingOfflineCopy,
              let scope = try? client.mediaScope(), let stamp else { return }
        guard targets.allSatisfy({ target in entries.contains { $0.item == target && $0.canDelete } }) else {
            message = "La selección cambió. Revisa los archivos antes de eliminarlos."; return
        }
        let actor = client.accessUser, run = UUID()
        operation = run; deleting = true; completed = 0; total = targets.count; failures = []; message = nil
        self.stamp = stamp
        task = Task {
            defer { if operation == run { deleting = false; task = nil } }
            for item in targets {
                do {
                    var result: MediaFolderDeletion
                    repeat {
                        try Task.checkCancellation()
                        guard operation == run, self.stamp == (try client.mediaAccessStamp()),
                              scope.id == (try client.mediaScope())?.id, actor == client.accessUser else { throw CancellationError() }
                        result = try await client.deleteMediaFileStep(item)
                        guard operation == run, scope.id == (try client.mediaScope())?.id,
                              actor == client.accessUser else { throw CancellationError() }
                        // This authorized delete advances the client's cache generation.
                        // Adopt only our own change, in the same session and permission set.
                        self.stamp = try client.mediaAccessStamp()
                        try Task.checkCancellation()
                        if result.complete != true { try await Task.sleep(for: .milliseconds(result.waiting == true ? 1000 : 100)) }
                    } while result.complete != true
                    completed += 1; entries.removeAll { $0.item.id == item.id }
                } catch {
                    guard operation == run else { return }
                    if error is CancellationError || (error as? URLError)?.code == .cancelled {
                        message = "Eliminación detenida. Los archivos ya eliminados no se pueden recuperar."; return
                    }
                    if case APIError.unauthorized = error { reset(); denied(error); return }
                    if case APIError.forbidden = error { reset(); denied(error); return }
                    failures.append(item.name + ": " + error.localizedDescription)
                }
            }
            if operation == run { message = "\(completed) de \(total) archivos eliminados." }
        }
    }
}

/// An exclusive gesture keeps a completed long press from opening the viewer
/// when the finger lifts. VoiceOver has the same explicit default action.
@MainActor
struct MediaSelectableTile: View {
    let item: MediaItem
    let feed: MediaFeed
    let client: PayrollClient
    @ObservedObject var selection: MediaBatchSelection
    let offline: Bool
    let disabled: Bool
    let opening: Bool
    let epoch: UUID
    let open: () -> Void
    let denied: (Error) -> Void
    @State private var suppressTapUntil = Date.distantPast
    private var selected: Bool { selection.contains(item.id) }
    var body: some View {
        MediaTile(item: item, client: client, offline: offline, opening: opening, epoch: epoch, denied: denied,
                  selectionValue: selection.active ? (selected ? "Seleccionado" : "No seleccionado") : nil)
                .overlay { if selected { RoundedRectangle(cornerRadius: 18).strokeBorder(JACTheme.action, lineWidth: 3) } }
                .overlay(alignment: .topTrailing) {
                    if selection.active {
                        Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                            .font(.title2).symbolRenderingMode(.palette).foregroundStyle(selected ? JACTheme.action : Color.secondary, Color.white)
                            .padding(10).accessibilityHidden(true)
                    }
                }
        .disabled(disabled)
        .contentShape(Rectangle())
        .onTapGesture { if Date() >= suppressTapUntil { tap() } }
        .simultaneousGesture(LongPressGesture(minimumDuration: 0.45, maximumDistance: 10).onEnded { _ in
            guard !disabled else { return }
            suppressTapUntil = Date().addingTimeInterval(0.35)
            selection.select(item, in: feed, client: client)
        })
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { tap() }
        .accessibilityIdentifier("media.item." + item.id)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
        .accessibilityAction(named: Text("Seleccionar")) { if !disabled { selection.select(item, in: feed, client: client) } }
        .overlay(alignment: .topTrailing) {
            if !selection.active, item.kind == "image" || item.kind == "video" {
                MediaPhotoMenu(item: item, client: client, canDelete: client.accessUser?.canDeleteMedia == true && feed.canDelete == true).padding(6)
            }
        }
    }
    private func tap() {
        guard !disabled else { return }
        if selection.active { selection.toggle(item, in: feed, client: client) }
        else { open() }
    }
}

/// An expanded folder keeps its own authorized feed. Opening a photo passes
/// that feed to the viewer, so the slideshow stays inside the same folder.
@MainActor
struct MediaInlineFolder: View {
    let folder: MediaFolder
    let collectionID: String?
    @Binding var expanded: Set<String>
    let epoch: UUID
    let disabled: Bool
    let opening: String?
    let open: (MediaItem, MediaFeed) -> Void
    let denied: (Error) -> Void
    let commands: (MediaFolder) -> AnyView
    @ObservedObject var selection: MediaBatchSelection
    var ancestry: Set<String> = []

    @EnvironmentObject private var store: PayrollStore
    @Environment(\.isWorkspaceActive) private var isWorkspaceActive
    @Environment(\.scenePhase) private var phase
    @State private var feed: MediaFeed?
    @State private var items: [MediaItem] = []
    @State private var loading = false
    @State private var offline = false
    @State private var error: String?
    @State private var loadedPages = 1
    @State private var generation = UUID()
    @State private var readTask: Task<Void, Never>?
    @StateObject private var thumbnails = MediaFolderThumbnailPrefetch()

    private var isExpanded: Bool { expanded.contains(folder.id) }
    private var accessStamp: String? { isExpanded ? store.client.mediaPresentationStamp : nil }
    private var workspaceCanRefresh: Bool { isWorkspaceActive && phase == .active }
    private var validPath: Bool { !ancestry.contains(folder.id) && ancestry.count < 64 }
    private var descendants: Set<String> { ancestry.union([folder.id]) }
    private var folders: [MediaItem] { items.filter { $0.kind == "folder" && !descendants.contains($0.id) } }
    private var files: [MediaItem] { items.filter { $0.kind != "folder" } }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 4) {
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        if isExpanded { expanded.remove(folder.id) }
                        else if validPath { expanded.insert(folder.id) }
                    }
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: isExpanded ? "folder.fill" : "folder")
                            .font(.system(size: 23, weight: .medium))
                            .foregroundStyle(JACTheme.action)
                            .frame(width: 32)
                        Text(folder.name).font(.body.weight(.semibold))
                            .foregroundStyle(JACTheme.ink)
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                            .rotationEffect(.degrees(isExpanded ? 90 : 0))
                            .accessibilityHidden(true)
                    }
                    .padding(.leading, 16).padding(.vertical, 17).padding(.trailing, 9)
                    .frame(maxWidth: .infinity, minHeight: 64)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(!validPath)
                .accessibilityIdentifier("media.item." + folder.id)
                .accessibilityValue(isExpanded ? "Abierta" : "Cerrada")

                Menu { commands(folder) } label: {
                    Image(systemName: "ellipsis")
                        .font(.body.weight(.semibold))
                        .frame(width: 44, height: 52).contentShape(Rectangle())
                }
                .buttonStyle(.plain).padding(.trailing, 6)
                .disabled(disabled)
                .accessibilityLabel("Opciones de " + folder.name)
                .accessibilityIdentifier("media.options." + folder.id)
            }
            .contextMenu { commands(folder) }

            if isExpanded && validPath {
                VStack(alignment: .leading, spacing: 14) {
                    if loading && items.isEmpty {
                        ProgressView().frame(maxWidth: .infinity).padding(.vertical, 18)
                    }
                    if let error {
                        HStack(alignment: .top, spacing: 10) {
                            Text(error).font(.footnote).foregroundStyle(.secondary)
                            Spacer(minLength: 0)
                            Button("Reintentar") { startRead() }.disabled(loading || disabled)
                        }
                    }
                    if feed != nil && items.isEmpty && !loading {
                        Text("Esta carpeta está vacía").font(.subheadline)
                            .foregroundStyle(.secondary).padding(.vertical, 10)
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                    ForEach(folders) { child in
                        AnyView(MediaInlineFolder(
                            folder: MediaFolder(id: child.id, name: child.name),
                            collectionID: collectionID,
                            expanded: $expanded,
                            epoch: epoch,
                            disabled: disabled,
                            opening: opening,
                            open: open,
                            denied: denied,
                            commands: commands,
                            selection: selection,
                            ancestry: descendants
                        ))
                    }
                    if let feed, !files.isEmpty {
                        LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                            ForEach(files) { item in
                                MediaSelectableTile(item: item, feed: feed, client: store.client, selection: selection,
                                                    offline: offline || store.isOffline, disabled: disabled || opening != nil,
                                                    opening: opening == item.id, epoch: epoch,
                                                    open: { open(item, previewFeed(feed)) }, denied: reject)
                            }
                        }
                    }
                    if !(feed?.nextPageToken ?? "").isEmpty {
                        Button {
                            loadedPages += 1
                            startRead()
                        } label: {
                            HStack { if loading { ProgressView() }; Text("Cargar más") }
                                .frame(maxWidth: .infinity).padding(.vertical, 8)
                        }
                        .disabled(loading || disabled || offline)
                        .accessibilityIdentifier("media.more." + folder.id)
                    }
                }
                .padding(.horizontal, 12).padding(.bottom, 14)
                .accessibilityIdentifier("media.contents." + folder.id)
            }
        }
        .background(JACTheme.card, in: RoundedRectangle(cornerRadius: 18))
        .overlay { RoundedRectangle(cornerRadius: 18).strokeBorder(JACTheme.action.opacity(0.07), lineWidth: 1) }
        .onAppear { if isExpanded { startRead() } }
        .onChange(of: workspaceCanRefresh) { _, active in
            if active && isExpanded { startRead() }
            else { stopRead(); thumbnails.stop() }
        }
        .onChange(of: isExpanded) { _, value in
            if value { startRead() }
            else { stopRead(); clearContent(); loadedPages = 1 }
        }
        .onChange(of: epoch) { _, _ in if isExpanded { startRead() } }
        .onChange(of: collectionID) { _, _ in
            stopRead(); clearContent(); loadedPages = 1
            if isExpanded { startRead() }
        }
        .onChange(of: accessStamp) { previous, stamp in
            // Opening already starts the read. Closed headers never need a
            // Keychain lookup or a decrypted folder index on every refresh.
            if previous == nil, stamp != nil {
                if isExpanded { startRead() }
                return
            }
            stopRead(); clearContent(); loadedPages = 1
            if stamp != nil && isExpanded { startRead() }
        }
        .onReceive(store.client.$cacheRevision.dropFirst()) {_ in
            guard isExpanded, workspaceCanRefresh else { return }
            if let saved=store.client.cachedMedia(folder:folder.id) {
                let remaining = MediaGalleryOrder.applyingDeletions(to: items, from: saved)
                if remaining != items { items = remaining }
                selection.reconcile(saved.replacingItems([]))
            }
        }
        .onChange(of: store.isOffline) { previous, current in
            if current { thumbnails.stop() }
            if previous && !current && offline && isExpanded { startRead() }
        }
        .onDisappear { stopRead(); thumbnails.stop() }
    }

    private func previewFeed(_ source: MediaFeed) -> MediaFeed {
        // A paginated read stores its final page as the cursor source. The
        // viewer receives the whole visible set and can continue from there.
        return MediaFeed(connected: source.connected, canRead: source.canRead,
                           canUpload: source.canUpload, canConnect: source.canConnect,
                           root: source.root, folder: source.folder,
                           breadcrumbs: source.breadcrumbs, items: items,
                           nextPageToken: source.nextPageToken, provider: source.provider,
                           collectionID: source.collectionID, canDelete: source.canDelete,
                           pendingDeletions: source.pendingDeletions,
                         deletedFolders: source.deletedFolders,deletedFiles:source.deletedFiles,pendingFileDeletions:source.pendingFileDeletions)
    }

    private func stopRead() {
        generation = UUID(); readTask?.cancel(); readTask = nil; loading = false
    }

    private func clearContent() {
        thumbnails.stop()
        feed = nil; items = []; offline = false; error = nil
    }

    private func reject(_ failure: Error) {
        stopRead(); clearContent(); denied(failure)
    }

    private func validate(_ value: MediaFeed) throws {
        guard value.connected, value.canRead else {
            throw APIError.forbidden("Esta carpeta ya no está disponible en Fotografía.")
        }
        guard value.folder?.id == folder.id, value.collectionID == collectionID else {
            throw APIError.invalid("La carpeta cambió. Actualiza Fotografía para volver a abrirla.")
        }
    }

    private func startRead() {
        guard workspaceCanRefresh, isExpanded, validPath, !loading else { return }
        stopRead()
        let expected = generation, pages = max(1, loadedPages)
        loading = true
        readTask = Task {
            defer { if expected == generation { loading = false; readTask = nil } }
            var stamp: String?
            do {
                stamp = try store.client.mediaAccessStamp()
                guard stamp != nil else { throw APIError.unauthorized }
                if feed == nil, let saved = store.client.cachedMedia(folder: folder.id), (try? validate(saved)) != nil {
                    feed = saved; items = uniqueSorted(saved.items)
                    thumbnails.start(saved, client: store.client, networkAllowed: !store.isOffline, denied: reject)
                }
                let read = try await MediaGalleryListing.read(minimumPages: pages, minimumItems: items.count) { cursor in
                    guard expected == generation, isExpanded, stamp == (try store.client.mediaAccessStamp()) else { throw CancellationError() }
                    let value = try await store.client.media(folder: folder.id, pageToken: cursor, forceNetwork: true)
                    try validate(value)
                    return value
                }
                try Task.checkCancellation()
                guard expected == generation, isExpanded, stamp == (try store.client.mediaAccessStamp()) else { throw CancellationError() }
                let result = read.feed
                loadedPages = read.pages; feed = result
                if items != result.items { items = result.items }
                offline = false; error = nil; selection.reconcile(previewFeed(result))
                thumbnails.start(previewFeed(result), client: store.client, networkAllowed: !store.isOffline, denied: reject)
            } catch {
                guard expected == generation, isExpanded, !Task.isCancelled else { return }
                if failureIsCancelled(error) { return }
                if case APIError.unauthorized = error { reject(error); return }
                if case APIError.forbidden = error { reject(error); return }
                if error is MediaFolderRemoved { reject(error); return }
                guard stamp != nil, stamp == (try? store.client.mediaAccessStamp()) else { clearContent(); return }
                if AgendaOfflineCache.isUnavailable(error), let saved = store.client.cachedMedia(folder: folder.id),
                   (try? validate(saved)) != nil {
                    if feed == nil { feed = saved; items = uniqueSorted(saved.items) }
                    offline = true; self.error = nil
                    thumbnails.stop()
                    return
                }
                self.error = error.localizedDescription
            }
        }
    }

    private func uniqueSorted(_ values: [MediaItem]) -> [MediaItem] {
        var seen = Set<String>()
        return MediaGalleryOrder.sorted(values.filter { seen.insert($0.id).inserted })
    }

    private func failureIsCancelled(_ failure: Error) -> Bool {
        failure is CancellationError || (failure as? URLError)?.code == .cancelled
    }
}
#endif
