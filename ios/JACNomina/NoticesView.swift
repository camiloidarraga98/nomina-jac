import SwiftUI
import UniformTypeIdentifiers
import PhotosUI
import UIKit

struct JACNotice: Decodable, Identifiable {
    let id: String; let kind: String; let title: String; let body: String; let filename: String; let size: Int; let createdAt: String; let read: Bool
    var travelDate: String? = nil
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
    var boardingUsers: [NoticeUser]? = nil; var today: String? = nil
}
struct NoticeSettings: Decodable { let version: Int; let slackConnected: Bool; let appleConfigured: Bool; let webPublicKey: String }
struct NoticeUser: Decodable, Identifiable { let id: String; let name: String }

struct NoticesView: View {
    @EnvironmentObject private var store: PayrollStore
    @Environment(\.scenePhase) private var scenePhase
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
    @State private var historyOpen = false
    @State private var history: NoticeFeed?
    @State private var historyRecords: [JACNotice] = []
    @State private var day = BoardingClock.today()
    @State private var boardingCount = 0
    @State private var tomorrowCount = 0
    @State private var boardingDocument: ExportedDocument?
    @State private var previousBoardingDocument: ExportedDocument?
    @State private var openingFile: String?
    @State private var documentGeneration = 0
    private var effectiveKind: String { incomingKind ?? kind }
    var body: some View {
        List {
            if let error { Section { InlineError(message: error); Button("Reintentar") { Task { await refresh() } } } }
            if let notice { Section { Text(notice).foregroundStyle(JACTheme.action) } }
            if loading && feed == nil { ProgressView("Consultando…") }
            if effectiveKind == "itinerary" { Section { NavigationLink { NoticesView(user:user,kind:"boarding_pass") } label: { VStack(alignment:.leading,spacing:6) { Label("Pases de abordar",systemImage:"airplane").font(.headline); Text(boardingCount > 0 ? "Para hoy: \(boardingCount) · Mañana: \(tomorrowCount)" : "Para mañana: \(tomorrowCount) · Próximos días e historial").font(.caption).foregroundStyle(.secondary) } }.accessibilityIdentifier("boarding.open") } }
            if effectiveKind == "boarding_pass" {
                ForEach(BoardingClock.priorityDays(day,hasToday:records.contains { $0.travelDate == day }),id:\.self) { date in
                    Section("Pases de abordar para " + (date == day ? "hoy" : "mañana") + " · \(records.filter { $0.travelDate == date }.count)") { let items=records.filter { $0.travelDate == date }; if items.isEmpty { Text(date == day ? "No tienes pases para hoy." : "No tienes pases para mañana.").foregroundStyle(.secondary) }; boardingRows(items) }
                }
                ForEach(Array(Set(records.compactMap(\.travelDate))).filter { $0 > BoardingClock.nextDay(day) }.sorted(),id:\.self) { date in Section(BoardingClock.label(date)) { boardingRows(records.filter { $0.travelDate == date }) } }
                if let cursor = feed?.nextCursor, !cursor.isEmpty { Section { Button("Ver más próximos pases") { Task { await refresh(cursor) } }.disabled(loading) } }
                Section { Button { historyOpen.toggle() } label: { Label(historyOpen ? "Ocultar historial de pases anteriores" : "Historial de pases anteriores",systemImage:historyOpen ? "chevron.up" : "chevron.down") }.accessibilityIdentifier("boarding.history") }
                if historyOpen { Section("Pases anteriores") { boardingRows(historyRecords.filter { ($0.travelDate ?? "") < day }); if historyRecords.isEmpty { Text("No tienes pases anteriores.").foregroundStyle(.secondary) }; if let cursor=history?.nextCursor,!cursor.isEmpty { Button("Ver más del historial") { Task { await loadHistory(cursor) } } } } }

            } else { Section(effectiveKind == "itinerary" ? "Itinerarios del equipo" : "Avisos del equipo") {
                let items = records.filter { $0.kind == effectiveKind }
                if items.isEmpty && feed != nil { Text(effectiveKind == "itinerary" ? "Todavía no hay itinerarios publicados." : "No tienes alertas en este momento.").foregroundStyle(.secondary) }
                ForEach(items) { item in Button { detail = item } label: { VStack(alignment: .leading, spacing: 7) { Label(item.title, systemImage: item.kind == "itinerary" ? "doc.text" : "bell").font(.headline); Text(item.createdLabel + (!item.files.isEmpty ? " · \(item.files.count) adjunto(s)" : "") + (item.read ? "" : " · Nuevo")).font(.caption).foregroundStyle(.secondary) } }.buttonStyle(.plain).accessibilityIdentifier("notices.item.\(item.id)") }
                if let cursor = feed?.nextCursor, !cursor.isEmpty { Button("Ver anteriores") { Task { await refresh(cursor) } }.disabled(loading) }
            } }

        }.jacSurface().navigationTitle(effectiveKind == "boarding_pass" ? "Pases de abordar" : effectiveKind == "itinerary" ? "Itinerarios" : "Alertas").refreshable { await refresh() }
            .toolbar { if user.isOwner && effectiveKind == "alert" { ToolbarItem(placement: .topBarTrailing) { Button { editor = true } label: { Image(systemName: "plus") }.accessibilityLabel("Crear alerta").accessibilityIdentifier("notices.create").disabled(feed == nil) } } }
            .task { await refresh(); while !Task.isCancelled { do { try await Task.sleep(for:.seconds(30)) } catch { break }; if scenePhase == .active { await refresh() } } }
            .onChange(of:historyOpen) { _,open in if open { Task { await loadHistory() } } }
            .onChange(of: scenePhase) { _, value in if value == .active { Task { await refresh() } } }
            .sheet(item:$boardingDocument,onDismiss:{ if let previousBoardingDocument { TemporaryDocuments.remove(previousBoardingDocument); self.previousBoardingDocument=nil } }) { file in
                NavigationStack { DocumentPreview(url:file.url).privacySensitive().ignoresSafeArea(edges:.bottom).navigationTitle(file.url.pathExtension.lowercased() == "pdf" ? "Pase de abordar PDF" : "Pase de abordar").navigationBarTitleDisplayMode(.inline).toolbar { ToolbarItem(placement:.cancellationAction) { Button("Listo") { boardingDocument=nil }.accessibilityIdentifier("notices.pdf.close") }; ToolbarItem(placement:.confirmationAction) { ShareLink(item:file.url) { Image(systemName:"square.and.arrow.up") }.accessibilityLabel("Compartir archivo") } } }
            }
            .onDisappear { documentGeneration += 1; if let previousBoardingDocument { TemporaryDocuments.remove(previousBoardingDocument); self.previousBoardingDocument=nil } }
            .sheet(item: $detail, onDismiss: { Task { await refresh() } }) { item in NoticeDetail(item: item, owner: user.isOwner) }
            .sheet(isPresented: $editor) { if let feed { NoticeComposer(users: feed.users, boardingUsers: feed.boardingUsers ?? feed.users) { savedKind in incomingKind = savedKind; notice = savedKind == "boarding_pass" ? "Pase publicado únicamente para la persona elegida." : savedKind == "itinerary" ? "Itinerario publicado para todo el equipo." : "Alerta guardada para los destinatarios elegidos."; await refresh() } } }
    }
    @ViewBuilder private func boardingRows(_ items:[JACNotice]) -> some View {
        ForEach(items) { item in ForEach(Array(item.files.enumerated()),id:\.element.id) { index,file in
            Button { Task { await openBoarding(item,file:file) } } label: {
                VStack(alignment:.leading,spacing:7) {
                    let info=BoardingClock.filenameDetails(file.filename)
                    Label(info.map { $0.origin + " → " + $0.destination } ?? item.title,systemImage:"airplane").font(.headline)
                    if let info { Text(info.passenger).font(.subheadline) }
                    Text(file.filename).font(.caption).foregroundStyle(.secondary)
                    HStack { Text(BoardingClock.label(item.travelDate ?? "")).font(.caption).foregroundStyle(.secondary); Spacer(); if openingFile == file.id { ProgressView() }; Text(file.mimeType == "application/pdf" ? "Abrir PDF" : "Abrir imagen").font(.subheadline.bold()) }
                }
            }.buttonStyle(.plain).disabled(openingFile != nil).accessibilityIdentifier(index == 0 ? "notices.item.\(item.id)" : "notices.file.\(file.id)")
        } }
    }
    private func openBoarding(_ item:JACNotice,file:NoticeAttachment) async {
        guard openingFile == nil else { return }; openingFile=file.id; let generation=documentGeneration; defer { openingFile=nil }
        do {
            let result=try await store.client.noticeFile(item,file:file)
            guard generation == documentGeneration else { TemporaryDocuments.remove(result); return }
            previousBoardingDocument=result; boardingDocument=result
            do { try await store.client.noticeCommand(.object(["action":.string("read"),"id":.string(item.id)])) } catch { self.error=store.reportReadFailure(error) }
        } catch { self.error=store.reportReadFailure(error) }
    }
    private func loadHistory(_ cursor:String = "") async { do { let result=try await store.client.notices(cursor:cursor,boarding:"history"); history=result; if cursor.isEmpty { historyRecords=result.notices } else { historyRecords += result.notices.filter { item in !historyRecords.contains { $0.id == item.id } } } } catch { self.error=store.reportReadFailure(error) } }
    private func refresh(_ cursor: String = "") async {
        guard !loading else { return }; loading = true; defer { loading = false }
        do { day = BoardingClock.today(); let result = try await store.client.notices(cursor: cursor, boarding:effectiveKind == "boarding_pass" ? "current" : nil); feed = result; if cursor.isEmpty { records = result.notices } else { records += result.notices.filter { item in !records.contains { $0.id == item.id } } }; error = nil
            if effectiveKind == "itinerary" { let passes = try await store.client.notices(boarding:"current"); boardingCount = passes.notices.filter { $0.travelDate == day }.count; tomorrowCount = passes.notices.filter { $0.travelDate == BoardingClock.nextDay(day) }.count }; if historyOpen { await loadHistory() }
            if !handledInitial, let initialNotice { handledInitial = true; let item: JACNotice; if let found = records.first(where: { $0.id == initialNotice }) { item = found } else { item = try await store.client.notice(id: initialNotice) }; incomingKind = item.kind; if item.kind == "boarding_pass",let first=item.files.first { await openBoarding(item,file:first) } else { detail = item } }
        } catch { self.error = store.reportReadFailure(error) }
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
                if owner && item.kind != "boarding_pass" { Section { Button("Eliminar " + (item.kind == "itinerary" ? "itinerario" : "alerta"), role: .destructive) { confirmingDelete = true }.disabled(deleting || downloading).accessibilityIdentifier("notices.delete") } }
            }.jacSurface().navigationTitle(item.kind == "boarding_pass" ? "Pase de abordar" : item.kind == "itinerary" ? "Itinerario" : "Alerta").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Listo") { dismiss() }.disabled(deleting).accessibilityIdentifier("notices.detail.close") } }
                // Closing the detail also cancels its best-effort read receipt.
                // Do not leave that cancellation in unrelated menus.
                .task { do { try await store.client.noticeCommand(.object(["action": .string("read"), "id": .string(item.id)])) } catch { store.reportReadFailure(error) } }
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
    let boardingUsers: [NoticeUser]
    let onSaved: (String) async -> Void
    @State private var requestID = UUID().uuidString.lowercased()
    @State private var kind = "alert"
    @State private var passOwner = ""
    @State private var travelDate = Date()
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
    init(users: [NoticeUser], boardingUsers: [NoticeUser]? = nil, onSaved: @escaping (String) async -> Void) { self.users = users; self.boardingUsers = boardingUsers ?? users; self.onSaved = onSaved; _recipients = State(initialValue: Set(users.map(\.id))) }
    var body: some View {
        NavigationStack {
            Form {
                if let error { Section { InlineError(message: error) } }
                Group {
                    Section("Publicar como") { Picker("Tipo", selection: $kind) { Text("Alerta").tag("alert"); Text("Itinerario").tag("itinerary"); Text("Pase").tag("boarding_pass") }.pickerStyle(.segmented).accessibilityIdentifier("notices.editor.kind") }
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
                    else if kind == "boarding_pass" { Section("Pase de abordar privado") { Picker("Persona",selection:$passOwner) { Text("Selecciona una persona").tag(""); ForEach(boardingUsers) { Text($0.name).tag($0.id) } }.accessibilityIdentifier("boarding.recipient"); DatePicker("Fecha del pase",selection:$travelDate,displayedComponents:.date).environment(\.timeZone,CalendarClock.calendar.timeZone).accessibilityIdentifier("boarding.date"); Text("Solo la persona elegida podrá abrirlo. Usa Camilo 16 de octubre Pereira-Bogota; puedes incluir el año. El pasajero debe corresponder a la persona elegida. Sin año se usa la fecha más cercana; revisa la fecha antes de publicar.").font(.footnote).foregroundStyle(.secondary) } }
                    else { Section { Text("Se publicará directamente en Itinerarios para todo el equipo activo y enviará el aviso de itinerario nuevo.") } }
                }.disabled(busy || attempted || importing)
                if attempted && !busy && error != nil { Section { Text("Reintenta con estos mismos datos. Para cambiar el contenido, cierra y abre un formulario nuevo.").font(.footnote) } }
                Section { Button(busy ? "Guardando…" : kind == "boarding_pass" ? "Publicar pase y notificar" : kind == "itinerary" ? "Publicar itinerario y notificar" : "Crear alerta y notificar") { Task { await save() } }.buttonStyle(JACPrimaryButtonStyle()).disabled(busy || importing).accessibilityIdentifier("notices.editor.save") }
            }.jacSurface().navigationTitle("Crear alerta o itinerario").navigationBarTitleDisplayMode(.inline).toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() }.disabled(busy) } }
                .fileImporter(isPresented: $picking, allowedContentTypes: [.pdf,.jpeg,.png], allowsMultipleSelection: true) { result in
                    do { let urls = try result.get(); var incoming: [NoticeUpload] = []
                        for url in urls { let access = url.startAccessingSecurityScopedResource(); defer { if access { url.stopAccessingSecurityScopedResource() } }; let size = try url.resourceValues(forKeys:[.fileSizeKey]).fileSize ?? 0; guard size <= 10*1024*1024 else { throw APIError.message("El archivo supera los 10 MB.") }; let data = try Data(contentsOf:url); _ = try NoticeUpload.mime(data); incoming.append(NoticeUpload(filename:url.lastPathComponent,data:data)) }; add(incoming)
                    } catch { self.error = error.localizedDescription }
                }
                .onChange(of: photos) { _, selected in Task { await readPhotos(selected) } }
        }.interactiveDismissDisabled(busy)
    }
    private func add(_ incoming: [NoticeUpload]) { guard !attempted, !busy else { return }; let combined = files + incoming; guard combined.count <= 5, combined.reduce(0, { $0 + $1.data.count }) <= 10*1024*1024 else { error = "Elige hasta 5 archivos que sumen como máximo 10 MB."; return }; files = combined; if let name=incoming.first?.filename,let parsed=BoardingClock.filenameDate(name) { travelDate=parsed }; error = nil }
    private func readPhotos(_ selected: [PhotosPickerItem]) async {
        guard !selected.isEmpty else { return }; importing = true; defer { importing = false }
        do { var incoming: [NoticeUpload] = []; for (index, photo) in selected.enumerated() { guard let data = try await photo.loadTransferable(type:Data.self), data.count <= 10*1024*1024, let image = UIImage(data:data), let jpeg = image.jpegData(compressionQuality:0.9) else { throw APIError.message("No se pudo leer la foto o supera los 10 MB.") }; incoming.append(NoticeUpload(filename:"Foto-\(index+1).jpg",data:jpeg)) }; add(incoming); photos = [] }
        catch { self.error = error.localizedDescription; photos = [] }
    }
    private func save() async {
        guard !busy else { return }; guard !title.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty, title.utf16.count <= 120, message.utf16.count <= 2000, (kind == "boarding_pass" && !passOwner.isEmpty && !files.isEmpty) || kind == "itinerary" || (kind == "alert" && !message.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty && !recipients.isEmpty) else { error = "Revisa el título, mensaje y destinatarios."; return }
        busy = true; attempted = true; defer { busy = false }; error = nil
        do { try await store.client.publishNotice(id:requestID,kind:kind,title:title,body:message,recipients:kind == "boarding_pass" ? [passOwner] : kind == "alert" ? recipients.sorted() : [],files:files,travelDate:kind == "boarding_pass" ? BoardingClock.today(travelDate) : nil); dismiss(); await onSaved(kind) }
        catch { if case APIError.invalid = error { attempted = false }; self.error = error.localizedDescription; store.report(error) }
    }
}


