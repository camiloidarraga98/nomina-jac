#if os(iOS)
import SwiftUI

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
        if feed.canDelete != true {
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
/// when the finger lifts. The button action remains available to VoiceOver.
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
    private var selected: Bool { selection.contains(item.id) }
    var body: some View {
        Button(action: tap) {
            MediaTile(item: item, client: client, offline: offline, opening: opening, epoch: epoch, denied: denied)
                .overlay { if selected { RoundedRectangle(cornerRadius: 18).strokeBorder(JACTheme.action, lineWidth: 3) } }
                .overlay(alignment: .topTrailing) {
                    if selection.active {
                        Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                            .font(.title2).symbolRenderingMode(.palette).foregroundStyle(selected ? JACTheme.action : Color.secondary, Color.white)
                            .padding(10).accessibilityHidden(true)
                    }
                }
        }
        .buttonStyle(.plain).disabled(disabled)
        .highPriorityGesture(LongPressGesture(minimumDuration: 0.45).exclusively(before: TapGesture()).onEnded { gesture in
            guard !disabled else { return }
            switch gesture {
            case .first: selection.select(item, in: feed, client: client)
            case .second: tap()
            }
        })
        .accessibilityIdentifier("media.item." + item.id)
        .accessibilityValue(selection.active ? (selected ? "Seleccionado" : "No seleccionado") : "")
        .accessibilityAddTraits(selected ? [.isSelected] : [])
        .accessibilityAction(named: Text("Seleccionar")) { if !disabled { selection.select(item, in: feed, client: client) } }
        .overlay(alignment: .topTrailing) {
            if !selection.active, item.kind == "image" {
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
    @State private var feed: MediaFeed?
    @State private var items: [MediaItem] = []
    @State private var loading = false
    @State private var offline = false
    @State private var error: String?
    @State private var loadedPages = 1
    @State private var generation = UUID()
    @State private var readTask: Task<Void, Never>?

    private var isExpanded: Bool { expanded.contains(folder.id) }
    private var accessStamp: String? { try? store.client.mediaAccessStamp() }
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
                .disabled(disabled || !validPath)
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
        .onChange(of: isExpanded) { _, value in
            if value { startRead() }
            else { stopRead(); clearContent(); loadedPages = 1 }
        }
        .onChange(of: epoch) { _, _ in if isExpanded { startRead() } }
        .onChange(of: collectionID) { _, _ in
            stopRead(); clearContent(); loadedPages = 1
            if isExpanded { startRead() }
        }
        .onChange(of: accessStamp) { _, stamp in
            stopRead(); clearContent(); loadedPages = 1
            if stamp != nil && isExpanded { startRead() }
        }
        .onReceive(store.client.$cacheRevision.dropFirst()) {_ in
            if let saved=store.client.cachedMedia(folder:folder.id) {items=uniqueSorted(saved.items);selection.reconcile(saved)}
        }
        .onChange(of: store.isOffline) { previous, current in
            if previous && !current && offline && isExpanded { startRead() }
        }
        .onDisappear { stopRead(); clearContent() }
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
        guard isExpanded, validPath else { return }
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
                }
                var result = try await store.client.media(folder: folder.id, forceNetwork: true)
                try validate(result)
                var all = result.items, cursor = result.nextPageToken ?? "", visited = Set<String>()
                for _ in 1..<pages {
                    guard !cursor.isEmpty else { break }
                    guard visited.insert(cursor).inserted else { throw APIError.invalid("No se pudo continuar la lista de esta carpeta.") }
                    try Task.checkCancellation()
                    guard expected == generation, isExpanded, stamp == (try store.client.mediaAccessStamp()) else { throw CancellationError() }
                    result = try await store.client.media(folder: folder.id, pageToken: cursor, forceNetwork: true)
                    try validate(result)
                    all += result.items; cursor = result.nextPageToken ?? ""
                }
                try Task.checkCancellation()
                guard expected == generation, isExpanded, stamp == (try store.client.mediaAccessStamp()) else { throw CancellationError() }
                feed = result; items = uniqueSorted(all); offline = false; error = nil; selection.reconcile(previewFeed(result))
            } catch {
                guard expected == generation, isExpanded, !Task.isCancelled else { return }
                if failureIsCancelled(error) { clearContent(); return }
                if case APIError.unauthorized = error { reject(error); return }
                if case APIError.forbidden = error { reject(error); return }
                if error is MediaFolderRemoved { reject(error); return }
                guard stamp != nil, stamp == (try? store.client.mediaAccessStamp()) else { clearContent(); return }
                if AgendaOfflineCache.isUnavailable(error), let saved = store.client.cachedMedia(folder: folder.id),
                   (try? validate(saved)) != nil {
                    feed = saved; items = uniqueSorted(saved.items); offline = true; self.error = nil
                    return
                }
                clearContent()
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
