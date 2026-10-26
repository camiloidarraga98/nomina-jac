#if os(iOS)
import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import CoreTransferable
import AVFoundation
import AVKit

struct MediaPreparedVideo: Sendable {
    let file: MediaLocalFile
    let detail: String?
}

/// Only checks the staged original; never exports or re-encodes video. The
/// recoverable queue adopts this same URL/UUID, including already queued copies.
enum MediaVideoPreparation {
    static func prepare(_ file: MediaLocalFile) async throws -> MediaPreparedVideo {
        try Task.checkCancellation()
        guard file.mimeType.hasPrefix("video/") else { return MediaPreparedVideo(file: file, detail: nil) }
        let work = Task.detached(priority: .userInitiated) {
            try Task.checkCancellation()
            let values = try file.url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
            guard values.isRegularFile == true, values.isSymbolicLink != true,
                  values.fileSize == Int(file.size), file.size > 0, file.size <= MediaLocalFile.maximumSize,
                  MediaLocalFile.mime(file.url) == file.mimeType else {
                throw APIError.invalid("El video cambió o no es compatible. Vuelve a seleccionarlo.")
            }
            let input = try FileHandle(forReadingFrom: file.url); defer { try? input.close() }
            let head = try input.read(upToCount: 64) ?? Data()
            let box = head.count >= 8 ? String(data: head.subdata(in: 4..<8), encoding: .ascii) : nil
            let webm = head.starts(with: [0x1a, 0x45, 0xdf, 0xa3])
            let valid = file.mimeType == "video/webm" ? webm : box == "ftyp" ||
                (file.mimeType == "video/quicktime" && ["moov", "mdat", "wide"].contains(box ?? ""))
            guard valid else { throw APIError.invalid("El archivo no corresponde a un video compatible.") }
            try Task.checkCancellation()
        }
        try await withTaskCancellationHandler { try await work.value } onCancel: { work.cancel() }
        try Task.checkCancellation()
        return MediaPreparedVideo(file: file, detail: "Video original · Sin compresión")
    }
}

// The default ambient audio session obeys the iPhone's silent switch. Explicit
// video playback should behave like a media player and release other audio on close.
@MainActor
enum MediaVideoAudioPlayback {
    static func activate() throws {
        NotificationCenter.default.post(name: Notification.Name("JACVideoPlaybackBegan"), object: nil)
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .moviePlayback)
        try session.setActive(true)
    }
    static func deactivate() {
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}

private struct MediaComposerVideoPreview: View {
    @State private var player: AVPlayer
    init(url: URL) { _player = State(initialValue: AVPlayer(url: url)) }
    var body: some View {
        VideoPlayer(player: player)
            .onAppear { try? MediaVideoAudioPlayback.activate() }
            .onDisappear { player.pause(); MediaVideoAudioPlayback.deactivate() }
    }
}

/// The sheet owns staged files until submission; the gallery owns them afterwards.
struct MediaSimpleUploadComposer: View {
    let root: MediaFolder
    let destination: MediaFolder?
    let submitted: (MediaFolder, [MediaLocalFile]) -> Void
    @EnvironmentObject private var store: PayrollStore
    @Environment(\.dismiss) private var dismiss
    @StateObject private var draft = MediaSimpleUploadDraft()
    @State private var pickingFiles = false
    @State private var videoPreview: MediaLocalFile?

