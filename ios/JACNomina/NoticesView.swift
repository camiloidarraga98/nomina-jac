import SwiftUI
import UniformTypeIdentifiers
import PhotosUI
import Vision
import ImageIO
import CryptoKit
#if os(iOS)
import UIKit
import PassKit
#else
import AppKit
#endif

struct JACNotice: Decodable, Identifiable {
    let id: String; let kind: String; let title: String; let body: String; let filename: String; let size: Int; let createdAt: String; let read: Bool
    var revision: Int? = nil; var updatedAt: String? = nil; var changeSummary: String? = nil; var confirmed: Bool? = nil; var receipts: [NoticeReceipt]? = nil
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
struct NoticeReceipt: Decodable, Identifiable { let userId: String; let name: String; let confirmed: Bool; let confirmedAt: String; var id: String { userId } }
struct NoticeAttachment: Decodable, Identifiable {
    let id: String; let filename: String; let mimeType: String; let size: Int
}
struct NoticeUpload: Identifiable {
    let id = UUID(); let filename: String; let data: Data
    static func readLocalFiles(_ urls:[URL]) throws -> [NoticeUpload] {
        guard !urls.isEmpty,urls.count<=5 else{throw APIError.invalid("Elige hasta 5 archivos.")}
        var result:[NoticeUpload]=[],total=0
        for url in urls {
            guard url.isFileURL else{throw APIError.invalid("Arrastra archivos de este Mac, no enlaces web.")}
            let access=url.startAccessingSecurityScopedResource();defer{if access{url.stopAccessingSecurityScopedResource()}}
            let values=try url.resourceValues(forKeys:[.fileSizeKey,.isRegularFileKey])
            guard values.isRegularFile == true,(values.fileSize ?? 0)<=10*1024*1024 else{throw APIError.invalid("Elige un PDF, JPG o PNG de hasta 10 MB.")}
            let bytes=try Data(contentsOf:url);total += bytes.count
            guard total<=10*1024*1024 else{throw APIError.invalid("Los archivos superan los 10 MB en total.")}
            _ = try mime(bytes);result.append(NoticeUpload(filename:url.lastPathComponent,data:bytes))
        }
        return result
    }
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
struct NoticeUser: Decodable, Identifiable { let id: String; let name: String; var ready: Bool? = nil }
struct NoticeRecipientRoster: Decodable {let users:[NoticeUser];let boardingUsers:[NoticeUser]}
enum NoticeRecipientSelection {
    static func reconcile(_ selected:Set<String>,users:[NoticeUser],initialized:Bool,reviewRequired:Bool=false,reviewed:Bool=false) -> (selected:Set<String>,removed:Bool,reviewRequired:Bool) {
        let allowed=Set(users.map(\.id)),removed=initialized && !selected.subtracting(allowed).isEmpty
        return (initialized ? selected.intersection(allowed):allowed,removed,removed || (reviewRequired && !reviewed))
    }
}

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
    @State private var boardingCode: BoardingCodeSelection?
    #if os(iOS)
    @State private var boardingWallet: BoardingCodeSelection?
    #endif
    @State private var fullPassAfterCode: BoardingCodeSelection?
    @State private var previousBoardingDocument: ExportedDocument?
    @State private var openingFile: String?
    @State private var documentGeneration = 0
    @State private var confirmingListDelete = false
    @State private var pendingDelete: JACNotice?
    @State private var deleting = false
    @State private var deletedIDs = Set<String>()
    private var effectiveKind: String { incomingKind ?? kind }
    private var noticeList: some View {
        List {
            if let error { Section { InlineError(message: error); Button("Reintentar") { Task { await refresh() } } } }
            if let notice { Section { Text(notice).foregroundStyle(JACTheme.action) } }
            if loading && feed == nil { ProgressView("Consultando…") }
            if effectiveKind == "itinerary" && user.hasSection(.boarding) {
                Section {
                    NavigationLink { NoticesView(user:user,kind:"boarding_pass") } label: {
                        JACFeatureBanner(eyebrow:"JAC · En ruta",title:"Pases de abordar",subtitle:boardingCount > 0 ? "Para hoy: \(boardingCount) · Mañana: \(tomorrowCount)" : "Para mañana: \(tomorrowCount) · Próximos días e historial",symbol:"airplane",tone:.teal)
                    }.buttonStyle(.plain).accessibilityIdentifier("boarding.open")
                }.jacStandaloneRow()
            }
            if effectiveKind == "alert" && user.isOwner {
                Section {
                    Button { editor = true } label: { Label("Crear alerta o itinerario",systemImage:"plus").frame(maxWidth:.infinity) }
                        .buttonStyle(JACPrimaryButtonStyle()).accessibilityLabel("Crear alerta").accessibilityIdentifier("notices.create").disabled(feed == nil || store.isOffline)
                }.jacStandaloneRow()
            }
            if effectiveKind == "boarding_pass" {
                ForEach(BoardingClock.priorityDays(day,hasToday:records.contains { $0.travelDate == day }),id:\.self) { date in
                    Section("Pases de abordar para " + (date == day ? "hoy" : "mañana") + " · \(records.filter { $0.travelDate == date }.count)") { let items=records.filter { $0.travelDate == date }; if items.isEmpty { Text(date == day ? "No tienes pases para hoy." : "No tienes pases para mañana.").foregroundStyle(.secondary) }; boardingRows(items) }
                }
                ForEach(Array(Set(records.compactMap(\.travelDate))).filter { $0 > BoardingClock.nextDay(day) }.sorted(),id:\.self) { date in Section(BoardingClock.label(date)) { boardingRows(records.filter { $0.travelDate == date }) } }
                if let cursor = feed?.nextCursor, !cursor.isEmpty { Section { Button("Ver más próximos pases") { Task { await refresh(cursor) } }.disabled(loading) } }
                Section { Button { historyOpen.toggle() } label: { Label(historyOpen ? "Ocultar historial de pases anteriores" : "Historial de pases anteriores",systemImage:historyOpen ? "chevron.up" : "chevron.down") }.buttonStyle(JACSecondaryButtonStyle(tone:.teal)).accessibilityIdentifier("boarding.history") }
                if historyOpen { Section("Pases anteriores") { boardingRows(historyRecords.filter { ($0.travelDate ?? "") < day }); if historyRecords.isEmpty { Text("No tienes pases anteriores.").foregroundStyle(.secondary) }; if let cursor=history?.nextCursor,!cursor.isEmpty { Button("Ver más del historial") { Task { await loadHistory(cursor) } } } } }

            } else { Section(effectiveKind == "itinerary" ? "Itinerarios del equipo" : "Avisos del equipo") {
                let items = records.filter { $0.kind == effectiveKind }
                if items.isEmpty && feed != nil { Text(effectiveKind == "itinerary" ? "Todavía no hay itinerarios publicados." : "No tienes alertas en este momento.").foregroundStyle(.secondary) }
                ForEach(items) { item in
                    Button { detail = item } label: { JACNoticeCard(item:item) }
                        .buttonStyle(.plain).accessibilityIdentifier("notices.item.\(item.id)").jacStandaloneRow()
                        .swipeActions(edge:.trailing,allowsFullSwipe:false) { if user.isOwner && item.kind == "itinerary" { deleteButton(item,destructive:false).tint(.red) } }
                        .contextMenu { if user.isOwner && item.kind == "itinerary" { deleteButton(item) } }
                }
                if let cursor = feed?.nextCursor, !cursor.isEmpty { Button("Ver anteriores") { Task { await refresh(cursor) } }.disabled(loading) }
            } }

        }
    }
    private var noticeUpdates: some View {
        noticeList.jacSurface().navigationTitle(effectiveKind == "boarding_pass" ? "Pases de abordar" : effectiveKind == "itinerary" ? "Itinerarios" : "Alertas").jacInlineTitle().refreshable { await refresh() }
            .task { restoreCached(); await refresh(); while !Task.isCancelled { do { try await Task.sleep(for:.seconds(30)) } catch { break }; if scenePhase == .active { await refresh() } } }
            .onChange(of: store.cacheRevision) { _, _ in restoreCached() }
            .onChange(of: store.isOffline) { _, offline in if !offline { Task { await refresh() } } }
            .onChange(of:historyOpen) { _,open in if open { Task { await loadHistory() } } }
            .onChange(of: scenePhase) { _, value in if value == .active { Task { await refresh() } } }
            #if os(iOS)
            .fullScreenCover(item:$boardingCode,onDismiss:openFullPassAfterCode) { selection in codeViewer(selection) }
            #else
            .sheet(item:$boardingCode,onDismiss:openFullPassAfterCode) { selection in codeViewer(selection).frame(minWidth:620,minHeight:540) }
            #endif
    }
    var body: some View {
        noticeUpdates.sheet(item:$boardingDocument,onDismiss:{ if let previousBoardingDocument { TemporaryDocuments.remove(previousBoardingDocument); self.previousBoardingDocument=nil } }) { file in
                NavigationStack { DocumentPreview(url:file.url).privacySensitive().ignoresSafeArea(edges:.bottom).navigationTitle(file.url.pathExtension.lowercased() == "pdf" ? "Pase de abordar PDF" : "Pase de abordar").jacInlineTitle().toolbar { ToolbarItem(placement:.cancellationAction) { Button("Listo") { boardingDocument=nil }.accessibilityIdentifier("notices.pdf.close") }
                    #if os(iOS)
                    ToolbarItem(placement:.confirmationAction) { ShareLink(item:file.url) { Image(systemName:"square.and.arrow.up") }.accessibilityLabel("Compartir archivo") }
                    #endif
                } }
            }
            .alert("Eliminar " + (pendingDelete?.kind == "boarding_pass" ? "pase de abordar" : "itinerario"),isPresented:$confirmingListDelete) {
                Button("Cancelar",role:.cancel) { pendingDelete=nil }.accessibilityIdentifier("notices.list.delete.cancel")
                Button("Eliminar",role:.destructive) { if let item=pendingDelete { Task { await remove(item) } } }.accessibilityIdentifier("notices.list.delete.confirm")
            } message: { Text(pendingDelete?.kind == "boarding_pass" ? "¿Estás seguro de que quieres eliminar este pase de abordar?" : "¿Estás seguro de que quieres eliminar este itinerario para todo el equipo?") }
            .onDisappear { documentGeneration += 1; if let previousBoardingDocument { TemporaryDocuments.remove(previousBoardingDocument); self.previousBoardingDocument=nil } }
            .sheet(item: $detail, onDismiss: { Task { await refresh() } }) { item in NoticeDetail(item: item, owner: user.isOwner) }
            .sheet(isPresented: $editor) { if let feed { NoticeComposer(users: feed.users, boardingUsers: feed.boardingUsers ?? feed.users) { savedKind in incomingKind = savedKind; notice = savedKind == "boarding_pass" ? "Pase publicado únicamente para la persona elegida." : savedKind == "itinerary" ? "Itinerario publicado para todo el equipo." : "Alerta guardada para los destinatarios elegidos."; await refresh() } } }
            #if os(iOS)
            .sheet(item:$boardingWallet) { selection in BoardingWalletPreparationView(selection:selection) }
            #endif
    }
    @ViewBuilder private func deleteButton(_ item:JACNotice,destructive:Bool = true) -> some View {
        Button(role:destructive ? .destructive : nil) { pendingDelete=item; confirmingListDelete=true } label: { Label(item.kind == "boarding_pass" ? "Eliminar pase de abordar" : "Eliminar itinerario",systemImage:"trash").font(.subheadline) }
            .disabled(deleting || openingFile != nil || store.isOffline).accessibilityIdentifier("notices.list.delete.\(item.id)")
    }
    private func remove(_ item:JACNotice) async {
        guard !deleting else { return }; deleting=true; defer { deleting=false }
        do { try await store.client.deleteNotice(item); deletedIDs.insert(item.id); records.removeAll { $0.id == item.id }; historyRecords.removeAll { $0.id == item.id }; pendingDelete=nil; notice=item.kind == "boarding_pass" ? "Pase de abordar eliminado." : "Itinerario eliminado para todo el equipo." }
        catch { self.error=error.localizedDescription; store.report(error) }
    }
    @ViewBuilder private func boardingRows(_ items:[JACNotice]) -> some View {
        ForEach(items) { item in VStack(alignment:.leading,spacing:16) {
            ForEach(Array(item.files.enumerated()),id:\.element.id) { index,file in
                VStack(alignment:.leading,spacing:0) {
                Button { Task { await openBoarding(item,file:file) } } label: {
                    VStack(alignment:.leading,spacing:16) {
                        let info=BoardingClock.filenameDetails(file.filename)
                        HStack { Label("PASE DE ABORDAR",systemImage:"airplane").font(.caption2.weight(.bold)).tracking(1);Spacer();JACBadge(title:file.mimeType == "application/pdf" ? "PDF":"Imagen",tone:.teal) }.foregroundStyle(JACTone.teal.color)
                        if let info {
                            Text(info.origin + " → " + info.destination).font(.system(.title3,design:.rounded,weight:.bold)).fixedSize(horizontal:false,vertical:true)
                            Text(info.passenger).font(.subheadline.weight(.medium))
                        } else { Text(item.title).font(.system(.headline,design:.rounded)) }
                        Rectangle().fill(JACTone.teal.color.opacity(0.18)).frame(height:1)
                        Text(file.filename).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.leading)
                        HStack(alignment:.center,spacing:14) {
                            Label(BoardingClock.label(item.travelDate ?? ""),systemImage:"calendar").font(.caption).foregroundStyle(.secondary)
                            Spacer(minLength:0)
                        }
                    }.padding(18).contentShape(Rectangle())
                }.buttonStyle(.plain).disabled(openingFile != nil || deleting).accessibilityIdentifier(index == 0 ? "notices.item.\(item.id)" : "notices.file.\(file.id)")
                HStack(spacing:16) {
                    Button { boardingCode=BoardingCodeSelection(item:item,file:file) } label: {
                        Label("Mostrar código",systemImage:"qrcode.viewfinder").font(.subheadline.weight(.semibold)).padding(.horizontal,12).frame(minHeight:44)
                            .background(JACTone.teal.color.opacity(0.09),in:RoundedRectangle(cornerRadius:12))
                    }.buttonStyle(.plain).accessibilityIdentifier("boarding.code.\(file.id)")
                    Spacer(minLength:0)
                    Button {Task {await openBoarding(item,file:file)}} label: {
                        HStack(spacing:8) {if openingFile == file.id {ProgressView()};Text(file.mimeType == "application/pdf" ? "Abrir PDF":"Abrir imagen").font(.subheadline.weight(.semibold))}.frame(minHeight:44).contentShape(Rectangle())
                    }.buttonStyle(.plain).accessibilityIdentifier("boarding.open.\(file.id)")
                    Menu { boardingMenuActions(item,file:file) } label: {
                        Image(systemName:"ellipsis.circle").font(.title3).frame(width:44,height:44).contentShape(Rectangle())
                    }.accessibilityLabel("Opciones del pase").accessibilityIdentifier("boarding.menu.\(file.id)")
                }.foregroundStyle(JACTone.teal.color).padding(.horizontal,18).padding(.bottom,14).disabled(openingFile != nil || deleting)
                }.background(JACTheme.card,in:RoundedRectangle(cornerRadius:22))
                    .overlay(RoundedRectangle(cornerRadius:22).stroke(JACTone.teal.color.opacity(0.18),lineWidth:1))
                    .contextMenu { boardingMenuActions(item,file:file) }
            }
        }.padding(.vertical,6).jacStandaloneRow()
            .swipeActions(edge:.trailing,allowsFullSwipe:false) { if user.isOwner { deleteButton(item,destructive:false).tint(.red) } }
        }
    }
    @ViewBuilder private func boardingMenuActions(_ item:JACNotice,file:NoticeAttachment) -> some View {
        #if os(iOS)
        if UIDevice.current.userInterfaceIdiom == .phone {
            Button {boardingWallet=BoardingCodeSelection(item:item,file:file)} label:{Label("Añadir a Apple Wallet",systemImage:"wallet.pass")}
                .disabled(store.isOffline).accessibilityIdentifier("boarding.wallet.menu.\(file.id)")
        }
        #endif
        Button {boardingCode=BoardingCodeSelection(item:item,file:file)} label:{Label("Mostrar código",systemImage:"qrcode.viewfinder")}
        Button {Task {await openBoarding(item,file:file)}} label:{Label(file.mimeType == "application/pdf" ? "Abrir PDF":"Abrir imagen",systemImage:"doc")}
        if user.isOwner {Divider();deleteButton(item)}
    }
    private func codeViewer(_ selection:BoardingCodeSelection) -> some View {
        BoardingCodeView(selection:selection) { fullPassAfterCode=selection;boardingCode=nil }
    }
    private func openFullPassAfterCode() {
        guard let selection=fullPassAfterCode else {return};fullPassAfterCode=nil
        Task { await openBoarding(selection.item,file:selection.file) }
    }
    private func openBoarding(_ item:JACNotice,file:NoticeAttachment) async {
        guard openingFile == nil else { return }; openingFile=file.id; let generation=documentGeneration; defer { openingFile=nil }
        do {
            let result=try await store.client.noticeFile(item,file:file)
            guard generation == documentGeneration else { TemporaryDocuments.remove(result); return }
            previousBoardingDocument=result; boardingDocument=result
            do { if !store.isOffline { try await store.client.noticeCommand(.object(["action":.string("read"),"id":.string(item.id)])) } } catch { self.error=store.reportReadFailure(error) }
        } catch { self.error=store.reportReadFailure(error) }
    }
    private func restoreCached() {
        let boarding: String? = effectiveKind == "boarding_pass" ? "current" : nil
        if let saved = store.client.cachedNotices(boarding: boarding) {
            feed = saved; records = store.isOffline || records.isEmpty ? saved.notices.filter { !deletedIDs.contains($0.id) } : records.compactMap { deletedIDs.contains($0.id) ? nil : store.client.cachedNotice($0.id) ?? $0 }
        }
        day = BoardingClock.today()
        if let passes = store.client.cachedNotices(boarding: "current") {
            boardingCount = passes.notices.filter { $0.travelDate == day }.count
            tomorrowCount = passes.notices.filter { $0.travelDate == BoardingClock.nextDay(day) }.count
        }
        if historyOpen, let saved = store.client.cachedNotices(boarding: "history") { history = saved; historyRecords = store.isOffline || historyRecords.isEmpty ? saved.notices.filter { !deletedIDs.contains($0.id) } : historyRecords.compactMap { deletedIDs.contains($0.id) ? nil : store.client.cachedNotice($0.id) ?? $0 } }
    }
    private func loadHistory(_ cursor:String = "") async { restoreCached(); do { let result=try await store.client.notices(cursor:cursor,boarding:"history"); history=result; let items=(store.isOffline ? store.client.cachedNotices(boarding:"history")?.notices ?? result.notices : result.notices).filter { !deletedIDs.contains($0.id) }; if cursor.isEmpty { historyRecords=items } else { historyRecords += items.filter { item in !historyRecords.contains { $0.id == item.id } } } } catch { self.error=store.reportReadFailure(error) } }
    private func refresh(_ cursor: String = "") async {
        guard user.permitsNotice(effectiveKind) else {records=[];return}
        guard !loading else { return }; loading = true; defer { loading = false }
        do { day = BoardingClock.today(); let result = try await store.client.notices(cursor: cursor, boarding:effectiveKind == "boarding_pass" ? "current" : nil); feed = result; let items=(store.isOffline ? store.client.cachedNotices(cursor: cursor, boarding: effectiveKind == "boarding_pass" ? "current" : nil)?.notices ?? result.notices : result.notices).filter { !deletedIDs.contains($0.id) }; if cursor.isEmpty { records = items } else { records += items.filter { item in !records.contains { $0.id == item.id } } }; error = nil
            if effectiveKind == "itinerary" && user.hasSection(.boarding) { let passes = try await store.client.notices(boarding:"current"); boardingCount = passes.notices.filter { $0.travelDate == day }.count; tomorrowCount = passes.notices.filter { $0.travelDate == BoardingClock.nextDay(day) }.count }; if historyOpen { await loadHistory() }
            if !handledInitial, let initialNotice { handledInitial = true; let item: JACNotice; if let found = records.first(where: { $0.id == initialNotice }) { item = found } else { item = try await store.client.notice(id: initialNotice) }; incomingKind = item.kind; if item.kind == "boarding_pass",let first=item.files.first { await openBoarding(item,file:first) } else { detail = item } }
        } catch { self.error = store.reportReadFailure(error) }
    }
}

