import SwiftUI
import QuickLook
import PhotosUI
import UniformTypeIdentifiers
import AVKit
import CoreTransferable
import CryptoKit
import ImageIO
#if os(iOS)
import Photos
#endif
#if os(iOS)
import UIKit
#else
import AppKit
#endif

struct DocumentsSection: View {
    @EnvironmentObject private var store: PayrollStore
    let detail: PeriodDetail
    let user: PayrollUser
    @State private var search = ""
    var body: some View {
        Section("Documentos de la quincena") {
            if !detail.period.isClosed {
                Text("Los documentos estarán disponibles cuando se cierre la quincena.").foregroundStyle(.secondary)
            } else if !user.can("export") {
                Text("Tu cuenta no tiene permiso para descargar documentos.").foregroundStyle(.secondary)
            } else {
                ForEach(DocumentFormat.allCases) { format in
                    ExportButton(periodID: detail.period.id, format: format)
                }
            }
        }
        if detail.period.isClosed && user.can("export") {
            Section("Desprendible individual") {
                TextField("Buscar persona para imprimir", text: $search)
                ForEach(uniqueEmployees, id: \.employeeId) { payment in
                    ExportButton(periodID: detail.period.id, format: .pdf, employeeID: payment.employeeId, title: payment.name)
                }
            }
        }
    }
    private var uniqueEmployees: [PayrollPayment] {
        var seen = Set<String>()
        return detail.calculation.rows.filter { seen.insert($0.employeeId).inserted && (search.isEmpty || $0.name.localizedCaseInsensitiveContains(search)) }.sorted { $0.name < $1.name }
    }
}

struct PaymentDetailView: View {
    let rows: [PayrollPayment]
    let period: PayrollPeriod
    let user: PayrollUser
    var conditions: JSONValue? = nil
    var body: some View {
        List {
            if let first = rows.first {
                Section {
                    Text(first.name).font(.title2.weight(.semibold))
                    LabeledContent("Documento", value: first.document); LabeledContent("Cargo", value: first.role)
                    AmountRow(title: "Neto total de la persona", value: rows.reduce(0) { $0 + $1.net })
                }
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    Section(PayrollFormat.category(row.category)) {
                        AmountRow(title: "Ingresos", value: row.gross); AmountRow(title: "Descuentos", value: row.deductions)
                        AmountRow(title: "Reintegros", value: row.reimbursements); AmountRow(title: "Neto", value: row.net)
                        ForEach(Array(row.items.enumerated()), id: \.offset) { _, item in
                            VStack(alignment: .leading, spacing: 5) {
                                AmountRow(title: item.concept, value: item.amount)
                                Text("\(PayrollFormat.number(item.quantity)) × \(PayrollFormat.money(item.rate)) · \(item.kind)").font(.caption).foregroundStyle(.secondary)
                                if let reference = item.reference { Text(reference).font(.caption).foregroundStyle(.secondary) }
                            }.padding(.vertical, 3)
                        }
                    }
                }
                if let conditions {
                    Section { NavigationLink("Condiciones utilizadas en este corte") { List { EmployeeConditionsSection(record: conditions) }.jacSurface().navigationTitle("Condiciones del corte") } }
                }
                if period.isClosed && user.can("export") {
                    Section { ExportButton(periodID: period.id, format: .pdf, employeeID: first.employeeId, title: "Desprendible PDF") }
                }
            }
        }.jacSurface().navigationTitle("Detalle del pago").jacInlineTitle()
    }
}

struct ExportButton: View {
    @EnvironmentObject private var store: PayrollStore
    let periodID: String
    let format: DocumentFormat
    var employeeID: String? = nil
    var title: String? = nil
    @State private var document: ExportedDocument?
    @State private var pendingDocument: ExportedDocument?
    @State private var downloading = false
    @State private var error: String?

    var body: some View {
        Button {
            downloading = true; error = nil
            Task {
                defer { downloading = false }
                do {
                    let result = try await store.client.download(periodID: periodID, format: format, employeeID: employeeID)
                    pendingDocument = result; document = result
                } catch { self.error = error.localizedDescription; store.report(error) }
            }
        } label: {
            HStack { Label(title ?? format.title, systemImage: "doc.text"); Spacer(); if downloading { ProgressView() } else { Image(systemName: "arrow.down.circle") } }
        }
        .disabled(downloading)
        .sheet(item: $document, onDismiss: {
            if let pendingDocument { TemporaryDocuments.remove(pendingDocument); self.pendingDocument = nil }
        }) { file in
            NavigationStack {
                DocumentPreview(url: file.url).ignoresSafeArea(edges: .bottom)
                    .jacSurface().navigationTitle(title ?? format.title).jacInlineTitle()
                    .toolbar {
                        ToolbarItem(placement: .jacLeading) { Button("Listo") { document = nil } }
                        #if os(iOS)
                        ToolbarItem(placement: .jacTrailing) {
                            if file.url.pathExtension.lowercased() == "pdf" { Button { JACPlatform.printDocument(file.url) } label: { Image(systemName: "printer") }.accessibilityLabel("Imprimir documento") }
                        }
                        ToolbarItem(placement: .jacTrailing) { ShareLink(item: file.url) { Image(systemName: "square.and.arrow.up") }.accessibilityLabel("Compartir documento") }
                        #endif
                    }
            }
        }
        .alert("No se pudo descargar", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("Aceptar", role: .cancel) { error = nil }
        } message: { Text(error ?? "Intenta de nuevo.") }
    }
}

#if os(iOS)
struct DocumentPreview: UIViewControllerRepresentable {
    let url: URL
    func makeCoordinator() -> Coordinator { Coordinator(url: url) }
    func makeUIViewController(context: Context) -> QLPreviewController {
        let controller = QLPreviewController()
        controller.dataSource = context.coordinator
        return controller
    }
    func updateUIViewController(_ controller: QLPreviewController, context: Context) {}
    final class Coordinator: NSObject, QLPreviewControllerDataSource {
        let url: URL
        init(url: URL) { self.url = url }
        func numberOfPreviewItems(in controller: QLPreviewController) -> Int { 1 }
        func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem { url as NSURL }
    }
}

#endif

