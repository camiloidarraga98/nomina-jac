import SwiftUI
import UniformTypeIdentifiers
import PhotosUI
import UIKit

struct JACNotice: Decodable, Identifiable {
    let id: String; let kind: String; let title: String; let body: String; let filename: String; let size: Int; let createdAt: String; let read: Bool
    var attachments: [NoticeAttachment]? = nil
    var files: [NoticeAttachment] { attachments ?? (filename.isEmpty ? [] : [NoticeAttachment(id: id, filename: filename, mimeType: "application/pdf", size: size)]) }
    var createdLabel: String {
        guard let date = CalendarClock.instant(createdAt) else { return "Fecha no disponible" }
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "es_CO"); formatter.timeZone = CalendarClock.calendar.timeZone
        formatter.dateStyle = .medium; formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}
struct NoticeAttachment: Decodable, Identifiable {
    let id: String; let filename: String; let mimeType: String; let size: Int
}
struct NoticeUpload: Identifiable {
    let id = UUID(); let filename: String; let data: Data
    static func mime(_ data: Data) throws -> String {
        if data.starts(with: Data("%PDF-".utf8)) { return "application/pdf" }
        if data.count > 8 && data.starts(with: Data([137,80,78,71,13,10,26,10])) { return "image/png" }
        if data.count > 3 && data.starts(with: Data([255,216,255])) { return "image/jpeg" }
        throw APIError.message("Solo se admiten archivos PDF, JPG o PNG válidos.")
    }
}
struct NoticeFeed: Decodable {
    let notices: [JACNotice]; let nextCursor: String; let settings: NoticeSettings; let users: [NoticeUser]
}
struct NoticeSettings: Decodable { let version: Int; let slackConnected: Bool; let appleConfigured: Bool; let webPublicKey: String }
struct NoticeUser: Decodable, Identifiable { let id: String; let name: String }

struct NoticesView: View {
    @EnvironmentObject private var store: PayrollStore
    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject private var push = JACNotifications.shared
    let user: PayrollUser
    var kind = "itinerary"
    var initialNotice: String? = nil
    @State private var feed: NoticeFeed?
    @State private var records: [JACNotice] = []
    @State private var error: String?
    @State private var notice: String?
    @State private var detail: JACNotice?
    @State private var editor = false
    @State private var loading = false
    @State private var handledInitial = false
    @State private var incomingKind: String?
    private var effectiveKind: String { incomingKind ?? kind }
    var body: some View {
        List {
            if let error { Section { InlineError(message: error); Button("Reintentar") { Task { await refresh() } } } }
            if let notice { Section { Text(notice).foregroundStyle(JACTheme.action) } }
            Section("Notificaciones") {
                if let message = push.message { Text(message).font(.footnote) }
                Button("Activar en este iPhone") { Task { await push.enable(store.client) } }.accessibilityIdentifier("notices.enable")
                Button("Desactivar en este iPhone") { Task { await push.disable(store.client) } }
                if feed?.settings.appleConfigured == false { Text(user.isOwner ? "Prepara Apple desde Itinerarios → Conexión en el webapp para habilitar los avisos push." : "Camilo está preparando los avisos push del iPhone.").font(.footnote).foregroundStyle(.secondary) }
            }
            if loading && feed == nil { ProgressView("Consultando…") }
            Section(effectiveKind == "itinerary" ? "Itinerarios del equipo" : "Avisos del equipo") {
                let items = records.filter { $0.kind == effectiveKind }
                if items.isEmpty && feed != nil { Text(effectiveKind == "itinerary" ? "Todavía no hay itinerarios publicados." : "No tienes alertas en este momento.").foregroundStyle(.secondary) }
                ForEach(items) { item in Button { detail = item } label: { VStack(alignment: .leading, spacing: 7) { Label(item.title, systemImage: item.kind == "itinerary" ? "doc.text" : "bell").font(.headline); Text(item.createdLabel + (!item.files.isEmpty ? " · \(item.files.count) adjunto(s)" : "") + (item.read ? "" : " · Nuevo")).font(.caption).foregroundStyle(.secondary) } }.buttonStyle(.plain).accessibilityIdentifier("notices.item.\(item.id)") }
                if let cursor = feed?.nextCursor, !cursor.isEmpty { Button("Ver anteriores") { Task { await refresh(cursor) } }.disabled(loading) }
            }
            if effectiveKind == "itinerary", feed?.settings.slackConnected == false { Section { Text(user.isOwner ? "Puedes publicar desde Alertas o conectar Slack en el webapp para recibir los PDF de #itinerarios-finales." : "Camilo está preparando la conexión de itinerarios.").font(.footnote).foregroundStyle(.secondary) } }
        }.jacSurface().navigationTitle(effectiveKind == "itinerary" ? "Itinerarios" : "Alertas").refreshable { await refresh() }
            .toolbar { if user.isOwner && effectiveKind == "alert" { ToolbarItem(placement: .topBarTrailing) { Button { editor = true } label: { Image(systemName: "plus") }.accessibilityLabel("Crear alerta").accessibilityIdentifier("notices.create").disabled(feed == nil) } } }
            .task { await refresh() }
            .onChange(of: scenePhase) { _, value in if value == .active { Task { await refresh() } } }
            .sheet(item: $detail, onDismiss: { Task { await refresh() } }) { item in NoticeDetail(item: item, owner: user.isOwner) }
            .sheet(isPresented: $editor) { if let feed { NoticeComposer(users: feed.users) { savedKind in incomingKind = savedKind; notice = savedKind == "itinerary" ? "Itinerario publicado para todo el equipo." : "Alerta guardada para los destinatarios elegidos."; await refresh() } } }
    }
    private func refresh(_ cursor: String = "") async {
        guard !loading else { return }; loading = true; defer { loading = false }
        do { let result = try await store.client.notices(cursor: cursor); feed = result; if cursor.isEmpty { records = result.notices } else { records += result.notices.filter { item in !records.contains { $0.id == item.id } } }; error = nil
            if !handledInitial, let initialNotice { handledInitial = true; let item: JACNotice; if let found = records.first(where: { $0.id == initialNotice }) { item = found } else { item = try await store.client.notice(id: initialNotice) }; incomingKind = item.kind; detail = item }
        } catch { self.error = error.localizedDescription; store.report(error) }
    }
}