struct BoardingCodeSelection: Identifiable {
    let id = UUID()
    let item: JACNotice
    let file: NoticeAttachment
}

struct BoardingCodeImage: Identifiable, @unchecked Sendable {
    let id = UUID()
    let image: CGImage
    let format: String
    let page: Int
    var walletBarcode: BoardingWalletBarcode? = nil
}

// Wallet accepts a text barcode, unlike the viewer which keeps original pixels.
// Only exact, printable ASCII BCBP payloads are eligible: never normalize, trim,
// transcode a binary barcode, or make a boarding code from itinerary metadata.
struct BoardingWalletBarcode: Equatable, Sendable {
    let format: String
    let message: String
    init?(format: String, message: String) {
        guard ["PKBarcodeFormatQR", "PKBarcodeFormatPDF417", "PKBarcodeFormatAztec"].contains(format),
              (60...4096).contains(message.utf8.count), message.utf8.count == message.unicodeScalars.count,
              message.unicodeScalars.allSatisfy({ (32...126).contains($0.value) }),
              message.first == "M", let count = message.dropFirst().first, "1234".contains(count) else { return nil }
        self.format = format; self.message = message
    }
    static func extracted(_ symbology: VNBarcodeSymbology, message: String?) -> BoardingWalletBarcode? {
        let formats: [VNBarcodeSymbology: String] = [.qr: "PKBarcodeFormatQR", .pdf417: "PKBarcodeFormatPDF417", .aztec: "PKBarcodeFormatAztec"]
        guard let format = formats[symbology], let message else { return nil }
        return BoardingWalletBarcode(format: format, message: message)
    }
}

