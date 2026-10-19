#if os(iOS)
import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import CoreTransferable
import AVFoundation
import AVKit

enum MediaVideoMode: Sendable { case original, web }

struct MediaPreparedVideo: Sendable {
    let file: MediaLocalFile
    let detail: String?
}

/// Runs before the upload UUID is reserved remotely. Retries upload these exact
/// bytes through the existing encrypted queue; the library file is never edited.
enum MediaVideoPreparation {
    static func worthKeeping(original: Int64, candidate: Int64) -> Bool {
        original > 0 && candidate > 0 && Double(candidate) <= Double(original) * 0.95
    }

    static func prepare(_ file: MediaLocalFile, mode: MediaVideoMode) async throws -> MediaPreparedVideo {
        try Task.checkCancellation()
        guard mode == .web, file.mimeType.hasPrefix("video/") else { return MediaPreparedVideo(file: file, detail: nil) }
        do {
            let candidate = try await exportCandidate(file)
            if worthKeeping(original: file.size, candidate: candidate.size) {
                let percent = Int((1 - Double(candidate.size) / Double(file.size)) * 100)
                let before = ByteCountFormatter.string(fromByteCount: file.size, countStyle: .file)
                let after = ByteCountFormatter.string(fromByteCount: candidate.size, countStyle: .file)
                return MediaPreparedVideo(file: candidate, detail: "\(before) → \(after) · \(percent)% menos · MP4 para web")
            }
            candidate.remove()
            return MediaPreparedVideo(file: file, detail: "Original conservado: la conversión no ahorra al menos un 5%.")
        } catch {
            if error is CancellationError || Task.isCancelled { throw CancellationError() }
            return MediaPreparedVideo(file: file, detail: "Original conservado: " + error.localizedDescription)
        }
    }

    static func exportCandidate(_ file: MediaLocalFile) async throws -> MediaLocalFile {
        try Task.checkCancellation()
        let asset = AVURLAsset(url: file.url)
        let videos = try await asset.loadTracks(withMediaType: .video)
        let audio = try await asset.loadTracks(withMediaType: .audio)
        guard videos.count == 1, audio.count <= 1, let video = videos.first else {
            throw APIError.invalid("Este video necesita conservar sus pistas originales.")
        }
        // H.264 SDR cannot preserve HDR/alpha. Never silently flatten those files.
        guard !video.hasMediaCharacteristic(.containsHDRVideo), !video.hasMediaCharacteristic(.containsAlphaChannel) else {
            throw APIError.invalid("Se conserva el HDR o la transparencia del video.")
        }
        guard MediaStorageReview.freeBytes > file.size + 64 * 1024 * 1024 else {
            throw APIError.invalid("No hay espacio suficiente para preparar otra copia.")
        }
        guard let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetHighestQuality),
              session.supportedFileTypes.contains(.mp4) else {
            throw APIError.invalid("El iPhone no puede convertir este formato a MP4.")
        }
        let folder = TemporaryDocuments.root.appendingPathComponent("media-video-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true, attributes: JACFileSecurity.directoryAttributes)
        var retained = false
        defer { if !retained { try? FileManager.default.removeItem(at: folder) } }
        var protectedFolder = folder
        var values = URLResourceValues(); values.isExcludedFromBackup = true
        try protectedFolder.setResourceValues(values)
        let stem = (file.name as NSString).deletingPathExtension
        let name = MediaLocalFile.safeName(stem + ".mp4")
        let url = folder.appendingPathComponent(name)
        session.outputURL = url
        session.outputFileType = .mp4
        session.shouldOptimizeForNetworkUse = true
        session.canPerformMultiplePassesOverSourceMediaData = true
        let operation = MediaVideoExportOperation(session)
        await withTaskCancellationHandler {
            if !Task.isCancelled { await session.export() }
        } onCancel: { operation.cancel() }
        try Task.checkCancellation()
        guard session.status == .completed else {
            throw APIError.invalid("No se pudo completar la conversión; puedes subirlo sin compresión.")
        }
        try FileManager.default.setAttributes(JACFileSecurity.fileAttributes, ofItemAtPath: url.path)
        let output = AVURLAsset(url: url)
        let outputVideos = try await output.loadTracks(withMediaType: .video)
        let outputAudio = try await output.loadTracks(withMediaType: .audio)
        guard outputVideos.count == 1, outputAudio.count == audio.count, let outputVideo = outputVideos.first else {
            throw APIError.invalid("No se pudieron conservar todas las pistas.")
        }
        let descriptions = try await outputVideo.load(.formatDescriptions)
        guard descriptions.allSatisfy({ CMFormatDescriptionGetMediaSubType($0) == kCMVideoCodecType_H264 }), !descriptions.isEmpty else {
            throw APIError.invalid("No se obtuvo un video H.264 compatible con la web.")
        }
        if let track = outputAudio.first {
            let formats = try await track.load(.formatDescriptions)
            guard !formats.isEmpty, formats.allSatisfy({ CMFormatDescriptionGetMediaSubType($0) == kAudioFormatMPEG4AAC }) else {
                throw APIError.invalid("No se obtuvo audio AAC compatible con la web.")
            }
        }
        let inputSize = try await displaySize(video)
        let outputSize = try await displaySize(outputVideo)
        let inputRate = try await video.load(.nominalFrameRate)
        let outputRate = try await outputVideo.load(.nominalFrameRate)
        let duration = try await asset.load(.duration).seconds
        let outputDuration = try await output.load(.duration).seconds
        guard inputSize == outputSize, inputRate > 0, abs(inputRate - outputRate) <= max(0.1, inputRate * 0.01),
              duration.isFinite, duration > 0, outputDuration.isFinite,
              abs(duration - outputDuration) <= max(0.1, 1 / Double(inputRate)) else {
            throw APIError.invalid("La conversión cambió la resolución, duración o fluidez.")
        }
        try Task.checkCancellation()
        let count = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard count > 0 else { throw APIError.invalid("La copia convertida está vacía.") }
        retained = true
        return MediaLocalFile(id: file.id, url: url, name: name, mimeType: "video/mp4", size: Int64(count))
    }

