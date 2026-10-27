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
                    Section { NavigationLink("Condiciones utilizadas en este corte") { List { EmployeeConditionsSection(record: conditions) }.jacSurface().navigationTitle("Condiciones del corte").jacInlineTitle() } }
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
        // Parse each distinct timestamp once, outside the O(n log n) comparator.
        let fractional = ISO8601DateFormatter(), seconds = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        seconds.formatOptions = [.withInternetDateTime]
        var dates: [String: Date] = [:]
        for value in Set(items.compactMap(\.createdAt)) {
            dates[value] = fractional.date(from: value) ?? seconds.date(from: value)
        }
        return items.sorted { left,right in
            if (left.kind == "folder") != (right.kind == "folder") {return left.kind == "folder"}
            let first=left.createdAt.flatMap { dates[$0] },second=right.createdAt.flatMap { dates[$0] }
            if first != second {if let first,let second {return first > second};return first != nil}
            // Match R2's SQLite BINARY name/id tie-break across page boundaries.
            // A localized/numeric comparator inserts later pages ahead of files
            // already visible (for example 1,10 followed by 2).
            if left.name.utf8.elementsEqual(right.name.utf8) { return left.id < right.id }
            return left.name.utf8.lexicographicallyPrecedes(right.name.utf8)
        }
    }
    static func applyingDeletions(to items: [MediaItem], from feed: MediaFeed) -> [MediaItem] {
        let removed = Set(feed.deletedFiles ?? []).union(feed.deletedFolders ?? [])
        return items.filter { !removed.contains($0.id) }
    }
}
struct MediaThumbnailUnavailable: Error {}
struct MediaPreviewUnavailable: LocalizedError {
    let message: String
    let preparing: Bool
    let retryAfter: Double
    var errorDescription: String? { message }
}
enum MediaThumbnail {
    static func jpeg(for file: MediaLocalFile, edge: Int = 360, quality: Double = 0.60, limit: Int = 512 * 1024) async -> Data? {
        let image: CGImage?
        if file.mimeType.hasPrefix("video/") {
            let generator = AVAssetImageGenerator(asset: AVURLAsset(url: file.url))
            generator.appliesPreferredTrackTransform = true; generator.maximumSize = CGSize(width: CGFloat(edge), height: CGFloat(edge))
            image = try? await generator.image(at: .zero).image
        } else if let source = CGImageSourceCreateWithURL(file.url as CFURL, nil) {
            image = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: edge, kCGImageSourceCreateThumbnailWithTransform: true, kCGImageSourceShouldCacheImmediately: false] as CFDictionary)
        } else { image = nil }
        guard !Task.isCancelled, let image else { return nil }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        guard CGImageDestinationFinalize(destination), data.length <= limit else { return nil }
        return data as Data
    }
    static func image(_ data:Data, decodeImmediately: Bool = false) -> JACPlatformImage? {
        guard data.count <= 512*1024,let source=CGImageSourceCreateWithData(data as CFData,nil),let thumbnail=CGImageSourceCreateThumbnailAtIndex(source,0,[kCGImageSourceCreateThumbnailFromImageAlways:true,kCGImageSourceThumbnailMaxPixelSize:360,kCGImageSourceCreateThumbnailWithTransform:true,kCGImageSourceShouldCacheImmediately:decodeImmediately] as CFDictionary) else{return nil}
        #if os(iOS)
        return UIImage(cgImage:thumbnail)
        #else
        return NSImage(cgImage:thumbnail,size:NSSize(width:thumbnail.width,height:thumbnail.height))
        #endif
    }
}
// Shared by iPhone, iPad and Mac. The selected item is frozen for each action,
// including a deletion retry, even if the viewer advances to another photo.
struct MediaPhotoMenu: View {
    let item:MediaItem
    let client:PayrollClient
    let canDelete:Bool
    var resuming=false
    @EnvironmentObject private var store:PayrollStore
    @State private var confirmation=false
    @State private var busy=false
    @State private var message:String?
    @State private var failure:String?
    @State private var document:ExportedDocument?
    @State private var ownedDocument:ExportedDocument?
    @State private var operation:Task<Void,Never>?
    @State private var pinned=false
    @State private var pinTask:Task<Void,Never>?
    var body:some View {
        Menu {
            if !resuming {
                Button {perform(.download)} label:{Label(Self.downloadLabel(item),systemImage:"square.and.arrow.down")}.accessibilityIdentifier("media.photo.download")
                Button {perform(.offline)} label:{Label(pinned ? "Disponible sin conexión":"Guardar sin conexión",systemImage:pinned ? "checkmark.circle":"arrow.down.circle")}.disabled(pinned).accessibilityIdentifier("media.photo.offline")
            }
            if canDelete {
                Divider()
                Button(role:.destructive) {confirmation=true} label:{Label(resuming ? "Continuar eliminación" : (item.kind == "video" ? "Eliminar video" : "Eliminar foto"),systemImage:"trash")}.disabled(store.isOffline).accessibilityIdentifier("media.photo.delete")
            }
        } label:{Image(systemName:"ellipsis.circle.fill").font(.title2).symbolRenderingMode(.palette).foregroundStyle(JACTheme.action,Color.white).frame(width:44,height:44).contentShape(Rectangle())}
            .buttonStyle(.plain).disabled(busy).accessibilityLabel("Opciones de "+item.name).accessibilityIdentifier("media.photo.options."+item.id)
            .onAppear {updatePinned()}
            .onReceive(client.$cacheRevision.dropFirst()) {_ in updatePinned()}
            .overlay {if busy {ProgressView().controlSize(.small)}}
            .alert(confirmation ? (item.kind == "video" ? "Eliminar video" : "Eliminar foto") : "Fotografía",isPresented:Binding(get:{confirmation || message != nil || failure != nil},set:{if !$0 {confirmation=false;message=nil;failure=nil}})) {
                if confirmation {
                    Button("Cancelar",role:.cancel){confirmation=false}
                    Button(item.kind == "video" ? "Eliminar video" : "Eliminar foto",role:.destructive){confirmation=false;perform(.delete)}.accessibilityIdentifier("media.photo.delete.confirm")
                } else {
                    Button("Aceptar",role:.cancel){message=nil;failure=nil}
                    if failure != nil && resuming {Button("Reintentar"){perform(.delete)}}
                }
            } message:{Text(confirmation ? "¿Estás seguro de eliminar «\(item.name)» de Fotografía? Se eliminará para todo el equipo.":failure ?? message ?? "")}
            .sheet(item:$document,onDismiss:clearDocument) {file in
                NavigationStack {DocumentPreview(url:file.url).privacySensitive().navigationTitle(item.name).jacInlineTitle()
                    .toolbar {ToolbarItem(placement:.cancellationAction){Button("Listo"){document=nil}}
                        #if os(iOS)
                        ToolbarItem(placement:.confirmationAction){ShareLink(item:file.url){Label("Guardar en Archivos o compartir",systemImage:"square.and.arrow.up")}}
                        #endif
                    }
                }
            }
            .onDisappear {operation?.cancel();operation=nil;pinTask?.cancel();pinTask=nil;clearDocument()}
    }
    private enum Action {case download,offline,delete}
    private static func downloadLabel(_ item: MediaItem) -> String {
        #if os(iOS)
        return "Guardar en Fotos"
        #else
        return item.kind == "video" ? "Descargar video" : "Descargar foto"
        #endif
    }
    private func updatePinned(){
        pinTask?.cancel()
        pinTask=Task {
            let value=await client.mediaPinnedForPresentation(item)
            guard !Task.isCancelled else{return}
            pinned=value
        }
    }
    private func clearDocument(){if let ownedDocument {TemporaryDocuments.remove(ownedDocument)};ownedDocument=nil}
    private func perform(_ action:Action){
        guard !busy else{return};let selected=item;busy=true;failure=nil
        operation=Task {
            defer{busy=false;operation=nil}
            do {
                switch action {
                case .download:
                    #if os(iOS)
                    try await MediaPhotosExport.save(selected, client: client, writer: MediaPhotosExport.writer(client))
                    message = selected.kind == "video" ? "Video guardado en Fotos." : "Foto guardada en Fotos."
                    #else
                    let stamp = try client.mediaAccessStamp()
                    let file=try await client.mediaDocument(selected)
                    guard !Task.isCancelled,stamp == (try? client.mediaAccessStamp()) else {TemporaryDocuments.remove(file);throw CancellationError()}
                    ownedDocument=file;document=file
                    #endif
                case .offline:
                    try await client.saveMediaOffline(selected);try Task.checkCancellation();updatePinned();message="Archivo disponible sin conexión en este \(JACDevice.name)."
                case .delete:
                    var result:MediaFolderDeletion
                    repeat {result=try await client.deleteMediaFileStep(selected);try Task.checkCancellation();if result.complete != true {try await Task.sleep(for:.milliseconds(result.waiting == true ? 1000:100))}}while result.complete != true
                    message="Archivo eliminado."
                }
            }catch{if let text=store.reportReadFailure(error){failure=text}}
        }
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
    var deletedFiles: [String]? = nil
    var pendingFileDeletions: [MediaFolderDeletion]? = nil
    func replacingItems(_ items: [MediaItem]) -> MediaFeed {
        MediaFeed(connected: connected, canRead: canRead, canUpload: canUpload, canConnect: canConnect,
                  root: root, folder: folder, breadcrumbs: breadcrumbs, items: items, nextPageToken: nextPageToken,
                  provider: provider, collectionID: collectionID, canDelete: canDelete,
                  pendingDeletions: pendingDeletions, deletedFolders: deletedFolders,
                  deletedFiles: deletedFiles, pendingFileDeletions: pendingFileDeletions)
    }
}
/// Fetch a complete replacement before publishing any page. Remember the
/// visible count too: a restored/pinned cache may contain more than one page.
@MainActor
enum MediaGalleryListing {
    static func read(minimumPages: Int, minimumItems: Int,
                     page: (String) async throws -> MediaFeed) async throws -> (feed: MediaFeed, pages: Int) {
        var result = try await page("")
        var seen = Set<String>()
        var all = result.items.filter { seen.insert($0.id).inserted }, pages = 1
        let collection = result.collectionID, folder = result.folder?.id
        var cursor = result.nextPageToken ?? "", visited = Set<String>()
        while !cursor.isEmpty && (pages < max(1, minimumPages) || all.count < minimumItems) {
            try Task.checkCancellation()
            guard visited.insert(cursor).inserted else { throw APIError.invalid("No se pudo continuar la lista de esta carpeta.") }
            let next = try await page(cursor)
            guard next.connected, next.canRead, next.collectionID == collection, next.folder?.id == folder else {
                throw APIError.forbidden("La carpeta cambió o dejó de estar disponible.")
            }
            result = next; all += next.items.filter { seen.insert($0.id).inserted }; pages += 1; cursor = next.nextPageToken ?? ""
        }
        try Task.checkCancellation()
        let ordered = MediaGalleryOrder.sorted(MediaGalleryOrder.applyingDeletions(to: all, from: result))
        return (result.replacingItems(ordered), pages)
    }
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
    // Legacy in-memory marker; new original videos do not require conversion.
    var videoPrepared = false
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
    #if os(iOS)
    @Environment(\.phoneSidebarMenu) private var phoneMenu
    #endif
    let user: PayrollUser
    private let notificationFolderID: String?
    init(user: PayrollUser, notificationFolder: MediaFeed? = nil) {
        self.user = user
        notificationFolderID = notificationFolder?.folder?.id
        _folderID = State(initialValue: notificationFolder?.folder?.id ?? "")
        _feed = State(initialValue: notificationFolder)
        _items = State(initialValue: MediaGalleryOrder.sorted(notificationFolder?.items ?? []))
    }
    @EnvironmentObject private var store: PayrollStore
    @Environment(\.scenePhase) private var phase
    @Environment(\.isWorkspaceActive) private var isWorkspaceActive
    @Environment(\.jacWorkspaceLayout) private var layout
    @StateObject private var folderTransfer = MediaFolderTransfer()
    @State private var transferReview: MediaTransferReview?
    @State private var confirmedTransfer: MediaTransferReview?
    @State private var uploadMeter=MediaUploadRate()
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
    @State private var downloadedFolderIDs = Set<String>()
    @State private var removingLocalFolder = false
    @State private var importing = false
    @State private var importTask: Task<Void, Never>?
    #if os(iOS)
    @StateObject private var selection = MediaBatchSelection()
    @StateObject private var thumbnails = MediaFolderThumbnailPrefetch()
    @State private var selectionDownloadChoices = false
    @State private var selectionConfirmation = false
    @State private var selectionDeletionTargets: [MediaItem] = []
    @ObservedObject private var persistentUploads = MediaUploadQueue.shared
    @State private var handingOffUploads = false
    @State private var uploadRefreshPending = false
    @State private var galleryVisible = false
    @State private var sharingFolder: MediaFolder?
    private var uploading: Bool { handingOffUploads }
    #else
    @State private var uploading = false
    #endif
    @State private var uploadTask: Task<Void, Never>?
    @State private var error: String?
    @State private var generation = UUID()
    @State private var thumbnailEpoch = UUID()
    @State private var preview: MediaPreview?
    @State private var previewFeed: MediaFeed?
    @State private var fullscreenPhotos:MediaPhotoPresentation?
    @State private var inlinePhotos:MediaPhotoPresentation?
    @State private var expandedFolders: Set<String> = []
    @State private var uploadComposition: MediaUploadComposition?
    @State private var confirmedUpload = false
    @State private var previewDocument: ExportedDocument?
    @State private var openingTask: Task<Void, Never>?
    @State private var opening: String?
    private var writable: Bool { user.canUploadMedia && feed?.canUpload == true && feed?.connected == true && !store.isOffline }
    private var parentID: String { feed?.folder?.id ?? feed?.root?.id ?? "" }
    private var compactGallery: Bool {
        #if os(iOS)
        return !JACDevice.isPad
        #else
        return false
        #endif
    }
    private var showingSelection: Bool {
        #if os(iOS)
        return selection.active
        #else
        return false
        #endif
    }
    private var galleryContent: some View {
        ScrollView {
            // Only the tile grids are lazy. A lazy ancestor estimates the height
            // of an entire expanded folder and can remove it while its children
            // are on screen, producing blank space and jumps in the scroll.
            VStack(alignment: .leading, spacing: 22) {
                #if os(iOS)
                if compactGallery {
                    if !selection.active && user.canUploadMedia {
                        HStack {
                            Spacer()
                            Button { beginUpload() } label: { Label("Subir",systemImage:"plus").foregroundStyle(.white) }.buttonStyle(.borderedProminent).disabled(!writable || uploading || !queue.isEmpty).accessibilityIdentifier("media.add")
                        }
                    }
                } else {
                VStack(alignment:.leading,spacing:12) {
                    Text(feed?.folder?.id == feed?.root?.id ? "Cada show, en imágenes." : feed?.folder?.name ?? "Fotos y videos de JAC").font(.system(.title2,design:.rounded,weight:.bold)).foregroundStyle(JACTheme.ink).fixedSize(horizontal:false,vertical:true).frame(maxWidth:.infinity,alignment:.leading).accessibilityIdentifier("media.heading")
                    HStack(alignment:.top,spacing:16) {
                        Text("Tu archivo de fotos y videos, organizado por día.").font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true).frame(maxWidth:.infinity,alignment:.leading)
                        if writable {Button {beginUpload()} label:{Label("Subir",systemImage:"plus")}.buttonStyle(.borderedProminent).fixedSize().accessibilityIdentifier("media.add")}
                    }
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
                if loading && feed == nil { ProgressView("Cargando carpetas…").frame(maxWidth: .infinity) }
                #if os(iOS)
                if !persistentUploads.jobs.isEmpty { persistentUploadPanel }
                #endif
                if let feed {
                    if !feed.connected {
                        ContentUnavailableView("Preparando el archivo de Fotografía", systemImage: "externaldrive.badge.questionmark", description: Text("El archivo privado de JAC se administra en Configuración general → Servicios conectados."))
                    } else if !feed.canRead || !user.canReadMedia {
                        ContentUnavailableView("Sin acceso a Fotografía", systemImage: "lock", description: Text("Tu cuenta no tiene acceso a estas fotos y videos."))
                    } else {
                        if !compactGallery { breadcrumbs(feed) }
                        if !showingSelection && (preparingTransfer || folderTransfer.running || folderTransfer.message != nil || !folderTransfer.failures.isEmpty) { transferStatus }
                        if user.canDeleteMedia,let pending=feed.pendingDeletions,!pending.isEmpty {
                            VStack(alignment:.leading,spacing:12) {ForEach(pending) {job in HStack {Text("Eliminación pendiente: "+job.name).font(.footnote);Spacer();Button("Continuar eliminación") {deletingFolder=MediaFolder(id:job.id,name:job.name);deletionConfirmed=true;beginFolderDeletion()}.disabled(deleting).accessibilityIdentifier("media.delete.resume."+job.id)}}}.padding(14).background(.orange.opacity(0.08),in:RoundedRectangle(cornerRadius:14))
                        }
                        if user.canDeleteMedia,let jobs=feed.pendingFileDeletions {
                            ForEach(jobs) {job in HStack{Text("Eliminación pendiente: "+job.name).font(.footnote);Spacer();MediaPhotoMenu(item:MediaItem(id:job.id,name:job.name,mimeType:"image/jpeg",kind:"image",size:0,modifiedAt:"",thumbnailAvailable:false),client:store.client,canDelete:true,resuming:true)}}
                        }
                        if !compactGallery && writable && uploadDestination?.id == parentID { uploadActions }
                        if importing { HStack { ProgressView("Preparando archivos…"); Spacer(); Button("Cancelar preparación") { importTask?.cancel() } } }
                        if let uploadNotice { Label(uploadNotice, systemImage: "checkmark.circle").font(.footnote).foregroundStyle(.secondary).accessibilityIdentifier("media.upload.status") }
                        if !queue.isEmpty { pendingUploads }
                        if items.isEmpty && !loading {
                            ContentUnavailableView("Esta carpeta está vacía", systemImage: "photo.on.rectangle", description: Text(writable ? "Crea una carpeta para cada show o día y agrega sus fotos y videos." : "Aquí aparecerán las fotos y videos que suba el fotógrafo."))
                        }
                        #if os(iOS)
                        if compactGallery { inlineFolders }
                        else { legacyGrid }
                        #else
                        legacyGrid
                        #endif
                        if !(feed.nextPageToken ?? "").isEmpty {
                            Button("Cargar más") { loadedPages += 1; Task { await reload() } }.frame(maxWidth: .infinity).disabled(loading || uploading).accessibilityIdentifier("media.more")
                        }
                    }
                }
            }.padding(.horizontal,18).padding(.top,JACTheme.pageTopSpacing).padding(.bottom,18).frame(maxWidth: 1160, alignment: .leading).frame(maxWidth: .infinity)
        }
    }
    private var galleryNavigation: some View {
        adaptiveGalleryContent.jacSurface().jacWorkspaceTitle(notificationFolderID != nil ? feed?.folder?.name ?? "Fotografía" : "Fotografía")
            #if os(iOS)
            .toolbar(compactGallery && notificationFolderID == nil && phoneMenu == nil ? .hidden : .automatic,for:.navigationBar)
            .safeAreaInset(edge: .bottom) { if selection.active { selectionActions } }
            .onChange(of: store.client.mediaPresentationStamp) { _, _ in
                sharingFolder = nil
                selection.synchronize(client: store.client)
                selectionDownloadChoices = false
                folderTransfer.cancel(); transferReview = nil; confirmedTransfer = nil
            }
            .onChange(of: feed?.collectionID) { _, _ in
                selectionDownloadChoices = false
                folderTransfer.cancel(); transferReview = nil; confirmedTransfer = nil
            }
            .confirmationDialog("Descargar selección", isPresented: $selectionDownloadChoices, titleVisibility: .visible) {
                Button("Guardar en Fotos") { prepareSelectionTransfer(photos: true) }
                    .accessibilityIdentifier("media.selection.savePhotos")
                Button("Guardar sin conexión") { prepareSelectionTransfer(photos: false) }
                    .accessibilityIdentifier("media.selection.offline")
                Button("Cancelar", role: .cancel) {}
            }
            .alert("Eliminar selección", isPresented: $selectionConfirmation) {
                Button("Cancelar", role: .cancel) { selectionDeletionTargets = [] }
                Button("Eliminar", role: .destructive) {
                    selection.delete(selectionDeletionTargets, client: store.client, denied: thumbnailDenied)
                    selectionDeletionTargets = []
                }.accessibilityIdentifier("media.selection.delete.confirm")
            } message: {
                Text("¿Estás seguro de eliminar los \(selectionDeletionTargets.count) archivos seleccionados? Se eliminarán para todo el equipo. Esta acción no se puede deshacer.")
            }
            #endif
            .refreshable { await reload() }
            .toolbar {
                if !compactGallery {
                ToolbarItem {Button {Task {await reload()}} label:{Image(systemName:"arrow.clockwise")}.accessibilityLabel("Actualizar fotografías").accessibilityIdentifier("media.refresh").disabled(loading || uploading)}
                ToolbarItem {if let folder=feed?.folder,feed?.canRead == true {Menu {folderCommands(folder);if user.canUploadMedia {Button("Calidad de las imágenes",systemImage:"slider.horizontal.3"){imageQualitySettings=true}.accessibilityIdentifier("media.quality")}} label:{Image(systemName:"ellipsis.circle")}.accessibilityLabel("Opciones de esta carpeta").accessibilityIdentifier("media.current.options")}}
                }
            }
    }
    private var adaptiveGalleryContent: some View {
        HStack(spacing: 0) {
            galleryContent.accessibilityIdentifier("media.gallery.scroll")
                .frame(maxWidth: layout.isWide ? max(290, layout.contentWidth * 0.47) : .infinity)
            #if os(iOS)
            if layout.isWide {
                Rectangle().fill(JACTheme.border).frame(width: 1)
                Group {
                    if let request = inlinePhotos {
                        MediaFullscreenPhotoView(selected: request.selected, feed: request.feed, client: store.client, embedded: true, close: { inlinePhotos = nil }, expand: { item in
                            fullscreenPhotos = MediaPhotoPresentation(selected: item, feed: request.feed)
                        }, denied: thumbnailDenied).id(request.id)
                    } else {
                        ContentUnavailableView("Selecciona una foto", systemImage: "photo", description: Text("Explora la carpeta y consulta sus fotos aquí. Puedes ampliarlas a pantalla completa."))
                    }
                }.frame(maxWidth: .infinity, maxHeight: .infinity).clipped().accessibilityIdentifier("media.wide.preview")
            }
            #endif
        }.accessibilityIdentifier(layout.isWide ? "phone.media.columns" : "phone.media.list")
            .onChange(of: layout.isWide) { _, wide in
                if !wide, let request = inlinePhotos { fullscreenPhotos = request; inlinePhotos = nil }
            }
    }
    private var galleryUpdates: some View {
        galleryNavigation.task(id: JACWorkspaceRefreshID(location: folderID, active: workspaceCanRefresh)) {
                guard workspaceCanRefresh else { return }
                await reload()
                while !Task.isCancelled {
                    do { try await Task.sleep(for: .seconds(30)) } catch { return }
                    guard workspaceCanRefresh else { return }
                    if !uploading && preview == nil && fullscreenPhotos == nil && !choosingDestination && uploadComposition == nil && opening == nil { await reload() }
                }
            }
            .onChange(of: workspaceCanRefresh) { _, active in
                if !active { generation = UUID(); loadingFolder = nil; loading = false }
                #if os(iOS)
                if active { refreshAfterUploads() } else { thumbnails.stop() }
                #endif
            }
            .onChange(of: store.isOffline) { old, new in if old && !new && mediaIsOffline && workspaceCanRefresh { Task { await reload() } } }
            #if os(iOS)
            .onAppear { galleryVisible = true }
            .onChange(of: persistentUploads.revision) { _, _ in
                uploadRefreshPending = true
                refreshAfterUploads()
            }
            .onChange(of: persistentUploads.uploading) { _, running in if !running { refreshAfterUploads() } }
            #endif
            .onReceive(store.client.$cacheRevision.dropFirst()) {_ in
                guard workspaceCanRefresh else { return }
                if let saved=store.client.cachedMedia(folder:folderID) {
                    let remaining = MediaGalleryOrder.applyingDeletions(to: items, from: saved)
                    if remaining != items { items = remaining }
                    #if os(iOS)
                    selection.reconcile(saved.replacingItems([]))
                    #endif
                }
            }
            .onChange(of: selectedPhotos) { _, selected in guard !selected.isEmpty else { return }; importTask?.cancel(); importTask = Task { await readPhotos(selected) } }
            .alert("Eliminar carpeta",isPresented:$deletionConfirmation) {
                Button("Cancelar",role:.cancel){deletingFolder=nil}
                Button("Eliminar",role:.destructive){deletionConfirmed=true;beginFolderDeletion()}.accessibilityIdentifier("media.delete.confirm")
            } message:{Text("¿Estás seguro de eliminar esta carpeta y todo su contenido?")}
            .overlay(alignment:.bottom) {if deleting {HStack(spacing:12){ProgressView();Text("Eliminando carpeta…").font(.subheadline)}.padding(18).background(.regularMaterial,in:RoundedRectangle(cornerRadius:16)).padding(20).accessibilityIdentifier("media.delete.progress")}else if let deletionError {HStack {Text(deletionError).font(.footnote);Button("Reintentar"){beginFolderDeletion()};Button("Cerrar"){self.deletionError=nil;deletingFolder=nil;deletionConfirmed=false}}.padding(16).background(.regularMaterial,in:RoundedRectangle(cornerRadius:16)).padding(20)}}
    }
    var body: some View {
        galleryUpdates.sheet(isPresented:$imageQualitySettings) {NavigationStack {MediaImageQualitySettings().toolbar {ToolbarItem(placement:.cancellationAction){Button("Listo"){imageQualitySettings=false}.accessibilityIdentifier("media.quality.close")}}}}
            .task(id: (store.client.mediaPresentationStamp ?? "") + ":" + String(store.client.cacheRevision)) {
                let ids = await store.client.localMediaFoldersForPresentation()
                if !Task.isCancelled { downloadedFolderIDs = ids }
            }
            #if os(iOS)
            .sheet(item: $sharingFolder) { folder in MediaFolderShareSheet(folder: folder, client: store.client) }
            #endif
            .sheet(isPresented:$choosingDestination) {if let location=feed?.folder ?? feed?.root {MediaUploadDestinationPicker(root:location,isRoot:location.id == feed?.root?.id) {selectDestination($0)}}}
            .sheet(item:$uploadComposition,onDismiss:{
                if confirmedUpload {confirmedUpload=false;if !queue.isEmpty {uploadTask=Task {await uploadAll()}}}
            }) { request in
                #if os(iOS)
                MediaSimpleUploadComposer(root:request.root,destination:request.destination) { folder,files in
                    uploadDestination=folder;queue=files;completed=[];progress=[:];uploadErrors=[:];expandedFolders.insert(folder.id);confirmedUpload=true;uploadComposition=nil
                }
                #endif
            }
            .sheet(item: $transferReview,onDismiss:{if let review=confirmedTransfer {
                confirmedTransfer=nil
                guard review.stamp != nil,review.stamp == (try? store.client.mediaAccessStamp()) else {return}
                folderTransfer.start(client:store.client,plan:review.plan,photos:review.photos,writer:photosWriter)
            }}) { review in MediaTransferReviewSheet(review: review) { confirmedTransfer=review } }
            .sheet(item: $preview, onDismiss: clearPreview) { document in MediaPreviewSheet(preview: document, photos: (previewFeed?.items ?? items).filter { $0.kind == "image" }, feed: previewFeed ?? feed, client: store.client, denied: thumbnailDenied) }
            #if os(iOS)
            .fullScreenCover(item:$fullscreenPhotos) {request in MediaFullscreenPhotoView(selected:request.selected,feed:request.feed,client:store.client,denied:thumbnailDenied)}
            #endif
            .fileImporter(isPresented: $pickingFiles, allowedContentTypes: [.image, .movie, .video], allowsMultipleSelection: true) { result in
                switch result { case .success(let urls): importTask?.cancel(); importTask = Task { await readFiles(urls) }; case .failure(let failure): if (failure as? CocoaError)?.code != .userCancelled { error = failure.localizedDescription } }
            }
            .jacFileDrop(enabled: !compactGallery && writable && !uploading && !importing) { urls in importTask?.cancel(); importTask = Task { await readFiles(urls);if uploadDestination == nil && !queue.isEmpty {if parentID == feed?.root?.id {choosingDestination=true}else{uploadDestination=feed?.folder}} } }
            .jacRefreshCommand { Task { await reload() } }
            .onDisappear {
                #if os(iOS)
                galleryVisible = false
                thumbnails.stop()
                #endif
                if fullscreenPhotos == nil || store.overview?.user.id != user.id {
                    #if os(iOS)
                    selection.reset(); selectionDownloadChoices = false; selectionConfirmation = false; selectionDeletionTargets = []
                    #endif
                    deletionTask?.cancel()
                    #if os(macOS)
                    uploadTask?.cancel()
                    #endif
                    importTask?.cancel(); folderTransfer.cancel(); openingTask?.cancel(); generation = UUID(); loadingFolder=nil;loading=false
                    discardStagedUploads()
                    clearPreview()
                }
            }
    }
    #if os(iOS)
    private var selectionBusy: Bool { selection.deleting || folderTransfer.running || preparingTransfer }
    private var selectionActions: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Text(selection.count == 1 ? "1 seleccionado" : "\(selection.count) seleccionados").font(.subheadline.weight(.semibold)).accessibilityIdentifier("media.selection.count")
                Spacer(minLength: 0)
                if selection.deleting {
                    Button("Detener") { selection.cancelDeletion() }.accessibilityIdentifier("media.selection.stop")
                } else if folderTransfer.running {
                    Button("Detener") { folderTransfer.cancel() }.accessibilityIdentifier("media.selection.stop")
                } else {
                    Button { prepareSelectionTransfer(photos: true) } label: {
                        Label("Guardar en Fotos", systemImage: "square.and.arrow.down").frame(minHeight: 44).contentShape(Rectangle())
                    }
                        .disabled(selection.count == 0 || selectionBusy || deleting).accessibilityIdentifier("media.selection.download")
                    Button { prepareSelectionTransfer(photos: false) } label: { Image(systemName: "arrow.down.circle").frame(width:44,height:44) }
                        .accessibilityLabel("Guardar selección sin conexión").accessibilityIdentifier("media.selection.offline")
                        .disabled(selection.count == 0 || selectionBusy || deleting)
                    if store.overview?.user.canDeleteMedia == true && selection.canDelete {
                        Button(role: .destructive) {
                            selectionDeletionTargets = selection.items; selectionConfirmation = true
                        } label: { Image(systemName: "trash") }
                            .disabled(selectionBusy || deleting || store.isOffline)
                            .accessibilityLabel("Eliminar selección").accessibilityIdentifier("media.selection.delete")
                    }
                }
                Button { selection.reset() } label: { Image(systemName: "xmark.circle").frame(width: 36, height: 36) }
                    .buttonStyle(.plain).disabled(selectionBusy)
                    .accessibilityLabel("Cancelar selección").accessibilityIdentifier("media.selection.cancel")
            }
            if selection.deleting {
                ProgressView(value: Double(selection.completed), total: Double(max(1, selection.total)))
                Text("Eliminando: \(selection.completed) de \(selection.total)").font(.footnote).accessibilityIdentifier("media.selection.progress")
            } else if folderTransfer.running {
                ProgressView(value: Double(folderTransfer.completed), total: Double(max(1, folderTransfer.total)))
                Text("Descargando: \(folderTransfer.completed) de \(folderTransfer.total)").font(.footnote).accessibilityIdentifier("media.selection.progress")
            }
            if let message = selection.message { Text(message).font(.footnote).accessibilityIdentifier("media.selection.status") }
            if !selection.failures.isEmpty {
                DisclosureGroup("\(selection.failures.count) archivos no se pudieron eliminar") {
                    ScrollView { VStack(alignment: .leading, spacing: 6) { ForEach(Array(selection.failures.enumerated()), id: \.offset) { _, failure in Text(failure).font(.caption).foregroundStyle(.red) } } }.frame(maxHeight: 120)
                }.font(.footnote)
            }
            if !folderTransfer.running, let message = folderTransfer.message {
                Text(message).font(.footnote).foregroundStyle(.secondary)
            }
            if !folderTransfer.failures.isEmpty {
                DisclosureGroup("\(folderTransfer.failures.count) archivos no se pudieron descargar") {
                    ScrollView { VStack(alignment: .leading, spacing: 6) { ForEach(Array(folderTransfer.failures.enumerated()), id: \.offset) { _, failure in Text(failure).font(.caption).foregroundStyle(.red) } } }.frame(maxHeight: 120)
                }.font(.footnote)
            }
        }.padding(16).background(.regularMaterial)
    }
    private func prepareSelectionTransfer(photos: Bool) {
        selection.synchronize(client: store.client)
        guard !selectionBusy, !deleting, !selection.items.isEmpty else { return }
        let files = selection.items
        let plan = MediaDownloadPlan(folder: MediaFolder(id: "selection", name: "\(files.count) archivos seleccionados"), files: files)
        if photos { folderTransfer.start(client: store.client, plan: plan, photos: true, writer: photosWriter); return }
        let scope = try? store.client.mediaScope(), cache = store.client.mediaOffline
        let pending = photos ? files : files.filter { item in scope.map { !cache.isPinned(item, scope: $0) } ?? true }
        transferReview = MediaTransferReview(plan: plan, photos: photos, requiredBytes: MediaStorageReview.required(pending), selection: true, stamp: try? store.client.mediaAccessStamp())
    }
    private var inlineFolders: some View {
        VStack(spacing:12) {
            ForEach(items.filter { $0.kind == "folder" }) { item in
                MediaInlineFolder(folder:MediaFolder(id:item.id,name:item.name),collectionID:feed?.collectionID,expanded:$expandedFolders,epoch:thumbnailEpoch,disabled:uploading || opening != nil || deleting || selectionBusy,opening:opening,open:{item,context in open(item,in:context)},denied:thumbnailDenied,commands:{AnyView(folderCommands($0))},selection:selection)
            }
            // Older general uploads remain readable without adding a heading.
            LazyVGrid(columns:[GridItem(.flexible()),GridItem(.flexible())],spacing:12) {
                ForEach(items.filter { $0.kind != "folder" }) {item in
                    if let feed {
                        MediaSelectableTile(item: item, feed: feed, client: store.client, selection: selection,
                                            offline: store.isOffline, disabled: opening != nil || uploading || deleting || selectionBusy,
                                            opening: opening == item.id, epoch: thumbnailEpoch,
                                            open: { open(item) }, denied: thumbnailDenied)
                    }
                }
            }
        }
    }
    #endif
    private var legacyGrid: some View {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 160, maximum: 280), spacing: 14)], spacing: 14) {
                            ForEach(items) { item in
                                VStack(alignment:.leading,spacing:0) {
                                    legacyTile(item)
                                    if item.kind == "folder" {
                                        HStack {Text("Carpeta del equipo").font(.caption).foregroundStyle(.secondary);Spacer(minLength:6)
                                            Menu {folderCommands(MediaFolder(id:item.id,name:item.name))} label:{Image(systemName:"ellipsis.circle").font(.title3).padding(4)}.buttonStyle(.plain).accessibilityLabel("Opciones de "+item.name).accessibilityIdentifier("media.options."+item.id)
                                        }.padding(.horizontal,12).padding(.bottom,10)
                                    }
                                }.background(JACTheme.card,in:RoundedRectangle(cornerRadius:18))
                                    .contextMenu {if item.kind == "folder" {folderCommands(MediaFolder(id:item.id,name:item.name))}}
                            }
                        }
    }
    @ViewBuilder private func legacyTile(_ item: MediaItem) -> some View {
        #if os(iOS)
        if item.kind != "folder", let feed {
            MediaSelectableTile(item: item, feed: feed, client: store.client, selection: selection,
                                offline: store.isOffline, disabled: opening != nil || uploading || deleting || selectionBusy,
                                opening: opening == item.id, epoch: thumbnailEpoch,
                                open: { open(item) }, denied: thumbnailDenied)
        } else { legacyOpenTile(item) }
        #else
        legacyOpenTile(item)
        #endif
    }
    private func legacyOpenTile(_ item: MediaItem) -> some View {
        Button { open(item) } label: { MediaTile(item: item, client: store.client, offline: store.isOffline, opening: opening == item.id, epoch:thumbnailEpoch, denied:thumbnailDenied) }
            .buttonStyle(.plain).disabled(uploading || opening != nil).accessibilityIdentifier("media.item." + item.id)
            .overlay(alignment: .topTrailing) { if item.kind == "image" || item.kind == "video" { MediaPhotoMenu(item:item,client:store.client,canDelete:user.canDeleteMedia && feed?.canDelete == true).padding(6) } }
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
        if compactGallery && writable {
            Button { if let root=feed?.root {uploadComposition=MediaUploadComposition(root:root,destination:folder)} } label:{Label("Subir aquí",systemImage:"plus")}.accessibilityIdentifier("media.upload.here")
                .disabled(uploading || importing || !queue.isEmpty)
        }
        Button {Task {await prepareTransfer(folder:folder.id,photos:false)}} label:{Label("Disponible sin conexión",systemImage:"arrow.down.circle")}.accessibilityIdentifier("media.offline")
            .disabled(preparingTransfer || folderTransfer.running || uploading || opening != nil)
        if downloadedFolderIDs.contains(folder.id) {
            Button(role:.destructive) { removeLocalFolder(folder) } label: { Label("Eliminar descarga sin conexión",systemImage:"iphone.slash") }
                .accessibilityIdentifier("media.offline.remove." + folder.id)
                .disabled(removingLocalFolder || preparingTransfer || folderTransfer.running)
        }
        #if os(iOS)
        if writable, folder.id != feed?.root?.id {
            Button { sharingFolder = folder } label: { Label("Compartir carpeta", systemImage: "link") }.accessibilityIdentifier("media.share.folder")
        }
        Button {Task {await prepareTransfer(folder:folder.id,photos:true,imagesOnly:true)}} label:{Label("Descargar todas las fotos",systemImage:"photo.on.rectangle")}.accessibilityIdentifier("media.savePhotosOnly")
            .disabled(preparingTransfer || folderTransfer.running || uploading || opening != nil)
        Button {Task {await prepareTransfer(folder:folder.id,photos:true)}} label:{Label("Descargar fotos y videos",systemImage:"square.and.arrow.down")}.accessibilityIdentifier("media.savePhotos")
            .disabled(preparingTransfer || folderTransfer.running || uploading || opening != nil)
        #endif
        if user.canDeleteMedia,feed?.canDelete == true,folder.id != feed?.root?.id {
            Divider()
            Button(role:.destructive) {deletionError=nil;deletionConfirmed=false;deletingFolder=folder;deletionConfirmation=true} label:{Label("Eliminar carpeta",systemImage:"trash")}.accessibilityIdentifier("media.delete.folder")
                .disabled(deleting || uploading || importing || preparingTransfer || folderTransfer.running || queue.contains(where:{!completed.contains($0.id)}) || store.isOffline)
        }
    }
    private func removeLocalFolder(_ folder: MediaFolder) {
        guard !removingLocalFolder, !folderTransfer.running, !preparingTransfer else { return }
        removingLocalFolder = true
        Task {
            defer { removingLocalFolder = false }
            do {
                let bytes = try await store.client.removeLocalMediaFolder(folder.id)
                uploadNotice = "Descarga eliminada de este \(JACDevice.name) · \(ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)) liberados."
                downloadedFolderIDs = await store.client.localMediaFoldersForPresentation()
            } catch { self.error = store.reportReadFailure(error) }
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
    private func prepareTransfer(folder:String,photos:Bool,imagesOnly:Bool=false) async {
        guard !preparingTransfer,!folderTransfer.running else {return};preparingTransfer=true;defer{preparingTransfer=false}
        do {
            let stamp=try store.client.mediaAccessStamp(),plan=try await store.client.mediaDownloadPlan(folder:folder,imagesOnly:imagesOnly)
            guard !Task.isCancelled,stamp == (try store.client.mediaAccessStamp()) else {throw CancellationError()}
            let scope=try store.client.mediaScope(),cache=store.client.mediaOffline
            let pending=photos ? plan.files:plan.files.filter{item in scope.map{!cache.hasFile(item,scope:$0)} ?? true}
            transferReview=MediaTransferReview(plan:plan,photos:photos,requiredBytes:MediaStorageReview.required(pending),imagesOnly:imagesOnly,stamp:stamp)
        } catch {if let message=store.reportReadFailure(error){self.error=message}else if !Task.isCancelled {self.error="No se pudo preparar la carpeta. Actualiza Fotografía e inténtalo de nuevo."}}
    }
    private func beginUpload() {
        guard writable,!uploading,queue.isEmpty else{return}
        if compactGallery {if let root=feed?.root {uploadComposition=MediaUploadComposition(root:root,destination:nil)};return}
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
                        let document = try TemporaryDocuments.save(bytes, filename: name); defer { TemporaryDocuments.remove(document) }
                        let source = try MediaLocalFile.stage(document.url)
                        #if os(iOS)
                        var prepared = false
                        defer { if !prepared { source.remove() } }
                        let result = try await MediaVideoPreparation.prepare(source)
                        if result.file.url != source.url { source.remove() }
                        queue.append(result.file)
                        prepared = true
                        #else
                        queue.append(source)
                        #endif
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
            TimelineView(.periodic(from:.now,by:0.5)) {_ in
                let total=queue.reduce(Int64(0)){$0+$1.size},sent=queue.reduce(Double(0)){$0+Double($1.size)*(completed.contains($1.id) ? 1 : progress[$1.id] ?? 0)},fraction=total>0 ? min(completed.count == queue.count ? 1:0.99,sent/Double(total)):0
                HStack(spacing:20) {
                    ZStack {Circle().stroke(JACTheme.action.opacity(0.12),lineWidth:8);Circle().trim(from:0,to:fraction).stroke(JACTheme.action,style:StrokeStyle(lineWidth:8,lineCap:.round)).rotationEffect(.degrees(-90));Text("\(Int(fraction*100))%").font(.title3.bold()).monospacedDigit()}.frame(width:82,height:82).accessibilityElement(children:.ignore).accessibilityLabel("Progreso general de subida").accessibilityValue("\(Int(fraction*100)) por ciento").accessibilityIdentifier("media.upload.progress")
                    VStack(alignment:.leading,spacing:5) {
                        Text(uploading ? "Subiendo al archivo":"Archivos seleccionados").font(.headline)
                        Text("\(completed.count) de \(queue.count) completados").font(.subheadline).foregroundStyle(.secondary)
                        Text(ByteCountFormatter.string(fromByteCount:Int64(sent),countStyle:.file)+" de "+ByteCountFormatter.string(fromByteCount:total,countStyle:.file)).font(.caption).foregroundStyle(.secondary)
                        if uploading {let rate=uploadMeter.rate();Text(rate>0 ? ByteCountFormatter.string(fromByteCount:Int64(rate),countStyle:.file)+"/s":"Esperando transferencia…").font(.subheadline.bold()).monospacedDigit().foregroundStyle(JACTheme.action).accessibilityIdentifier("media.upload.speed")}
                    };Spacer(minLength:0)
                }.padding(.vertical,6)
            }
            if !uploadErrors.isEmpty {Text("Hay archivos por reintentar. Abre Ver archivos para revisar el detalle.").font(.footnote).foregroundStyle(.red)}
            DisclosureGroup("Ver archivos") {
            ForEach(queue) { file in
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 10) {
                        Image(systemName: completed.contains(file.id) ? "checkmark.circle.fill" : file.mimeType.hasPrefix("video/") ? "video" : "photo").foregroundStyle(completed.contains(file.id) ? .green : JACTheme.action)
                        Text(file.name).font(.subheadline).lineLimit(2); Spacer(minLength: 8)
                        if !uploading { Button { file.remove(); queue.removeAll { $0.id == file.id }; completed.remove(file.id) } label: { Image(systemName: "xmark.circle") }.buttonStyle(.plain).accessibilityLabel("Quitar " + file.name) }
                    }
                    if uploading && !completed.contains(file.id) {Text(progress[file.id] == nil ? "En espera":"Subiendo y confirmando…").font(.caption).foregroundStyle(.secondary)}
                    if let failure = uploadErrors[file.id] { Text(failure).font(.footnote).foregroundStyle(.red) }
                }
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
    #if os(iOS)
    private var persistentUploadPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            TimelineView(.periodic(from: .now, by: 0.5)) { _ in
                let jobs = persistentUploads.jobs
                let total = jobs.reduce(Int64(0)) { $0 + $1.size }
                let sent = jobs.reduce(Double(0)) { $0 + Double($1.size) * ($1.completed ? 1 : $1.progress) }
                let done = jobs.filter(\.completed).count
                let fraction = total > 0 ? min(done == jobs.count ? 1 : 0.99, sent / Double(total)) : 0
                HStack(spacing: 18) {
                    ZStack {
                        Circle().stroke(JACTheme.action.opacity(0.12), lineWidth: 8)
                        Circle().trim(from: 0, to: fraction).stroke(JACTheme.action, style: StrokeStyle(lineWidth: 8, lineCap: .round)).rotationEffect(.degrees(-90))
                        Text("\(Int(fraction * 100))%").font(.title3.bold()).monospacedDigit()
                    }.frame(width: 76, height: 76)
                        .accessibilityElement(children: .ignore).accessibilityLabel("Progreso general de subida").accessibilityValue("\(Int(fraction * 100)) por ciento").accessibilityIdentifier("media.upload.progress")
                    VStack(alignment: .leading, spacing: 5) {
                        Text(persistentUploads.uploading ? "Subiendo al archivo" : done == jobs.count ? "Archivos subidos" : "Subida en pausa").font(.headline)
                        Text("\(done) de \(jobs.count) completados").font(.subheadline).foregroundStyle(.secondary)
                        Text(ByteCountFormatter.string(fromByteCount: Int64(sent), countStyle: .file) + " de " + ByteCountFormatter.string(fromByteCount: total, countStyle: .file)).font(.caption).foregroundStyle(.secondary)
                        if persistentUploads.uploading {
                            let rate = persistentUploads.meter.rate()
                            Text(rate > 0 ? ByteCountFormatter.string(fromByteCount: Int64(rate), countStyle: .file) + "/s" : "Esperando transferencia…").font(.subheadline.bold()).monospacedDigit().foregroundStyle(JACTheme.action).accessibilityIdentifier("media.upload.speed")
                        }
                    }
                    Spacer(minLength: 0)
                }
            }
            if let notice = persistentUploads.notice { Text(notice).font(.footnote).foregroundStyle(.secondary).accessibilityIdentifier("media.queue.status") }
            if persistentUploads.uploading { Text("Puedes seguir usando JAC mientras termina la subida.").font(.footnote).foregroundStyle(.secondary) }
            DisclosureGroup("Ver archivos") {
                ForEach(persistentUploads.jobs) { job in
                    VStack(alignment: .leading, spacing: 5) {
                        HStack(spacing: 10) {
                            Image(systemName: job.completed ? "checkmark.circle.fill" : job.mimeType.hasPrefix("video/") ? "video" : "photo").foregroundStyle(job.completed ? .green : JACTheme.action)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(job.name).font(.subheadline).lineLimit(2)
                                Text(job.destination.name).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            }
                            Spacer(minLength: 8)
                            if !persistentUploads.uploading { Button { persistentUploads.remove(id: job.id) } label: { Image(systemName: "xmark.circle") }.buttonStyle(.plain).accessibilityLabel("Quitar " + job.name).accessibilityIdentifier("media.queue.remove." + job.id) }
                        }
                        if let failure = job.error { Text(failure).font(.footnote).foregroundStyle(.red) }
                        else if !job.completed { ProgressView(value: job.progress).tint(JACTheme.action) }
                    }.accessibilityIdentifier("media.queue.job." + job.id)
                }
            }
            if persistentUploads.uploading {
                Button("Detener subida") { persistentUploads.stop() }.buttonStyle(.bordered).accessibilityIdentifier("media.upload.stop")
            } else if persistentUploads.jobs.contains(where: { !$0.completed || $0.error != nil }) {
                Button("Reintentar pendientes") { persistentUploads.retry() }.buttonStyle(.borderedProminent).disabled(store.isOffline || !user.canUploadMedia).accessibilityIdentifier("media.upload.retry")
            } else {
                Button("Ocultar completados") { for job in persistentUploads.jobs { persistentUploads.remove(id: job.id) } }.buttonStyle(.bordered).accessibilityIdentifier("media.upload.clear")
            }
        }.padding(18).background(JACTheme.card, in: RoundedRectangle(cornerRadius: 18))
    }
    private func refreshAfterUploads() {
        guard galleryVisible, workspaceCanRefresh, uploadRefreshPending, !persistentUploads.uploading else { return }
        uploadRefreshPending = false
        Task { await reload() }
    }
    #endif
    private func discardStagedUploads() {
        #if os(iOS)
        // enqueue owns the staged files only after its durable handoff returns.
        guard !handingOffUploads else { return }
        #endif
        queue.forEach { $0.remove() }; queue = []
    }
    private var workspaceCanRefresh: Bool { isWorkspaceActive && phase == .active }
    private func reload() async {
        guard workspaceCanRefresh, !Task.isCancelled, !uploading, loadingFolder != folderID else { return }
        let expected = UUID(), requestedFolder = folderID; generation = expected
        loading = true; loadingFolder=requestedFolder
        defer { if generation == expected { loading = false;loadingFolder=nil } }
        // A restored copy is available immediately; it does not prove the
        // network is unavailable. Revalidate independently of workspace startup.
        if feed == nil, let saved = store.client.cachedMedia(folder: requestedFolder) {
            feed=saved;items=MediaGalleryOrder.sorted(saved.items)
        }
        do {
            let read = try await MediaGalleryListing.read(minimumPages: loadedPages, minimumItems: items.count) { cursor in
                guard expected == generation, workspaceCanRefresh, !Task.isCancelled else { throw CancellationError() }
                return try await store.client.media(folder: requestedFolder, pageToken: cursor, forceNetwork: true)
            }
            let result = read.feed
            guard expected == generation, requestedFolder == folderID, workspaceCanRefresh, !Task.isCancelled else { return }
            if let previous=feed?.collectionID,previous != result.collectionID {expandedFolders=[];clearPreview()}
            loadedPages = read.pages; feed = result
            if items != result.items { items = result.items }
            thumbnailEpoch=UUID(); error = nil;mediaIsOffline=false
            #if os(iOS)
            selection.reconcile(result)
            thumbnails.start(result, client: store.client, networkAllowed: !store.isOffline, denied: thumbnailDenied)
            #endif
            if !result.canRead || !result.connected { items = []; expandedFolders=[];uploadComposition=nil;clearPreview(); discardStagedUploads() }
            // A live gallery does not grant unrelated financial permissions.
            // Join session revalidation before restoring write controls.
            if store.isOffline { try? await store.refreshAutomatically() }
        } catch {
            guard expected == generation, requestedFolder == folderID, workspaceCanRefresh, !Task.isCancelled else { return }
            if AgendaOfflineCache.isUnavailable(error), let saved = store.client.cachedMedia(folder: requestedFolder) {
                if feed == nil { feed=saved;items=MediaGalleryOrder.sorted(saved.items) }
                mediaIsOffline=true;self.error=nil;return
            }
            if let message = store.reportReadFailure(error) { self.error = message }
            if case APIError.forbidden = error { items = []; feed = nil; expandedFolders=[];uploadComposition=nil;clearPreview() }
            if error is MediaFolderRemoved {
                clearPreview(); expandedFolders=[]
                if notificationFolderID != nil { items=[]; feed=nil }
                else { navigate(to:"") }
            }
        }
    }
    private func open(_ item: MediaItem,in context:MediaFeed?=nil) {
        if item.kind == "folder" { navigate(to: item.id); return }
        if compactGallery,item.kind == "image",let source=context ?? feed {
            let whole=MediaFeed(connected:source.connected,canRead:source.canRead,canUpload:source.canUpload,canConnect:source.canConnect,root:source.root,folder:source.folder,breadcrumbs:source.breadcrumbs,items:context?.items ?? items,nextPageToken:source.nextPageToken,provider:source.provider,collectionID:source.collectionID,canDelete:source.canDelete,pendingDeletions:source.pendingDeletions,deletedFolders:source.deletedFolders,deletedFiles:source.deletedFiles,pendingFileDeletions:source.pendingFileDeletions)
            if layout.isWide { inlinePhotos=MediaPhotoPresentation(selected:item,feed:whole) }
            else { fullscreenPhotos=MediaPhotoPresentation(selected:item,feed:whole) }
            return
        }
        guard opening == nil else { return }; opening = item.id
        openingTask = Task {
            defer { opening = nil; openingTask = nil }
            do {
                let stamp=try store.client.mediaAccessStamp()
                if item.kind == "video", !store.client.usingOfflineCopy {
                    try await store.client.validateMediaItem(item)
                    try Task.checkCancellation()
                    guard stamp == (try store.client.mediaAccessStamp()) else {throw CancellationError()}
                    previewFeed=context
                    preview = MediaPreview(item: item, document: nil, stream: nil)
                } else {
                    let document: ExportedDocument
                    if item.kind == "image" { document = try await store.client.mediaPhotoPreview(item) } else { document = try await store.client.mediaDocument(item) }
                    guard !Task.isCancelled,stamp == (try store.client.mediaAccessStamp()) else {TemporaryDocuments.remove(document);throw CancellationError()}
                    previewFeed=context;previewDocument = document; preview = MediaPreview(item: item, document: document, stream: nil)
                }
            }
            catch { if let message = store.reportReadFailure(error) { self.error = message } }
        }
    }
    private func navigate(to id: String) {
        guard !queue.contains(where: { !completed.contains($0.id) }) else { error = "Sube o quita los archivos seleccionados antes de cambiar de carpeta."; return }
        queue = []; completed = [];uploadDestination=nil; generation = UUID(); folderID = id; loadedPages = 1; feed = nil; items = []
        #if os(iOS)
        selection.reset()
        #endif
    }
    private func clearPreview() { preview?.stream?.cancel(); if let document = previewDocument { TemporaryDocuments.remove(document) }; previewDocument = nil; preview = nil;previewFeed=nil;fullscreenPhotos=nil }
    private func thumbnailDenied(_ failure:Error) {
        #if os(iOS)
        selection.reset(); selectionConfirmation = false; selectionDeletionTargets = []
        #endif
        generation=UUID();loadingFolder=nil;loading=false;expandedFolders=[];openingTask?.cancel();clearPreview()
        if failure is MediaFolderRemoved || failure is MediaFileRemoved {if compactGallery {Task {await reload()}}else{navigate(to:"")};return}
        items=[];feed=nil;discardStagedUploads();uploadDestination=nil;uploadComposition=nil;error=store.reportReadFailure(failure)
    }
    private func readFiles(_ urls: [URL]) async {
        guard writable, !uploading, !importing, let stamp = try? store.client.mediaAccessStamp() else { return }; importing = true; defer { importing = false; importTask = nil }
        for url in urls {
            do {
                let worker = Task.detached(priority: .userInitiated) { try MediaLocalFile.stage(url) }
                let file = try await withTaskCancellationHandler { try await worker.value } onCancel: { worker.cancel() }
                guard !Task.isCancelled, stamp == (try? store.client.mediaAccessStamp()), store.overview?.user.canUploadMedia == true else { file.remove(); return }
                #if os(iOS)
                var prepared = false
                defer { if !prepared { file.remove() } }
                let result = try await MediaVideoPreparation.prepare(file)
                guard !Task.isCancelled, stamp == (try? store.client.mediaAccessStamp()), store.overview?.user.canUploadMedia == true else { if result.file.url != file.url { result.file.remove() }; return }
                if result.file.url != file.url { file.remove() }
                queue.append(result.file); prepared = true
                #else
                queue.append(file)
                #endif
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
                #if os(iOS)
                var prepared = false
                defer { if !prepared { file.staged.remove() } }
                let result = try await MediaVideoPreparation.prepare(file.staged)
                guard !Task.isCancelled, stamp == (try? store.client.mediaAccessStamp()), store.overview?.user.canUploadMedia == true else { if result.file.url != file.staged.url { result.file.remove() }; return }
                if result.file.url != file.staged.url { file.staged.remove() }
                queue.append(result.file); prepared = true
                #else
                queue.append(file.staged)
                #endif
            } catch { self.error = error.localizedDescription }
        }
    }
    private func uploadAll() async {
        #if os(iOS)
        guard writable, !handingOffUploads, let target = uploadDestination, compactGallery || target.id == parentID else { error = "Elige la carpeta del show antes de subir los archivos."; return }
        handingOffUploads = true; error = nil; uploadNotice = nil
        defer {
            handingOffUploads = false; uploadTask = nil
            if !galleryVisible { discardStagedUploads() }
        }
        let files = queue.filter { !completed.contains($0.id) }
        do {
            try await persistentUploads.enqueue(files, destination: target, client: store.client)
            let adopted = Set(files.map(\.id))
            queue.removeAll { adopted.contains($0.id) }; completed = []; progress = [:]; uploadErrors = [:]
            if queue.isEmpty { uploadDestination = nil }
        } catch { if let message = store.reportReadFailure(error) { self.error = message } }
        #else
        guard writable,!uploading,let target=uploadDestination,compactGallery || target.id == parentID else {error="Elige la carpeta del show antes de subir los archivos.";return};uploading = true; error = nil; uploadNotice = nil
        defer {
            if !completed.isEmpty { uploadNotice = "\(completed.count) archivos subidos." }
            queue.removeAll { completed.contains($0.id) }; completed = [];if queue.isEmpty {uploadDestination=nil}
            uploading = false; uploadTask = nil; Task { await reload() }
        }
        let destination = target.id,files=queue.filter{!completed.contains($0.id)}
        uploadMeter=MediaUploadRate();for file in files {progress[file.id]=nil;uploadErrors[file.id]=nil}
        await withTaskGroup(of:Bool.self) {group in
            var iterator=files.makeIterator()
            for _ in 0..<2 {if let file=iterator.next(){group.addTask {@MainActor in await uploadOne(file,destination:destination)}}}
            while let keepGoing=await group.next() {
                if !keepGoing || Task.isCancelled {group.cancelAll();return}
                if let file=iterator.next(){group.addTask {@MainActor in await uploadOne(file,destination:destination)}}
            }
        }
        #endif
    }
    private func uploadOne(_ file:MediaLocalFile,destination:String) async -> Bool {
        guard !Task.isCancelled else{return false}
        do {
            try await store.client.uploadMedia(file,parentID:destination,transferred:{delta in uploadMeter.record(delta)},progress:{sent,total in progress[file.id]=total>0 ? Double(sent)/Double(total):0})
            try Task.checkCancellation();completed.insert(file.id);file.remove();return true
        }catch {
            if error is CancellationError || (error as? URLError)?.code == .cancelled {return false}
            uploadErrors[file.id]=error.localizedDescription;store.report(error)
            if case APIError.unauthorized=error{return false};if case APIError.forbidden=error{return false};return true
        }
    }
}