    private var writable: Bool {
        store.overview?.user.canUploadMedia == true && !store.isOffline
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    if let destination {
                        Label(destination.name, systemImage: "folder.fill")
                            .font(.headline).foregroundStyle(JACTheme.action)
                    } else {
                        VStack(alignment: .leading, spacing: 9) {
                            Text("Nombre de la carpeta").font(.subheadline.weight(.semibold))
                            TextField("Nombre de la carpeta", text: $draft.name)
                                .textFieldStyle(.roundedBorder).textInputAutocapitalization(.sentences)
                                .autocorrectionDisabled().submitLabel(.done)
                                .disabled(draft.creating || draft.attemptedName != nil)
                                .accessibilityIdentifier("media.folder.name")
                        }
                    }

                    VStack(alignment: .leading, spacing: 14) {
                        Label("Videos en calidad original", systemImage: "video.fill")
                            .font(.subheadline.weight(.semibold)).accessibilityIdentifier("media.video.original")
                        Text("Sin compresión previa. Se conservan la calidad, el sonido y el formato original.")
                            .font(.caption).foregroundStyle(.secondary)
                        HStack(spacing: 12) {
                            PhotosPicker(selection: $draft.selectedPhotos, matching: .any(of: [.images, .videos]), preferredItemEncoding: .current) {
                                Label("Fotos y videos", systemImage: "photo.on.rectangle")
                                    .frame(maxWidth: .infinity, minHeight: 36)
                            }.buttonStyle(.bordered).accessibilityIdentifier("media.library")
                            Button { pickingFiles = true } label: {
                                Label("Archivos", systemImage: "folder")
                                    .frame(maxWidth: .infinity, minHeight: 36)
                            }.buttonStyle(.bordered).accessibilityIdentifier("media.files")
                        }.disabled(!writable || draft.importing || draft.creating)

                        if draft.importing {
                            ProgressView(draft.preparingMessage).font(.subheadline)
                            Text("Mantén JAC abierta mientras prepara los videos. Después, la cola de subida puede continuar en segundo plano.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        if draft.files.isEmpty && !draft.importing {
                            Text("Elige las fotos o videos que quieres subir.")
                                .font(.subheadline).foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 10)
                        }
                        ForEach(draft.files) { file in
                            HStack(spacing: 12) {
                                Image(systemName: file.mimeType.hasPrefix("video/") ? "video.fill" : "photo.fill")
                                    .foregroundStyle(JACTheme.action).frame(width: 24)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(file.name).font(.subheadline).lineLimit(2)
                                    Text(ByteCountFormatter.string(fromByteCount: file.size, countStyle: .file))
                                        .font(.caption).foregroundStyle(.secondary)
                                    if let detail = draft.videoDetails[file.id] {
                                        Text(detail).font(.caption).foregroundStyle(.secondary)
                                            .accessibilityIdentifier("media.video.result." + file.id)
                                    }
                                    if file.mimeType.hasPrefix("video/") {
                                        Button("Ver video antes de subir") { videoPreview = file }
                                            .font(.caption).buttonStyle(.plain).foregroundStyle(JACTheme.action)
                                    }
                                }
                                Spacer(minLength: 4)
                                Button { draft.remove(file) } label: {
                                    Image(systemName: "xmark.circle.fill").font(.title3)
                                        .foregroundStyle(.secondary).frame(width: 44, height: 44)
                                        .contentShape(Rectangle())
                                }.buttonStyle(.plain).accessibilityLabel("Quitar \(file.name)")
                                    .disabled(draft.creating || draft.importing)
                            }
                            .padding(12).background(JACTheme.card, in: RoundedRectangle(cornerRadius: 14))
                        }
                        #if DEBUG
                        if store.client.baseURL.host?.hasSuffix(".invalid") == true {
                            Button("Adjuntar foto y video ficticios") { draft.addFixture(store: store) }
                                .disabled(!writable || draft.importing || draft.creating)
                                .accessibilityIdentifier("media.fixture")
                        }
                        #endif
                    }
                    if let error = draft.error { InlineError(message: error) }
                }.padding(20)
            }
            .jacSurface().navigationTitle("Subir archivos").jacInlineTitle()
            .safeAreaInset(edge: .bottom) {
                Button {
                    draft.submit(root: root, destination: destination, store: store) { folder, files in
                        submitted(folder, files)
                        dismiss()
                    }
                } label: {
                    HStack {
                        if draft.creating { ProgressView().tint(.white) }
                        Text(draft.creating ? "Preparando subida…" : "Subir")
                    }.frame(maxWidth: .infinity)
                }.buttonStyle(JACPrimaryButtonStyle())
                    .disabled(!writable || draft.importing || draft.creating || draft.files.isEmpty || (destination == nil && draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty))
                    .accessibilityIdentifier("media.upload")
                    .padding(.horizontal, 20).padding(.vertical, 12).background(.bar)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { draft.cancel(); dismiss() }
                        .disabled(draft.creating).accessibilityIdentifier("media.composer.cancel")
                }
            }
            .fileImporter(isPresented: $pickingFiles, allowedContentTypes: [.image, .movie, .video], allowsMultipleSelection: true) { result in
                switch result {
                case .success(let urls): draft.importFiles(urls, store: store)
                case .failure(let error):
                    if (error as NSError).code != NSUserCancelledError { draft.error = error.localizedDescription }
                }
            }
            .onChange(of: draft.selectedPhotos) { _, photos in draft.importPhotos(photos, store: store) }
            .onChange(of: store.overview?.user.canUploadMedia) { _, allowed in
                if allowed != true { videoPreview = nil; draft.cancel(); dismiss() }
            }
            .onChange(of: try? store.client.mediaAccessStamp()) { old, new in
                if old != new { videoPreview = nil; draft.cancel(); dismiss() }
            }
            .onChange(of: store.overview?.user.id) { _, _ in videoPreview = nil; draft.cancel(); dismiss() }
            .sheet(item: $videoPreview) { file in
                NavigationStack {
                    MediaComposerVideoPreview(url: file.url).navigationTitle("Revisar video").jacInlineTitle()
                        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Listo") { videoPreview = nil } } }
                }
            }
        }
        // System file/photo pickers may temporarily hide this sheet. Cleanup is
        // tied to cancellation/ownership, never a transient onDisappear.
        .interactiveDismissDisabled(draft.importing || draft.creating)
    }
}