struct BoardingWalletStatus: Decodable, Sendable {
    let configured: Bool
    let version: Int
    let passTypeId: String?
    let expiresAt: String?
}

enum BoardingCodeExtractor {
    static func configure(_ request:VNRequest) throws {
        #if targetEnvironment(simulator)
        // This CoreSimulator runtime cannot load revision 3's barcode models.
        // Revision 2 decodes the same original pixels on CPU. Physical iPhones
        // retain the current detector and Vision's normal hardware selection.
        (request as? VNDetectBarcodesRequest)?.revision=VNDetectBarcodesRequestRevision2
        for (stage,devices) in try request.supportedComputeStageDevices {
            if let cpu=devices.first(where:{if case .cpu = $0 {return true};return false}) {request.setComputeDevice(cpu,for:stage)}
        }
        #endif
    }
    // Render and crop the original pixels: never recreate a code from a text
    // payload, which could change its binary encoding or airline signature.
    static func extract(_ data: Data, mime: String) throws -> [BoardingCodeImage] {
        guard data.count <= 10*1024*1024 else { throw APIError.invalid("El pase supera los 10 MB.") }
        try Task.checkCancellation()
        if mime == "application/pdf" {
            guard let provider=CGDataProvider(data:data as CFData),let pdf=CGPDFDocument(provider), !pdf.isEncrypted,
                  (1...12).contains(pdf.numberOfPages) else { throw APIError.invalid("No se pudo analizar este PDF. Abre el pase completo.") }
            var codes:[BoardingCodeImage]=[]
            for number in 1...pdf.numberOfPages {
                try Task.checkCancellation()
                let found = try autoreleasepool { () throws -> [BoardingCodeImage] in
                    guard let page=pdf.page(at:number) else { return [] }
                    let box=page.getBoxRect(.cropBox)
                    guard box.width.isFinite,box.height.isFinite,box.width>0,box.height>0 else {return []}
                    let rotated=abs(page.rotationAngle)%180 == 90
                    let w=rotated ? box.height:box.width,h=rotated ? box.width:box.height
                    let scale=3200/max(w,h),width=max(1,Int((w*scale).rounded())),height=max(1,Int((h*scale).rounded()))
                    guard let context=bitmap(width:width,height:height) else { throw APIError.message("No se pudo preparar el pase.") }
                    context.setFillColor(CGColor(gray:1,alpha:1));context.fill(CGRect(x:0,y:0,width:width,height:height))
                    context.concatenate(page.getDrawingTransform(.cropBox,rect:CGRect(x:0,y:0,width:width,height:height),rotate:0,preserveAspectRatio:true))
                    context.drawPDFPage(page)
                    guard let image=context.makeImage() else {return []}
                    return try detect(image,page:number)
                }
                let pixels=(codes+found).reduce(0) {$0+$1.image.width*$1.image.height}
                guard codes.count+found.count <= 24,pixels <= 16_000_000 else { throw APIError.invalid("Este documento tiene demasiados códigos. Abre el pase completo para revisarlos.") }
                codes += found
            }
            return codes
        }
        guard ["image/jpeg","image/png"].contains(mime),let source=CGImageSourceCreateWithData(data as CFData,nil),
              let image=CGImageSourceCreateThumbnailAtIndex(source,0,[kCGImageSourceCreateThumbnailFromImageAlways:true,kCGImageSourceCreateThumbnailWithTransform:true,kCGImageSourceThumbnailMaxPixelSize:3200] as CFDictionary) else {
            throw APIError.invalid("No se pudo analizar esta imagen. Abre el pase completo.")
        }
        return try detect(image,page:1)
    }
    private static func bitmap(width:Int,height:Int) -> CGContext? {
        CGContext(data:nil,width:width,height:height,bitsPerComponent:8,bytesPerRow:width*4,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)
    }
    private static func detect(_ image:CGImage,page:Int) throws -> [BoardingCodeImage] {
        try Task.checkCancellation()
        let request=VNDetectBarcodesRequest()
        try configure(request)
        request.symbologies=[.qr,.pdf417,.aztec,.dataMatrix]
        try VNImageRequestHandler(cgImage:image,options:[:]).perform([request])
        try Task.checkCancellation()
        let observations=(request.results ?? []).sorted { a,b in abs(a.boundingBox.midY-b.boundingBox.midY)>0.03 ? a.boundingBox.midY>b.boundingBox.midY : a.boundingBox.minX<b.boundingBox.minX }
        return observations.prefix(25).compactMap { observation in
            let b=observation.boundingBox,w=CGFloat(image.width),h=CGFloat(image.height)
            // Vision coordinates start at the bottom left; CGImage crops start
            // at the top left. Include the original quiet zone and white margin.
            let bounds=CGRect(x:0,y:0,width:w,height:h)
            let rect=CGRect(x:b.minX*w,y:(1-b.maxY)*h,width:b.width*w,height:b.height*h)
            let margin=max(12,min(rect.width,rect.height)*0.12)
            let crop=rect.insetBy(dx:-margin,dy:-margin).intersection(bounds).integral
            guard !crop.isEmpty,let original=image.cropping(to:crop) else {return nil}
            let padding=max(20,Int(min(crop.width,crop.height)*0.12))
            guard let context=bitmap(width:original.width+padding*2,height:original.height+padding*2) else {return nil}
            context.setFillColor(CGColor(gray:1,alpha:1));context.fill(CGRect(x:0,y:0,width:context.width,height:context.height))
            context.interpolationQuality = .none
            context.draw(original,in:CGRect(x:padding,y:padding,width:original.width,height:original.height))
            guard let cropped=context.makeImage() else {return nil}
            let names:[VNBarcodeSymbology:String]=[.qr:"QR",.pdf417:"PDF417",.aztec:"Aztec",.dataMatrix:"Data Matrix"]
            return BoardingCodeImage(image:cropped,format:names[observation.symbology] ?? "Código",page:page,walletBarcode:BoardingWalletBarcode.extracted(observation.symbology,message:observation.payloadStringValue))
        }
    }
}