// Fotografía shares JAC's session. No Drive token, public link or browser is
// involved in browsing, selecting, uploading or previewing these private files.
struct MediaFolder: Codable, Identifiable, Equatable { let id: String; let name: String }
struct MediaItem: Codable, Identifiable, Equatable {
    let id: String
    let name: String
    let mimeType: String
    let kind: String
    let size: Int64
    let modifiedAt: String
    let thumbnailAvailable: Bool
    var createdAt: String? = nil
    var sizeLabel: String { ByteCountFormatter.string(fromByteCount: size, countStyle: .file) }
}
enum MediaGalleryOrder {
    static func sorted(_ items:[MediaItem]) -> [MediaItem] {
        items.sorted { left,right in
            if (left.kind == "folder") != (right.kind == "folder") {return left.kind == "folder"}
            let first=left.createdAt.flatMap(CalendarClock.instant),second=right.createdAt.flatMap(CalendarClock.instant)
            if first != second {if let first,let second {return first > second};return first != nil}
            let order=left.name.localizedStandardCompare(right.name)
            return order == .orderedSame ? left.id < right.id : order == .orderedAscending
        }
    }
}
enum MediaThumbnail {
    static func jpeg(for file: MediaLocalFile) async -> Data? {
        let image: CGImage?
        if file.mimeType.hasPrefix("video/") {
            let generator = AVAssetImageGenerator(asset: AVURLAsset(url: file.url))
            generator.appliesPreferredTrackTransform = true; generator.maximumSize = CGSize(width: 640, height: 640)
            image = try? await generator.image(at: .zero).image
        } else if let source = CGImageSourceCreateWithURL(file.url as CFURL, nil) {
            image = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: 640, kCGImageSourceCreateThumbnailWithTransform: true, kCGImageSourceShouldCacheImmediately: false] as CFDictionary)
        } else { image = nil }
        guard !Task.isCancelled, let image else { return nil }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.76] as CFDictionary)
        guard CGImageDestinationFinalize(destination), data.length <= 512 * 1024 else { return nil }
        return data as Data
    }
    static func image(_ data:Data) -> JACPlatformImage? {
        guard data.count <= 512*1024,let source=CGImageSourceCreateWithData(data as CFData,nil),let thumbnail=CGImageSourceCreateThumbnailAtIndex(source,0,[kCGImageSourceCreateThumbnailFromImageAlways:true,kCGImageSourceThumbnailMaxPixelSize:360,kCGImageSourceCreateThumbnailWithTransform:true,kCGImageSourceShouldCacheImmediately:false] as CFDictionary) else{return nil}
        #if os(iOS)
        return UIImage(cgImage:thumbnail)
        #else
        return NSImage(cgImage:thumbnail,size:NSSize(width:thumbnail.width,height:thumbnail.height))
        #endif
    }
}
struct MediaFolderRemoved: LocalizedError {var errorDescription:String? {"Esta carpeta se eliminó de Fotografía."}}
struct MediaFolderDeletion: Codable, Identifiable {
    let id:String
    let parentId:String
    let name:String
    let removed:Int
    var complete:Bool?=nil
    var waiting:Bool?=nil
}
struct MediaFeed: Codable {
    let connected: Bool
    let canRead: Bool
    let canUpload: Bool
    let canConnect: Bool
    let root: MediaFolder?
    let folder: MediaFolder?
    let breadcrumbs: [MediaFolder]
    let items: [MediaItem]
    let nextPageToken: String?
    var provider: String? = nil
    var collectionID: String? = nil
    var canDelete: Bool? = nil
    var pendingDeletions: [MediaFolderDeletion]? = nil
    var deletedFolders: [String]? = nil
}
struct MediaUploadState: Decodable {
    let id: String
    let offset: Int64
    let chunkSize: Int
    let complete: Bool
    let uploadURL: URL?
    var provider: String? = nil
    var fileId: String? = nil
    func validate(for file: MediaLocalFile) throws {
        guard id == file.id, offset >= 0, offset <= file.size, chunkSize > 0, chunkSize <= 8 * 1024 * 1024, (chunkSize <= 1024 * 1024 || complete || uploadURL != nil),
              !complete || offset == file.size else { throw APIError.invalid("El estado de la subida no es válido. Vuelve a intentarlo.") }
    }
}
enum MediaImageQuality: Int, CaseIterable, Sendable, Identifiable {
    case compact=2_000_000, balanced=4_000_000, detailed=6_000_000, original=0
    static let preferenceKey="jac.media.image-quality.v1"
    var id:Int {rawValue}
    var label:String {self == .original ? "Sin compresión" : "Hasta \(rawValue/1_000_000) MB"}
    static var current:Self {guard UserDefaults.standard.object(forKey:preferenceKey) != nil else{return .compact};return Self(rawValue:UserDefaults.standard.integer(forKey:preferenceKey)) ?? .compact}
}
struct MediaImageQualitySettings: View {
    @AppStorage(MediaImageQuality.preferenceKey) private var limit=MediaImageQuality.compact.rawValue
    var body: some View {
        Form {
            Section("Imágenes de Fotografía") {
                ForEach(MediaImageQuality.allCases) {quality in Button {limit=quality.rawValue} label:{HStack {Text(quality.label).foregroundStyle(JACTheme.ink);Spacer();if limit==quality.rawValue {Image(systemName:"checkmark").foregroundStyle(JACTheme.action)}}.padding(.vertical,8).contentShape(Rectangle())}.buttonStyle(.plain).accessibilityIdentifier("media.quality.option."+String(quality.rawValue)).accessibilityValue(limit==quality.rawValue ? "Seleccionado" : "")}
                Text("Se usará en las próximas selecciones de este dispositivo. Los videos siempre se suben completos.").font(.footnote).foregroundStyle(.secondary)
            }
            Section {
                Text("Las imágenes que ya pesan menos se conservan. Al reducirlas se guardan como JPG; el archivo de origen queda intacto. Sin compresión conserva todos los bytes. Las miniaturas se generan por separado.").font(.footnote).foregroundStyle(.secondary)
            }
        }.formStyle(.grouped).navigationTitle("Calidad de las imágenes").jacInlineTitle().jacSurface()
    }
}
enum MediaJPEGOptimization {
    static let maximumBytes = 2_000_000
    static func prepare(_ url: URL, maximumBytes: Int = 2_000_000) throws -> Int64 {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary) else { throw APIError.invalid("No pudimos abrir este JPG para optimizarlo.") }
        guard CGImageSourceGetCount(source)==1 else{throw APIError.invalid("Para conservar esta imagen animada o de varias páginas, elige Sin compresión.")}
        let properties=CGImageSourceCopyPropertiesAtIndex(source,0,nil) as? [CFString:Any]
        var edge=min(8192,max(properties?[kCGImagePropertyPixelWidth] as? Int ?? 4096,properties?[kCGImagePropertyPixelHeight] as? Int ?? 4096))
        for _ in 0..<6 {
            try Task.checkCancellation()
            guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: edge, kCGImageSourceCreateThumbnailWithTransform: true, kCGImageSourceShouldCacheImmediately: false] as CFDictionary) else { throw APIError.invalid("No pudimos preparar este JPG.") }
            func encoded(_ quality: Double) throws -> Data {
                let output = NSMutableData()
                guard let destination = CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil) else { throw APIError.invalid("No pudimos optimizar el JPG.") }
                CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
                guard CGImageDestinationFinalize(destination) else { throw APIError.invalid("No pudimos optimizar el JPG.") }
                return output as Data
            }
            var accepted: Data?; let best = try encoded(0.92)
            if best.count <= maximumBytes { accepted = best }
            else {
                var low = 0.48, high = 0.92
                for attempt in 0..<6 {
                    try Task.checkCancellation(); let quality = attempt == 0 ? low : (low + high) / 2, data = try encoded(quality)
                    if data.count <= maximumBytes { accepted = data; low = quality }
                    else { high = quality; if attempt == 0 { break } }
                }
            }
            if let accepted {
                try Task.checkCancellation()
                try accepted.write(to: url, options: JACFileSecurity.writeOptions)
                try FileManager.default.setAttributes(JACFileSecurity.fileAttributes, ofItemAtPath: url.path)
                return Int64(accepted.count)
            }
            edge = edge * 3 / 4
        }
        throw APIError.invalid("No pudimos reducir esta imagen al tamaño elegido. Usa otro nivel o Sin compresión.")
    }
}
struct MediaLocalFile: Identifiable, Sendable {
    static let maximumSize: Int64 = 20 * 1024 * 1024 * 1024
    let id: String
    let url: URL
    let name: String
    let mimeType: String
    let size: Int64
    var imageLimit: Int64 = 0
    static func safeName(_ value: String) -> String {
        let name = (value as NSString).lastPathComponent.replacingOccurrences(of: "\u{0}", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty || name == "." || name == ".." ? "Archivo" : String(name.prefix(220))
    }
    static func mime(_ url: URL) -> String? {
        ["jpg":"image/jpeg", "jpeg":"image/jpeg", "png":"image/png", "gif":"image/gif", "webp":"image/webp", "heic":"image/heic", "heif":"image/heif", "tif":"image/tiff", "tiff":"image/tiff", "mp4":"video/mp4", "mov":"video/quicktime", "webm":"video/webm", "m4v":"video/x-m4v"][url.pathExtension.lowercased()]
    }
    static func stage(_ source: URL, quality: MediaImageQuality = .current) throws -> MediaLocalFile {
        guard source.isFileURL, var mimeType = mime(source) else { throw APIError.invalid("Elige fotos JPG, PNG, GIF, WebP, HEIC, HEIF o TIFF; o videos MP4, MOV, WebM o M4V.") }
        let access = source.startAccessingSecurityScopedResource(); defer { if access { source.stopAccessingSecurityScopedResource() } }
        let values = try source.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true, let count = values.fileSize, count > 0, Int64(count) <= maximumSize else { throw APIError.invalid("El archivo debe contener una foto o video y pesar como máximo 20 GB.") }
        guard MediaStorageReview.freeBytes > Int64(count) + 64 * 1024 * 1024 else { throw APIError.invalid("No hay espacio suficiente para preparar este archivo. Libera espacio e inténtalo de nuevo.") }
        let id = UUID().uuidString.lowercased();var name = safeName(source.lastPathComponent)
        let folder = TemporaryDocuments.root.appendingPathComponent("media-upload-" + id, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true, attributes: JACFileSecurity.directoryAttributes)
        try FileManager.default.setAttributes(JACFileSecurity.directoryAttributes, ofItemAtPath: TemporaryDocuments.root.path)
        var destination = folder.appendingPathComponent(name)
        do {
            guard FileManager.default.createFile(atPath: destination.path, contents: nil, attributes: JACFileSecurity.fileAttributes) else { throw APIError.message("No se pudo preparar el archivo para subirlo.") }
            let input = try FileHandle(forReadingFrom: source); defer { try? input.close() }
            let output = try FileHandle(forWritingTo: destination); defer { try? output.close() }
            var written: Int64 = 0
            while let chunk = try input.read(upToCount: 1024 * 1024), !chunk.isEmpty {
                try Task.checkCancellation(); written += Int64(chunk.count)
                guard written <= Int64(count) else { throw APIError.invalid("El archivo cambió mientras se leía. Vuelve a seleccionarlo.") }
                try output.write(contentsOf: chunk)
            }
            guard written == Int64(count) else { throw APIError.invalid("El archivo cambió mientras se leía. Vuelve a seleccionarlo.") }
            try output.close()
            let imageLimit=mimeType.hasPrefix("image/") ? quality.rawValue : 0
            if imageLimit>0,written>imageLimit {
                written=try MediaJPEGOptimization.prepare(destination,maximumBytes:imageLimit)
                if mimeType != "image/jpeg" {let renamed=destination.deletingPathExtension().appendingPathExtension("jpg");try FileManager.default.moveItem(at:destination,to:renamed);destination=renamed;name=renamed.lastPathComponent;mimeType="image/jpeg"}
            }
            return MediaLocalFile(id: id, url: destination, name: name, mimeType: mimeType, size: written, imageLimit:Int64(imageLimit))
        } catch { try? FileManager.default.removeItem(at: folder); throw error }
    }
    func remove() { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
}
private struct MediaLibraryFile: Transferable {
    let staged: MediaLocalFile
    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(importedContentType: .image) { received in MediaLibraryFile(staged: try MediaLocalFile.stage(received.file)) }
        FileRepresentation(importedContentType: .movie) { received in MediaLibraryFile(staged: try MediaLocalFile.stage(received.file)) }
    }
}

struct MediaGalleryView: View {
    let user: PayrollUser
    @EnvironmentObject private var store: PayrollStore
    @Environment(\.scenePhase) private var phase
    @StateObject private var folderTransfer = MediaFolderTransfer()
    @State private var transferReview: MediaTransferReview?
    @State private var preparingTransfer = false
    @State private var feed: MediaFeed?
    @State private var items: [MediaItem] = []
    @State private var folderID = ""
    @State private var loadedPages = 1
    @State private var loading = false
    @State private var loadingFolder: String?
    @State private var mediaIsOffline = false
    @State private var choosingDestination = false
    @State private var imageQualitySettings = false
    @State private var deletingFolder:MediaFolder?
    @State private var deletionConfirmed=false
    @State private var deletionConfirmation=false
    @State private var deleting=false
    @State private var deletionError:String?
    @State private var deletionTask:Task<Void,Never>?
    @State private var uploadDestination: MediaFolder?
    @State private var pickingFiles = false
    @State private var selectedPhotos: [PhotosPickerItem] = []
    @State private var queue: [MediaLocalFile] = []
    @State private var completed: Set<String> = []
    @State private var progress: [String: Double] = [:]
    @State private var uploadErrors: [String: String] = [:]
    @State private var uploadNotice: String?
    @State private var importing = false
    @State private var importTask: Task<Void, Never>?
    @State private var uploading = false
    @State private var uploadTask: Task<Void, Never>?
    @State private var error: String?
    @State private var generation = UUID()
    @State private var thumbnailEpoch = UUID()
    @State private var preview: MediaPreview?
    @State private var previewDocument: ExportedDocument?
    @State private var openingTask: Task<Void, Never>?
    @State private var opening: String?
    private var writable: Bool { user.canUploadMedia && feed?.canUpload == true && feed?.connected == true && !store.isOffline }
    private var parentID: String { feed?.folder?.id ?? feed?.root?.id ?? "" }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                #if os(iOS)
                VStack(alignment:.leading,spacing:12) {
                    Text(feed?.folder?.id == feed?.root?.id ? "Cada show, en imágenes." : feed?.folder?.name ?? "Fotos y videos de JAC").font(.system(.title2,design:.rounded,weight:.bold)).foregroundStyle(JACTheme.ink).fixedSize(horizontal:false,vertical:true).frame(maxWidth:.infinity,alignment:.leading).accessibilityIdentifier("media.heading")
                    HStack(alignment:.top,spacing:16) {
                        Text("Tu archivo de fotos y videos, organizado por día.").font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true).frame(maxWidth:.infinity,alignment:.leading)
                        if writable {Button {beginUpload()} label:{Label("Subir",systemImage:"plus")}.buttonStyle(.borderedProminent).fixedSize().accessibilityIdentifier("media.add")}
                    }
                }
                #else
                HStack(alignment:.top,spacing:16) {
                    VStack(alignment:.leading,spacing:6) {
                        Text(feed?.folder?.id == feed?.root?.id ? "Cada show, en imágenes." : feed?.folder?.name ?? "Fotos y videos de JAC").font(.system(.title2,design:.rounded,weight:.bold)).foregroundStyle(JACTheme.ink)
                        Text("Tu archivo de fotos y videos, organizado por día.").font(.subheadline).foregroundStyle(.secondary)
                    }
                    Spacer(minLength:0)
                    if writable {Button {beginUpload()} label:{Label("Subir",systemImage:"plus")}.buttonStyle(.borderedProminent).accessibilityIdentifier("media.add")}
                }
                #endif
                if let error { InlineError(message: error) }
                if mediaIsOffline { Label("Sin conexión · Puedes consultar los archivos descargados.", systemImage: "wifi.slash").font(.footnote).foregroundStyle(.secondary).accessibilityIdentifier("media.offline.status") }
                if loading && feed == nil { ProgressView("Cargando carpetas…").frame(maxWidth: .infinity) }
                if let feed {
                    if !feed.connected {
                        ContentUnavailableView("Preparando el archivo de Fotografía", systemImage: "externaldrive.badge.questionmark", description: Text("El archivo privado de JAC se administra en Configuración general → Servicios conectados."))
                    } else if !feed.canRead || !user.canReadMedia {
                        ContentUnavailableView("Sin acceso a Fotografía", systemImage: "lock", description: Text("Tu cuenta no tiene acceso a estas fotos y videos."))
                    } else {
                        breadcrumbs(feed)
                        transferStatus
                        if user.canDeleteMedia,let pending=feed.pendingDeletions,!pending.isEmpty {
                            VStack(alignment:.leading,spacing:12) {ForEach(pending) {job in HStack {Text("Eliminación pendiente: "+job.name).font(.footnote);Spacer();Button("Continuar eliminación") {deletingFolder=MediaFolder(id:job.id,name:job.name);deletionConfirmed=true;beginFolderDeletion()}.disabled(deleting).accessibilityIdentifier("media.delete.resume."+job.id)}}}.padding(14).background(.orange.opacity(0.08),in:RoundedRectangle(cornerRadius:14))
                        }
                        if writable && uploadDestination?.id == parentID { uploadActions }
                        if importing { HStack { ProgressView("Preparando archivos…"); Spacer(); Button("Cancelar preparación") { importTask?.cancel() } } }
                        if let uploadNotice { Label(uploadNotice, systemImage: "checkmark.circle").font(.footnote).foregroundStyle(.secondary).accessibilityIdentifier("media.upload.status") }
                        if !queue.isEmpty { pendingUploads }
                        if items.isEmpty && !loading {
                            ContentUnavailableView("Esta carpeta está vacía", systemImage: "photo.on.rectangle", description: Text(writable ? "Crea una carpeta para cada show o día y agrega sus fotos y videos." : "Aquí aparecerán las fotos y videos que suba el fotógrafo."))
                        }
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 160, maximum: 280), spacing: 14)], spacing: 14) {
                            ForEach(items) { item in
                                VStack(alignment:.leading,spacing:0) {
                                    Button { open(item) } label: { MediaTile(item: item, client: store.client, offline: store.isOffline, opening: opening == item.id, epoch:thumbnailEpoch, denied:thumbnailDenied) }
                                        .buttonStyle(.plain).disabled(uploading || opening != nil).accessibilityIdentifier("media.item." + item.id)
                                    if item.kind == "folder" {
                                        HStack {Text("Carpeta del equipo").font(.caption).foregroundStyle(.secondary);Spacer(minLength:6)
                                            Menu {folderCommands(MediaFolder(id:item.id,name:item.name))} label:{Image(systemName:"ellipsis.circle").font(.title3).padding(4)}.buttonStyle(.plain).accessibilityLabel("Opciones de "+item.name).accessibilityIdentifier("media.options."+item.id)
                                        }.padding(.horizontal,12).padding(.bottom,10)
                                    }
                                }.background(JACTheme.card,in:RoundedRectangle(cornerRadius:18))
                                    .contextMenu {if item.kind == "folder" {folderCommands(MediaFolder(id:item.id,name:item.name))}}
                            }
                        }
                        if !(feed.nextPageToken ?? "").isEmpty {
                            Button("Cargar más") { loadedPages += 1; Task { await reload() } }.frame(maxWidth: .infinity).disabled(loading || uploading).accessibilityIdentifier("media.more")
                        }
                    }
                }
            }.padding(18).frame(maxWidth: 1160, alignment: .leading).frame(maxWidth: .infinity)
        }.jacSurface().navigationTitle("Fotografía").jacInlineTitle()
            .refreshable { await reload() }
            .toolbar {
                ToolbarItem {Button {Task {await reload()}} label:{Image(systemName:"arrow.clockwise")}.accessibilityLabel("Actualizar fotografías").accessibilityIdentifier("media.refresh").disabled(loading || uploading)}
                ToolbarItem {if let folder=feed?.folder,feed?.canRead == true {Menu {folderCommands(folder);if user.canUploadMedia {Button("Calidad de las imágenes",systemImage:"slider.horizontal.3"){imageQualitySettings=true}.accessibilityIdentifier("media.quality")}} label:{Image(systemName:"ellipsis.circle")}.accessibilityLabel("Opciones de esta carpeta").accessibilityIdentifier("media.current.options")}}
            }
            .task(id: folderID) {
                await reload()
                while !Task.isCancelled {
                    do { try await Task.sleep(for: .seconds(30)) } catch { return }
                    if phase == .active && !uploading && preview == nil && !choosingDestination && opening == nil { await reload() }
                }
            }
            .onChange(of: phase) { _, value in if value == .active && !uploading { Task { await reload() } } }
            .onChange(of: store.isOffline) { old, new in if old && !new && mediaIsOffline { Task { await reload() } } }
            .onChange(of: selectedPhotos) { _, selected in guard !selected.isEmpty else { return }; importTask?.cancel(); importTask = Task { await readPhotos(selected) } }
            .alert("Eliminar carpeta",isPresented:$deletionConfirmation) {
                Button("Cancelar",role:.cancel){deletingFolder=nil}
                Button("Eliminar",role:.destructive){deletionConfirmed=true;beginFolderDeletion()}.accessibilityIdentifier("media.delete.confirm")
            } message:{Text("¿Estás seguro de eliminar esta carpeta y todo su contenido?")}
            .overlay(alignment:.bottom) {if deleting {HStack(spacing:12){ProgressView();Text("Eliminando carpeta…").font(.subheadline)}.padding(18).background(.regularMaterial,in:RoundedRectangle(cornerRadius:16)).padding(20).accessibilityIdentifier("media.delete.progress")}else if let deletionError {HStack {Text(deletionError).font(.footnote);Button("Reintentar"){beginFolderDeletion()};Button("Cerrar"){self.deletionError=nil;deletingFolder=nil;deletionConfirmed=false}}.padding(16).background(.regularMaterial,in:RoundedRectangle(cornerRadius:16)).padding(20)}}
            .sheet(isPresented:$imageQualitySettings) {NavigationStack {MediaImageQualitySettings().toolbar {ToolbarItem(placement:.cancellationAction){Button("Listo"){imageQualitySettings=false}.accessibilityIdentifier("media.quality.close")}}}}
            .sheet(isPresented:$choosingDestination) {if let location=feed?.folder ?? feed?.root {MediaUploadDestinationPicker(root:location,isRoot:location.id == feed?.root?.id) {selectDestination($0)}}}
            .sheet(item: $transferReview) { review in MediaTransferReviewSheet(review: review) { folderTransfer.start(client: store.client, plan: review.plan, photos: review.photos, writer: photosWriter) } }
            .sheet(item: $preview, onDismiss: clearPreview) { document in MediaPreviewSheet(preview: document, photos: items.filter { $0.kind == "image" }, feed: feed, client: store.client, denied: thumbnailDenied) }
            .fileImporter(isPresented: $pickingFiles, allowedContentTypes: [.image, .movie, .video], allowsMultipleSelection: true) { result in
                switch result { case .success(let urls): importTask?.cancel(); importTask = Task { await readFiles(urls) }; case .failure(let failure): if (failure as? CocoaError)?.code != .userCancelled { error = failure.localizedDescription } }
            }
            .jacFileDrop(enabled: writable && !uploading && !importing) { urls in importTask?.cancel(); importTask = Task { await readFiles(urls);if uploadDestination == nil && !queue.isEmpty {if parentID == feed?.root?.id {choosingDestination=true}else{uploadDestination=feed?.folder}} } }
            .jacRefreshCommand { Task { await reload() } }
            .onDisappear { deletionTask?.cancel();uploadTask?.cancel(); importTask?.cancel(); folderTransfer.cancel(); openingTask?.cancel(); generation = UUID(); loadingFolder=nil;loading=false; queue.forEach { $0.remove() }; clearPreview() }
    }
    private var photosWriter: any MediaPhotosWriting {
        #if DEBUG
        if store.client.baseURL.host?.hasSuffix(".invalid") == true { return FixtureMediaPhotosWriter() }
        #endif
        return DeviceMediaPhotosWriter()
    }
    private var transferStatus: some View {
        VStack(alignment:.leading,spacing:12) {
            if preparingTransfer {ProgressView("Revisando todos los archivos de la carpeta…")}
            if folderTransfer.running {
                ProgressView(value:Double(folderTransfer.completed),total:Double(max(1,folderTransfer.total)))
                HStack {Text("\(folderTransfer.completed) de \(folderTransfer.total) archivos completados").font(.footnote);Spacer();Button("Detener") {folderTransfer.cancel()}}
            }
            if let message=folderTransfer.message {Text(message).font(.footnote).foregroundStyle(.secondary).accessibilityIdentifier("media.transfer.status")}
            if !folderTransfer.failures.isEmpty {DisclosureGroup("\(folderTransfer.failures.count) archivos con problemas") {ForEach(Array(folderTransfer.failures.enumerated()),id:\.offset) {_,message in Text(message).font(.footnote).foregroundStyle(.red).frame(maxWidth:.infinity,alignment:.leading)}}}
        }
    }
    @ViewBuilder private func folderCommands(_ folder:MediaFolder) -> some View {
        Button {Task {await prepareTransfer(folder:folder.id,photos:false)}} label:{Label("Disponible sin conexión",systemImage:"arrow.down.circle")}.accessibilityIdentifier("media.offline")
            .disabled(preparingTransfer || folderTransfer.running || uploading || opening != nil)
        #if os(iOS)
        Button {Task {await prepareTransfer(folder:folder.id,photos:true)}} label:{Label("Guardar carpeta en Fotos",systemImage:"square.and.arrow.down")}.accessibilityIdentifier("media.savePhotos")
            .disabled(preparingTransfer || folderTransfer.running || uploading || opening != nil)
        #endif
        if user.canDeleteMedia,feed?.canDelete == true,folder.id != feed?.root?.id {
            Divider()
            Button(role:.destructive) {deletionError=nil;deletionConfirmed=false;deletingFolder=folder;deletionConfirmation=true} label:{Label("Eliminar carpeta",systemImage:"trash")}.accessibilityIdentifier("media.delete.folder")
                .disabled(deleting || uploading || importing || preparingTransfer || folderTransfer.running || queue.contains(where:{!completed.contains($0.id)}) || store.isOffline)
        }
    }
    private func beginFolderDeletion() {
        guard let target=deletingFolder,!deleting,user.canDeleteMedia,!store.isOffline else{return}
        deletionTask?.cancel();deleting=true;deletionError=nil;generation=UUID();openingTask?.cancel();clearPreview();folderTransfer.cancel()
        deletionTask=Task {
            defer {deleting=false;deletionTask=nil}
            do {
                var result:MediaFolderDeletion
                repeat {result=try await store.client.deleteMediaFolderStep(target);try Task.checkCancellation();if result.complete != true {try await Task.sleep(for:.milliseconds(result.waiting == true ? 1000:100))}}while result.complete != true
                deletingFolder=nil;deletionConfirmed=false;uploadNotice="Carpeta eliminada.";items.removeAll{$0.id==target.id}
                if parentID==target.id {navigate(to:result.parentId==feed?.root?.id ? "" : result.parentId)}else{await reload()}
            }catch{if let message=store.reportReadFailure(error){deletionError=message};if !Task.isCancelled {await reload()}}
        }
    }
    private func prepareTransfer(folder:String,photos:Bool) async {
        guard !preparingTransfer,!folderTransfer.running else {return};preparingTransfer=true;defer{preparingTransfer=false}
        do {
            let stamp=try store.client.mediaAccessStamp(),plan=try await store.client.mediaDownloadPlan(folder:folder)
            guard !Task.isCancelled,stamp == (try store.client.mediaAccessStamp()) else {throw CancellationError()}
            let scope=try store.client.mediaScope(),cache=store.client.mediaOffline
            let pending=photos ? plan.files:plan.files.filter{item in scope.map{!cache.hasFile(item,scope:$0)} ?? true}
            transferReview=MediaTransferReview(plan:plan,photos:photos,requiredBytes:MediaStorageReview.required(pending))
        } catch {if let message=store.reportReadFailure(error){self.error=message}}
    }
    private func beginUpload() {
        guard writable,!uploading else{return}
        if let target=uploadDestination,target.id == parentID {return}
        choosingDestination=true
    }
    private func selectDestination(_ folder:MediaFolder) {
        guard uploadDestination == nil || queue.isEmpty else{return}
        uploadDestination=folder;choosingDestination=false;generation=UUID();folderID=folder.id;loadedPages=1;feed=nil;items=[]
        Task {await reload()}
    }
    @ViewBuilder private func breadcrumbs(_ feed: MediaFeed) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 9) {
                ForEach(feed.breadcrumbs) { crumb in
                    Button(crumb.id == feed.root?.id ? "Fotografía" : crumb.name) { navigate(to: crumb.id) }.buttonStyle(.bordered).disabled(uploading || queue.contains(where: { !completed.contains($0.id) }) || crumb.id == feed.folder?.id).accessibilityIdentifier("media.folder." + crumb.id)
                    if crumb.id != feed.breadcrumbs.last?.id { Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary) }
                }
            }
        }
    }
    private var uploadActions: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {Label(uploadDestination?.name ?? "Carpeta elegida",systemImage:"folder.fill").font(.subheadline.weight(.semibold));Spacer();if queue.isEmpty {Button("Listo") {uploadDestination=nil}}}
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) { libraryButton; fileButton }
                VStack(alignment: .leading, spacing: 10) { libraryButton; fileButton }
            }
            #if DEBUG
            if store.client.baseURL.host?.hasSuffix(".invalid") == true { Button("Adjuntar foto ficticia") { Task {
                do {
                    for (name, bytes) in [("Foto de prueba.png", MediaFixture.photo), ("Video de prueba.mov", MediaFixture.video)] {
                        let document = try TemporaryDocuments.save(bytes, filename: name); defer { TemporaryDocuments.remove(document) }; queue.append(try MediaLocalFile.stage(document.url))
                    }
                } catch { self.error = error.localizedDescription }
            } }.accessibilityIdentifier("media.fixture") }
            #endif
            Text("Las carpetas y archivos se guardan en la carpeta compartida de JAC. Los videos se suben por partes para poder reintentar sin duplicarlos.").font(.footnote).foregroundStyle(.secondary)
        }.disabled(uploading || importing || parentID.isEmpty)
    }

    private var libraryButton: some View { PhotosPicker(selection: $selectedPhotos, matching: .any(of: [.images, .videos]), preferredItemEncoding: .current) { Label("Fotos y videos", systemImage: "photo.on.rectangle") }.buttonStyle(.bordered).accessibilityIdentifier("media.library") }
    private var fileButton: some View { Button { pickingFiles = true } label: { Label("Archivos", systemImage: "folder") }.buttonStyle(.bordered).accessibilityIdentifier("media.files") }
    private var pendingUploads: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Archivos seleccionados").font(.headline)
            ForEach(queue) { file in
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 10) {
                        Image(systemName: completed.contains(file.id) ? "checkmark.circle.fill" : file.mimeType.hasPrefix("video/") ? "video" : "photo").foregroundStyle(completed.contains(file.id) ? .green : JACTheme.action)
                        Text(file.name).font(.subheadline).lineLimit(2); Spacer(minLength: 8)
                        if !uploading { Button { file.remove(); queue.removeAll { $0.id == file.id }; completed.remove(file.id) } label: { Image(systemName: "xmark.circle") }.buttonStyle(.plain).accessibilityLabel("Quitar " + file.name) }
                    }
                    if uploading || progress[file.id] != nil { ProgressView(value: progress[file.id] ?? 0).tint(JACTheme.action) }
                    if let failure = uploadErrors[file.id] { Text(failure).font(.footnote).foregroundStyle(.red) }
                }
            }
            if uploading {
                Button("Detener subida") { uploadTask?.cancel() }.buttonStyle(.bordered)
            } else if uploadDestination == nil {
                Button("Elegir carpeta de destino") {choosingDestination=true}.buttonStyle(.borderedProminent).accessibilityIdentifier("media.destination.choose")
            } else if queue.contains(where: { !completed.contains($0.id) }) {
                Button { uploadTask = Task { await uploadAll() } } label: { Label(uploadErrors.isEmpty ? "Subir archivos seleccionados" : "Reintentar pendientes", systemImage: "arrow.up.circle.fill").frame(maxWidth: .infinity) }.buttonStyle(JACPrimaryButtonStyle()).disabled(!writable || importing).accessibilityIdentifier("media.upload")
            }
        }.padding(18).background(JACTheme.card, in: RoundedRectangle(cornerRadius: 18))
    }
    private func reload() async {
        guard !uploading, loadingFolder != folderID else { return }
        let expected = UUID(), requestedFolder = folderID; generation = expected
        loading = true; loadingFolder=requestedFolder
        defer { if generation == expected { loading = false;loadingFolder=nil } }
        // A restored copy is available immediately; it does not prove the
        // network is unavailable. Revalidate independently of workspace startup.
        if feed == nil, let saved = store.client.cachedMedia(folder: requestedFolder) {
            feed=saved;items=MediaGalleryOrder.sorted(saved.items)
        }
        do {
            var result = try await store.client.media(folder: requestedFolder, forceNetwork: true), all = result.items
            var cursor = result.nextPageToken ?? "", visited = Set<String>()
            for _ in 1..<max(1, loadedPages) {
                guard !cursor.isEmpty, visited.insert(cursor).inserted else { break }
                result = try await store.client.media(folder: requestedFolder, pageToken: cursor, forceNetwork: true); all += result.items; cursor = result.nextPageToken ?? ""
            }
            guard expected == generation, requestedFolder == folderID, !Task.isCancelled else { return }
            feed = result; var seen = Set<String>(); items = MediaGalleryOrder.sorted(all.filter { seen.insert($0.id).inserted });thumbnailEpoch=UUID(); error = nil;mediaIsOffline=false
            if !result.canRead || !result.connected { items = []; clearPreview(); queue.forEach { $0.remove() }; queue = [] }
            // A live gallery does not grant unrelated financial permissions.
            // Join session revalidation before restoring write controls.
            if store.isOffline { try? await store.refreshAutomatically() }
        } catch {
            guard expected == generation, requestedFolder == folderID, !Task.isCancelled else { return }
            if AgendaOfflineCache.isUnavailable(error), let saved = store.client.cachedMedia(folder: requestedFolder) {
                feed=saved;items=MediaGalleryOrder.sorted(saved.items);mediaIsOffline=true;self.error=nil;return
            }
            if let message = store.reportReadFailure(error) { self.error = message }
            if case APIError.forbidden = error { items = []; feed = nil; clearPreview() }
            if error is MediaFolderRemoved {clearPreview();navigate(to:"")}
        }
    }
    private func open(_ item: MediaItem) {
        if item.kind == "folder" { navigate(to: item.id); return }
        guard opening == nil else { return }; opening = item.id
        openingTask = Task {
            defer { opening = nil; openingTask = nil }
            do {
                if item.kind == "video", !store.client.usingOfflineCopy {
                    try await store.client.validateMediaItem(item)
                    try Task.checkCancellation()
                    preview = MediaPreview(item: item, document: nil, stream: try MediaVideoStream(client: store.client, item: item))
                } else {
                    let document = try await store.client.mediaDocument(item); previewDocument = document; preview = MediaPreview(item: item, document: document, stream: nil)
                }
            }
            catch { if let message = store.reportReadFailure(error) { self.error = message } }
        }
    }
    private func navigate(to id: String) {
        guard !queue.contains(where: { !completed.contains($0.id) }) else { error = "Sube o quita los archivos seleccionados antes de cambiar de carpeta."; return }
        queue = []; completed = [];uploadDestination=nil; generation = UUID(); folderID = id; loadedPages = 1; feed = nil; items = []
    }
    private func clearPreview() { preview?.stream?.cancel(); if let document = previewDocument { TemporaryDocuments.remove(document) }; previewDocument = nil; preview = nil }
    private func thumbnailDenied(_ failure:Error) {
        if failure is MediaFolderRemoved {clearPreview();navigate(to:"");return}
        items=[];feed=nil;queue.forEach{$0.remove()};queue=[];uploadDestination=nil;clearPreview();error=store.reportReadFailure(failure)
    }
    private func readFiles(_ urls: [URL]) async {
        guard writable, !uploading, !importing, let stamp = try? store.client.mediaAccessStamp() else { return }; importing = true; defer { importing = false; importTask = nil }
        for url in urls {
            do {
                let worker = Task.detached(priority: .userInitiated) { try MediaLocalFile.stage(url) }
                let file = try await withTaskCancellationHandler { try await worker.value } onCancel: { worker.cancel() }
                guard !Task.isCancelled, stamp == (try? store.client.mediaAccessStamp()), store.overview?.user.canUploadMedia == true else { file.remove(); return }
                queue.append(file)
            }
            catch { self.error = error.localizedDescription }
        }
    }
    private func readPhotos(_ photos: [PhotosPickerItem]) async {
        guard writable, !photos.isEmpty, !uploading, !importing, let stamp = try? store.client.mediaAccessStamp() else { return }; importing = true; defer { importing = false; selectedPhotos = []; importTask = nil }
        for photo in photos {
            do {
                guard let file = try await photo.loadTransferable(type: MediaLibraryFile.self) else { throw APIError.message("No se pudo leer esa foto o video.") }
                guard !Task.isCancelled, stamp == (try? store.client.mediaAccessStamp()), store.overview?.user.canUploadMedia == true else { file.staged.remove(); return }
                queue.append(file.staged)
            } catch { self.error = error.localizedDescription }
        }
    }
    private func uploadAll() async {
        guard writable,!uploading,uploadDestination?.id == parentID else {error="Elige la carpeta del show antes de subir los archivos.";return};uploading = true; error = nil; uploadNotice = nil
        defer {
            if !completed.isEmpty { uploadNotice = "\(completed.count) archivos subidos." }
            queue.removeAll { completed.contains($0.id) }; completed = [];if queue.isEmpty {uploadDestination=nil}
            uploading = false; uploadTask = nil; Task { await reload() }
        }
        let destination = parentID
        for file in queue where !completed.contains(file.id) {
            if Task.isCancelled { return }; uploadErrors[file.id] = nil
            do {
                try await store.client.uploadMedia(file, parentID: destination) { sent, total in progress[file.id] = total > 0 ? Double(sent) / Double(total) : 0 }
                completed.insert(file.id); file.remove()
            } catch {
                if error is CancellationError || (error as? URLError)?.code == .cancelled { return }
                uploadErrors[file.id] = error.localizedDescription; store.report(error)
                if case APIError.unauthorized = error { return }; if case APIError.forbidden = error { return }
            }
        }
    }
}