private struct MediaComposerLibraryFile: Transferable {
    let staged: MediaLocalFile
    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(importedContentType: .image) { received in
            MediaComposerLibraryFile(staged: try MediaLocalFile.stage(received.file))
        }
        FileRepresentation(importedContentType: .movie) { received in
            MediaComposerLibraryFile(staged: try MediaLocalFile.stage(received.file))
        }
    }
}

// Ownership is separate from observable UI state so destruction can always
// remove staged bytes, including when Swift destroys the view off its actor.
private final class MediaComposerStaging {
    private var owned: [String: MediaLocalFile] = [:]
    func retain(_ file: MediaLocalFile) { owned[file.id] = file }
    func remove(_ file: MediaLocalFile) { owned.removeValue(forKey: file.id)?.remove() }
    func clear() { owned.values.forEach { $0.remove() }; owned = [:] }
    func handoff() { owned = [:] }
    deinit { clear() }
}

@MainActor private final class MediaSimpleUploadDraft: ObservableObject {
    @Published var name = ""
    @Published var selectedPhotos: [PhotosPickerItem] = []
    @Published private(set) var files: [MediaLocalFile] = []
    @Published private(set) var importing = false
    @Published private(set) var creating = false
    @Published private(set) var attemptedName: String?
    @Published private(set) var videoDetails: [String: String] = [:]
    @Published private(set) var preparingMessage = "Preparando archivos…"
    @Published var error: String?
    private let requestID = UUID().uuidString.lowercased()
    private let staging = MediaComposerStaging()
    private var active = true
    private var importTask: Task<Void, Never>?
    private var creationTask: Task<Void, Never>?

    deinit {
        importTask?.cancel()
        creationTask?.cancel()
    }

    func cancel() {
        active = false
        importTask?.cancel()
        creationTask?.cancel()
        staging.clear()
        files = []
        videoDetails = [:]
    }

    func remove(_ file: MediaLocalFile) {
        guard !creating, !importing else { return }
        files.removeAll { $0.id == file.id }
        videoDetails.removeValue(forKey: file.id)
        staging.remove(file)
    }

    private func accept(_ source: MediaLocalFile, stamp: String, store: PayrollStore) async throws {
        guard isCurrent(stamp, store: store) else { source.remove(); throw CancellationError() }
        // Keep the source alive through cancellation; ownership transfers only
        // after validation and the session/permission check have both completed.
        var accepted = false
        defer { if !accepted { source.remove() } }
        preparingMessage = source.mimeType.hasPrefix("video/") ? "Revisando video original…" : "Preparando archivos…"
        let result = try await MediaVideoPreparation.prepare(source)
        guard isCurrent(stamp, store: store) else { if result.file.url != source.url { result.file.remove() }; throw CancellationError() }
        if result.file.url != source.url { source.remove() }
        staging.retain(result.file)
        files.append(result.file)
        videoDetails[source.id] = result.detail
        accepted = true
    }

    private func isCurrent(_ stamp: String, store: PayrollStore) -> Bool {
        active && !Task.isCancelled && stamp == (try? store.client.mediaAccessStamp()) && store.overview?.user.canUploadMedia == true
    }