    private static func displaySize(_ track: AVAssetTrack) async throws -> CGSize {
        let size = try await track.load(.naturalSize)
        let transform = try await track.load(.preferredTransform)
        let rect = CGRect(origin: .zero, size: size).applying(transform)
        return CGSize(width: abs(rect.width).rounded(), height: abs(rect.height).rounded())
    }
}

private final class MediaVideoExportOperation: @unchecked Sendable {
    let session: AVAssetExportSession
    init(_ session: AVAssetExportSession) { self.session = session }
    func cancel() { session.cancelExport() }
}

private struct MediaComposerVideoPreview: View {
    @State private var player: AVPlayer
    init(url: URL) { _player = State(initialValue: AVPlayer(url: url)) }
    var body: some View {
        VideoPlayer(player: player).onDisappear { player.pause() }
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
                        Toggle("Optimizar videos para web", isOn: $draft.optimizeVideos)
                            .disabled(draft.importing || draft.creating || !draft.files.isEmpty)
                            .accessibilityIdentifier("media.video.optimize")
                        Text("Elige antes de agregar archivos. MP4 de alta calidad, sin fijar un tamaño máximo ni bajar la resolución. Tu original queda intacto. La reducción depende del video; HDR y formatos especiales se conservan originales.")
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
                            .accessibilityIdentifier("media.composer.file." + file.id)
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
    @Published var optimizeVideos = false
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
        // after encoding and the session/permission check have both completed.
        var accepted = false
        defer { if !accepted { source.remove() } }
        preparingMessage = optimizeVideos && source.mimeType.hasPrefix("video/") ? "Optimizando \(source.name)…" : "Preparando archivos…"
        let result = try await MediaVideoPreparation.prepare(source, mode: optimizeVideos ? .web : .original)
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
            for url in urls {
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
            for photo in photos {
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