private struct MediaTile: View {
    let item: MediaItem
    let client: PayrollClient
    let offline: Bool
    let opening: Bool
    let epoch:UUID
    let denied:(Error)->Void
    @State private var image: JACPlatformImage?
    @State private var loadedRevision:String?
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 12).fill(JACTheme.action.opacity(0.08)).overlay {
                    if let image {
                    #if os(iOS)
                    Image(uiImage: image).resizable().scaledToFill()
                    #else
                    Image(nsImage: image).resizable().scaledToFill()
                    #endif
                    }
                }
                if image == nil { Image(systemName: item.kind == "folder" ? "folder.fill" : item.kind == "video" ? "video.fill" : "photo").font(.system(size: 36)).foregroundStyle(JACTheme.action) }
                if item.kind == "video" { Image(systemName: "play.circle.fill").font(.system(size: 36)).symbolRenderingMode(.palette).foregroundStyle(.white, .black.opacity(0.45)) }
                if opening { ProgressView().padding(12).background(.regularMaterial, in: Capsule()) }
            }.frame(height:item.kind == "folder" ? 84:140).frame(maxWidth:.infinity).clipped().clipShape(RoundedRectangle(cornerRadius:12)).accessibilityIdentifier(image == nil ? "media.placeholder."+item.id:"media.thumbnail."+item.id)
            Text(item.name).font(.subheadline.weight(.semibold)).foregroundStyle(JACTheme.ink).lineLimit(2).frame(maxWidth: .infinity, alignment: .leading)
            if item.kind != "folder" {Text((item.kind == "video" ? "Video · ":"Foto · ")+item.sizeLabel).font(.caption).foregroundStyle(.secondary)}
        }.padding(12).background(JACTheme.card, in: RoundedRectangle(cornerRadius: 18)).contentShape(Rectangle())
            .task(id: item.id + item.modifiedAt + epoch.uuidString + (offline ? "offline":"online")) {
                guard item.kind != "folder",!offline,loadedRevision != item.modifiedAt else{return}
                if loadedRevision != nil {image=nil;loadedRevision=nil}
                do {let data=try await client.mediaThumbnail(item);try Task.checkCancellation();if let thumbnail=MediaThumbnail.image(data){image=thumbnail;loadedRevision=item.modifiedAt}}
                catch {if case APIError.unauthorized = error {denied(error)}else if case APIError.forbidden = error {denied(error)}}
            }.onDisappear {image=nil;loadedRevision=nil}
    }
}
private struct MediaUploadDestinationPicker: View {
    let root:MediaFolder
    let isRoot:Bool
    let selected:(MediaFolder)->Void
    @EnvironmentObject private var store:PayrollStore
    @Environment(\.dismiss) private var dismiss
    @State private var folders:[MediaItem]=[]
    @State private var cursor=""
    @State private var search=""
    @State private var loading=false
    @State private var creating=false
    @State private var error:String?
    var body:some View {
        NavigationStack {
            List {
                Section {
                    LabeledContent("Ubicación",value:root.name)
                    Text("Elige el show o día de trabajo antes de seleccionar tus fotos y videos.").font(.subheadline).foregroundStyle(.secondary)
                    Button {selected(root);dismiss()} label:{Label(isRoot ? "Archivo JAC (general)":"Subir en esta carpeta",systemImage:"folder.fill")}.accessibilityIdentifier("media.destination.current")
                    Button {creating=true} label:{Label("Crear carpeta de evento",systemImage:"folder.badge.plus")}.accessibilityIdentifier("media.createFolder").disabled(loading || store.isOffline)
                }
                if let error {Section {InlineError(message:error);Button("Reintentar") {Task{await load()}}}}
                Section("Carpetas existentes") {
                    ForEach(folders.filter{search.isEmpty || $0.name.localizedCaseInsensitiveContains(search)}) {folder in
                        Button {selected(MediaFolder(id:folder.id,name:folder.name));dismiss()} label:{Label(folder.name,systemImage:"folder.fill").frame(maxWidth:.infinity,alignment:.leading).contentShape(Rectangle())}.accessibilityIdentifier("media.destination."+folder.id)
                    }
                    if folders.isEmpty && !loading {Text("Crea una carpeta para el primer show o día de trabajo.").foregroundStyle(.secondary)}
                    if !cursor.isEmpty {Button("Cargar más carpetas") {Task {await load(cursor)}}.disabled(loading).accessibilityIdentifier("media.destination.more")}
                    if loading {ProgressView("Consultando carpetas…")}
                }
            }.jacSurface().navigationTitle("¿Dónde quieres subir?").jacInlineTitle().searchable(text:$search,prompt:"Buscar show o fecha")
                .toolbar {ToolbarItem(placement:.cancellationAction) {Button("Cancelar") {dismiss()}}}
                .task {await load()}
                .sheet(isPresented:$creating) {MediaFolderEditor(parentID:root.id,parentName:root.name) {folder in selected(folder);dismiss()}}
        }
        #if os(macOS)
        .frame(minWidth:560,minHeight:560)
        #endif
    }
    private func load(_ page:String="") async {
        guard !loading else{return};loading=true;defer{loading=false}
        do {
            let feed=try await store.client.media(folder:root.id,pageToken:page);try Task.checkCancellation()
            guard feed.connected,feed.canUpload,store.overview?.user.canUploadMedia == true else {throw APIError.forbidden("Tu cuenta no puede subir archivos en esta carpeta.")}
            var seen=Set<String>();folders=MediaGalleryOrder.sorted((page.isEmpty ? []:folders)+feed.items.filter{$0.kind == "folder"}).filter{seen.insert($0.id).inserted};cursor=feed.nextPageToken ?? "";error=nil
        } catch {if let message=store.reportReadFailure(error){self.error=message}}
    }
}
private struct MediaFolderEditor: View {
    let parentID: String
    var parentName:String=""
    let saved: (MediaFolder) -> Void
    @EnvironmentObject private var store: PayrollStore
    @Environment(\.dismiss) private var dismiss
    @State private var requestID = UUID().uuidString.lowercased()
    @State private var name = ""
    @State private var attempted = false
    @State private var busy = false
    @State private var error: String?
    var body: some View {
        NavigationStack {
            Form {
                Section("Show o día de trabajo") {
                    if !parentName.isEmpty {LabeledContent("Ubicación",value:parentName)}
                    TextField("Nombre del show o lugar", text: $name).accessibilityIdentifier("media.folder.name")
                    Text("Se guardará con este nombre. Las carpetas más recientes aparecen primero.").font(.footnote).foregroundStyle(.secondary)
                }.disabled(busy || attempted)
                if let error { Section { InlineError(message: error) } }
                Section { Button(busy ? "Creando…" : "Crear carpeta") { Task { await save() } }.buttonStyle(JACPrimaryButtonStyle()).disabled(busy || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || store.isOffline).accessibilityIdentifier("media.folder.save") }
            }.jacSurface().navigationTitle("Nueva carpeta").jacInlineTitle()
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() }.disabled(busy) } }
        }.interactiveDismissDisabled(busy)
    }
    private func save() async {
        guard !busy else { return }; busy = true; attempted = true; defer { busy = false }
        do { let folder = try await store.client.createMediaFolder(id: requestID, parentID: parentID, name: name, date: BoardingClock.today()); saved(folder); dismiss() }
        catch { if case APIError.invalid = error { attempted = false }; self.error = error.localizedDescription; store.report(error) }
    }
}
private struct MediaPreview: Identifiable { let item: MediaItem; let document: ExportedDocument?; let stream: MediaVideoStream?; var id: String { item.id } }
// One sheet/navigation stack stays alive while the selected document changes.
// Each original is authorized by PayrollClient; only metadata is paged ahead.
@MainActor
final class MediaPhotoViewer: ObservableObject {
    @Published private(set) var items: [MediaItem]
    @Published private(set) var selected: MediaItem
    @Published private(set) var document: ExportedDocument?
    @Published private(set) var token: String
    @Published private(set) var loading = false
    @Published private(set) var error: String?
    private let folderID: String
    private let collectionID: String?
    private let load: (MediaItem) async throws -> ExportedDocument
    private let page: (String) async throws -> MediaFeed
    private let denied: (Error) -> Void
    private var task: Task<Void, Never>?
    private var active = true
    private var ownedDocument = false
    init(selected: MediaItem, document: ExportedDocument?, items: [MediaItem], token: String, folderID: String, collectionID: String?, load: @escaping (MediaItem) async throws -> ExportedDocument, page: @escaping (String) async throws -> MediaFeed, denied: @escaping (Error) -> Void) {
        self.selected=selected;self.document=document;self.items=items.contains(where:{$0.id==selected.id}) ? items : [selected];self.token=token;self.folderID=folderID;self.collectionID=collectionID;self.load=load;self.page=page;self.denied=denied
    }
    var index: Int { items.firstIndex(where:{$0.id==selected.id}) ?? 0 }
    var canPrevious: Bool { !loading && index > 0 }
    var canNext: Bool { !loading && (index+1 < items.count || !token.isEmpty) }
    var counter: String { "\(index+1) de \(items.count)" + (token.isEmpty ? "" : "+") }
    func start(_ direction: Int) { guard !loading else{return};task=Task {await move(direction)} }
    func move(_ direction: Int) async {
        guard active, !loading, direction == -1 || direction == 1 else {return}
        let target=index+direction;guard target >= 0, target < items.count || direction == 1 && !token.isEmpty else{return}
        loading=true;error=nil;defer {if active {loading=false}}
        do {
            var seen=Set<String>()
            while target >= items.count && !token.isEmpty {
                guard seen.insert(token).inserted else {throw APIError.invalid("No pudimos continuar la carpeta. Cierra el visor y actualiza.")}
                let result=try await page(token);try Task.checkCancellation();guard active else{return}
                guard result.connected,result.canRead,result.folder?.id==folderID,result.collectionID==collectionID else {throw APIError.invalid("La carpeta cambió. Cierra el visor y actualiza.")}
                var ids=Set(items.map(\.id));items.append(contentsOf:result.items.filter {$0.kind=="image" && ids.insert($0.id).inserted});token=result.nextPageToken ?? ""
            }
            guard target < items.count else{return}
            let photo=items[target],next=try await load(photo)
            guard active,!Task.isCancelled else{TemporaryDocuments.remove(next);return}
            if ownedDocument,let document {TemporaryDocuments.remove(document)}
            document=next;ownedDocument=true;selected=photo
        } catch {
            guard active,!Task.isCancelled else{return}
            switch error {case is MediaFolderRemoved:stop();denied(error)
            case APIError.unauthorized,APIError.forbidden:stop();denied(error)
            default:if !(error is CancellationError) && (error as? URLError)?.code != .cancelled {self.error=error.localizedDescription}}
        }
    }
    func stop() {active=false;task?.cancel();task=nil;if ownedDocument,let document {TemporaryDocuments.remove(document)};document=nil;ownedDocument=false}
}
private struct MediaPreviewSheet: View {
    let preview: MediaPreview
    @StateObject private var photos: MediaPhotoViewer
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var phase
    @State private var player: AVPlayer?
    init(preview: MediaPreview, photos: [MediaItem], feed: MediaFeed?, client: PayrollClient, denied: @escaping (Error)->Void) {
        self.preview=preview
        _photos=StateObject(wrappedValue:MediaPhotoViewer(selected:preview.item,document:preview.document,items:photos,token:feed?.nextPageToken ?? "",folderID:feed?.folder?.id ?? "",collectionID:feed?.collectionID,load:{try await client.mediaDocument($0)},page:{try await client.media(folder:feed?.folder?.id ?? "",pageToken:$0)},denied:denied))
    }
    var body: some View {
        NavigationStack {
            VStack(spacing:0) {
                Group {
                    if let stream = preview.stream { MediaStreamingPlayer(stream: stream) }
                    else if let document = preview.document, preview.item.kind == "video" { MediaNativePlayer(player: player).frame(maxWidth: .infinity, minHeight: 420, maxHeight: .infinity).accessibilityElement(children: .contain).accessibilityIdentifier("media.video").onAppear { player = AVPlayer(url: document.url); player?.play() }.onDisappear { player?.pause(); player = nil } }
                    else if let document = photos.document { DocumentPreview(url: document.url).id(document.url).accessibilityIdentifier("media.photo.document") }
                }.frame(maxWidth:.infinity,maxHeight:.infinity)
                if preview.item.kind == "image" {
                    Divider()
                    HStack(spacing:18) {
                        Button {photos.start(-1)} label:{Image(systemName:"chevron.left").frame(width:44,height:44).contentShape(Rectangle())}.disabled(!photos.canPrevious).keyboardShortcut(.leftArrow,modifiers:[]).accessibilityLabel("Foto anterior").accessibilityIdentifier("media.preview.previous")
                        Spacer(minLength:0)
                        VStack(spacing:3) {
                            Text(photos.selected.name).font(.caption).lineLimit(1).accessibilityIdentifier("media.preview.name")
                            if photos.loading {ProgressView().controlSize(.small)} else {Text(photos.counter).font(.caption2).foregroundStyle(.secondary).monospacedDigit().accessibilityIdentifier("media.preview.counter")}
                        }
                        Spacer(minLength:0)
                        Button {photos.start(1)} label:{Image(systemName:"chevron.right").frame(width:44,height:44).contentShape(Rectangle())}.disabled(!photos.canNext).keyboardShortcut(.rightArrow,modifiers:[]).accessibilityLabel("Foto siguiente").accessibilityIdentifier("media.preview.next")
                    }.buttonStyle(.plain).padding(.horizontal,16).padding(.vertical,6).background(.bar)
                    if let error=photos.error {Text(error).font(.footnote).foregroundStyle(.red).padding(12)}
                }
            }.simultaneousGesture(DragGesture(minimumDistance:60).onEnded {value in
                guard preview.item.kind=="image",abs(value.translation.width)>abs(value.translation.height)*1.5 else{return}
                photos.start(value.translation.width<0 ? 1 : -1)
            })
            .privacySensitive().navigationTitle(preview.item.kind=="image" ? photos.selected.name : preview.item.name).jacInlineTitle()
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Listo") { dismiss() }.accessibilityIdentifier("media.preview.close") } }
        }.onChange(of: phase) { _, value in if value != .active { player?.pause() } }
        .onDisappear {photos.stop();player?.pause()}
        #if os(macOS)
        .frame(minWidth: 720, minHeight: 520)
        .onMoveCommand {direction in if preview.item.kind=="image" {if direction == .left {photos.start(-1)};if direction == .right {photos.start(1)}}}
        #endif
    }
}