@MainActor protocol BoardingScreenBrightness: AnyObject { var brightness: CGFloat { get set } }

@MainActor final class BoardingBrightnessLease {
    private var screen: (any BoardingScreenBrightness)?
    private var original: CGFloat?
    func begin(_ next:any BoardingScreenBrightness) {
        if let screen,screen === next { return }
        end();screen=next;original=next.brightness;next.brightness=1
    }
    func end() { if let screen,let original {screen.brightness=original};screen=nil;original=nil }
}

#if os(iOS)
extension UIScreen: BoardingScreenBrightness {}

@MainActor private struct BoardingWalletPresentation: Identifiable {
    let id = UUID()
    let controller: PKAddPassesViewController
}

@MainActor private struct BoardingWalletAddButton: UIViewRepresentable {
    let enabled: Bool
    let action: () -> Void
    func makeCoordinator() -> Coordinator { Coordinator(action) }
    func makeUIView(context: Context) -> PKAddPassButton {
        let button = PKAddPassButton(addPassButtonStyle: .black)
        button.addTarget(context.coordinator, action: #selector(Coordinator.add), for: .touchUpInside)
        button.accessibilityIdentifier = "boarding.wallet.add"
        return button
    }
    func updateUIView(_ button: PKAddPassButton, context: Context) { context.coordinator.action = action; button.isEnabled = enabled }
    final class Coordinator: NSObject {
        var action: () -> Void
        init(_ action: @escaping () -> Void) { self.action = action }
        @objc func add() { action() }
    }
}

@MainActor private struct BoardingWalletAddSheet: UIViewControllerRepresentable {
    let presentation: BoardingWalletPresentation
    let finished: () -> Void
    func makeCoordinator() -> Coordinator { Coordinator(finished) }
    func makeUIViewController(context: Context) -> PKAddPassesViewController {
        presentation.controller.delegate = context.coordinator
        return presentation.controller
    }
    func updateUIViewController(_ controller: PKAddPassesViewController, context: Context) { context.coordinator.finished = finished }
    final class Coordinator: NSObject, PKAddPassesViewControllerDelegate {
        var finished: () -> Void
        init(_ finished: @escaping () -> Void) { self.finished = finished }
        func addPassesViewControllerDidFinish(_ controller: PKAddPassesViewController) { finished() }
    }
}

private struct BoardingBrightness: UIViewRepresentable {
    let enabled:Bool
    func makeUIView(context:Context) -> Anchor { Anchor() }
    func updateUIView(_ view:Anchor,context:Context) { view.enabled=enabled;view.update() }
    static func dismantleUIView(_ view:Anchor,coordinator:()) {view.stop()}
    final class Anchor:UIView {
        var enabled=false
        private let lease=BoardingBrightnessLease()
        private var observers:[NSObjectProtocol]=[]
        private var sceneObservers:[NSObjectProtocol]=[]
        init() {
            super.init(frame:.zero);isUserInteractionEnabled=false
            observers.append(NotificationCenter.default.addObserver(forName:UIApplication.willResignActiveNotification,object:nil,queue:.main) { [weak self] _ in MainActor.assumeIsolated {self?.lease.end()} })
            observers.append(NotificationCenter.default.addObserver(forName:UIApplication.didBecomeActiveNotification,object:nil,queue:.main) { [weak self] _ in MainActor.assumeIsolated {self?.update()} })
        }
        required init?(coder:NSCoder) {fatalError("init(coder:) has not been implemented")}
        override func didMoveToWindow() {
            super.didMoveToWindow();lease.end()
            sceneObservers.forEach(NotificationCenter.default.removeObserver);sceneObservers=[]
            if let scene=window?.windowScene {
                sceneObservers.append(NotificationCenter.default.addObserver(forName:UIScene.willDeactivateNotification,object:scene,queue:.main) { [weak self] _ in MainActor.assumeIsolated {self?.lease.end()} })
                sceneObservers.append(NotificationCenter.default.addObserver(forName:UIScene.didActivateNotification,object:scene,queue:.main) { [weak self] _ in MainActor.assumeIsolated {self?.update()} })
            }
            update()
        }
        func update() {
            if enabled,UIApplication.shared.applicationState == .active,let scene=window?.windowScene,scene.activationState == .foregroundActive {lease.begin(scene.screen)}
            else {lease.end()}
        }
        func stop() {lease.end();(observers+sceneObservers).forEach(NotificationCenter.default.removeObserver);observers=[];sceneObservers=[];enabled=false}
    }
}
#endif

#if os(iOS)
private struct BoardingWalletCodeOption: Identifiable, Sendable {
    let id:Int
    let page:Int
    let format:String
    let barcode:BoardingWalletBarcode
}
private struct BoardingWalletSource: Sendable {
    let data:Data
    let codes:[BoardingWalletCodeOption]
    let sha256:String
}

private struct BoardingWalletPreparationView: View {
    @EnvironmentObject private var store:PayrollStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    let selection:BoardingCodeSelection
    @State private var codes:[BoardingWalletCodeOption]=[]
    @State private var codeIndex=0
    @State private var legIndex=0
    @State private var details=BoardingWalletDetails()
    @State private var sourceData:Data?
    @State private var sourceSha256:String?
    @State private var stamp:String?
    @State private var loading=true
    @State private var resolvingDetails=false
    @State private var revoked=false
    @State private var error:String?
    @State private var walletStatus:BoardingWalletStatus?
    @State private var preparingWallet=false
    @State private var walletPresentation:BoardingWalletPresentation?
    @State private var generation=0
    @State private var detailGeneration=0
    @State private var walletGeneration=0
    @State private var extractionTask:Task<BoardingWalletSource,Error>?
    @State private var detailsTask:Task<Void,Never>?
    @State private var walletTask:Task<Void,Never>?
    @FocusState private var focusedField:String?
    private var selectedCode:BoardingWalletCodeOption? {codes.indices.contains(codeIndex) ? codes[codeIndex]:nil}
    private var legs:[BoardingWalletLeg] {
        guard let code=selectedCode else {return []}
        let parsed=BoardingWalletDetailsExtractor.legs(barcode:code.barcode)
        if parsed.isEmpty,let count=BoardingWalletDetailsExtractor.declaredLegCount(barcode:code.barcode),count>1 {
            return (0..<count).map {BoardingWalletLeg(index:$0,details:BoardingWalletDetails())}
        }
        return parsed
    }
    private var canAddPasses:Bool {UIDevice.current.userInterfaceIdiom == .phone && PKAddPassesViewController.canAddPasses()}
    private var hasSelectedLeg:Bool {
        guard let code=selectedCode,let count=Int(String(code.barcode.message.dropFirst().prefix(1))) else {return false}
        return count == 1 ? legIndex == 0:legs.count == count && legs.contains(where:{$0.index == legIndex})
    }
    private var canPrepare:Bool {
        !loading && !resolvingDetails && !preparingWallet && !revoked && !store.isOffline && walletStatus?.configured == true &&
        selectedCode != nil && hasSelectedLeg && details.validationMessage == nil && scenePhase == .active
    }
    var body:some View {
        NavigationStack {
            Group {
                if scenePhase != .active {Color.clear}
                else if revoked {ContentUnavailableView("Pase no disponible",systemImage:"lock",description:Text("Vuelve a abrir tus pases con tu sesión actual."))}
                else {preparationForm}
            }.privacySensitive().navigationTitle("Añadir a Apple Wallet").jacInlineTitle()
                .toolbar {
                    ToolbarItem(placement:.cancellationAction) {Button("Cerrar") {dismiss()}.accessibilityIdentifier("boarding.wallet.close")}
                    ToolbarItemGroup(placement:.keyboard) {Spacer();Button("Listo") {focusedField=nil}.accessibilityIdentifier("boarding.wallet.keyboard.done")}
                }
        }
        .task {await load()}
        .onChange(of:codeIndex) {_,_ in guard !loading else {return};legIndex=legs.count>1 ? -1:0;stopSigning();startSuggestions()}
        .onChange(of:legIndex) {_,_ in guard !loading else {return};stopSigning();startSuggestions()}
        .onChange(of:details) {_,_ in stopSigning()}
        .onChange(of:store.cacheRevision) {_,_ in validateAccess()}
        .onChange(of:store.overview?.user) {_,_ in validateAccess()}
        .onChange(of:store.isOffline) {_,offline in if offline {stopSigning()}}
        .onChange(of:scenePhase) {_,phase in
            if phase == .background {clearPrivate()}
            else if phase == .active,sourceData == nil,!revoked {Task {await load()}}
        }
        .sheet(item:$walletPresentation,onDismiss:{walletPresentation=nil}) {presentation in
            BoardingWalletAddSheet(presentation:presentation) {walletPresentation=nil}.privacySensitive()
        }
        .onDisappear {clearPrivate()}
    }
    private var preparationForm:some View {
        Form {
            Section {Text(selection.file.filename).font(.footnote).foregroundStyle(.secondary)}
            if loading {Section {ProgressView("Leyendo los datos del pase…").accessibilityIdentifier("boarding.wallet.loading")}}
            if let error {Section {InlineError(message:error).accessibilityIdentifier("boarding.wallet.error")}}
            if !loading,!codes.isEmpty {
                if codes.count>1 || legs.count>1 {
                    Section("Elige tu vuelo") {
                        if codes.count>1 {
                            Picker("Código del documento",selection:$codeIndex) {
                                ForEach(Array(codes.enumerated()),id:\.element.id) {index,code in
                                    Text("Código \(index+1) · Pág. \(code.page) · \(code.format)").tag(index)
                                }
                            }.accessibilityIdentifier("boarding.wallet.codePicker")
                        }
                        if legs.count>1 {
                            Picker("Tramo",selection:$legIndex) {
                                Text("Selecciona tu vuelo").tag(-1)
                                ForEach(legs,id:\.index) {leg in Text(leg.label).tag(leg.index)}
                            }
                                .accessibilityIdentifier("boarding.wallet.legPicker")
                        }
                    }.disabled(resolvingDetails || preparingWallet)
                }
                if !hasSelectedLeg {Section {Text(legs.count>1 ? "Selecciona el tramo de este pase antes de preparar Wallet.":"No se pudieron identificar los tramos de este código. Conserva el documento original.").font(.footnote).foregroundStyle(.secondary)}}
                Section {
                    if resolvingDetails {ProgressView("Leyendo los datos de este vuelo…")}
                    detailField("Nombre del pasajero",text:$details.passenger,id:"passenger")
                    detailField("Origen",text:$details.origin,id:"origin")
                    detailField("Destino",text:$details.destination,id:"destination")
                    detailField("Hora del vuelo",text:$details.departureTime,id:"departureTime",clock:true)
                    detailField("Hora en sala",text:$details.boardingTime,id:"boardingTime",clock:true)
                    detailField("Silla asignada",text:$details.seat,id:"seat")
                } header:{Text("Datos del vuelo")} footer:{
                    Text("Revisa estos datos con tu pase original. Puedes corregirlos o dejar vacíos los que no aparezcan. Las horas se muestran como figuran en el documento.")
                }.disabled(resolvingDetails || preparingWallet || !hasSelectedLeg)
                if let message=details.validationMessage {Section {Text(message).foregroundStyle(.red).font(.footnote)}}
                Section {
                    if walletStatus?.configured == false {Text("Wallet estará disponible cuando el administrador complete la conexión.").foregroundStyle(.secondary)}
                    if canAddPasses {
                        BoardingWalletAddButton(enabled:canPrepare) {beginWallet()}.frame(width:220,height:44).frame(maxWidth:.infinity)
                        Text("Se guardará una copia en Wallet.").font(.caption).foregroundStyle(.secondary)
                    } else {Text("Este dispositivo no permite añadir pases a Apple Wallet.").font(.footnote).foregroundStyle(.secondary)}
                    if preparingWallet {ProgressView("Preparando pase…").accessibilityIdentifier("boarding.wallet.signing")}
                }
            }
            if !loading,error != nil || walletStatus?.configured == nil {
                Section {Button("Volver a leer el pase") {Task {await load()}}.disabled(store.isOffline || preparingWallet)}
            }
        }.scrollDismissesKeyboard(.interactively).accessibilityIdentifier("boarding.wallet.form")
    }
    private func detailField(_ label:String,text:Binding<String>,id:String,clock:Bool=false) -> some View {
        VStack(alignment:.leading,spacing:5) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            TextField(clock ? "HH:mm":"Sin detectar",text:text).textInputAutocapitalization(clock ? .never:.words)
                .autocorrectionDisabled().keyboardType(clock ? .numbersAndPunctuation:.default).submitLabel(.done)
                .focused($focusedField,equals:id).accessibilityLabel(label).accessibilityIdentifier("boarding.wallet."+id)
        }
    }
    private func validateAccess() {
        guard let stamp else {return}
        if (try? store.client.boardingCodeAccessStamp(selection.item,file:selection.file)) != stamp {
            revoked=true;clearPrivate();loading=false
        }
    }
    private func clearPrivate() {
        generation += 1;detailGeneration += 1;extractionTask?.cancel();extractionTask=nil;detailsTask?.cancel();detailsTask=nil
        stopSigning();sourceData=nil;sourceSha256=nil;stamp=nil;codes=[];details=BoardingWalletDetails();walletStatus=nil
        loading=false;resolvingDetails=false
    }
    private func stopSigning() {
        walletGeneration += 1;walletTask?.cancel();walletTask=nil;walletPresentation=nil;preparingWallet=false
    }
    private func load() async {
        guard !revoked,scenePhase == .active else {return}
        clearPrivate();loading=true;error=nil;codeIndex=0;legIndex=0
        let request=generation
        do {
            let start=try store.client.boardingCodeAccessStamp(selection.item,file:selection.file);stamp=start
            let document=try await store.client.noticeFile(selection.item,file:selection.file)
            defer {TemporaryDocuments.remove(document)}
            try Task.checkCancellation()
            guard request == generation,!revoked,scenePhase == .active,start == (try store.client.boardingCodeAccessStamp(selection.item,file:selection.file)) else {throw CancellationError()}
            let url=document.url,mime=selection.file.mimeType
            let worker=Task.detached(priority:.userInitiated) { () throws -> BoardingWalletSource in
                let data=try Data(contentsOf:url)
                let found=try BoardingCodeExtractor.extract(data,mime:mime)
                let codes=found.enumerated().compactMap {index,code in
                    code.walletBarcode.map {BoardingWalletCodeOption(id:index,page:code.page,format:code.format,barcode:$0)}
                }
                try Task.checkCancellation()
                return BoardingWalletSource(data:data,codes:codes,sha256:SHA256.hash(data:data).map {String(format:"%02x",$0)}.joined())
            }
            extractionTask=worker
            let source=try await withTaskCancellationHandler {try await worker.value} onCancel:{worker.cancel()}
            try Task.checkCancellation()
            guard request == generation,!revoked,scenePhase == .active,start == (try store.client.boardingCodeAccessStamp(selection.item,file:selection.file)) else {throw CancellationError()}
            guard !source.codes.isEmpty else {throw APIError.invalid("No se encontró un código de embarque compatible con Wallet. Puedes seguir usando el documento original y Mostrar código.")}
            let status=try await store.client.boardingWalletStatus(selection.item,file:selection.file)
            try Task.checkCancellation()
            guard request == generation,!revoked,scenePhase == .active,start == (try store.client.boardingCodeAccessStamp(selection.item,file:selection.file)) else {throw CancellationError()}
            sourceData=source.data;sourceSha256=source.sha256;codes=source.codes;walletStatus=status
            legIndex=legs.count>1 ? -1:0;loading=false;extractionTask=nil
            startSuggestions()
        } catch {
            guard request == generation,!Task.isCancelled else {return}
            loading=false;extractionTask=nil
            if !revoked {self.error=error is CancellationError ? "El pase cambió. Vuelve a abrir tus pases.":store.reportReadFailure(error)}
            validateAccess()
        }
    }
    private func startSuggestions() {
        guard !loading,!revoked,let code=selectedCode,let data=sourceData,let stamp else {return}
        detailGeneration += 1;detailsTask?.cancel();details=BoardingWalletDetails();error=nil
        guard hasSelectedLeg else {resolvingDetails=false;detailsTask=nil;return}
        resolvingDetails=true
        let request=detailGeneration,sourceGeneration=generation,selectedLeg=legIndex,mime=selection.file.mimeType
        let worker=Task.detached(priority:.userInitiated) {
            try BoardingWalletDetailsExtractor.suggestions(data:data,mime:mime,barcode:code.barcode,page:code.page,legIndex:selectedLeg)
        }
        detailsTask=Task {
            defer {if request == detailGeneration {resolvingDetails=false;detailsTask=nil}}
            do {
                let found=try await withTaskCancellationHandler {try await worker.value} onCancel:{worker.cancel()}
                try Task.checkCancellation()
                guard request == detailGeneration,sourceGeneration == generation,!revoked,scenePhase == .active,
                      selectedCode?.id == code.id,legIndex == selectedLeg,stamp == (try store.client.boardingCodeAccessStamp(selection.item,file:selection.file)) else {return}
                details=found
            } catch {
                guard request == detailGeneration,!Task.isCancelled else {return}
                self.error="No se pudieron leer todos los datos. Puedes completarlos con el documento original."
                validateAccess()
            }
        }
    }
    private func beginWallet() {
        guard canPrepare,let code=selectedCode,let sourceSha256,let stamp else {return}
        stopSigning();preparingWallet=true;error=nil
        let request=walletGeneration,sourceGeneration=generation,selectedLeg=legIndex,confirmed=details
        walletTask=Task {
            defer {if request == walletGeneration {preparingWallet=false;walletTask=nil}}
            do {
                let bytes=try await store.client.boardingWalletPass(selection.item,file:selection.file,sourceSha256:sourceSha256,barcode:code.barcode,legIndex:selectedLeg,details:confirmed)
                try Task.checkCancellation()
                guard request == walletGeneration,sourceGeneration == generation,!revoked,scenePhase == .active,
                      selectedCode?.id == code.id,legIndex == selectedLeg,details == confirmed,
                      stamp == (try store.client.boardingCodeAccessStamp(selection.item,file:selection.file)) else {throw CancellationError()}
                let pass:PKPass
                do {pass=try PKPass(data:bytes)} catch {throw APIError.invalid("Apple Wallet no pudo validar este pase. Conserva el documento original y vuelve a intentarlo.")}
                guard let controller=PKAddPassesViewController(pass:pass) else {throw APIError.invalid("No se pudo abrir Apple Wallet en este iPhone.")}
                walletPresentation=BoardingWalletPresentation(controller:controller)
            } catch {
                guard request == walletGeneration,!Task.isCancelled else {return}
                self.error=error.localizedDescription;validateAccess()
            }
        }
    }
}
#endif