    func importFiles(_ urls: [URL], store: PayrollStore) {
        guard active, !importing, !creating, !store.isOffline, store.overview?.user.canUploadMedia == true,
              let stamp = try? store.client.mediaAccessStamp() else { return }
        importing = true
        error = nil
        importTask = Task { [weak self] in
            guard let self else { return }
            defer { self.importing = false; self.importTask = nil }
            for (index, url) in urls.enumerated() {
                preparingMessage = "Copiando archivo \(index + 1) de \(urls.count)…"
                do {
                    try Task.checkCancellation()
                    let worker = Task.detached(priority: .userInitiated) { try MediaLocalFile.stage(url) }
                    let file = try await withTaskCancellationHandler { try await worker.value } onCancel: { worker.cancel() }
                    try await self.accept(file, stamp: stamp, store: store)
                } catch {
                    if self.isCurrent(stamp, store: store), !(error is CancellationError) { self.error = error.localizedDescription }
                }
            }
        }
    }

    func importPhotos(_ photos: [PhotosPickerItem], store: PayrollStore) {
        guard active, !photos.isEmpty, !importing, !creating, !store.isOffline, store.overview?.user.canUploadMedia == true,
              let stamp = try? store.client.mediaAccessStamp() else { return }
        importing = true
        error = nil
        importTask = Task { [weak self] in
            guard let self else { return }
            defer { self.importing = false; self.selectedPhotos = []; self.importTask = nil }
            for (index, photo) in photos.enumerated() {
                preparingMessage = "Obteniendo de Fotos \(index + 1) de \(photos.count)…"
                do {
                    try Task.checkCancellation()
                    guard let result = try await photo.loadTransferable(type: MediaComposerLibraryFile.self) else {
                        throw APIError.message("No se pudo leer esa foto o video.")
                    }
                    try await self.accept(result.staged, stamp: stamp, store: store)
                } catch {
                    if self.isCurrent(stamp, store: store), !(error is CancellationError) { self.error = error.localizedDescription }
                }
            }
        }
    }

    func submit(root: MediaFolder, destination: MediaFolder?, store: PayrollStore, submitted: @escaping (MediaFolder, [MediaLocalFile]) -> Void) {
        guard active, !creating, !importing, !files.isEmpty, !root.id.isEmpty, !store.isOffline,
              store.overview?.user.canUploadMedia == true, let stamp = try? store.client.mediaAccessStamp() else { return }
        let folderName = attemptedName ?? name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard destination != nil || !folderName.isEmpty else { return }
        creating = true
        error = nil
        if destination == nil { attemptedName = folderName }
        creationTask = Task { [weak self] in
            guard let self else { return }
            defer { self.creating = false; self.creationTask = nil }
            do {
                let folder: MediaFolder
                if let destination { folder = destination }
                else { folder = try await store.client.createMediaFolder(id: self.requestID, parentID: root.id, name: folderName, date: BoardingClock.today()) }
                guard self.isCurrent(stamp, store: store) else { throw CancellationError() }
                let transferred = self.files
                self.files = []
                self.staging.handoff()
                self.active = false
                submitted(folder, transferred)
            } catch {
                guard self.active else { return }
                if case APIError.invalid = error { self.attemptedName = nil }
                self.error = store.reportReadFailure(error)
            }
        }
    }

    #if DEBUG
    func addFixture(store: PayrollStore) {
        guard active, !creating, !importing, !store.isOffline, store.overview?.user.canUploadMedia == true,
              store.client.baseURL.host?.hasSuffix(".invalid") == true,
              let stamp = try? store.client.mediaAccessStamp() else { return }
        importing = true
        error = nil
        importTask = Task { [weak self] in
            guard let self else { return }
            defer { self.importing = false; self.importTask = nil }
            do {
                for (name, bytes) in [("Foto de prueba.png", MediaFixture.photo), ("Video de prueba.mov", MediaFixture.video)] {
                    try Task.checkCancellation()
                    let document = try TemporaryDocuments.save(bytes, filename: name)
                    defer { TemporaryDocuments.remove(document) }
                    let file = try MediaLocalFile.stage(document.url)
                    try await self.accept(file, stamp: stamp, store: store)
                }
            } catch {
                if self.isCurrent(stamp, store: store), !(error is CancellationError) { self.error = error.localizedDescription }
            }
        }
    }
    #endif
}
#endif