// AVFoundation asks for only the byte ranges it needs. JAC authorizes each
// range; the Google credential never enters AVPlayer. The small block cache is
// memory-only and tied to this asset, revision and Keychain session generation.
@MainActor
final class MediaVideoStream: NSObject, ObservableObject, AVAssetResourceLoaderDelegate {
    let asset: AVURLAsset
    private let client: PayrollClient
    private let item: MediaItem
    private let stamp: String
    private var active = true
    private var requests: [ObjectIdentifier: Task<Void, Never>] = [:]
    private var blocks: [Int64: Data] = [:]
    private var order: [Int64] = []
    @Published private(set) var error: String?
    init(client: PayrollClient, item: MediaItem) throws {
        guard let stamp = try client.mediaAccessStamp() else { throw APIError.unauthorized }
        self.client = client; self.item = item; self.stamp = stamp
        asset = AVURLAsset(url: URL(string: "jac-media://asset/" + UUID().uuidString)!)
        super.init(); asset.resourceLoader.setDelegate(self, queue: .main)
    }
    nonisolated func resourceLoader(_ resourceLoader: AVAssetResourceLoader, shouldWaitForLoadingOfRequestedResource request: AVAssetResourceLoadingRequest) -> Bool {
        Task { @MainActor [weak self] in self?.start(request) }; return true
    }
    nonisolated func resourceLoader(_ resourceLoader: AVAssetResourceLoader, didCancel request: AVAssetResourceLoadingRequest) {
        Task { @MainActor [weak self] in self?.requests.removeValue(forKey: ObjectIdentifier(request))?.cancel() }
    }
    private func valid() throws {
        try Task.checkCancellation()
        guard active, stamp == (try client.mediaAccessStamp()), client.accessUser?.canReadMedia != false else { blocks.removeAll(); order.removeAll(); throw CancellationError() }
    }
    private func start(_ request: AVAssetResourceLoadingRequest) {
        let key = ObjectIdentifier(request)
        guard active, !request.isCancelled else { request.finishLoading(with: CancellationError()); return }
        requests[key] = Task { @MainActor [weak self] in
            guard let self else { return }; defer { requests.removeValue(forKey: key) }
            do {
                try valid()
                if let info = request.contentInformationRequest {
                    info.contentType = UTType(mimeType: item.mimeType)?.identifier
                    info.contentLength = item.size; info.isByteRangeAccessSupported = true
                }
                if let dataRequest = request.dataRequest {
                    let start = max(dataRequest.currentOffset, dataRequest.requestedOffset)
                    let end = dataRequest.requestsAllDataToEndOfResource ? item.size : min(item.size, dataRequest.requestedOffset + Int64(dataRequest.requestedLength))
                    guard start >= 0, start <= end, end <= item.size else { throw APIError.invalid("El tramo de video no es válido.") }
                    var offset = start
                    while offset < end {
                        try valid(); guard !request.isCancelled else { throw CancellationError() }
                        let blockStart = offset / (1024 * 1024) * (1024 * 1024)
                        let block: Data
                        if let saved = blocks[blockStart] { block = saved }
                        else {
                            block = try await client.mediaRange(item, offset: blockStart, count: Int(min(1024 * 1024, item.size - blockStart)))
                            try valid(); blocks[blockStart] = block; order.removeAll { $0 == blockStart }; order.append(blockStart)
                            while order.count > 8 { blocks.removeValue(forKey: order.removeFirst()) }
                        }
                        try valid(); guard !request.isCancelled else { throw CancellationError() }
                        let index = Int(offset - blockStart), count = min(block.count - index, Int(end - offset))
                        guard count > 0 else { throw APIError.invalid("El video llegó incompleto.") }
                        dataRequest.respond(with: block.subdata(in: index..<(index + count))); offset += Int64(count)
                    }
                }
                try valid(); if !request.isCancelled { request.finishLoading() }
            } catch {
                if !(error is CancellationError), (error as? URLError)?.code != .cancelled { self.error = error.localizedDescription }
                blocks.removeAll(); order.removeAll()
                if !request.isCancelled { request.finishLoading(with: error) }
            }
        }
    }
    func trimCache() { blocks.removeAll(); order.removeAll() }
    func cancel() { active = false; requests.values.forEach { $0.cancel() }; requests.removeAll(); blocks.removeAll(); order.removeAll(); asset.cancelLoading() }
}
private struct MediaStreamingPlayer: View {
    @ObservedObject var stream: MediaVideoStream
    @Environment(\.scenePhase) private var phase
    @State private var player: AVPlayer?
    var body: some View {
        VStack(spacing: 12) {
            if let error = stream.error { InlineError(message: error) }
            MediaNativePlayer(player: player).frame(maxWidth: .infinity, minHeight: 420, maxHeight: .infinity).accessibilityElement(children: .contain).accessibilityIdentifier("media.video")
        }
        .onAppear { player = AVPlayer(playerItem: AVPlayerItem(asset: stream.asset)); player?.play() }
        .onChange(of: stream.error) { _, value in if value != nil { player?.pause(); player?.replaceCurrentItem(with: nil); stream.cancel() } }
        .onDisappear { player?.pause(); player?.replaceCurrentItem(with: nil); player = nil; stream.cancel() }
        .onChange(of: phase) { _, value in if value != .active { player?.pause(); stream.trimCache() } }
    }
}