private struct MediaUploadComposition:Identifiable {
    let id=UUID()
    let root:MediaFolder
    let destination:MediaFolder?
}
private struct MediaPhotoPresentation:Identifiable {
    let id=UUID()
    let selected:MediaItem
    let feed:MediaFeed
}

struct MediaTile: View {
    let item: MediaItem
    @ObservedObject var client: PayrollClient
    let offline: Bool
    let opening: Bool
    let epoch:UUID
    let denied:(Error)->Void
    var selectionValue: String? = nil
    @Environment(\.isWorkspaceActive) private var isWorkspaceActive
    @Environment(\.scenePhase) private var phase
    #if os(iOS)
    @StateObject private var thumbnail = MediaTileThumbnail()
    private var image: UIImage? { thumbnail.image }
    private var thumbnailKey: String {
        "\(item.id)|\(item.modifiedAt)|\(item.size)|\(item.thumbnailAvailable)|\(item.mimeType)|\(client.mediaPresentationRevision)"
    }
    private func showThumbnail() {
        guard isWorkspaceActive, phase == .active else { return }
        let stamp = client.mediaPresentationStamp
        let cached = stamp.flatMap { MediaGridThumbnailLoader.shared.cachedImage(item, client: client, stamp: $0) }
        thumbnail.show(key: thumbnailKey, authorized: {
            stamp != nil && stamp == client.mediaPresentationStamp && client.accessUser?.canReadMedia != false
        }, cached: cached, load: { try await MediaGridThumbnailLoader.shared.image(item, client: client, networkAllowed: !offline) }, denied: denied)
    }
    #else
    @State private var image: JACPlatformImage?
    @State private var loadedRevision:String?
    #endif
    var body: some View {
        VStack(alignment: .leading, spacing: item.kind == "folder" ? 10 : 0) {
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
                if item.kind == "video" { VStack { Spacer(); HStack { Spacer(); Image(systemName: "video.fill").font(.system(size: 13, weight: .semibold)).foregroundStyle(.white).frame(width: 28, height: 28).background(.black.opacity(0.45), in: Circle()).padding(8) } }.accessibilityHidden(true) }
                if opening { ProgressView().padding(12).background(.regularMaterial, in: Capsule()) }
            }.frame(height:item.kind == "folder" ? 84:170).frame(maxWidth:.infinity).clipped().clipShape(RoundedRectangle(cornerRadius:12)).accessibilityIdentifier(image == nil ? "media.placeholder."+item.id:"media.thumbnail."+item.id)
            if item.kind == "folder" { Text(item.name).font(.subheadline.weight(.semibold)).foregroundStyle(JACTheme.ink).lineLimit(2, reservesSpace: true).frame(maxWidth: .infinity, alignment: .leading) }
        }.padding(item.kind == "folder" ? 12 : 0).background(JACTheme.card, in: RoundedRectangle(cornerRadius: 18)).contentShape(Rectangle())
            .accessibilityLabel(item.name)
            .accessibilityValue(selectionValue ?? (image != nil ? "Miniatura cargada" : item.thumbnailAvailable ? "Miniatura pendiente" : "Sin miniatura"))
            #if os(iOS)
            .onAppear { if item.kind != "folder" { showThumbnail() } }
            .onChange(of: isWorkspaceActive && phase == .active) { _, active in
                if active && item.kind != "folder" { showThumbnail() } else { thumbnail.pause() }
            }
            .onChange(of: thumbnailKey) { _, _ in if thumbnail.visible { showThumbnail() } }
            .onChange(of: offline || client.usingOfflineCopy) { _, _ in if thumbnail.visible { showThumbnail() } }
            .onDisappear { thumbnail.hide() }
            #else
            .task(id: item.id + item.modifiedAt + epoch.uuidString + (offline ? "offline":"online")) {
                guard item.kind != "folder",!offline,loadedRevision != item.modifiedAt else{return}
                if loadedRevision != nil {image=nil;loadedRevision=nil}
                do {
                    let data = try await client.mediaThumbnail(item)
                    let thumbnail = MediaThumbnail.image(data)
                    try Task.checkCancellation()
                    if let thumbnail { image = thumbnail; loadedRevision = item.modifiedAt }
                }
                catch {if case APIError.unauthorized = error {denied(error)}else if case APIError.forbidden = error {denied(error)}}
            }.onDisappear {image=nil;loadedRevision=nil}
            #endif
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
    private var matches:[MediaItem] {folders.filter{search.isEmpty || $0.name.localizedCaseInsensitiveContains(search)}}
    var body:some View {
        #if os(macOS)
        macPicker
        #else
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
            }.jacSurface().navigationTitle("¿Dónde quieres subir?").jacInlineTitle().jacSearchable(text:$search,prompt:"Buscar show o fecha")
                .toolbar {ToolbarItem(placement:.cancellationAction) {Button("Cancelar") {dismiss()}}}
                .task {await load()}
                .sheet(isPresented:$creating) {MediaFolderEditor(parentID:root.id,parentName:root.name) {folder in selected(folder);dismiss()}}
        }
        #endif
    }
    #if os(macOS)
    private var macPicker:some View {
        VStack(spacing:0) {
            HStack(alignment:.top,spacing:16) {
                Image(systemName:"square.and.arrow.up").font(.system(size:24,weight:.medium)).foregroundStyle(JACTheme.action)
                    .frame(width:50,height:50).background(JACTheme.action.opacity(0.09),in:RoundedRectangle(cornerRadius:14))
                VStack(alignment:.leading,spacing:5) {
                    Text("Subir fotos y videos").font(.system(size:23,weight:.semibold,design:.rounded)).foregroundStyle(JACTheme.ink)
                    Text("Elige una carpeta para tus archivos.").font(.subheadline).foregroundStyle(.secondary)
                }.frame(maxWidth:.infinity,alignment:.leading)
                Button {dismiss()} label:{Image(systemName:"xmark").font(.system(size:11,weight:.semibold)).frame(width:28,height:28).contentShape(Circle())}.buttonStyle(.plain).foregroundStyle(.secondary).accessibilityLabel("Cerrar").accessibilityIdentifier("media.destination.close")
            }.padding(24)
            Divider()
            VStack(alignment:.leading,spacing:18) {
                Label(root.name,systemImage:"folder").font(.subheadline).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                HStack(spacing:12) {
                    macShortcut(title:"Crear carpeta",subtitle:"Para un nuevo evento o día de trabajo",symbol:"folder.badge.plus",primary:true) {creating=true}.accessibilityIdentifier("media.createFolder").disabled(loading || store.isOffline)
                    macShortcut(title:isRoot ? "Archivo general":"Usar esta carpeta",subtitle:root.name,symbol:"folder.fill",primary:false) {selected(root);dismiss()}.accessibilityIdentifier("media.destination.current")
                }
                HStack(spacing:12) {
                    Text("Carpetas existentes").font(.headline)
                    Spacer(minLength:8)
                    HStack(spacing:7) {
                        Image(systemName:"magnifyingglass").foregroundStyle(.secondary)
                        TextField("Buscar carpeta",text:$search).textFieldStyle(.plain).accessibilityIdentifier("media.destination.search")
                        if !search.isEmpty {Button {search=""} label:{Image(systemName:"xmark.circle.fill").foregroundStyle(.secondary)}.buttonStyle(.plain).accessibilityLabel("Limpiar búsqueda")}
                    }.padding(.horizontal,11).padding(.vertical,9).frame(width:240).background(JACTheme.card,in:RoundedRectangle(cornerRadius:9))
                        .overlay(RoundedRectangle(cornerRadius:9).strokeBorder(Color.secondary.opacity(0.18)))
                }
                if let error {HStack(alignment:.top) {InlineError(message:error);Spacer();Button("Reintentar"){Task{await load()}}}.font(.subheadline)}
                ScrollView {
                    LazyVStack(spacing:6) {
                        if matches.isEmpty && !loading {
                            VStack(spacing:10) {
                                Image(systemName:search.isEmpty ? "folder.badge.plus":"magnifyingglass").font(.system(size:30,weight:.light)).foregroundStyle(JACTheme.action.opacity(0.65))
                                Text(search.isEmpty ? "Tu próximo evento empieza aquí":"No hay carpetas con ese nombre").font(.headline)
                                Text(search.isEmpty ? "Crea una carpeta para organizar sus fotos y videos.":"Prueba con otro nombre.").font(.subheadline).foregroundStyle(.secondary)
                            }.frame(maxWidth:.infinity,minHeight:190).padding(.horizontal,16).multilineTextAlignment(.center).accessibilityIdentifier("media.destination.empty")
                        }
                        ForEach(matches) {folder in
                            Button {selected(MediaFolder(id:folder.id,name:folder.name));dismiss()} label:{
                                HStack(spacing:13) {
                                    Image(systemName:"folder.fill").font(.system(size:20)).foregroundStyle(JACTheme.action).frame(width:40,height:40).background(JACTheme.action.opacity(0.07),in:RoundedRectangle(cornerRadius:10))
                                    Text(folder.name).font(.system(size:14,weight:.medium)).foregroundStyle(JACTheme.ink).lineLimit(2).frame(maxWidth:.infinity,alignment:.leading)
                                    Image(systemName:"chevron.right").font(.system(size:11,weight:.semibold)).foregroundStyle(.tertiary)
                                }.padding(12).frame(maxWidth:.infinity).background(JACTheme.card,in:RoundedRectangle(cornerRadius:12)).contentShape(RoundedRectangle(cornerRadius:12))
                            }.buttonStyle(.plain).accessibilityIdentifier("media.destination."+folder.id)
                        }
                        if !cursor.isEmpty {Button("Cargar más carpetas"){Task{await load(cursor)}}.disabled(loading).padding(8).accessibilityIdentifier("media.destination.more")}
                        if loading {ProgressView("Consultando carpetas…").frame(maxWidth:.infinity).padding(24)}
                    }.padding(1)
                }.frame(maxWidth:.infinity,maxHeight:.infinity).accessibilityIdentifier("media.destination.list")
            }.padding(.horizontal,24).padding(.top,20).padding(.bottom,12)
            Divider()
            HStack {
                Text("Después podrás seleccionar tus fotos y videos.").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Cancelar"){dismiss()}.keyboardShortcut(.cancelAction).controlSize(.large).accessibilityIdentifier("media.destination.cancel")
            }.padding(.horizontal,24).padding(.vertical,16).background(JACTheme.card)
        }.frame(width:680,height:620).background(JACTheme.canvas).privacySensitive()
            .task {await load()}
            .sheet(isPresented:$creating) {MediaFolderEditor(parentID:root.id,parentName:root.name) {folder in selected(folder);dismiss()}}
    }
    private func macShortcut(title:String,subtitle:String,symbol:String,primary:Bool,action:@escaping()->Void)->some View {
        Button(action:action) {
            HStack(alignment:.top,spacing:12) {
                Image(systemName:symbol).font(.system(size:21,weight:.medium)).frame(width:28)
                VStack(alignment:.leading,spacing:5) {Text(title).font(.system(size:15,weight:.semibold));Text(subtitle).font(.system(size:12)).foregroundStyle(primary ? Color.white.opacity(0.83):Color.secondary).lineLimit(2).frame(maxWidth:.infinity,alignment:.leading)}
            }.foregroundStyle(primary ? Color.white:JACTheme.ink).padding(17).frame(maxWidth:.infinity,minHeight:96,alignment:.topLeading)
                .background(primary ? JACTheme.action:JACTheme.card,in:RoundedRectangle(cornerRadius:14))
                .overlay(RoundedRectangle(cornerRadius:14).strokeBorder(primary ? Color.clear:Color.secondary.opacity(0.12))).contentShape(RoundedRectangle(cornerRadius:14))
        }.buttonStyle(.plain)
    }
    #endif
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
        #if os(macOS)
        VStack(alignment:.leading,spacing:22) {
            HStack(spacing:14) {
                Image(systemName:"folder.badge.plus").font(.system(size:25)).foregroundStyle(JACTheme.action).frame(width:48,height:48).background(JACTheme.action.opacity(0.08),in:RoundedRectangle(cornerRadius:13))
                VStack(alignment:.leading,spacing:5) {Text("Crear carpeta").font(.system(size:22,weight:.semibold,design:.rounded));Text(parentName.isEmpty ? "Fotografía JAC":parentName).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)}
            }
            VStack(alignment:.leading,spacing:9) {
                Text("Nombre del evento o día de trabajo").font(.subheadline.weight(.medium))
                TextField("Por ejemplo: Pereira · 18 de octubre",text:$name).textFieldStyle(.roundedBorder).controlSize(.large).accessibilityIdentifier("media.folder.name")
                Text("La carpeta conservará el nombre que escribas.").font(.caption).foregroundStyle(.secondary)
            }.disabled(busy || attempted)
            if let error {InlineError(message:error).fixedSize(horizontal:false,vertical:true)}
            Divider()
            HStack {Spacer();Button("Cancelar"){dismiss()}.keyboardShortcut(.cancelAction).disabled(busy);Button(busy ? "Creando…":"Crear carpeta"){Task{await save()}}.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction).disabled(busy || name.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty || store.isOffline).accessibilityIdentifier("media.folder.save")}.controlSize(.large)
        }.padding(26).frame(width:540).background(JACTheme.canvas).privacySensitive().interactiveDismissDisabled(busy)
        #else
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
        #endif
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
    let client:PayrollClient
    let canDelete:Bool
    private let denied:(Error)->Void
    @StateObject private var photos: MediaPhotoViewer
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var phase
    @State private var player: AVPlayer?
    init(preview: MediaPreview, photos: [MediaItem], feed: MediaFeed?, client: PayrollClient, denied: @escaping (Error)->Void) {
        self.preview=preview;self.client=client;self.denied=denied;self.canDelete=feed?.canDelete == true
        _photos=StateObject(wrappedValue:MediaPhotoViewer(selected:preview.item,document:preview.document,items:photos,token:feed?.nextPageToken ?? "",folderID:feed?.folder?.id ?? "",collectionID:feed?.collectionID,load:{try await client.mediaPhotoPreview($0)},page:{try await client.media(folder:feed?.folder?.id ?? "",pageToken:$0)},denied:denied))
    }
    var body: some View {
        NavigationStack {
            VStack(spacing:0) {
                Group {
                    if let stream = preview.stream { MediaStreamingPlayer(stream: stream) }
                    else if preview.item.kind == "video", preview.document == nil { MediaAdaptivePlaybackView(item: preview.item, client: client, denied: denied) }
                    else if let document = preview.document, preview.item.kind == "video" { MediaNativePlayer(player: player).frame(maxWidth: .infinity, minHeight: 180, maxHeight: .infinity).accessibilityElement(children: .contain).accessibilityIdentifier("media.video").onAppear { player = AVPlayer(url: document.url); player?.play() }.onDisappear { player?.pause(); player = nil } }
                    else if let document = photos.document {
                        #if os(iOS)
                        MediaZoomPhoto(url:document.url,name:photos.selected.name,canPrevious:photos.canPrevious,canNext:photos.canNext,active:phase == .active) {photos.start($0)}
                            .accessibilityIdentifier("media.photo.document")
                        #else
                        DocumentPreview(url: document.url).id(document.url).accessibilityIdentifier("media.photo.document")
                        #endif
                    }
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
            }
            #if os(macOS)
            .simultaneousGesture(DragGesture(minimumDistance:60).onEnded {value in
                guard preview.item.kind=="image",abs(value.translation.width)>abs(value.translation.height)*1.5 else{return}
                photos.start(value.translation.width<0 ? 1 : -1)
            })
            #endif
            .privacySensitive().navigationTitle(preview.item.kind=="image" ? photos.selected.name : preview.item.name).jacInlineTitle()
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Listo") { dismiss() }.accessibilityIdentifier("media.preview.close") };ToolbarItem(placement:.confirmationAction){if preview.item.kind=="image" || preview.item.kind=="video" {MediaPhotoMenu(item:preview.item.kind == "video" ? preview.item : photos.selected,client:client,canDelete:canDelete && client.accessUser?.canDeleteMedia == true).id(photos.selected.id)}} }
        }.onChange(of: phase) { _, value in if value != .active { player?.pause() } }
        .onReceive(client.$cacheRevision) {_ in if let scope=try? client.mediaScope(),client.mediaOffline.isDeleted(photos.selected.id,scope:scope) {photos.stop();dismiss()}}
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
    private var authorization: Task<Void, Never>?
    init(client: PayrollClient, item: MediaItem, playbackURL: URL? = nil) throws {
        guard let stamp = try client.mediaAccessStamp() else { throw APIError.unauthorized }
        self.client = client; self.item = item; self.stamp = stamp
        asset = AVURLAsset(url: playbackURL ?? URL(string: "jac-media://asset/" + UUID().uuidString)!)
        super.init()
        if playbackURL == nil { asset.resourceLoader.setDelegate(self, queue: .main) }
        else { authorization = Task { [weak self] in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .seconds(30))
                    guard let self else { return }; try self.valid(); try await client.validateMediaItem(item)
                } catch {
                    guard let self, !Task.isCancelled else { return }
                    self.error = error.localizedDescription; self.cancel(); return
                }
            }
        } }
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
    func cancel() { authorization?.cancel(); authorization = nil; active = false; requests.values.forEach { $0.cancel() }; requests.removeAll(); blocks.removeAll(); order.removeAll(); asset.cancelLoading() }
}
private struct MediaAdaptivePlaybackView: View {
    let item: MediaItem
    let client: PayrollClient
    let denied: (Error) -> Void
    @State private var stream: MediaVideoStream?
    @State private var preparing = true
    @State private var retry = 0
    @State private var message = "Preparando reproducción adaptativa…"
    var body: some View {
        Group {
            if let stream { MediaStreamingPlayer(stream: stream) }
            else { VStack(spacing: 16) { if preparing { ProgressView() }; Text(message).font(.footnote).multilineTextAlignment(.center); if !preparing { Button("Reintentar") { retry += 1 } } }.padding(24).frame(maxWidth: .infinity, maxHeight: .infinity) }
        }.task(id: retry) {
            preparing = true
            defer { preparing = false }
            let stamp = try? client.mediaAccessStamp()
            for attempt in 0..<8 {
                guard !Task.isCancelled, stamp != nil, stamp == (try? client.mediaAccessStamp()) else { return }
                do {
                    let url = try await client.mediaPlayback(item)
                    try Task.checkCancellation()
                    guard stamp == (try? client.mediaAccessStamp()) else { return }
                    stream = try MediaVideoStream(client: client, item: item, playbackURL: url); return
                } catch {
                    if case APIError.unauthorized = error { denied(error); return }
                    if case APIError.forbidden = error { denied(error); return }
                    if Task.isCancelled { return }; message = error.localizedDescription
                    guard error is MediaPlaybackPending else { return }
                }
                do { try await Task.sleep(for: .seconds(min(30, 4 * (1 << min(attempt, 3))))) } catch { return }
            }
        }.onDisappear { stream?.cancel(); stream = nil }
    }
}
private struct MediaStreamingPlayer: View {
    @ObservedObject var stream: MediaVideoStream
    @Environment(\.scenePhase) private var phase
    @State private var player: AVPlayer?
    var body: some View {
        VStack(spacing: 12) {
            if let error = stream.error { InlineError(message: error) }
            MediaNativePlayer(player: player).frame(maxWidth: .infinity, minHeight: 180, maxHeight: .infinity).accessibilityElement(children: .contain).accessibilityIdentifier("media.video")
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
        var pinnedFiles: [String: MediaItem]?
    }
    let root: URL
    private let lock = NSRecursiveLock()
    private var revoked: Set<String> = []
    private struct CachedIndex {
        let scopeID: String
        let modified: Date
        let size: Int
        let index: Index
    }
    private var cachedIndex: CachedIndex?
    private var previewEpoch: UInt64 = 0
    private var localRemovalEpoch: UInt64 = 0
    var localDownloadEpoch: UInt64 { lock.lock(); defer { lock.unlock() }; return localRemovalEpoch }
    var photoPreviewEpoch: UInt64 { lock.lock(); defer { lock.unlock() }; return previewEpoch }
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
        guard permitted(scope), let attributes = try? indexFile(scope).resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey]),
              let size = attributes.fileSize, size < 64 * 1024 * 1024, let modified = attributes.contentModificationDate else { cachedIndex = nil; return Index() }
        if let saved = cachedIndex, saved.scopeID == scope.id, saved.size == size, saved.modified == modified { return saved.index }
        guard
              let bytes = try? Data(contentsOf: indexFile(scope)), let box = try? AES.GCM.SealedBox(combined: bytes),
              let data = try? AES.GCM.open(box, using: scope.key, authenticating: Data("jac-media-index-v1".utf8)),
              let index = try? JSONDecoder().decode(Index.self, from: data) else { cachedIndex = nil; return Index() }
        cachedIndex = CachedIndex(scopeID: scope.id, modified: modified, size: size, index: index)
        return index
    }
    private func writeIndex(_ index: Index, scope: AgendaCacheScope) throws {
        cachedIndex = nil
        try prepare(scope)
        let data = try JSONEncoder().encode(index)
        guard data.count < 64 * 1024 * 1024 else { throw APIError.message("La lista de archivos supera el tamaño de la copia local.") }
        let sealed = try AES.GCM.seal(data, using: scope.key, authenticating: Data("jac-media-index-v1".utf8)).combined!
        try sealed.write(to: indexFile(scope), options: JACFileSecurity.writeOptions)
        try FileManager.default.setAttributes(JACFileSecurity.fileAttributes, ofItemAtPath: indexFile(scope).path)
        if let modified = try indexFile(scope).resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate {
            cachedIndex = CachedIndex(scopeID: scope.id, modified: modified, size: sealed.count, index: index)
        }
    }
    @discardableResult func saveFeed(_ feed: MediaFeed, key: String, append: Bool, scope: AgendaCacheScope) throws -> MediaFeed {
        lock.lock(); defer { lock.unlock() }
        var index = readIndex(scope), result = feed
        if let previous = index.collectionID, feed.collectionID == nil, previous.hasPrefix("jac-r2-") { throw CancellationError() }
        if index.collectionID != feed.collectionID {
            previewEpoch &+= 1
            // A new collection replaces only this account's encrypted gallery
            // cache. No Drive originals or other modules are touched.
            try? FileManager.default.removeItem(at: folder(scope))
            index = Index(); index.collectionID = feed.collectionID
        }
        if let previous = index.feeds[key], append {
            var seen = Set<String>()
            result = MediaFeed(connected: feed.connected, canRead: feed.canRead, canUpload: feed.canUpload, canConnect: feed.canConnect, root: feed.root, folder: feed.folder, breadcrumbs: feed.breadcrumbs, items: (previous.items + feed.items).filter { seen.insert($0.id).inserted }, nextPageToken: feed.nextPageToken, provider: feed.provider, collectionID: feed.collectionID,canDelete:feed.canDelete,pendingDeletions:feed.pendingDeletions,deletedFolders:feed.deletedFolders,deletedFiles:feed.deletedFiles,pendingFileDeletions:feed.pendingFileDeletions)
        }
        let deletedFiles=Set(index.deletedFiles ?? []).union(feed.deletedFiles ?? [])
        removeThumbnails(deletedFiles.subtracting(index.deletedFiles ?? []), scope: scope)
        for id in deletedFiles {
            if let file=index.files.removeValue(forKey:id) {try? FileManager.default.removeItem(at:encryptedFile(file,scope:scope))}
            index.pinnedFiles?.removeValue(forKey:id);index.previewAccess?.removeValue(forKey:id)
        }
        index.deletedFiles=Array(deletedFiles)
        index.feeds=index.feeds.mapValues{filteredFeed($0,removed:deletedFiles)}
        index.downloads=index.downloads.mapValues{filteredFeed($0,removed:deletedFiles)}
        result=filteredFeed(result,removed:deletedFiles)
        let removed=Set(index.deletedFolders ?? []).union(feed.deletedFolders ?? [])
        if !removed.isEmpty {pruneFolders(removed,index:&index,scope:scope)}
        if result.breadcrumbs.contains(where:{removed.contains($0.id)}) {try writeIndex(index,scope:scope);throw MediaFolderRemoved()}
        result=filteredFeed(result,removed:removed)
        index.feeds[key] = result
        if let id = feed.folder?.id { index.feeds[id] = result }
        try writeIndex(index, scope: scope)
        return filteredFeed(feed,removed:removed.union(deletedFiles))
    }
    private func filteredFeed(_ feed:MediaFeed,removed:Set<String>)->MediaFeed {
        MediaFeed(connected:feed.connected,canRead:feed.canRead,canUpload:feed.canUpload,canConnect:feed.canConnect,root:feed.root,folder:feed.folder,breadcrumbs:feed.breadcrumbs,items:feed.items.filter{!removed.contains($0.id)},nextPageToken:feed.nextPageToken,provider:feed.provider,collectionID:feed.collectionID,canDelete:feed.canDelete,pendingDeletions:feed.pendingDeletions,deletedFolders:feed.deletedFolders,deletedFiles:feed.deletedFiles,pendingFileDeletions:feed.pendingFileDeletions)
    }
    private func pruneFolders(_ removed:Set<String>,index:inout Index,scope:AgendaCacheScope) {
        let feeds=Array(index.feeds.values)+Array(index.downloads.values)
        let affected=feeds.filter {feed in removed.contains(feed.folder?.id ?? "") || feed.breadcrumbs.contains{removed.contains($0.id)}}
        let fileIDs=Set(index.deletedFiles ?? []).union(affected.flatMap{$0.items.filter{$0.kind != "folder"}.map(\.id)})
        removeThumbnails(fileIDs.subtracting(index.deletedFiles ?? []), scope: scope)
        for id in fileIDs {if let item=index.files.removeValue(forKey:id){try? FileManager.default.removeItem(at:encryptedFile(item,scope:scope))};index.previewAccess?.removeValue(forKey:id);index.pinnedFiles?.removeValue(forKey:id)}
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
        return MediaFeed(connected: saved.connected, canRead: saved.canRead, canUpload: false, canConnect: false, root: saved.root, folder: saved.folder, breadcrumbs: saved.breadcrumbs, items: saved.items, nextPageToken: nil, provider: saved.provider, collectionID: saved.collectionID, deletedFolders: index.deletedFolders, deletedFiles: index.deletedFiles)
    }
    func pinFeed(_ feed: MediaFeed, key: String, scope: AgendaCacheScope) throws {
        lock.lock(); defer { lock.unlock() }
        var index = readIndex(scope)
        guard index.collectionID == feed.collectionID else { throw CancellationError() }
        let removed=Set(index.deletedFolders ?? [])
        guard !feed.breadcrumbs.contains(where:{removed.contains($0.id)}) else{throw MediaFolderRemoved()}
        let clean=filteredFeed(feed,removed:removed.union(index.deletedFiles ?? []))
        index.downloads[key] = clean
        if let id = feed.folder?.id { index.downloads[id] = clean }
        try writeIndex(index, scope: scope)
    }
    func pinFile(_ item:MediaItem,scope:AgendaCacheScope) throws {
        lock.lock();defer{lock.unlock()}
        var index=readIndex(scope)
        guard hasFile(item,scope:scope),!(index.deletedFiles ?? []).contains(item.id),!revoked.contains(scope.id) else {throw MediaFileRemoved()}
        index.pinnedFiles=(index.pinnedFiles ?? [:]).merging([item.id:item]){_,new in new}
        index.previewAccess?.removeValue(forKey:item.id)
        try writeIndex(index,scope:scope)
    }
    // Explicitly remove a local audio download while allowing it to be saved again.
    // Server deletion continues to use removeFile and its revocation tombstone.
    func allowBackgroundAudio(_ scope: AgendaCacheScope) throws {
        #if os(iOS)
        lock.lock(); defer { lock.unlock() }
        guard !revoked.contains(scope.id) else { throw CancellationError() }
        let attributes: [FileAttributeKey: Any] = [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication]
        try FileManager.default.setAttributes(attributes, ofItemAtPath: root.path)
        try FileManager.default.setAttributes(attributes, ofItemAtPath: folder(scope).path)
        if let enumerator = FileManager.default.enumerator(at: folder(scope), includingPropertiesForKeys: nil) {
            for case let url as URL in enumerator { try FileManager.default.setAttributes(attributes, ofItemAtPath: url.path) }
        }
        #endif
    }
    func forgetLocalFile(_ item: MediaItem, scope: AgendaCacheScope) throws {
        lock.lock(); defer { lock.unlock() }
        guard !revoked.contains(scope.id) else { throw CancellationError() }
        var index = readIndex(scope)
        index.files.removeValue(forKey: item.id); index.pinnedFiles?.removeValue(forKey: item.id)
        index.previewAccess?.removeValue(forKey: item.id)
        try? FileManager.default.removeItem(at: encryptedFile(item, scope: scope))
        try writeIndex(index, scope: scope)
    }
    // Local removal has no server tombstone. Keep gallery metadata so the
    // original remains visible and can be downloaded again, including offline.
    func localFolderIDs(scope: AgendaCacheScope) -> Set<String> {
        lock.lock(); defer { lock.unlock() }
        JACPerformanceDiagnostics.record(.diskRead)
        guard !revoked.contains(scope.id) else { return [] }
        let index = readIndex(scope)
        let feeds = Array(index.feeds.values) + Array(index.downloads.values)
        return Set(feeds.filter { feed in feed.items.contains { index.files[$0.id] != nil } }
            .flatMap { feed in feed.breadcrumbs.map(\.id) + [feed.folder?.id ?? feed.root?.id ?? ""] }.filter { !$0.isEmpty })
    }
    @discardableResult func forgetLocalFolder(_ id: String, scope: AgendaCacheScope) throws -> Int64 {
        lock.lock(); defer { lock.unlock() }
        try Task.checkCancellation()
        guard !revoked.contains(scope.id) else { throw CancellationError() }
        var index = readIndex(scope)
        func belongs(_ feed: MediaFeed) -> Bool { feed.folder?.id == id || feed.root?.id == id && feed.folder == nil || feed.breadcrumbs.contains { $0.id == id } }
        let affected = (Array(index.feeds.values) + Array(index.downloads.values)).filter(belongs)
        let ids = Set(affected.flatMap { $0.items.filter { $0.kind != "folder" }.map(\.id) })
        localRemovalEpoch &+= 1
        var removed: Int64 = 0
        for fileID in ids {
            if let item = index.files[fileID] {
                let url = encryptedFile(item, scope: scope)
                if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url); removed += item.size }
                index.files.removeValue(forKey: fileID)
            }
            index.pinnedFiles?.removeValue(forKey: fileID)
            index.previewAccess?.removeValue(forKey: fileID)
        }
        index.downloads = index.downloads.filter { !belongs($0.value) }
        try writeIndex(index, scope: scope)
        return removed
    }
    func isDeleted(_ id:String,scope:AgendaCacheScope) -> Bool {
        lock.lock();defer{lock.unlock()};return (readIndex(scope).deletedFiles ?? []).contains(id)
    }
    func isPinned(_ item:MediaItem,scope:AgendaCacheScope) -> Bool {
        lock.lock();defer{lock.unlock()}
        // The pin probe inspects encrypted-index metadata and file existence.
        // Count the real cache entry point so tests detect a move to MainActor.
        JACPerformanceDiagnostics.record(.diskRead)
        return hasFile(item,scope:scope) && (readIndex(scope).pinnedFiles?[item.id] != nil || readIndex(scope).downloads.values.contains{$0.items.contains{$0.id==item.id}})
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
    func removeFile(_ item: MediaItem, scope: AgendaCacheScope) throws {
        lock.lock(); defer { lock.unlock() }
        guard !revoked.contains(scope.id) else { return }
        var index = readIndex(scope)
        index.files.removeValue(forKey: item.id); index.previewAccess?.removeValue(forKey: item.id);index.pinnedFiles?.removeValue(forKey:item.id)
        removeThumbnails([item.id], scope: scope)
        index.deletedFiles = Array(Set(index.deletedFiles ?? []).union([item.id]))
        func withoutFile(_ feed: MediaFeed) -> MediaFeed {
            MediaFeed(connected: feed.connected, canRead: feed.canRead, canUpload: feed.canUpload,
                      canConnect: feed.canConnect, root: feed.root, folder: feed.folder,
                      breadcrumbs: feed.breadcrumbs, items: feed.items.filter { $0.id != item.id },
                      nextPageToken: feed.nextPageToken, provider: feed.provider,
                      collectionID: feed.collectionID, canDelete: feed.canDelete,
                      pendingDeletions: feed.pendingDeletions, deletedFolders: feed.deletedFolders,deletedFiles:feed.deletedFiles,pendingFileDeletions:feed.pendingFileDeletions)
        }
        index.feeds = index.feeds.mapValues(withoutFile)
        index.downloads = index.downloads.mapValues(withoutFile)
        try? FileManager.default.removeItem(at: encryptedFile(item, scope: scope))
        do { try writeIndex(index, scope: scope) }
        catch { clear(scope); throw error }
    }
    // Temporary JPEGs have their own bounded, encrypted store. They are never
    // registered as downloaded originals or exported to Photos.
    private func thumbnailURL(_ item: MediaItem, scope: AgendaCacheScope) -> URL {
        let identity = Data("thumbnail-v1|\(item.id)|\(item.modifiedAt)|\(item.size)|\(item.mimeType)".utf8)
        let name = SHA256.hash(data: identity).map { String(format: "%02x", $0) }.joined()
        return folder(scope).appendingPathComponent("thumbnails", isDirectory: true).appendingPathComponent(thumbnailPrefix(item.id) + name + ".sealed")
    }
    private func thumbnailPrefix(_ id: String) -> String { SHA256.hash(data: Data(id.utf8)).map { String(format: "%02x", $0) }.joined() + "-" }
    private func removeThumbnails(_ ids: Set<String>, scope: AgendaCacheScope) {
        guard !ids.isEmpty else { return }
        previewEpoch &+= 1
        let prefixes = Set(ids.map { thumbnailPrefix($0) })
        for directory in ["thumbnails", "photo-previews"] {
            let files = (try? FileManager.default.contentsOfDirectory(at: folder(scope).appendingPathComponent(directory, isDirectory: true), includingPropertiesForKeys: nil)) ?? []
            for file in files where prefixes.contains(String(file.lastPathComponent.prefix(65))) { try? FileManager.default.removeItem(at: file) }
        }
    }
    func loadThumbnail(_ item: MediaItem, scope: AgendaCacheScope, now: Date = Date()) -> Data? {
        lock.lock(); defer { lock.unlock() }
        guard !revoked.contains(scope.id) else { return nil }
        let url = thumbnailURL(item, scope: scope)
        guard let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey]),
              let date = values.contentModificationDate, now.timeIntervalSince(date) < 48 * 3600,
              let size = values.fileSize, size <= 512 * 1024 + 64,
              let sealed = try? Data(contentsOf: url), let box = try? AES.GCM.SealedBox(combined: sealed),
              let data = try? AES.GCM.open(box, using: scope.key, authenticating: associated(item, scope: scope, block: -1)),
              !data.isEmpty, data.count <= 512 * 1024 else { try? FileManager.default.removeItem(at: url); return nil }
        try? FileManager.default.setAttributes([.modificationDate: now], ofItemAtPath: url.path)
        return data
    }
    private var thumbnailWrites: [String: Int] = [:]
    func saveThumbnail(_ data: Data, item: MediaItem, scope: AgendaCacheScope, now: Date = Date()) throws {
        lock.lock(); defer { lock.unlock() }
        try prepare(scope)
        guard !data.isEmpty, data.count <= 512 * 1024, !(readIndex(scope).deletedFiles ?? []).contains(item.id) else { throw CancellationError() }
        let url = thumbnailURL(item, scope: scope), directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: JACFileSecurity.directoryAttributes)
        let sealed = try AES.GCM.seal(data, using: scope.key, authenticating: associated(item, scope: scope, block: -1)).combined!
        try sealed.write(to: url, options: JACFileSecurity.writeOptions)
        try FileManager.default.setAttributes(JACFileSecurity.fileAttributes.merging([.modificationDate: now]) { _, value in value }, ofItemAtPath: url.path)
        thumbnailWrites[scope.id, default: 0] += 1
        if thumbnailWrites[scope.id] == 1 || thumbnailWrites[scope.id, default: 0] % 32 == 0 {
            let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey])) ?? []
            var saved: [(URL, Int, Date)] = []
            for file in files {
                guard let values = try? file.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey]), let date = values.contentModificationDate else { continue }
                if now.timeIntervalSince(date) >= 48 * 3600 { try? FileManager.default.removeItem(at: file) }
                else { saved.append((file, values.fileSize ?? 0, date)) }
            }
            var bytes = saved.reduce(0) { $0 + $1.1 }, count = saved.count
            for file in saved.sorted(by: { $0.2 < $1.2 }) where bytes > 128 * 1024 * 1024 || count > 4096 {
                try? FileManager.default.removeItem(at: file.0); bytes -= file.1; count -= 1
            }
        }
    }
    func photoPreviewCollection(scope: AgendaCacheScope) -> String? {
        lock.lock(); defer { lock.unlock() }; return readIndex(scope).collectionID
    }
    struct PhotoPreviewSnapshot: Sendable {
        let data: Data?
        let quality: MediaPhotoPreviewQuality
        let collectionID: String?
        let epoch: UInt64
    }
    func photoPreviewSnapshot(_ item: MediaItem, quality: MediaPhotoPreviewQuality, allowBalanced: Bool,
                              scope: AgendaCacheScope) -> PhotoPreviewSnapshot {
        lock.lock(); defer { lock.unlock() }
        let collection = readIndex(scope).collectionID
        if let data = loadPhotoPreview(item, quality: .detail, scope: scope) {
            return PhotoPreviewSnapshot(data: data, quality: .detail, collectionID: collection, epoch: previewEpoch)
        }
        return PhotoPreviewSnapshot(data: quality == .balanced || allowBalanced ? loadPhotoPreview(item, quality: .balanced, scope: scope) : nil,
                                    quality: .balanced, collectionID: collection, epoch: previewEpoch)
    }
    private func photoPreviewIdentity(_ item: MediaItem, quality: MediaPhotoPreviewQuality, scope: AgendaCacheScope) -> Data {
        Data("jac-photo-preview-v1|\(scope.id)|\(item.id)|\(item.modifiedAt)|\(item.size)|\(item.mimeType)|\(quality.rawValue)".utf8)
    }
    private func photoPreviewURL(_ item: MediaItem, quality: MediaPhotoPreviewQuality, scope: AgendaCacheScope) -> URL {
        let digest = SHA256.hash(data: photoPreviewIdentity(item, quality: quality, scope: scope)).map { String(format: "%02x", $0) }.joined()
        return folder(scope).appendingPathComponent("photo-previews", isDirectory: true).appendingPathComponent(thumbnailPrefix(item.id) + digest + ".sealed")
    }
    func loadPhotoPreview(_ item: MediaItem, quality: MediaPhotoPreviewQuality, scope: AgendaCacheScope, now: Date = Date()) -> Data? {
        lock.lock(); defer { lock.unlock() }
        guard !revoked.contains(scope.id), !(readIndex(scope).deletedFiles ?? []).contains(item.id) else { return nil }
        let url = photoPreviewURL(item, quality: quality, scope: scope)
        guard let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey]),
              let date = values.contentModificationDate, now.timeIntervalSince(date) < 48 * 3600,
              let size = values.fileSize, size <= quality.maximumBytes + 64,
              let bytes = try? Data(contentsOf: url), let sealed = try? AES.GCM.SealedBox(combined: bytes),
              let data = try? AES.GCM.open(sealed, using: scope.key, authenticating: photoPreviewIdentity(item, quality: quality, scope: scope)),
              !data.isEmpty, data.count <= quality.maximumBytes else { try? FileManager.default.removeItem(at: url); return nil }
        if now.timeIntervalSince(date) >= 30 { try? FileManager.default.setAttributes([.modificationDate: now], ofItemAtPath: url.path) }
        return data
    }
    func savePhotoPreview(_ data: Data, item: MediaItem, quality: MediaPhotoPreviewQuality, scope: AgendaCacheScope,
                          collectionID: String?, now: Date = Date()) throws {
        lock.lock(); defer { lock.unlock() }
        try Task.checkCancellation()
        let index = readIndex(scope)
        guard !revoked.contains(scope.id), index.collectionID == collectionID,
              !(index.deletedFiles ?? []).contains(item.id), !data.isEmpty, data.count <= quality.maximumBytes else { throw CancellationError() }
        try prepare(scope)
        let url = photoPreviewURL(item, quality: quality, scope: scope), directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: JACFileSecurity.directoryAttributes)
        let bytes = try AES.GCM.seal(data, using: scope.key, authenticating: photoPreviewIdentity(item, quality: quality, scope: scope)).combined!
        try bytes.write(to: url, options: JACFileSecurity.writeOptions)
        try FileManager.default.setAttributes(JACFileSecurity.fileAttributes.merging([.modificationDate: now]) { _, new in new }, ofItemAtPath: url.path)
        // A separate LRU budget never evicts a manually downloaded original.
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey])) ?? []
        var kept: [(URL, Int, Date)] = []
        for file in files {
            guard let values = try? file.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey]), let date = values.contentModificationDate else { continue }
            if now.timeIntervalSince(date) >= 48 * 3600 { try? FileManager.default.removeItem(at: file) }
            else { kept.append((file, values.fileSize ?? 0, date)) }
        }
        var total = kept.reduce(0) { $0 + $1.1 }, count = kept.count
        for file in kept.sorted(by: { $0.2 < $1.2 }) where total > 96 * 1024 * 1024 || count > 2048 {
            try? FileManager.default.removeItem(at: file.0); total -= file.1; count -= 1
        }
    }
    private func associated(_ item: MediaItem, scope: AgendaCacheScope, block: Int) -> Data { Data("jac-media-v1|\(scope.id)|\(item.id)|\(item.modifiedAt)|\(item.size)|\(block)".utf8) }
    private func length(_ value: Int) -> Data { var size = UInt32(value).bigEndian; return withUnsafeBytes(of: &size) { Data($0) } }
    private func readExactly(_ handle: FileHandle, count: Int) throws -> Data {
        var result = Data()
        while result.count < count { guard let next = try handle.read(upToCount: count - result.count), !next.isEmpty else { throw APIError.invalid("La copia del archivo está incompleta. Vuelve a descargarlo.") }; result.append(next) }
        return result
    }
    func saveFile(_ source: URL, item: MediaItem, scope: AgendaCacheScope, preview: Bool = false, expectedLocalEpoch: UInt64? = nil) throws {
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
        guard !revoked.contains(scope.id), expectedLocalEpoch == nil || expectedLocalEpoch == localRemovalEpoch else { throw CancellationError() }
        let current = readIndex(scope)
        guard !(current.deletedFiles ?? []).contains(item.id) else {throw MediaFolderRemoved()}
        guard current.collectionID?.hasPrefix("jac-r2-") != true || item.id.hasPrefix("r2_") else { throw CancellationError() }
        if FileManager.default.fileExists(atPath: destination.path) { try FileManager.default.removeItem(at: destination) }
        try FileManager.default.moveItem(at: partial, to: destination)
        var index = readIndex(scope); index.files[item.id] = item
        if preview { index.previewAccess = (index.previewAccess ?? [:]).merging([item.id: Date().timeIntervalSince1970]) { _, new in new } }
        else { index.previewAccess?.removeValue(forKey: item.id) }
        let pinned = Set(index.downloads.values.flatMap { $0.items.map(\.id) }).union(index.pinnedFiles?.keys.map{$0} ?? [])
        var automatic = (index.previewAccess ?? [:]).filter { !pinned.contains($0.key) }
        var total = automatic.keys.reduce(Int64(0)) { $0 + (index.files[$1]?.size ?? 0) }
        for id in automatic.sorted(by: { $0.value < $1.value }).map(\.key) where total > 128 * 1024 * 1024 {
            if let old = index.files.removeValue(forKey: id) { total -= old.size; try? FileManager.default.removeItem(at: encryptedFile(old, scope: scope)) }
            automatic.removeValue(forKey: id); index.previewAccess?.removeValue(forKey: id)
        }
        try writeIndex(index, scope: scope)
    }
    func document(_ item: MediaItem, scope: AgendaCacheScope, accessedAt: TimeInterval = Date().timeIntervalSince1970, backgroundAudio: Bool = false) throws -> ExportedDocument? {
        var directoryAttributes = JACFileSecurity.directoryAttributes, fileAttributes = JACFileSecurity.fileAttributes
        #if os(iOS)
        if backgroundAudio { directoryAttributes[.protectionKey] = FileProtectionType.completeUntilFirstUserAuthentication; fileAttributes[.protectionKey] = FileProtectionType.completeUntilFirstUserAuthentication }
        #endif
        guard hasFile(item, scope: scope) else { return nil }
        let id = UUID(), destinationFolder = (backgroundAudio ? MusicPlaybackDocuments.root : TemporaryDocuments.root).appendingPathComponent(id.uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: destinationFolder, withIntermediateDirectories: true, attributes: directoryAttributes)
        let destination = destinationFolder.appendingPathComponent(MediaLocalFile.safeName(item.name))
        do {
            guard FileManager.default.createFile(atPath: destination.path, contents: nil, attributes: fileAttributes) else { throw APIError.message("No se pudo abrir la copia guardada.") }
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
            try finishRead(item, scope: scope, accessedAt: accessedAt)
            return ExportedDocument(id: id, url: destination)
        } catch { try? FileManager.default.removeItem(at: destinationFolder); if !(error is CancellationError) { invalidateFile(item, scope: scope) }; throw error }
    }
    private func finishRead(_ item: MediaItem, scope: AgendaCacheScope, accessedAt: TimeInterval) throws {
        lock.lock(); defer { lock.unlock() }
        // A folder deletion or collection change may finish while a file is
        // being decrypted. Never expose that now-retired plaintext document.
        guard !revoked.contains(scope.id) else { throw CancellationError() }
        var index = readIndex(scope)
        guard let saved = index.files[item.id], saved.modifiedAt == item.modifiedAt,
              saved.size == item.size, saved.mimeType == item.mimeType,
              !(index.deletedFiles ?? []).contains(item.id) else { throw CancellationError() }
        let pinned = index.pinnedFiles?[item.id] != nil || index.downloads.values.contains { $0.items.contains { $0.id == item.id } }
        if !pinned, let previous = index.previewAccess?[item.id], accessedAt - previous >= 30 {
            index.previewAccess?[item.id] = accessedAt
            // Recency is best effort: a full disk must not prevent opening an
            // already verified copy. The previous bounded index remains valid.
            try? writeIndex(index, scope: scope)
        }
    }
    func clear(_ scope: AgendaCacheScope) {
        lock.lock(); defer { lock.unlock() }; revoked.insert(scope.id)
        previewEpoch &+= 1
        if cachedIndex?.scopeID == scope.id { cachedIndex = nil }
        try? FileManager.default.removeItem(at: folder(scope))
    }
    func removeOtherSessions(_ scope: AgendaCacheScope) {
        lock.lock(); defer { lock.unlock() }
        if cachedIndex?.scopeID != scope.id { cachedIndex = nil }
        for url in (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? [] where url.lastPathComponent != scope.id {
            revoked.insert(url.lastPathComponent); try? FileManager.default.removeItem(at: url)
        }
    }
}