struct NoticeDetail: View {
    @EnvironmentObject private var store: PayrollStore
    @Environment(\.dismiss) private var dismiss
    let item: JACNotice
    var owner = false
    @State private var document: ExportedDocument?
    @State private var previousDocument: ExportedDocument?
    @State private var downloading = false
    @State private var error: String?
    @State private var confirmingDelete = false
    @State private var deleting = false
    var body: some View {
        NavigationStack {
            List {
                Section { Text(item.title).font(.title2.bold()); Text(item.createdLabel).foregroundStyle(.secondary) }
                if let error { Section { InlineError(message: error) } }
                if !item.body.isEmpty { Section { Text(item.body).textSelection(.enabled) } }
                if !item.files.isEmpty { Section("Adjuntos") { ForEach(item.files) { file in
                    VStack(alignment: .leading, spacing: 12) {
                        Text(file.filename).font(.headline); Text("\(max(1,file.size/1024)) KB").font(.caption).foregroundStyle(.secondary)
                        Button { Task { await open(file) } } label: { HStack { Label(file.mimeType == "application/pdf" ? "Abrir PDF" : "Abrir imagen", systemImage: file.mimeType == "application/pdf" ? "doc.text" : "photo"); if downloading { ProgressView() } } }.buttonStyle(JACPrimaryButtonStyle()).disabled(downloading || deleting).accessibilityIdentifier(file.mimeType == "application/pdf" ? "notices.pdf" : "notices.image")
                    }.padding(.vertical, 8)
                } } }
                if owner { Section { Button("Eliminar " + (item.kind == "itinerary" ? "itinerario" : "alerta"), role: .destructive) { confirmingDelete = true }.disabled(deleting || downloading).accessibilityIdentifier("notices.delete") } }
            }.jacSurface().navigationTitle(item.kind == "itinerary" ? "Itinerario" : "Alerta").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Listo") { dismiss() }.disabled(deleting).accessibilityIdentifier("notices.detail.close") } }
                .task { do { try await store.client.noticeCommand(.object(["action": .string("read"), "id": .string(item.id)])) } catch { store.report(error) } }
                .alert("Eliminar " + (item.kind == "itinerary" ? "itinerario" : "alerta"), isPresented: $confirmingDelete) {
                    Button("Cancelar", role: .cancel) {}.accessibilityIdentifier("notices.delete.cancel")
                    Button("Eliminar", role: .destructive) { Task { await remove() } }.accessibilityIdentifier("notices.delete.confirm")
                } message: { Text("¿Eliminar “\(item.title)”? Se retirará para todos sus destinatarios, junto con sus archivos de JAC y entregas pendientes. El original de Slack se conserva. Los avisos ya recibidos no se pueden retirar. Esta acción no se puede deshacer.") }
                .sheet(item: $document, onDismiss: { if let previousDocument { TemporaryDocuments.remove(previousDocument); self.previousDocument = nil } }) { file in
                    NavigationStack { DocumentPreview(url: file.url).privacySensitive().ignoresSafeArea(edges: .bottom).navigationTitle(file.url.pathExtension.lowercased() == "pdf" ? "Itinerario PDF" : "Imagen adjunta").navigationBarTitleDisplayMode(.inline)
                        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Listo") { document = nil }.accessibilityIdentifier("notices.pdf.close") }; ToolbarItem(placement: .confirmationAction) { ShareLink(item: file.url) { Image(systemName: "square.and.arrow.up") }.accessibilityLabel("Compartir archivo") } }
                    }
                }
        }.interactiveDismissDisabled(deleting)
    }
    private func open(_ file: NoticeAttachment) async {
        downloading = true; defer { downloading = false }
        do { let result = item.attachments == nil && item.kind == "itinerary" ? try await store.client.itinerary(item) : try await store.client.noticeFile(item, file: file); previousDocument = result; document = result }
        catch { self.error = error.localizedDescription; store.report(error) }
    }
    private func remove() async {
        guard !deleting else { return }; deleting = true; defer { deleting = false }
        do { try await store.client.deleteNotice(item); dismiss() } catch { self.error = error.localizedDescription; store.report(error) }
    }
}
struct NoticeComposer: View {
    @EnvironmentObject private var store: PayrollStore
    @Environment(\.dismiss) private var dismiss
    let users: [NoticeUser]
    let onSaved: (String) async -> Void
    @State private var requestID = UUID().uuidString.lowercased()
    @State private var kind = "alert"
    @State private var title = ""
    @State private var message = ""
    @State private var recipients: Set<String>
    @State private var files: [NoticeUpload] = []
    @State private var picking = false
    @State private var photos: [PhotosPickerItem] = []
    @State private var busy = false
    @State private var attempted = false
    @State private var importing = false
    @State private var error: String?
    init(users: [NoticeUser], onSaved: @escaping (String) async -> Void) { self.users = users; self.onSaved = onSaved; _recipients = State(initialValue: Set(users.map(\.id))) }
    var body: some View {
        NavigationStack {
            Form {
                if let error { Section { InlineError(message: error) } }
                Group {
                    Section("Publicar como") { Picker("Tipo", selection: $kind) { Text("Alerta").tag("alert"); Text("Itinerario").tag("itinerary") }.pickerStyle(.segmented).accessibilityIdentifier("notices.editor.kind") }
                    Section(kind == "itinerary" ? "Itinerario" : "Alerta") { TextField("Título", text: $title).accessibilityIdentifier("notices.editor.title"); TextField(kind == "itinerary" ? "Mensaje opcional" : "Mensaje", text: $message, axis: .vertical).lineLimit(4...10).accessibilityIdentifier("notices.editor.message") }
                    Section("Adjuntos") {
                        Button("Elegir PDF o imágenes de Archivos") { picking = true }.accessibilityIdentifier("notices.editor.files")
                        PhotosPicker(selection: $photos, maxSelectionCount: 5, matching: .images) { Label("Elegir fotos", systemImage: "photo") }
                        ForEach(files) { file in HStack { Text(file.filename); Spacer(); Button(role: .destructive) { files.removeAll { $0.id == file.id } } label: { Image(systemName: "xmark.circle") }.accessibilityLabel("Quitar " + file.filename) } }
                        Text("Hasta 5 archivos PDF, JPG o PNG; 10 MB en total.").font(.footnote).foregroundStyle(.secondary)
                        #if DEBUG
                        if store.client.baseURL.host?.hasSuffix(".invalid") == true { Button("Adjuntar PDF ficticio") { let data = UIGraphicsPDFRenderer(bounds: CGRect(x:0,y:0,width:200,height:200)).pdfData { context in context.beginPage(); ("PRUEBA JAC" as NSString).draw(at: CGPoint(x:20,y:20), withAttributes:nil) }; add([NoticeUpload(filename:"Prueba.pdf",data:data)]) }.accessibilityIdentifier("notices.editor.fixture") }
                        #endif
                    }
                    if kind == "alert" { Section("Destinatarios") { ForEach(users) { user in Toggle(user.name, isOn: Binding(get: { recipients.contains(user.id) }, set: { value in if value { recipients.insert(user.id) } else { recipients.remove(user.id) } })).accessibilityIdentifier("notices.recipient.\(user.id)") } } }
                    else { Section { Text("Se publicará directamente en Itinerarios para todo el equipo activo y enviará el aviso de itinerario nuevo.") } }
                }.disabled(busy || attempted || importing)
                if attempted && !busy && error != nil { Section { Text("Reintenta con estos mismos datos. Para cambiar el contenido, cierra y abre un formulario nuevo.").font(.footnote) } }
                Section { Button(busy ? "Guardando…" : kind == "itinerary" ? "Publicar itinerario y notificar" : "Crear alerta y notificar") { Task { await save() } }.buttonStyle(JACPrimaryButtonStyle()).disabled(busy || importing).accessibilityIdentifier("notices.editor.save") }
            }.jacSurface().navigationTitle("Crear alerta o itinerario").navigationBarTitleDisplayMode(.inline).toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() }.disabled(busy) } }
                .fileImporter(isPresented: $picking, allowedContentTypes: [.pdf,.jpeg,.png], allowsMultipleSelection: true) { result in
                    do { let urls = try result.get(); var incoming: [NoticeUpload] = []
                        for url in urls { let access = url.startAccessingSecurityScopedResource(); defer { if access { url.stopAccessingSecurityScopedResource() } }; let size = try url.resourceValues(forKeys:[.fileSizeKey]).fileSize ?? 0; guard size <= 10*1024*1024 else { throw APIError.message("El archivo supera los 10 MB.") }; let data = try Data(contentsOf:url); _ = try NoticeUpload.mime(data); incoming.append(NoticeUpload(filename:url.lastPathComponent,data:data)) }; add(incoming)
                    } catch { self.error = error.localizedDescription }
                }
                .onChange(of: photos) { _, selected in Task { await readPhotos(selected) } }
        }.interactiveDismissDisabled(busy)
    }
    private func add(_ incoming: [NoticeUpload]) { guard !attempted, !busy else { return }; let combined = files + incoming; guard combined.count <= 5, combined.reduce(0, { $0 + $1.data.count }) <= 10*1024*1024 else { error = "Elige hasta 5 archivos que sumen como máximo 10 MB."; return }; files = combined; error = nil }
    private func readPhotos(_ selected: [PhotosPickerItem]) async {
        guard !selected.isEmpty else { return }; importing = true; defer { importing = false }
        do { var incoming: [NoticeUpload] = []; for (index, photo) in selected.enumerated() { guard let data = try await photo.loadTransferable(type:Data.self), data.count <= 10*1024*1024, let image = UIImage(data:data), let jpeg = image.jpegData(compressionQuality:0.9) else { throw APIError.message("No se pudo leer la foto o supera los 10 MB.") }; incoming.append(NoticeUpload(filename:"Foto-\(index+1).jpg",data:jpeg)) }; add(incoming); photos = [] }
        catch { self.error = error.localizedDescription; photos = [] }
    }
    private func save() async {
        guard !busy else { return }; guard !title.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty, title.utf16.count <= 120, message.utf16.count <= 2000, kind == "itinerary" || (!message.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty && !recipients.isEmpty) else { error = "Revisa el título, mensaje y destinatarios."; return }
        busy = true; attempted = true; defer { busy = false }; error = nil
        do { try await store.client.publishNotice(id:requestID,kind:kind,title:title,body:message,recipients:kind == "alert" ? recipients.sorted() : [],files:files); dismiss(); await onSaved(kind) }
        catch { if case APIError.invalid = error { attempted = false }; self.error = error.localizedDescription; store.report(error) }
    }
}