// Explicitly downloaded media is encrypted in independent authenticated blocks.
// The key derives from the origin/session already held in Keychain. No plaintext
// copy, token or filenames are persisted in Application Support or backups.
final class MediaOfflineCache: @unchecked Sendable {
    private struct Index: Codable {
        var feeds: [String: MediaFeed] = [:]
        var files: [String: MediaItem] = [:]
        var downloads: [String: MediaFeed] = [:]
        var previewAccess: [String: Double]?
        var collectionID: String?
        var deletedFolders: [String]?
        var deletedFiles: [String]?
    }
    let root: URL
    private let lock = NSRecursiveLock()
    private var revoked: Set<String> = []
    private static let chunkSize = 1024 * 1024
    init(root: URL? = nil) {
        self.root = root ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("JACMediaOffline", isDirectory: true)
    }
    private func folder(_ scope: AgendaCacheScope) -> URL { root.appendingPathComponent(scope.id, isDirectory: true) }
    func encryptedFile(_ item: MediaItem, scope: AgendaCacheScope) -> URL { folder(scope).appendingPathComponent(SHA256.hash(data: Data(item.id.utf8)).map { String(format: "%02x", $0) }.joined() + ".media") }
    private func indexFile(_ scope: AgendaCacheScope) -> URL { folder(scope).appendingPathComponent("index.sealed") }
    private func permitted(_ scope: AgendaCacheScope) -> Bool { lock.lock(); defer { lock.unlock() }; return !revoked.contains(scope.id) }
    func allow(_ scope: AgendaCacheScope) { lock.lock(); defer { lock.unlock() }; revoked.remove(scope.id) }
    private func prepare(_ scope: AgendaCacheScope) throws {
        guard !revoked.contains(scope.id) else { throw CancellationError() }
        let manager = FileManager.default
        try manager.createDirectory(at: folder(scope), withIntermediateDirectories: true, attributes: JACFileSecurity.directoryAttributes)
        try manager.setAttributes(JACFileSecurity.directoryAttributes, ofItemAtPath: root.path)
        try manager.setAttributes(JACFileSecurity.directoryAttributes, ofItemAtPath: folder(scope).path)
        var excluded = root, values = URLResourceValues(); values.isExcludedFromBackup = true; try excluded.setResourceValues(values)
    }
    private func readIndex(_ scope: AgendaCacheScope) -> Index {
        guard permitted(scope), let size = try? indexFile(scope).resourceValues(forKeys: [.fileSizeKey]).fileSize, size < 64 * 1024 * 1024,
              let bytes = try? Data(contentsOf: indexFile(scope)), let box = try? AES.GCM.SealedBox(combined: bytes),
              let data = try? AES.GCM.open(box, using: scope.key, authenticating: Data("jac-media-index-v1".utf8)),
              let index = try? JSONDecoder().decode(Index.self, from: data) else { return Index() }
        return index
    }
    private func writeIndex(_ index: Index, scope: AgendaCacheScope) throws {
        try prepare(scope)
        let data = try JSONEncoder().encode(index)
        guard data.count < 64 * 1024 * 1024 else { throw APIError.message("La lista de archivos supera el tamaño de la copia local.") }
        let sealed = try AES.GCM.seal(data, using: scope.key, authenticating: Data("jac-media-index-v1".utf8)).combined!
        try sealed.write(to: indexFile(scope), options: JACFileSecurity.writeOptions)
        try FileManager.default.setAttributes(JACFileSecurity.fileAttributes, ofItemAtPath: indexFile(scope).path)
    }
    func saveFeed(_ feed: MediaFeed, key: String, append: Bool, scope: AgendaCacheScope) throws {
        lock.lock(); defer { lock.unlock() }
        var index = readIndex(scope), result = feed
        if let previous = index.collectionID, feed.collectionID == nil, previous.hasPrefix("jac-r2-") { throw CancellationError() }
        if index.collectionID != feed.collectionID {
            // A new collection replaces only this account's encrypted gallery
            // cache. No Drive originals or other modules are touched.
            try? FileManager.default.removeItem(at: folder(scope))
            index = Index(); index.collectionID = feed.collectionID
        }
        if let previous = index.feeds[key], append {
            var seen = Set<String>()
            result = MediaFeed(connected: feed.connected, canRead: feed.canRead, canUpload: feed.canUpload, canConnect: feed.canConnect, root: feed.root, folder: feed.folder, breadcrumbs: feed.breadcrumbs, items: (previous.items + feed.items).filter { seen.insert($0.id).inserted }, nextPageToken: feed.nextPageToken, provider: feed.provider, collectionID: feed.collectionID,canDelete:feed.canDelete,pendingDeletions:feed.pendingDeletions,deletedFolders:feed.deletedFolders)
        }
        let removed=Set(index.deletedFolders ?? []).union(feed.deletedFolders ?? [])
        if !removed.isEmpty {pruneFolders(removed,index:&index,scope:scope)}
        if result.breadcrumbs.contains(where:{removed.contains($0.id)}) {try writeIndex(index,scope:scope);throw MediaFolderRemoved()}
        result=filteredFeed(result,removed:removed)
        index.feeds[key] = result
        if let id = feed.folder?.id { index.feeds[id] = result }
        try writeIndex(index, scope: scope)
    }
    private func filteredFeed(_ feed:MediaFeed,removed:Set<String>)->MediaFeed {
        MediaFeed(connected:feed.connected,canRead:feed.canRead,canUpload:feed.canUpload,canConnect:feed.canConnect,root:feed.root,folder:feed.folder,breadcrumbs:feed.breadcrumbs,items:feed.items.filter{!removed.contains($0.id)},nextPageToken:feed.nextPageToken,provider:feed.provider,collectionID:feed.collectionID,canDelete:feed.canDelete,pendingDeletions:feed.pendingDeletions,deletedFolders:Array(removed))
    }
    private func pruneFolders(_ removed:Set<String>,index:inout Index,scope:AgendaCacheScope) {
        let feeds=Array(index.feeds.values)+Array(index.downloads.values)
        let affected=feeds.filter {feed in removed.contains(feed.folder?.id ?? "") || feed.breadcrumbs.contains{removed.contains($0.id)}}
        let fileIDs=Set(index.deletedFiles ?? []).union(affected.flatMap{$0.items.filter{$0.kind != "folder"}.map(\.id)})
        for id in fileIDs {if let item=index.files.removeValue(forKey:id){try? FileManager.default.removeItem(at:encryptedFile(item,scope:scope))};index.previewAccess?.removeValue(forKey:id)}
        func keep(_ feed:MediaFeed)->Bool {!removed.contains(feed.folder?.id ?? "") && !feed.breadcrumbs.contains{removed.contains($0.id)}}
        index.feeds=index.feeds.filter{keep($0.value)}.mapValues{filteredFeed($0,removed:removed)}
        index.downloads=index.downloads.filter{keep($0.value)}.mapValues{filteredFeed($0,removed:removed)}
        index.deletedFolders=Array(removed);index.deletedFiles=Array(fileIDs)
    }
    func removeFolders(_ ids:[String],scope:AgendaCacheScope) throws {
        lock.lock();defer{lock.unlock()};var index=readIndex(scope);pruneFolders(Set(index.deletedFolders ?? []).union(ids),index:&index,scope:scope)
        do{try writeIndex(index,scope:scope)}catch{clear(scope);throw error}
    }
    func loadFeed(_ key: String, scope: AgendaCacheScope) -> MediaFeed? {
        lock.lock(); defer { lock.unlock() }
        let index = readIndex(scope)
        guard let saved = index.downloads[key] ?? index.feeds[key] else { return nil }
        return MediaFeed(connected: saved.connected, canRead: saved.canRead, canUpload: false, canConnect: false, root: saved.root, folder: saved.folder, breadcrumbs: saved.breadcrumbs, items: saved.items, nextPageToken: nil, provider: saved.provider, collectionID: saved.collectionID)
    }
    func pinFeed(_ feed: MediaFeed, key: String, scope: AgendaCacheScope) throws {
        lock.lock(); defer { lock.unlock() }
        var index = readIndex(scope)
        guard index.collectionID == feed.collectionID else { throw CancellationError() }
        let removed=Set(index.deletedFolders ?? [])
        guard !feed.breadcrumbs.contains(where:{removed.contains($0.id)}) else{throw MediaFolderRemoved()}
        let clean=filteredFeed(feed,removed:removed)
        index.downloads[key] = clean
        if let id = feed.folder?.id { index.downloads[id] = clean }
        try writeIndex(index, scope: scope)
    }
    func hasFile(_ item: MediaItem, scope: AgendaCacheScope) -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard let saved = readIndex(scope).files[item.id], saved.modifiedAt == item.modifiedAt, saved.size == item.size, saved.mimeType == item.mimeType else { return false }
        return FileManager.default.fileExists(atPath: encryptedFile(item, scope: scope).path)
    }
    private func invalidateFile(_ item: MediaItem, scope: AgendaCacheScope) {
        lock.lock(); defer { lock.unlock() }
        try? FileManager.default.removeItem(at: encryptedFile(item, scope: scope))
        guard !revoked.contains(scope.id) else { return }
        var index = readIndex(scope); index.files.removeValue(forKey: item.id); try? writeIndex(index, scope: scope)
    }
    private func associated(_ item: MediaItem, scope: AgendaCacheScope, block: Int) -> Data { Data("jac-media-v1|\(scope.id)|\(item.id)|\(item.modifiedAt)|\(item.size)|\(block)".utf8) }
    private func length(_ value: Int) -> Data { var size = UInt32(value).bigEndian; return withUnsafeBytes(of: &size) { Data($0) } }
    private func readExactly(_ handle: FileHandle, count: Int) throws -> Data {
        var result = Data()
        while result.count < count { guard let next = try handle.read(upToCount: count - result.count), !next.isEmpty else { throw APIError.invalid("La copia del archivo está incompleta. Vuelve a descargarlo.") }; result.append(next) }
        return result
    }
    func saveFile(_ source: URL, item: MediaItem, scope: AgendaCacheScope, preview: Bool = false) throws {
        lock.lock(); do { try prepare(scope) } catch { lock.unlock(); throw error }; lock.unlock()
        let destination = encryptedFile(item, scope: scope), partial = destination.appendingPathExtension(UUID().uuidString + ".partial")
        defer { try? FileManager.default.removeItem(at: partial) }
        guard FileManager.default.createFile(atPath: partial.path, contents: nil, attributes: JACFileSecurity.fileAttributes) else { throw APIError.message("No se pudo guardar la copia sin conexión.") }
        let input = try FileHandle(forReadingFrom: source), output = try FileHandle(forWritingTo: partial)
        defer { try? input.close(); try? output.close() }
        try output.write(contentsOf: Data("JACMEDIA1".utf8))
        var count: Int64 = 0, block = 0
        while let chunk = try input.read(upToCount: Self.chunkSize), !chunk.isEmpty {
            try Task.checkCancellation(); guard permitted(scope) else { throw CancellationError() }
            count += Int64(chunk.count); guard count <= item.size else { throw APIError.invalid("El archivo cambió. Actualiza la carpeta y vuelve a descargarlo.") }
            let sealed = try AES.GCM.seal(chunk, using: scope.key, authenticating: associated(item, scope: scope, block: block)).combined!
            try output.write(contentsOf: length(sealed.count)); try output.write(contentsOf: sealed); block += 1
        }
        guard count == item.size else { throw APIError.invalid("El archivo llegó incompleto. Vuelve a descargarlo.") }
        try output.write(contentsOf: length(0)); try output.synchronize()
        lock.lock(); defer { lock.unlock() }
        guard !revoked.contains(scope.id) else { throw CancellationError() }
        let current = readIndex(scope)
        guard !(current.deletedFiles ?? []).contains(item.id) else {throw MediaFolderRemoved()}
        guard current.collectionID?.hasPrefix("jac-r2-") != true || item.id.hasPrefix("r2_") else { throw CancellationError() }
        if FileManager.default.fileExists(atPath: destination.path) { try FileManager.default.removeItem(at: destination) }
        try FileManager.default.moveItem(at: partial, to: destination)
        var index = readIndex(scope); index.files[item.id] = item
        if preview { index.previewAccess = (index.previewAccess ?? [:]).merging([item.id: Date().timeIntervalSince1970]) { _, new in new } }
        else { index.previewAccess?.removeValue(forKey: item.id) }
        let pinned = Set(index.downloads.values.flatMap { $0.items.map(\.id) })
        var automatic = (index.previewAccess ?? [:]).filter { !pinned.contains($0.key) }
        var total = automatic.keys.reduce(Int64(0)) { $0 + (index.files[$1]?.size ?? 0) }
        for id in automatic.sorted(by: { $0.value < $1.value }).map(\.key) where total > 128 * 1024 * 1024 {
            if let old = index.files.removeValue(forKey: id) { total -= old.size; try? FileManager.default.removeItem(at: encryptedFile(old, scope: scope)) }
            automatic.removeValue(forKey: id); index.previewAccess?.removeValue(forKey: id)
        }
        try writeIndex(index, scope: scope)
    }
    func document(_ item: MediaItem, scope: AgendaCacheScope) throws -> ExportedDocument? {
        guard hasFile(item, scope: scope) else { return nil }
        let id = UUID(), destinationFolder = TemporaryDocuments.root.appendingPathComponent(id.uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: destinationFolder, withIntermediateDirectories: true, attributes: JACFileSecurity.directoryAttributes)
        let destination = destinationFolder.appendingPathComponent(MediaLocalFile.safeName(item.name))
        do {
            guard FileManager.default.createFile(atPath: destination.path, contents: nil, attributes: JACFileSecurity.fileAttributes) else { throw APIError.message("No se pudo abrir la copia guardada.") }
            let input = try FileHandle(forReadingFrom: encryptedFile(item, scope: scope)), output = try FileHandle(forWritingTo: destination)
            defer { try? input.close(); try? output.close() }
            guard try readExactly(input, count: 9) == Data("JACMEDIA1".utf8) else { throw APIError.invalid("La copia no es válida.") }
            var count: Int64 = 0, block = 0
            while true {
                try Task.checkCancellation(); guard permitted(scope) else { throw CancellationError() }
                let header = try readExactly(input, count: 4), length = header.reduce(0) { ($0 << 8) | Int($1) }
                if length == 0 { break }
                guard length >= 28, length <= Self.chunkSize + 28 else { throw APIError.invalid("La copia no es válida.") }
                let sealed = try AES.GCM.SealedBox(combined: readExactly(input, count: length))
                let plain = try AES.GCM.open(sealed, using: scope.key, authenticating: associated(item, scope: scope, block: block))
                count += Int64(plain.count); guard count <= item.size else { throw APIError.invalid("La copia no es válida.") }
                try output.write(contentsOf: plain); block += 1
            }
            guard count == item.size, (try input.read(upToCount: 1))?.isEmpty != false else { throw APIError.invalid("La copia está incompleta o cambió.") }
            return ExportedDocument(id: id, url: destination)
        } catch { try? FileManager.default.removeItem(at: destinationFolder); if !(error is CancellationError) { invalidateFile(item, scope: scope) }; throw error }
    }
    func clear(_ scope: AgendaCacheScope) {
        lock.lock(); defer { lock.unlock() }; revoked.insert(scope.id)
        try? FileManager.default.removeItem(at: folder(scope))
    }
    func removeOtherSessions(_ scope: AgendaCacheScope) {
        lock.lock(); defer { lock.unlock() }
        for url in (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? [] where url.lastPathComponent != scope.id {
            revoked.insert(url.lastPathComponent); try? FileManager.default.removeItem(at: url)
        }
    }
}

