#if os(iOS)
import SwiftUI

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
                            ancestry: descendants
                        ))
                    }
                    if let feed, !files.isEmpty {
                        LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                            ForEach(files) { item in
                                Button { open(item, previewFeed(feed)) } label: {
                                    MediaTile(item: item, client: store.client,
                                              offline: offline || store.isOffline,
                                              opening: opening == item.id,
                                              epoch: epoch, denied: reject)
                                }
                                .buttonStyle(.plain).disabled(disabled || opening != nil)
                                .accessibilityIdentifier("media.item." + item.id)
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
                         deletedFolders: source.deletedFolders)
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
                feed = result; items = uniqueSorted(all); offline = false; error = nil
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