struct MediaUploadRate {
    private var samples:[(time:TimeInterval,bytes:Int64)]=[]
    mutating func record(_ bytes:Int64,at now:TimeInterval=ProcessInfo.processInfo.systemUptime){
        samples.removeAll{now-$0.time>=4};if bytes>0 {samples.append((now,bytes))}
    }
    func rate(at now:TimeInterval=ProcessInfo.processInfo.systemUptime)->Double {
        let recent=samples.filter{now-$0.time<4};guard let first=recent.first else{return 0}
        return Double(recent.reduce(Int64(0)){$0+$1.bytes})/max(0.5,min(4,now-first.time+0.5))
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
@MainActor enum MediaPhotosExport {
    static func writer(_ client: PayrollClient) -> any MediaPhotosWriting {
        #if DEBUG
        if client.baseURL.host?.hasSuffix(".invalid") == true { return FixtureMediaPhotosWriter() }
        #endif
        return DeviceMediaPhotosWriter()
    }
    static func save(_ item: MediaItem, client: PayrollClient, writer: any MediaPhotosWriting) async throws {
        let stamp = try client.mediaAccessStamp()
        try Task.checkCancellation()
        try await writer.authorize()
        guard !Task.isCancelled, stamp == (try client.mediaAccessStamp()) else { throw CancellationError() }
        let document = try await client.mediaDocument(item)
        defer { TemporaryDocuments.remove(document) }
        guard !Task.isCancelled, stamp == (try client.mediaAccessStamp()) else { throw CancellationError() }
        try await writer.save(document, item: item)
        try Task.checkCancellation()
        guard stamp == (try client.mediaAccessStamp()) else { throw CancellationError() }
    }
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
        let stamp = try? client.mediaAccessStamp()
        task = Task {
            defer { running = false; task = nil }
            guard !Task.isCancelled, stamp != nil, stamp == (try? client.mediaAccessStamp()) else { message = "Operación detenida. Los archivos completados se conservan."; return }
            if photos { do { try await writer.authorize() } catch { failures = [error.localizedDescription];message="No se pudo iniciar el guardado en Fotos. "+error.localizedDescription; return } }
            for item in plan.files {
                do {
                    try Task.checkCancellation()
                    guard stamp != nil, stamp == (try client.mediaAccessStamp()) else { throw CancellationError() }
                    if photos {
                        let document = try await client.mediaDocument(item); defer { TemporaryDocuments.remove(document) }
                        try Task.checkCancellation()
                        guard stamp == (try client.mediaAccessStamp()) else { throw CancellationError() }
                        try await writer.save(document, item: item)
                    } else { try await client.saveMediaOffline(item) }
                    try Task.checkCancellation()
                    guard stamp == (try client.mediaAccessStamp()) else { throw CancellationError() }
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
    var selection = false
    var imagesOnly = false
    var stamp: String? = nil
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
                    if review.imagesOnly { Text("Solo fotos · Sin videos · Incluye subcarpetas").font(.subheadline).accessibilityIdentifier("media.transfer.photosOnly") }
                    LabeledContent("Tamaño total", value: ByteCountFormatter.string(fromByteCount: review.plan.totalBytes, countStyle: .file))
                    LabeledContent("Espacio disponible", value: ByteCountFormatter.string(fromByteCount: MediaStorageReview.freeBytes, countStyle: .file))
                    if review.requiredBytes > MediaStorageReview.freeBytes { Text("No hay espacio suficiente. Se necesitan aproximadamente " + ByteCountFormatter.string(fromByteCount: review.requiredBytes, countStyle: .file) + " libres, incluyendo los archivos temporales.").font(.footnote).foregroundStyle(.red) }
                    Text(review.selection
                         ? (review.photos ? "Se agregarán a Fotos solo las fotos y videos seleccionados, conservando los originales. JAC pedirá permiso para agregar archivos; no leerá tu biblioteca." : "Se guardará una copia privada y cifrada solo de los archivos seleccionados para abrirlos dentro de JAC sin internet. Se elimina al cerrar sesión o al revocarse el acceso.")
                         : (review.photos ? (review.imagesOnly ? "Se agregarán a Fotos únicamente las fotos de esta carpeta y sus subcarpetas. Los videos quedan excluidos. JAC pedirá permiso para agregar archivos; no leerá tu biblioteca." : "Se agregarán a Fotos las fotos y videos de esta carpeta y sus subcarpetas. JAC pedirá permiso para agregar archivos; no leerá tu biblioteca.") : "Se guardará una copia privada y cifrada de esta carpeta y sus subcarpetas para abrirlas dentro de JAC sin internet. Se elimina al cerrar sesión o al revocarse el acceso.")).font(.footnote).foregroundStyle(.secondary)
                }
                Section { Button(review.photos ? "Guardar todos en Fotos" : review.selection ? "Descargar selección" : "Descargar carpeta completa") { begin(); dismiss() }.buttonStyle(JACPrimaryButtonStyle()).disabled(review.plan.files.isEmpty || review.requiredBytes > MediaStorageReview.freeBytes).accessibilityIdentifier("media.transfer.begin") }
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
        try? MediaVideoAudioPlayback.activate()
        let controller = AVPlayerViewController(); controller.player = player; controller.view.accessibilityIdentifier = "media.video"; return controller
    }
    func updateUIViewController(_ controller: AVPlayerViewController, context: Context) { controller.player = player }
    static func dismantleUIViewController(_ controller: AVPlayerViewController, coordinator: ()) { controller.player?.pause(); controller.player = nil; MediaVideoAudioPlayback.deactivate() }
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

#if os(iOS)
// QuickLook owns the pan recognizers inside its preview controller. Keep the
// photo gesture in the same UIKit surface as zoom so a drag on the image itself
// reliably advances, while a magnified photo can still be inspected by panning.
private struct MediaZoomPhoto: UIViewRepresentable {
    let url: URL
    let name: String
    let canPrevious: Bool
    let canNext: Bool
    let active: Bool
    let move: (Int) -> Void
    func makeUIView(context: Context) -> MediaZoomPhotoView { MediaZoomPhotoView() }
    func updateUIView(_ view: MediaZoomPhotoView, context: Context) {
        view.configure(url:url,name:name,canPrevious:canPrevious,canNext:canNext,active:active,move:move)
    }
    static func dismantleUIView(_ view: MediaZoomPhotoView, coordinator: ()) { view.stop() }
}

private final class MediaZoomPhotoView: UIView, UIScrollViewDelegate, UIGestureRecognizerDelegate {
    private let scroll = UIScrollView()
    private let imageView = UIImageView()
    private let spinner = UIActivityIndicatorView(style:.medium)
    private let failure = UILabel()
    private var photoURL: URL?
    private var decodeTask: Task<Void,Never>?
    private var decodeID = UUID()
    private var viewport = CGSize.zero
    private var active = true
    private var canPrevious = false
    private var canNext = false
    private var move: ((Int)->Void)?
    private lazy var photoPan = UIPanGestureRecognizer(target:self,action:#selector(panPhoto(_:)))
    override init(frame: CGRect) {
        super.init(frame:frame)
        backgroundColor = .clear
        clipsToBounds = true
        scroll.delegate = self
        scroll.minimumZoomScale = 1
        scroll.maximumZoomScale = 5
        scroll.bouncesZoom = true
        scroll.showsHorizontalScrollIndicator = false
        scroll.showsVerticalScrollIndicator = false
        scroll.scrollsToTop = false
        scroll.contentInsetAdjustmentBehavior = .never
        imageView.contentMode = .scaleAspectFit
        imageView.isAccessibilityElement = false
        scroll.addSubview(imageView)
        addSubview(scroll)
        spinner.hidesWhenStopped = true
        addSubview(spinner)
        failure.text = "No se pudo mostrar esta imagen."
        failure.font = .preferredFont(forTextStyle:.subheadline)
        failure.textColor = .secondaryLabel
        failure.numberOfLines = 0
        failure.textAlignment = .center
        failure.isHidden = true
        addSubview(failure)
        photoPan.maximumNumberOfTouches = 1
        photoPan.delegate = self
        scroll.addGestureRecognizer(photoPan)
        scroll.panGestureRecognizer.require(toFail:photoPan)
        let doubleTap = UITapGestureRecognizer(target:self,action:#selector(doubleTapPhoto(_:)))
        doubleTap.numberOfTapsRequired = 2
        scroll.addGestureRecognizer(doubleTap)
        isAccessibilityElement = true
        accessibilityTraits = .image
        accessibilityIdentifier = "media.photo.document"
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    func configure(url:URL,name:String,canPrevious:Bool,canNext:Bool,active:Bool,move:@escaping (Int)->Void) {
        self.canPrevious=canPrevious;self.canNext=canNext;self.move=move
        accessibilityLabel=name
        self.active=active
        scroll.isHidden = !active
        spinner.isHidden = !active
        if !active {decodeTask?.cancel();decodeTask=nil;decodeID=UUID();failure.isHidden=true}
        if photoURL != url {
            decodeTask?.cancel();decodeTask=nil;decodeID=UUID();photoURL=url
            scroll.setZoomScale(1,animated:false);imageView.image=nil;viewport = .zero
            failure.isHidden=true
        }
        if active,imageView.image == nil,decodeTask == nil {decode(url)}
        updateAccessibility()
    }
    override func layoutSubviews() {
        super.layoutSubviews()
        let changed = viewport != bounds.size
        scroll.frame=bounds
        spinner.center=CGPoint(x:bounds.midX,y:bounds.midY)
        failure.frame=bounds.insetBy(dx:24,dy:24)
        if changed {fitImage()}
    }
    private func decode(_ url:URL) {
        let expected=UUID();decodeID=expected;spinner.startAnimating();failure.isHidden=true
        decodeTask=Task { [weak self] in
            let work=Task.detached(priority:.userInitiated) { Self.decodedImage(url) }
            let image=await withTaskCancellationHandler {await work.value} onCancel:{work.cancel()}
            guard !Task.isCancelled,let self,self.active,self.decodeID==expected,self.photoURL==url else{return}
            self.decodeTask=nil;self.spinner.stopAnimating();self.imageView.image=image
            self.failure.isHidden = image != nil;self.viewport = .zero;self.setNeedsLayout()
        }
    }
    nonisolated private static func decodedImage(_ url:URL) -> UIImage? {
        // Display decoding never alters the authorized local original. Bound
        // the bitmap (4096 px, at most about 64 MiB) even for very large stills.
        autoreleasepool {
            guard !Task.isCancelled,let source=CGImageSourceCreateWithURL(url as CFURL,[kCGImageSourceShouldCache:false] as CFDictionary),
                  let image=CGImageSourceCreateThumbnailAtIndex(source,0,[kCGImageSourceCreateThumbnailFromImageAlways:true,kCGImageSourceThumbnailMaxPixelSize:4096,kCGImageSourceCreateThumbnailWithTransform:true,kCGImageSourceShouldCacheImmediately:true] as CFDictionary),!Task.isCancelled else{return nil}
            return UIImage(cgImage:image)
        }
    }
    private func fitImage() {
        guard let image=imageView.image,bounds.width>0,bounds.height>0 else{return}
        viewport=bounds.size
        scroll.setZoomScale(1,animated:false)
        let scale=min(bounds.width/image.size.width,bounds.height/image.size.height)
        let size=CGSize(width:image.size.width*scale,height:image.size.height*scale)
        imageView.frame=CGRect(origin:.zero,size:size);scroll.contentSize=size
        centerImage()
        scroll.contentOffset=CGPoint(x:-scroll.contentInset.left,y:-scroll.contentInset.top)
    }
    private func centerImage() {
        scroll.contentInset=UIEdgeInsets(top:max(0,(scroll.bounds.height-scroll.contentSize.height)/2),left:max(0,(scroll.bounds.width-scroll.contentSize.width)/2),bottom:0,right:0)
    }
    func viewForZooming(in scrollView: UIScrollView) -> UIView? { imageView }
    func scrollViewDidZoom(_ scrollView: UIScrollView) {centerImage();updateAccessibility()}
    override func gestureRecognizerShouldBegin(_ recognizer: UIGestureRecognizer) -> Bool {
        guard recognizer === photoPan else{return true}
        guard active,imageView.image != nil,scroll.zoomScale <= scroll.minimumZoomScale+0.01 else{return false}
        let velocity=photoPan.velocity(in:scroll)
        guard abs(velocity.x)>abs(velocity.y)*1.2 else{return false}
        return velocity.x<0 ? canNext:canPrevious
    }
    @objc private func panPhoto(_ recognizer:UIPanGestureRecognizer) {
        guard recognizer.state == .ended,active,scroll.zoomScale <= scroll.minimumZoomScale+0.01 else{return}
        let translation=recognizer.translation(in:scroll),velocity=recognizer.velocity(in:scroll)
        guard abs(translation.x)>abs(translation.y)*1.2,
              abs(translation.x)>=44 || (abs(translation.x)>=14 && abs(velocity.x)>=350) else{return}
        let direction=translation.x<0 ? 1:-1
        guard direction==1 ? canNext:canPrevious else{return}
        move?(direction)
    }
    @objc private func doubleTapPhoto(_ recognizer:UITapGestureRecognizer) {
        guard active,imageView.image != nil else{return}
        if scroll.zoomScale>scroll.minimumZoomScale+0.01 {scroll.setZoomScale(1,animated:true);return}
        let point=recognizer.location(in:imageView),scale:CGFloat=2.5
        let size=CGSize(width:scroll.bounds.width/scale,height:scroll.bounds.height/scale)
        scroll.zoom(to:CGRect(x:point.x-size.width/2,y:point.y-size.height/2,width:size.width,height:size.height),animated:true)
    }
    private func updateAccessibility() {
        accessibilityValue = scroll.zoomScale>1.01 ? "Ampliada":"Tamaño original"
        var actions:[UIAccessibilityCustomAction]=[]
        if canPrevious {actions.append(UIAccessibilityCustomAction(name:"Foto anterior") {[weak self] _ in guard let self,self.active,self.canPrevious else{return false};self.move?(-1);return true})}
        if canNext {actions.append(UIAccessibilityCustomAction(name:"Foto siguiente") {[weak self] _ in guard let self,self.active,self.canNext else{return false};self.move?(1);return true})}
        actions.append(UIAccessibilityCustomAction(name:"Restablecer zoom") {[weak self] _ in guard let self,self.active else{return false};self.scroll.setZoomScale(1,animated:true);return true})
        accessibilityCustomActions=actions
    }
    func stop() {
        active=false;decodeID=UUID();decodeTask?.cancel();decodeTask=nil;move=nil
        scroll.delegate=nil;imageView.image=nil;photoURL=nil;spinner.stopAnimating()
    }
}
#endif