struct MediaDownloadPlan: Identifiable {
    let id = UUID()
    let folder: MediaFolder
    let files: [MediaItem]
    var totalBytes: Int64 { files.reduce(0) { $0 + $1.size } }
}
protocol MediaPhotosWriting {
    @MainActor func authorize() async throws
    @MainActor func save(_ document: ExportedDocument, item: MediaItem) async throws
}
struct DeviceMediaPhotosWriter: MediaPhotosWriting {
    @MainActor func authorize() async throws {
        #if os(iOS)
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else { throw APIError.invalid("Permite a JAC agregar fotos desde Ajustes para guardarlas en Fotos.") }
        #else
        throw APIError.invalid("Guardar en Fotos está disponible en el iPhone.")
        #endif
    }
    static func validateCreatedAsset(_ created: Bool) throws {
        guard created else { throw APIError.invalid("Fotos no pudo agregar este formato de archivo. Los demás archivos continuarán guardándose.") }
    }
    @MainActor func save(_ document: ExportedDocument, item: MediaItem) async throws {
        #if os(iOS)
        let result = MediaCreatedAssetFlag()
        try await PHPhotoLibrary.shared().performChanges {
            let request = item.kind == "video" ? PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: document.url) : PHAssetChangeRequest.creationRequestForAssetFromImage(atFileURL: document.url)
            result.mark(request?.placeholderForCreatedAsset != nil)
        }
        try Self.validateCreatedAsset(result.created)
        #else
        throw APIError.invalid("Guardar en Fotos está disponible en el iPhone.")
        #endif
    }
}
@MainActor final class MediaFolderTransfer: ObservableObject {
    @Published private(set) var running = false
    @Published private(set) var completed = 0
    @Published private(set) var total = 0
    @Published private(set) var failures: [String] = []
    @Published private(set) var message: String?
    private var task: Task<Void, Never>?
    func cancel() { task?.cancel() }
    func start(client: PayrollClient, plan: MediaDownloadPlan, photos: Bool, writer: any MediaPhotosWriting = DeviceMediaPhotosWriter()) {
        guard !running else { return }; running = true; completed = 0; total = plan.files.count; failures = []; message = nil
        task = Task {
            defer { running = false; task = nil }
            if photos { do { try await writer.authorize() } catch { failures = [error.localizedDescription]; return } }
            for item in plan.files {
                do {
                    try Task.checkCancellation()
                    if photos {
                        let document = try await client.mediaDocument(item); defer { TemporaryDocuments.remove(document) }
                        try Task.checkCancellation(); try await writer.save(document, item: item)
                    } else { try await client.saveMediaOffline(item) }
                    completed += 1
                } catch {
                    if error is CancellationError || (error as? URLError)?.code == .cancelled { message = "Operación detenida. Los archivos completados se conservan."; return }
                    failures.append(item.name + ": " + error.localizedDescription)
                    if case APIError.unauthorized = error { return }; if case APIError.forbidden = error { return }
                }
            }
            message = photos ? "\(completed) de \(total) archivos guardados en Fotos." : "\(completed) de \(total) archivos disponibles sin conexión."
        }
    }
}