struct BoardingFilenameDetails: Equatable { let passenger:String; let origin:String; let destination:String }
enum BoardingClock {
    static func nextDay(_ day:String) -> String { guard let date=parse(day),let next=CalendarClock.calendar.date(byAdding:.day,value:1,to:date) else { return day }; return today(next) }
    static func priorityDays(_ day:String,hasToday:Bool) -> [String] { hasToday ? [day,nextDay(day)] : [nextDay(day),day] }
    static func filenameDetails(_ name:String) -> BoardingFilenameDetails? {
        let stem=name.replacingOccurrences(of:#"\.(pdf|png|jpe?g)$"#,with:"",options:[.regularExpression,.caseInsensitive]).trimmingCharacters(in:.whitespacesAndNewlines)
        let pattern=#"^(.+?)\s+\d{1,2}\s+de\s+(?:enero|febrero|marzo|abril|mayo|junio|julio|agosto|septiembre|setiembre|octubre|noviembre|diciembre)(?:\s+(?:de\s+)?20\d{2})?\s+(.+?)\s*[-–—]\s*(.+)$"#
        guard filenameDate(name) != nil,let re=try? NSRegularExpression(pattern:pattern,options:.caseInsensitive),let m=re.firstMatch(in:stem,range:NSRange(stem.startIndex...,in:stem)) else { return nil }
        let fields=(1...3).compactMap { i -> String? in guard let r=Range(m.range(at:i),in:stem) else { return nil }; return String(stem[r]).trimmingCharacters(in:.whitespacesAndNewlines) }
        guard fields.count == 3,fields.allSatisfy({ $0.count <= 80 && $0.range(of:#"^[\p{L}][\p{L}\p{M} .’']*$"#,options:.regularExpression) != nil }) else { return nil }
        return BoardingFilenameDetails(passenger:fields[0],origin:fields[1],destination:fields[2])
    }

    static func today(_ date:Date = Date()) -> String { let f=DateFormatter(); f.calendar=Calendar(identifier:.gregorian); f.timeZone=TimeZone(identifier:"America/Bogota"); f.locale=Locale(identifier:"en_US_POSIX"); f.dateFormat="yyyy-MM-dd"; return f.string(from:date) }
    static func label(_ text:String) -> String { guard let date=parse(text) else { return "Fecha no disponible" }; let f=DateFormatter(); f.locale=Locale(identifier:"es_CO"); f.timeZone=TimeZone(identifier:"America/Bogota"); f.dateStyle = .full; return f.string(from:date) }
    static func parse(_ text:String) -> Date? { let f=DateFormatter(); f.calendar=Calendar(identifier:.gregorian); f.timeZone=TimeZone(identifier:"America/Bogota"); f.locale=Locale(identifier:"en_US_POSIX"); f.dateFormat="yyyy-MM-dd"; f.isLenient=false; guard let d=f.date(from:text),today(d)==text else { return nil }; return d }
    static func filenameDate(_ name:String,at:Date=Date()) -> Date? {
        let text=name.folding(options:[.diacriticInsensitive,.caseInsensitive],locale:Locale(identifier:"es_CO")),pattern=#"(?:^|[^\d])(\d{1,2})\s+de\s+(enero|febrero|marzo|abril|mayo|junio|julio|agosto|septiembre|setiembre|octubre|noviembre|diciembre)(?:\s+(?:de\s+)?(20\d{2}))?(?=$|[^a-z0-9])"#
        guard let re=try? NSRegularExpression(pattern:pattern) else { return nil }; let matches=re.matches(in:text,range:NSRange(text.startIndex...,in:text)); guard matches.count==1 else { return nil }; let match=matches[0]
        func group(_ i:Int)->String? { guard let r=Range(match.range(at:i),in:text) else { return nil }; return String(text[r]) }
        let months=["enero","febrero","marzo","abril","mayo","junio","julio","agosto","septiembre","octubre","noviembre","diciembre"]
        guard let day=group(1),let month=group(2),let index=months.firstIndex(of:month=="setiembre" ? "septiembre" : month),let current=Int(today(at).prefix(4)) else { return nil }
        let years=group(3).flatMap(Int.init).map { [$0] } ?? [current-1,current,current+1]
        return years.compactMap { parse(String(format:"%04d-%02d-%02d",$0,index+1,Int(day) ?? 0)) }.sorted { let a=abs($0.timeIntervalSince(at)),b=abs($1.timeIntervalSince(at)); return a == b ? $0 > $1 : a < b }.first
    }
}
