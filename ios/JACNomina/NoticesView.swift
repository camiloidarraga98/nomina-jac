import SwiftUI
import UniformTypeIdentifiers
import PhotosUI
import Vision
import ImageIO
#if os(iOS)
import UIKit
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
    @State private var fullPassAfterCode: BoardingCodeSelection?
    @State private var previousBoardingDocument: ExportedDocument?
    @State private var openingFile: String?
    @State private var documentGeneration = 0
    @State private var confirmingListDelete = false
    @State private var pendingDelete: JACNotice?
    @State private var deleting = false
    @State private var deletedIDs = Set<String>()
    private var effectiveKind: String { incomingKind ?? kind }
    var body: some View {
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
            if effectiveKind == "alert" {
                Section {
                    JACFeatureBanner(eyebrow:"JAC · Equipo",title:"Lo importante, cerca.",subtitle:"Avisos y documentos para estar al tanto.",symbol:"bell.badge",tone:.amber)
                    if user.isOwner {
                        Button { editor = true } label: { Label("Crear alerta o itinerario",systemImage:"plus").frame(maxWidth:.infinity) }
                            .buttonStyle(JACPrimaryButtonStyle()).accessibilityLabel("Crear alerta").accessibilityIdentifier("notices.create").disabled(feed == nil || store.isOffline).padding(.top,5)
                    }
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

        }.jacSurface().navigationTitle(effectiveKind == "boarding_pass" ? "Pases de abordar" : effectiveKind == "itinerary" ? "Itinerarios" : "Alertas").jacInlineTitle().jacConnectionStatus().refreshable { await refresh() }
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
            .sheet(item:$boardingDocument,onDismiss:{ if let previousBoardingDocument { TemporaryDocuments.remove(previousBoardingDocument); self.previousBoardingDocument=nil } }) { file in
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
                }.foregroundStyle(JACTone.teal.color).padding(.horizontal,18).padding(.bottom,14).disabled(openingFile != nil || deleting)
                }.background(JACTheme.card,in:RoundedRectangle(cornerRadius:22))
                    .overlay(RoundedRectangle(cornerRadius:22).stroke(JACTone.teal.color.opacity(0.18),lineWidth:1))
            }
        }.padding(.vertical,6).jacStandaloneRow()
            .swipeActions(edge:.trailing,allowsFullSwipe:false) { if user.isOwner { deleteButton(item,destructive:false).tint(.red) } }
            .contextMenu { if user.isOwner { deleteButton(item) } }
        }
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
            return BoardingCodeImage(image:cropped,format:names[observation.symbology] ?? "Código",page:page)
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
                        if store.client.baseURL.host?.hasSuffix(".invalid") == true { Button("Adjuntar PDF ficticio") { let data = JACPlatform.fixturePDF(); add([NoticeUpload(filename:"Prueba.pdf",data:data)]) }.accessibilityIdentifier("notices.editor.fixture") }
                        #endif
                    }
                    if kind == "alert" { Section("Destinatarios") { ForEach(users) { user in Toggle(user.name + (user.ready == false ? " · Pendiente de activación" : ""), isOn: Binding(get: { recipients.contains(user.id) }, set: { value in if value { recipients.insert(user.id) } else { recipients.remove(user.id) } })).accessibilityIdentifier("notices.recipient.\(user.id)") } } }
                    else if kind == "boarding_pass" { Section("Pase de abordar privado") { Picker("Persona",selection:$passOwner) { Text("Selecciona una persona").tag(""); ForEach(boardingUsers) { Text($0.name).tag($0.id) } }.accessibilityIdentifier("boarding.recipient"); JACDatePicker("Fecha del pase",selection:$travelDate,displayedComponents:.date).environment(\.timeZone,CalendarClock.calendar.timeZone).accessibilityIdentifier("boarding.date"); Text("Solo la persona elegida podrá abrirlo. Usa Camilo 16 de octubre Pereira-Bogota; puedes incluir el año. El pasajero debe corresponder a la persona elegida. Sin año se usa la fecha más cercana; revisa la fecha antes de publicar.").font(.footnote).foregroundStyle(.secondary) } }
                    else { Section { Text("Se publicará directamente en Itinerarios para todo el equipo activo y enviará el aviso de itinerario nuevo.") } }
                }.disabled(busy || attempted || importing)
                if attempted && !busy && error != nil { Section { Text("Reintenta con estos mismos datos. Para cambiar el contenido, cierra y abre un formulario nuevo.").font(.footnote) } }
                Section { Button(busy ? "Guardando…" : kind == "boarding_pass" ? "Publicar pase y notificar" : kind == "itinerary" ? "Publicar itinerario y notificar" : "Crear alerta y notificar") { Task { await save() } }.buttonStyle(JACPrimaryButtonStyle()).disabled(busy || importing || store.isOffline).accessibilityIdentifier("notices.editor.save") }
            }.jacSurface().navigationTitle("Crear alerta o itinerario").jacInlineTitle().toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() }.disabled(busy) } }
                .fileImporter(isPresented: $picking, allowedContentTypes: [.pdf,.jpeg,.png], allowsMultipleSelection: true) { result in
                    do { let urls = try result.get(); var incoming: [NoticeUpload] = []
                        for url in urls { let access = url.startAccessingSecurityScopedResource(); defer { if access { url.stopAccessingSecurityScopedResource() } }; let size = try url.resourceValues(forKeys:[.fileSizeKey]).fileSize ?? 0; guard size <= 10*1024*1024 else { throw APIError.message("El archivo supera los 10 MB.") }; let data = try Data(contentsOf:url); _ = try NoticeUpload.mime(data); incoming.append(NoticeUpload(filename:url.lastPathComponent,data:data)) }; add(incoming)
                    } catch { self.error = error.localizedDescription }
                }
                .jacFileDrop(enabled:!busy && !attempted && !importing) {urls in do{add(try NoticeUpload.readLocalFiles(urls))}catch{self.error=error.localizedDescription}}
                .onChange(of: photos) { _, selected in Task { await readPhotos(selected) } }
        }.interactiveDismissDisabled(busy)
    }
    private func add(_ incoming: [NoticeUpload]) { guard !attempted, !busy else { return }; let combined = files + incoming; guard combined.count <= 5, combined.reduce(0, { $0 + $1.data.count }) <= 10*1024*1024 else { error = "Elige hasta 5 archivos que sumen como máximo 10 MB."; return }; files = combined; if let name=incoming.first?.filename,let parsed=BoardingClock.filenameDate(name) { travelDate=parsed }; error = nil }
    private func readPhotos(_ selected: [PhotosPickerItem]) async {
        guard !selected.isEmpty else { return }; importing = true; defer { importing = false }
        do { var incoming: [NoticeUpload] = []; for (index, photo) in selected.enumerated() { guard let data = try await photo.loadTransferable(type:Data.self), data.count <= 10*1024*1024, let image = JACPlatformImage(data:data), let jpeg = image.jpegData(compressionQuality:0.9) else { throw APIError.message("No se pudo leer la foto o supera los 10 MB.") }; incoming.append(NoticeUpload(filename:"Foto-\(index+1).jpg",data:jpeg)) }; add(incoming); photos = [] }
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