private struct MediaTransferReview: Identifiable {
    let id = UUID()
    let plan: MediaDownloadPlan
    let photos: Bool
    let requiredBytes: Int64
}
private struct MediaTransferReviewSheet: View {
    let review: MediaTransferReview
    let begin: () -> Void
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text(review.plan.folder.name).font(.headline)
                    LabeledContent("Archivos", value: String(review.plan.files.count))
                    LabeledContent("Tamaño total", value: ByteCountFormatter.string(fromByteCount: review.plan.totalBytes, countStyle: .file))
                    LabeledContent("Espacio disponible", value: ByteCountFormatter.string(fromByteCount: MediaStorageReview.freeBytes, countStyle: .file))
                    if review.requiredBytes > MediaStorageReview.freeBytes { Text("No hay espacio suficiente. Se necesitan aproximadamente " + ByteCountFormatter.string(fromByteCount: review.requiredBytes, countStyle: .file) + " libres, incluyendo los archivos temporales.").font(.footnote).foregroundStyle(.red) }
                    Text(review.photos ? "Se agregarán a Fotos las fotos y videos de esta carpeta y sus subcarpetas. JAC pedirá permiso para agregar archivos; no leerá tu biblioteca." : "Se guardará una copia privada y cifrada de esta carpeta y sus subcarpetas para abrirlas dentro de JAC sin internet. Se elimina al cerrar sesión o al revocarse el acceso.").font(.footnote).foregroundStyle(.secondary)
                }
                Section { Button(review.photos ? "Guardar todos en Fotos" : "Descargar carpeta completa") { begin(); dismiss() }.buttonStyle(JACPrimaryButtonStyle()).disabled(review.plan.files.isEmpty || review.requiredBytes > MediaStorageReview.freeBytes).accessibilityIdentifier("media.transfer.begin") }
                Section("Archivos incluidos") { ForEach(review.plan.files) { file in HStack { Image(systemName: file.kind == "video" ? "video" : "photo"); Text(file.name); Spacer(); Text(file.sizeLabel).font(.caption).foregroundStyle(.secondary) } } }
            }.jacSurface().navigationTitle(review.photos ? "Guardar en Fotos" : "Disponible sin conexión").jacInlineTitle()
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } } }
        }
    }
}