private struct BoardingCodeView: View {
    @EnvironmentObject private var store:PayrollStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    let selection:BoardingCodeSelection
    let openFullPass:()->Void
    @State private var codes:[BoardingCodeImage]=[]
    @State private var index=0
    @State private var loading=true
    @State private var error:String?
    @State private var stamp:String?
    @State private var revoked=false
    private var visible:Bool { !codes.isEmpty && !revoked && scenePhase == .active }
    var body:some View {
        NavigationStack {
            VStack(spacing:16) {
                if loading {Spacer();ProgressView("Buscando el código del pase…").accessibilityIdentifier("boarding.code.loading");Spacer()}
                else if let error {Spacer();Image(systemName:"qrcode.viewfinder").font(.largeTitle);Text(error).multilineTextAlignment(.center).accessibilityIdentifier("boarding.code.error");Spacer()}
                else if visible,codes.indices.contains(index) {
                    let code=codes[index]
                    Image(code.image,scale:1,label:Text("Código \(code.format) del pase de abordar")).resizable().interpolation(.none).scaledToFit().padding(12)
                        .accessibilityLabel("Código \(code.format) del pase de abordar").accessibilityIdentifier("boarding.code.image").accessibilityHidden(false)
                    if codes.count>1 {
                        HStack(spacing:20) {
                            Button {index-=1} label:{Image(systemName:"chevron.left").frame(width:44,height:44)}.disabled(index==0).accessibilityLabel("Código anterior")
                            Text("\(index+1) de \(codes.count) · \(code.format) · Pág. \(code.page)").font(.footnote).accessibilityIdentifier("boarding.code.position")
                            Button {index+=1} label:{Image(systemName:"chevron.right").frame(width:44,height:44)}.disabled(index==codes.count-1).accessibilityLabel("Código siguiente")
                        }
                        Text("Elige el código que corresponde a tu vuelo.").font(.footnote).foregroundStyle(.secondary)
                    }
                } else {Spacer();Color.white;Spacer()}
                if !loading && !revoked {Button("Abrir pase completo",action:openFullPass).accessibilityIdentifier("boarding.code.fullpass").padding(.bottom,12)}
            }.padding(20).frame(maxWidth:.infinity,maxHeight:.infinity).background(.white).foregroundStyle(.black)
                .privacySensitive().navigationTitle("Código de embarque").jacInlineTitle()
                .toolbar {ToolbarItem(placement:.cancellationAction) {Button("Listo") {dismiss()}.accessibilityIdentifier("boarding.code.close")}}
                #if os(iOS)
                .toolbarBackground(.white,for:.navigationBar).toolbarBackground(.visible,for:.navigationBar)
                .background(BoardingBrightness(enabled:visible))
                #endif
        }.preferredColorScheme(.light).task {await load()}
            .onChange(of:store.cacheRevision) {_,_ in validateAccess()}
            .onChange(of:store.overview?.user) {_,_ in validateAccess()}
            .onDisappear {codes=[];stamp=nil}
    }
    private func validateAccess() {
        guard let stamp else {return}
        if (try? store.client.boardingCodeAccessStamp(selection.item,file:selection.file)) != stamp {
            revoked=true;codes=[];error="El pase cambió o ya no está disponible. Vuelve a abrir tus pases.";loading=false
        }
    }
    private func load() async {
        do {
            let start=try store.client.boardingCodeAccessStamp(selection.item,file:selection.file);stamp=start
            let document=try await store.client.noticeFile(selection.item,file:selection.file)
            defer {TemporaryDocuments.remove(document)}
            try Task.checkCancellation()
            let data=try Data(contentsOf:document.url),mime=selection.file.mimeType
            let worker=Task.detached(priority:.userInitiated) {try BoardingCodeExtractor.extract(data,mime:mime)}
            let found=try await withTaskCancellationHandler {try await worker.value} onCancel:{worker.cancel()}
            try Task.checkCancellation()
            guard !revoked,start == (try store.client.boardingCodeAccessStamp(selection.item,file:selection.file)) else {throw CancellationError()}
            if found.isEmpty {error="No se encontró un código legible. Puedes abrir el pase completo."} else {codes=found}
            loading=false
        } catch {
            guard !Task.isCancelled else {return}
            codes=[];loading=false
            if !revoked {self.error=error is CancellationError ? "El pase cambió. Vuelve a abrir tus pases.":store.reportReadFailure(error)}
        }
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
    @State private var current: JACNotice?
    @State private var confirmingReceipt = false
    @State private var updating = false
    private var shown: JACNotice { current ?? item }
    var body: some View {
        NavigationStack {
            List {
                Section { Text(shown.title).font(.title2.bold()); Text(shown.createdLabel).foregroundStyle(.secondary) }
                if let error { Section { InlineError(message: error) } }
                if !shown.body.isEmpty { Section { Text(shown.body).textSelection(.enabled) } }
                if !shown.files.isEmpty { Section("Adjuntos") { ForEach(shown.files) { file in
                    VStack(alignment: .leading, spacing: 12) {
                        Text(file.filename).font(.headline); Text("\(max(1,file.size/1024)) KB").font(.caption).foregroundStyle(.secondary)
                        Button { Task { await open(file) } } label: { HStack { Label(file.mimeType == "application/pdf" ? "Abrir PDF" : "Abrir imagen", systemImage: file.mimeType == "application/pdf" ? "doc.text" : "photo"); if downloading { ProgressView() } } }.buttonStyle(JACPrimaryButtonStyle()).disabled(downloading || deleting).accessibilityIdentifier(file.mimeType == "application/pdf" ? "notices.pdf" : "notices.image")
                    }.padding(.vertical, 8)
                } } }
                if (shown.revision ?? 1) > 1 { Section("Actualizado · Versión \(shown.revision ?? 1)") { Text(shown.changeSummary ?? "Consulta la nueva versión.").foregroundStyle(Color.accentColor) } }
                if shown.kind != "boarding_pass" { Section("Confirmación de recepción") {
                    Button(shown.confirmed == true ? "✓ Recibido" : "Confirmar recibido") { Task { await confirm() } }.disabled(confirmingReceipt || shown.confirmed == true || store.isOffline).accessibilityIdentifier("notices.confirm")
                    Text("Confirma que leíste esta versión.").font(.footnote).foregroundStyle(.secondary)
                    if owner,let receipts=shown.receipts { DisclosureGroup("Confirmaciones · \(receipts.filter(\.confirmed).count)/\(receipts.count)") { ForEach(receipts) { receipt in LabeledContent(receipt.name,value:receipt.confirmed ? "Recibido" : "Pendiente") } }.accessibilityIdentifier("notices.receipts") }
                } }
                if owner && shown.kind == "itinerary" { Section { Button("Actualizar itinerario") { updating=true }.disabled(store.isOffline).accessibilityIdentifier("notices.update") } }
                if owner && shown.kind != "boarding_pass" { Section { Button("Eliminar " + (shown.kind == "itinerary" ? "itinerario" : "alerta"), role: .destructive) { confirmingDelete = true }.disabled(deleting || downloading || store.isOffline).accessibilityIdentifier("notices.delete") } }
            }.jacSurface().navigationTitle(shown.kind == "boarding_pass" ? "Pase de abordar" : shown.kind == "itinerary" ? "Itinerario" : "Alerta").jacInlineTitle()
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Listo") { dismiss() }.disabled(deleting).accessibilityIdentifier("notices.detail.close") } }
                // Closing the detail also cancels its best-effort read receipt.
                // Do not leave that cancellation in unrelated menus.
                .task { current = store.client.cachedNotice(item.id); do { current = try await store.client.notice(id:shown.id); if !store.isOffline { try await store.client.noticeCommand(.object(["action": .string("read"), "id": .string(shown.id)])) } } catch { store.reportReadFailure(error) } }
                .onChange(of: store.cacheRevision) { _, _ in if let saved = store.client.cachedNotice(item.id) { current = saved } }
                .alert("Eliminar " + (shown.kind == "itinerary" ? "itinerario" : "alerta"), isPresented: $confirmingDelete) {
                    Button("Cancelar", role: .cancel) {}.accessibilityIdentifier("notices.delete.cancel")
                    Button("Eliminar", role: .destructive) { Task { await remove() } }.accessibilityIdentifier("notices.delete.confirm")
                } message: { Text("¿Eliminar “\(shown.title)”? Se retirará para todos sus destinatarios, junto con sus archivos de JAC y entregas pendientes. El original de Slack se conserva. Los avisos ya recibidos no se pueden retirar. Esta acción no se puede deshacer.") }
                .sheet(isPresented:$updating) { ItineraryUpdateView(item:shown) { do { current=try await store.client.notice(id:shown.id) } catch { self.error=store.reportReadFailure(error) } } }
                .sheet(item: $document, onDismiss: { if let previousDocument { TemporaryDocuments.remove(previousDocument); self.previousDocument = nil } }) { file in
                    NavigationStack { DocumentPreview(url: file.url).privacySensitive().ignoresSafeArea(edges: .bottom).navigationTitle(file.url.pathExtension.lowercased() == "pdf" ? "Itinerario PDF" : "Imagen adjunta").jacInlineTitle()
                        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Listo") { document = nil }.accessibilityIdentifier("notices.pdf.close") }
                            #if os(iOS)
                            ToolbarItem(placement:.confirmationAction) { ShareLink(item:file.url) { Image(systemName:"square.and.arrow.up") }.accessibilityLabel("Compartir archivo") }
                            #endif
                        }
                    }
                }
        }.interactiveDismissDisabled(deleting)
    }
    private func confirm() async {
        confirmingReceipt=true;defer { confirmingReceipt=false }
        do { try await store.client.confirmNotice(shown);current=try await store.client.notice(id:shown.id);error=nil } catch { self.error=error.localizedDescription;store.report(error) }
    }
    private func open(_ file: NoticeAttachment) async {
        downloading = true; defer { downloading = false }
        do { let result = shown.attachments == nil && shown.kind == "itinerary" ? try await store.client.itinerary(shown) : try await store.client.noticeFile(shown, file: file); previousDocument = result; document = result }
        catch { self.error = error.localizedDescription; store.report(error) }
    }
    private func remove() async {
        guard !deleting else { return }; deleting = true; defer { deleting = false }
        do { try await store.client.deleteNotice(shown); dismiss() } catch { self.error = error.localizedDescription; store.report(error) }
    }
}
struct NoticeComposer: View {
    @EnvironmentObject private var store: PayrollStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    let users: [NoticeUser]
    let boardingUsers: [NoticeUser]
    let onSaved: (String) async -> Void
    @State private var requestID = UUID().uuidString.lowercased()
    @State private var kind = "alert"
    @State private var passOwner = ""
    @State private var travelDate = Date()
    @State private var title = ""
    @State private var message = ""
    @State private var recipients=Set<String>()
    @State private var roster:NoticeRecipientRoster?
    @State private var rosterInitialized=false
    @State private var rosterReady=false
    @State private var rosterBusy=false
    @State private var rosterGeneration=0
    @State private var rosterError:String?
    @State private var recipientReviewRequired=false
    @State private var files: [NoticeUpload] = []
    @State private var picking = false
    @State private var photos: [PhotosPickerItem] = []
    @State private var busy = false
    @State private var attempted = false
    @State private var importing = false
    @State private var error: String?
    init(users: [NoticeUser], boardingUsers: [NoticeUser]? = nil, onSaved: @escaping (String) async -> Void) { self.users = users; self.boardingUsers = boardingUsers ?? users; self.onSaved = onSaved }
    var body: some View {
        NavigationStack {
            Form {
                if let error { Section { InlineError(message: error) } }
                if let rosterError {Section {InlineError(message:rosterError);Button("Actualizar destinatarios") {Task {_ = await refreshRecipients(reviewed:true)}}.disabled(rosterBusy || busy)}}
                if rosterBusy && !rosterInitialized {Section {ProgressView("Consultando destinatarios…")}}
                Group {
                    Section("Publicar como") { Picker("Tipo", selection: $kind) { Text("Alerta").tag("alert"); Text("Itinerario").tag("itinerary"); Text("Pase").tag("boarding_pass") }.pickerStyle(.segmented).accessibilityIdentifier("notices.editor.kind") }
                    Section(kind == "itinerary" ? "Itinerario" : "Alerta") { TextField("Título", text: $title).accessibilityIdentifier("notices.editor.title"); TextField(kind == "itinerary" ? "Mensaje opcional" : "Mensaje", text: $message, axis: .vertical).lineLimit(4...10).accessibilityIdentifier("notices.editor.message") }
                    Section("Adjuntos") {
                        Button("Elegir PDF o imágenes de Archivos") { picking = true }.accessibilityIdentifier("notices.editor.files")
                        PhotosPicker(selection: $photos, maxSelectionCount: 5, matching: .images) { Label("Elegir fotos", systemImage: "photo") }
                        ForEach(files) { file in HStack { Text(file.filename); Spacer(); Button(role: .destructive) { files.removeAll { $0.id == file.id } } label: { Image(systemName: "xmark.circle") }.accessibilityLabel("Quitar " + file.filename) } }
                        Text("Hasta 5 archivos PDF, JPG o PNG; 10 MB en total.").font(.footnote).foregroundStyle(.secondary)
                        #if DEBUG
                        if store.client.baseURL.host?.hasSuffix(".invalid") == true { Button("Adjuntar PDF ficticio") { let data = JACPlatform.fixturePDF(); add([NoticeUpload(filename:"Prueba.pdf",data:data)]) }.accessibilityIdentifier("notices.editor.fixture") }
                        #endif
                    }
                    if kind == "alert" { Section("Destinatarios") { ForEach(roster?.users ?? []) { user in Toggle(user.name + (user.ready == false ? " · Pendiente de activación" : ""), isOn: Binding(get: { recipients.contains(user.id) }, set: { value in if value { recipients.insert(user.id) } else { recipients.remove(user.id) } })).accessibilityIdentifier("notices.recipient.\(user.id)") } } }
                    else if kind == "boarding_pass" { Section("Pase de abordar privado") { Picker("Persona",selection:$passOwner) { Text("Selecciona una persona").tag(""); ForEach(roster?.boardingUsers ?? []) { Text($0.name).tag($0.id) } }.accessibilityIdentifier("boarding.recipient"); JACDatePicker("Fecha del pase",selection:$travelDate,displayedComponents:.date).environment(\.timeZone,CalendarClock.calendar.timeZone).accessibilityIdentifier("boarding.date"); Text("Solo la persona elegida podrá abrirlo. Usa Camilo 16 de octubre Pereira-Bogota; puedes incluir el año. El pasajero debe corresponder a la persona elegida. Sin año se usa la fecha más cercana; revisa la fecha antes de publicar.").font(.footnote).foregroundStyle(.secondary) } }
                    else { Section { Text("Se publicará directamente en Itinerarios para todo el equipo activo y enviará el aviso de itinerario nuevo.") } }
                }.disabled(busy || attempted || importing)
                if attempted && !busy && error != nil { Section { Text("Reintenta con estos mismos datos. Para cambiar el contenido, cierra y abre un formulario nuevo.").font(.footnote) } }
                Section { Button(busy ? "Guardando…" : kind == "boarding_pass" ? "Publicar pase y notificar" : kind == "itinerary" ? "Publicar itinerario y notificar" : "Crear alerta y notificar") { Task { await save() } }.buttonStyle(JACPrimaryButtonStyle()).disabled(busy || importing || store.isOffline || rosterBusy || !rosterReady).accessibilityIdentifier("notices.editor.save") }
            }.jacSurface().navigationTitle("Crear alerta o itinerario").jacInlineTitle().toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() }.disabled(busy) } }
                .fileImporter(isPresented: $picking, allowedContentTypes: [.pdf,.jpeg,.png], allowsMultipleSelection: true) { result in
                    do { let urls = try result.get(); var incoming: [NoticeUpload] = []
                        for url in urls { let access = url.startAccessingSecurityScopedResource(); defer { if access { url.stopAccessingSecurityScopedResource() } }; let size = try url.resourceValues(forKeys:[.fileSizeKey]).fileSize ?? 0; guard size <= 10*1024*1024 else { throw APIError.message("El archivo supera los 10 MB.") }; let data = try Data(contentsOf:url); _ = try NoticeUpload.mime(data); incoming.append(NoticeUpload(filename:url.lastPathComponent,data:data)) }; add(incoming)
                    } catch { self.error = error.localizedDescription }
                }
                .jacFileDrop(enabled:!busy && !attempted && !importing) {urls in do{add(try NoticeUpload.readLocalFiles(urls))}catch{self.error=error.localizedDescription}}
                .onChange(of: photos) { _, selected in Task { await readPhotos(selected) } }
        }.interactiveDismissDisabled(busy)
            .task {
                _ = await refreshRecipients()
                while !Task.isCancelled {
                    do {try await Task.sleep(for:.seconds(30))} catch {break}
                    if scenePhase == .active,!busy {_ = await refreshRecipients()}
                }
            }
            .onChange(of:scenePhase) {_,phase in
                if phase == .active,!busy {Task {_ = await refreshRecipients()}}
                else if phase == .background {rosterGeneration += 1;rosterBusy=false;rosterReady=false}
            }
            .onChange(of:store.overview?.user) {_,user in
                if user?.isOwner != true || user?.hasSection(.crm) != true {rosterGeneration += 1;roster=nil;recipients=[];passOwner="";rosterReady=false;rosterBusy=false;rosterError="Tu sesión o tus permisos cambiaron. Cierra este formulario."}
            }
            .onDisappear {rosterGeneration += 1;rosterBusy=false}
    }
    private func refreshRecipients(reviewed:Bool=false) async -> Bool {
        guard !rosterBusy,scenePhase == .active else {return false}
        rosterBusy=true;rosterGeneration += 1
        let request=rosterGeneration
        defer {if request == rosterGeneration {rosterBusy=false}}
        do {
            let fresh=try await store.client.noticeRecipients()
            try Task.checkCancellation()
            guard request == rosterGeneration,scenePhase == .active else {return false}
            let next=NoticeRecipientSelection.reconcile(recipients,users:fresh.users,initialized:rosterInitialized,reviewRequired:recipientReviewRequired,reviewed:reviewed)
            let ownerRemoved = !passOwner.isEmpty && !fresh.boardingUsers.contains(where:{$0.id == passOwner})
            roster=fresh
            if attempted && (next.removed || ownerRemoved) {
                rosterReady=false;rosterError="Los destinatarios cambiaron. Cierra y abre un formulario nuevo antes de volver a enviar.";return false
            }
            recipients=next.selected;rosterInitialized=true;rosterReady=true
            if ownerRemoved {passOwner=""}
            recipientReviewRequired=next.reviewRequired || ownerRemoved
            if recipientReviewRequired {rosterError="Cambió el acceso de algún destinatario. Revisa la lista y pulsa Actualizar destinatarios antes de publicar.";return false}
            rosterError=nil;return true
        } catch {
            guard request == rosterGeneration,!Task.isCancelled else {return false}
            rosterReady=false;rosterError=error.localizedDescription
            if case APIError.forbidden = error {roster=nil;recipients=[];passOwner=""}
            if case APIError.unauthorized = error {roster=nil;recipients=[];passOwner=""}
            return false
        }
    }
    private func add(_ incoming: [NoticeUpload]) { guard !attempted, !busy else { return }; let combined = files + incoming; guard combined.count <= 5, combined.reduce(0, { $0 + $1.data.count }) <= 10*1024*1024 else { error = "Elige hasta 5 archivos que sumen como máximo 10 MB."; return }; files = combined; if let name=incoming.first?.filename,let parsed=BoardingClock.filenameDate(name) { travelDate=parsed }; error = nil }
    private func readPhotos(_ selected: [PhotosPickerItem]) async {
        guard !selected.isEmpty else { return }; importing = true; defer { importing = false }
        do { var incoming: [NoticeUpload] = []; for (index, photo) in selected.enumerated() { guard let data = try await photo.loadTransferable(type:Data.self), data.count <= 10*1024*1024, let image = JACPlatformImage(data:data), let jpeg = image.jpegData(compressionQuality:0.9) else { throw APIError.message("No se pudo leer la foto o supera los 10 MB.") }; incoming.append(NoticeUpload(filename:"Foto-\(index+1).jpg",data:jpeg)) }; add(incoming); photos = [] }
        catch { self.error = error.localizedDescription; photos = [] }
    }
    private func save() async {
        guard !busy else { return }; guard !title.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty, title.utf16.count <= 120, message.utf16.count <= 2000, (kind == "boarding_pass" && !passOwner.isEmpty && !files.isEmpty) || kind == "itinerary" || (kind == "alert" && !message.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty && !recipients.isEmpty) else { error = "Revisa el título, mensaje y destinatarios."; return }
        busy = true; defer { busy = false }; error = nil
        guard await refreshRecipients() else {return}
        attempted = true
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


private struct JACNoticeCard: View {
    let item: JACNotice
    private var tone: JACTone { item.kind == "itinerary" ? .blue : .amber }
    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack(alignment: .top, spacing: 12) {
                JACIcon(symbol: item.kind == "itinerary" ? "doc.text" : "bell", tone: tone)
                VStack(alignment: .leading, spacing: 6) {
                    Text(item.title).font(.system(.headline, design: .rounded)).foregroundStyle(JACTheme.ink).fixedSize(horizontal:false,vertical:true)
                    Text(item.createdLabel).font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength:0)
                Image(systemName:"arrow.up.right").font(.caption.bold()).foregroundStyle(tone.color).accessibilityHidden(true)
            }
            if !item.body.isEmpty { Text(item.body).font(.subheadline).foregroundStyle(.secondary).lineLimit(2).multilineTextAlignment(.leading) }
            HStack(spacing:10) {
                if !item.files.isEmpty { Label("\(item.files.count) adjunto(s)",systemImage:"paperclip").font(.caption).foregroundStyle(.secondary) }
                Spacer(minLength:0)
                if item.confirmed == true { JACBadge(title:"✓ Recibido",tone:tone) }
                else if (item.revision ?? 1) > 1 { JACBadge(title:"Actualizado · Versión \(item.revision ?? 1)",tone:tone) }
                else if !item.read { JACBadge(title:"Nuevo",tone:tone) }
            }
        }.padding(18).frame(maxWidth:.infinity,alignment:.leading)
            .background(JACTheme.card,in:RoundedRectangle(cornerRadius:22))
            .overlay(RoundedRectangle(cornerRadius:22).stroke(tone.color.opacity(0.12),lineWidth:1))
            .contentShape(RoundedRectangle(cornerRadius:22))
    }
}