private final class MediaCreatedAssetFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false
    var created: Bool { lock.lock(); defer { lock.unlock() }; return value }
    func mark(_ created: Bool) { lock.lock(); defer { lock.unlock() }; value = created }
}
// The native AVKit views preserve all playback controls. The SwiftUI VideoPlayer
// overlay currently crashes in metadata initialization on this Mac/Xcode build.
#if os(iOS)
private struct MediaNativePlayer: UIViewControllerRepresentable {
    let player: AVPlayer?
    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController(); controller.player = player; controller.view.accessibilityIdentifier = "media.video"; return controller
    }
    func updateUIViewController(_ controller: AVPlayerViewController, context: Context) { controller.player = player }
    static func dismantleUIViewController(_ controller: AVPlayerViewController, coordinator: ()) { controller.player?.pause(); controller.player = nil }
}
#else
private struct MediaNativePlayer: NSViewRepresentable {
    let player: AVPlayer?
    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView(); view.player = player; view.controlsStyle = .inline; view.setAccessibilityIdentifier("media.video"); return view
    }
    func updateNSView(_ view: AVPlayerView, context: Context) { view.player = player }
    static func dismantleNSView(_ view: AVPlayerView, coordinator: ()) { view.player?.pause(); view.player = nil }
}
#endif

enum MediaStorageReview {
    static var freeBytes: Int64 { (try? FileManager.default.attributesOfFileSystem(forPath: FileManager.default.temporaryDirectory.path)[.systemFreeSize] as? NSNumber)?.int64Value ?? 0 }
    static func required(_ files: [MediaItem]) -> Int64 {
        guard !files.isEmpty else { return 0 }
        let total = files.reduce(Int64(0)) { $0 + $1.size }, largest = files.map(\.size).max() ?? 0
        return total + largest + (total / (1024 * 1024) + Int64(files.count)) * 28 + 64 * 1024 * 1024
    }
}
