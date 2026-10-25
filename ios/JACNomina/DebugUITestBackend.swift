#if DEBUG
import Foundation
import CoreImage
import CoreText
import ImageIO

// Opt-in UI fixtures use .invalid URLs and an ephemeral protocol. They are
// excluded from Release and never read or write the real payroll or Keychain.
enum UITestBackend {
    static let base = URL(string: "https://ui-fixture.example.invalid")!
    // Synthetic codes; deliberately not a valid boarding pass or airline payload.
    static func boardingCodePDF() throws -> Data {
        let bytes=NSMutableData(),consumer=CGDataConsumer(data:bytes)!
        var box=CGRect(x:0,y:0,width:600,height:800)
        let pdf=CGContext(consumer:consumer,mediaBox:&box,nil)!,ci=CIContext()
        for (position,type) in ["CIQRCodeGenerator","CIPDF417BarcodeGenerator"].enumerated() {
            let filter=CIFilter(name:type)!
            filter.setValue(Data("JAC FICTICIO SIN VALIDEZ - CODIGO \(position+1)".utf8),forKey:"inputMessage")
            let output=filter.outputImage!,image=ci.createCGImage(output,from:output.extent)!
            pdf.beginPDFPage(nil);pdf.setFillColor(CGColor(gray:1,alpha:1));pdf.fill(box);pdf.interpolationQuality = .none
            let width:CGFloat=position == 0 ? 180:460,height=width*CGFloat(image.height)/CGFloat(image.width)
            pdf.draw(image,in:CGRect(x:position == 0 ? 65:80,y:position == 0 ? 110:540,width:width,height:height))
            pdf.endPDFPage()
        }
        pdf.closePDF();return bytes as Data
    }
    // Generated locally for one Wallet-menu UI flow. No real passenger, flight,
    // airline credentials or provider request is included in this document.
    static func boardingWalletPDF(departureTime: String = "18:45") throws -> Data {
        let passenger = "TRAVELLER/FIXTURE".padding(toLength:20,withPad:" ",startingAt:0)
        let message = "M1" + passenger + "E" + "DEMO123" + "BOG" + "MDE" + "ZZ " + "00123" + "123" + "Y" + "012A" + "00001" + "1" + "00"
        let bytes=NSMutableData(),consumer=CGDataConsumer(data:bytes)!
        var box=CGRect(x:0,y:0,width:600,height:800)
        let pdf=CGContext(consumer:consumer,mediaBox:&box,nil)!,filter=CIFilter(name:"CIQRCodeGenerator")!
        filter.setValue(Data(message.utf8),forKey:"inputMessage")
        filter.setValue("M",forKey:"inputCorrectionLevel")
        let output=filter.outputImage!,image=CIContext().createCGImage(output,from:output.extent)!
        pdf.beginPDFPage(nil);pdf.setFillColor(CGColor(gray:1,alpha:1));pdf.fill(box)
        let attributes:[NSAttributedString.Key:Any]=[
            NSAttributedString.Key(kCTFontAttributeName as String):CTFontCreateWithName("Helvetica" as CFString,16,nil),
            NSAttributedString.Key(kCTForegroundColorAttributeName as String):CGColor(gray:0,alpha:1),
        ]
        let labels=["DOCUMENTO FICTICIO - SIN VALIDEZ", "PASAJERO: FIXTURE TRAVELLER", "ORIGEN: BOG", "DESTINO: MDE", "HORA DEL VUELO: " + departureTime, "HORA EN SALA: 18:05", "SILLA: 12A"]
        for (index,text) in labels.enumerated() {
            pdf.textMatrix = .identity;pdf.textPosition=CGPoint(x:50,y:740-CGFloat(index)*30)
            CTLineDraw(CTLineCreateWithAttributedString(NSAttributedString(string:text,attributes:attributes) as CFAttributedString),pdf)
        }
        pdf.interpolationQuality = .none;pdf.draw(image,in:CGRect(x:70,y:110,width:300,height:300))
        pdf.endPDFPage();pdf.closePDF();return bytes as Data
    }
    @MainActor static func client(reader: Bool = false, conflict: Bool = false, cancelledReads: Bool = false, offline: Bool = false, slowAgenda: Bool = false, persistentAgenda: Bool = false, resetAgenda: Bool = false, contentCache: OfflineResponseCache? = nil, downloadOffline: Bool? = nil) -> PayrollClient {
        FixtureProtocol.reset(reader: reader, conflict: conflict, cancelledReads: cancelledReads, offline: offline, slowAgenda: slowAgenda)
        let configuration = URLSessionConfiguration.ephemeral; configuration.protocolClasses = [FixtureProtocol.self]
        let cache = AgendaOfflineCache(root: persistentAgenda ? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("JACAgendaUITest") : FileManager.default.temporaryDirectory.appendingPathComponent("agenda-fixture-" + UUID().uuidString))
        if resetAgenda { try? FileManager.default.removeItem(at: cache.root) }
        let arguments = ProcessInfo.processInfo.arguments
        let persistent = arguments.contains("--uitest-offline-content")
        if persistent { FixtureProtocol.seedOfflineContent() }
        let content = OfflineResponseCache(root: persistent ? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("JACContentUITest") : FileManager.default.temporaryDirectory.appendingPathComponent("content-fixture-" + UUID().uuidString))
        if arguments.contains("--uitest-reset-content") { try? FileManager.default.removeItem(at: content.root) }
        let mediaRoot = persistent ? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("JACMediaUITest") : FileManager.default.temporaryDirectory.appendingPathComponent("media-fixture-" + UUID().uuidString)
        if arguments.contains("--uitest-reset-media") { try? FileManager.default.removeItem(at: mediaRoot) }
        let vault = FixtureSession(); if reader { vault.token = String(repeating: "r", count: 43) }
        return PayrollClient(baseURL: base, vault: vault, configuration: configuration, agendaCache: cache, offlineCache: contentCache ?? content, mediaOffline: MediaOfflineCache(root: mediaRoot), automaticallyDownloadOffline: downloadOffline ?? persistent)
    }
}
private final class FixtureSession: SessionStoring {
    var token: String? = String(repeating: "f", count: 43)
    func load() throws -> String? { token }
    func save(_ token: String) throws { self.token = token }
    func clear() throws { token = nil }
}
private final class FixtureProtocol: URLProtocol {
    private var delayedResponse:DispatchWorkItem?
    private let responseLock=NSLock()
    private var stopped=false
    private var isStopped:Bool {responseLock.lock();defer{responseLock.unlock()};return stopped}
    static let lock = NSRecursiveLock()
    static var state = initialState()
    static var revision = 1
    static var reader = false
    static var conflict = false
    static var agendaChanges: [String: JSONValue] = [:]
    static var overrides:[String:JSONValue]=[:]
    static var expenses:[JSONValue]=[]
    static var alerts: [JSONValue] = []
    static var deletedNotices = Set<String>()
    static var attachments: [String: Data] = [:]
    static var contracts:[JSONValue]=[]
    static var readsToCancel = Set<String>()
    static var offline = false
    static var slowAgenda = false
    static var slowedWorkspace = false
    static var slowedMedia = false
    static func reset(reader: Bool, conflict: Bool, cancelledReads: Bool, offline: Bool, slowAgenda: Bool) { lock.lock(); defer { lock.unlock() }; state = initialState();CRMFixture.reset();MediaFixture.reset(); revision = 1; self.reader = reader; self.conflict = conflict; self.offline = offline; self.slowAgenda = slowAgenda; slowedWorkspace = false; slowedMedia = false; agendaChanges = [:]; overrides=[:];expenses=[];alerts = []; contracts=ProcessInfo.processInfo.arguments.contains("--uitest-contract-archive") ? [.object(["id":.string("11111111-1234-4234-8234-111111111111"),"filename":.string("Contrato JAC - Pereira - 31 de octubre 2026.pdf"),"municipality":.string("Pereira"),"company":.string("EMPRESA FICTICIA JAC SAS"),"eventDate":.string("2026-10-31"),"price":.number(140000000),"showId":.null,"showTitle":.string(""),"version":.number(1)])]:[]; deletedNotices = []; attachments = [:]; readsToCancel = cancelledReads ? ["/api/mobile/payroll?period", "/api/calendar", "/api/notices", "/api/notices?read", "/api/payroll/email", "/api/users"] : [] }
    static func seedOfflineContent() {
        lock.lock(); defer { lock.unlock() }
        var alert = itinerary
        alert["id"] = .string("55555555-5555-4555-8555-555555555555"); alert["kind"] = .string("alert")
        alert["title"] = .string("Alerta guardada de prueba"); alert["body"] = .string("Contenido ficticio disponible sin conexión.")
        alert["attachments"] = .array([]); alerts = [alert]
    }
    static func cancelRead(_ request: URLRequest) -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard request.httpMethod == "GET", let url = request.url else { return false }
        let key = url.path + (url.path == "/api/mobile/payroll" && url.query?.contains("period=") == true ? "?period" : "")
        return readsToCancel.remove(key) != nil
    }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        if ProcessInfo.processInfo.arguments.contains("--uitest-async-slow-workspace"), request.url?.host == "ui-fixture.example.invalid", request.url?.path == "/api/mobile/payroll", request.url?.query?.contains("workspace=1") == true {
            Self.lock.lock();let delay = !Self.slowedWorkspace;Self.slowedWorkspace=true;Self.lock.unlock()
            if delay {
                let work=DispatchWorkItem { [weak self] in self?.deliverResponse() };delayedResponse=work
                DispatchQueue.global(qos:.userInitiated).asyncAfter(deadline:.now()+8,execute:work)
                return
            }
        }
        deliverResponse()
    }
    private func deliverResponse() {
        do {
            guard request.url?.host == "ui-fixture.example.invalid" || (request.url?.host == "www.googleapis.com" && request.url?.path == "/upload/drive/v3/files") else { throw URLError(.unsupportedURL) }
            if Self.offline { throw URLError(.notConnectedToInternet) }
            if ProcessInfo.processInfo.arguments.contains("--uitest-slow-content"), request.url?.path == "/api/mobile/payroll", request.url?.query?.contains("workspace=1") == true {
                Self.lock.lock(); let delay = !Self.slowedWorkspace; Self.slowedWorkspace = true; Self.lock.unlock()
                if delay { Thread.sleep(forTimeInterval: 8) }
            }
            if ProcessInfo.processInfo.arguments.contains("--uitest-slow-media"), request.url?.path == "/api/media", request.httpMethod == "GET" {
                Self.lock.lock();let delay = !Self.slowedMedia;Self.slowedMedia = true;Self.lock.unlock()
                if delay {Thread.sleep(forTimeInterval:2)}
            }
            if Self.slowAgenda, request.url?.path == "/api/calendar", request.httpMethod == "GET" { Thread.sleep(forTimeInterval: 3) }
            if Self.cancelRead(request) { throw URLError(.cancelled) }
            if request.url?.host == "www.googleapis.com" {
                guard request.url?.path == "/upload/drive/v3/files", request.value(forHTTPHeaderField: "Cookie") == nil, request.value(forHTTPHeaderField: "Authorization") == nil else { throw URLError(.unsupportedURL) }
                if ProcessInfo.processInfo.arguments.contains("--uitest-slow-media-upload"){Thread.sleep(forTimeInterval:2)}
                let result = try MediaFixture.direct(request), response = HTTPURLResponse(url: request.url!, statusCode: result, httpVersion: nil, headerFields: nil)!
                client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed); client?.urlProtocolDidFinishLoading(self); return
            }
            if request.url?.path == "/api/media/file" {
                let result = try MediaFixture.file(request)
                var code = result.0, body = result.2, headers = ["Content-Type": result.1]
                if code == 200, let range = request.value(forHTTPHeaderField: "Range") {
                    let parts = range.replacingOccurrences(of: "bytes=", with: "").split(separator: "-")
                    guard parts.count == 2, let start = Int(parts[0]), let end = Int(parts[1]), start >= 0, end >= start, end < body.count else { throw URLError(.badServerResponse) }
                    headers["Content-Range"] = "bytes \(start)-\(end)/\(body.count)"; code = 206; body = body.subdata(in: start..<(end + 1))
                }
                if ProcessInfo.processInfo.arguments.contains("--uitest-slow-photo-preview"),code==200,
                   let query=URLComponents(url:request.url!,resolvingAgainstBaseURL:false)?.queryItems,
                   query.contains(where:{$0.name=="id" && $0.value?.hasSuffix("media-photo-2")==true}),
                   !query.contains(where:{["thumbnail","metadata"].contains($0.name)}) {
                    headers["Content-Length"]=String(body.count)
                    let response=HTTPURLResponse(url:request.url!,statusCode:code,httpVersion:nil,headerFields:headers)!,split=max(1,body.count/2)
                    client?.urlProtocol(self,didReceive:response,cacheStoragePolicy:.notAllowed)
                    client?.urlProtocol(self,didLoad:body.prefix(split))
                    let tail=body.dropFirst(split)
                    let work=DispatchWorkItem { [weak self] in
                        guard let self,!self.isStopped else{return}
                        self.client?.urlProtocol(self,didLoad:Data(tail));self.client?.urlProtocolDidFinishLoading(self)
                    };delayedResponse=work
                    DispatchQueue.global(qos:.userInitiated).asyncAfter(deadline:.now()+12,execute:work)
                    return
                }
                let response = HTTPURLResponse(url: request.url!, statusCode: code, httpVersion: nil, headerFields: headers)!
                client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed); client?.urlProtocol(self, didLoad: body); client?.urlProtocolDidFinishLoading(self); return
            }
            if request.url?.path == "/api/mobile/contracts" {
                Self.lock.lock();defer {Self.lock.unlock()}
                guard request.value(forHTTPHeaderField:"Authorization") == "Bearer "+String(repeating:"f",count:43),request.value(forHTTPHeaderField:"Cookie") == nil else {throw URLError(.userAuthenticationRequired)}
                if Self.reader {let r=HTTPURLResponse(url:request.url!,statusCode:403,httpVersion:nil,headerFields:["Content-Type":"application/json"])!;client?.urlProtocol(self,didReceive:r,cacheStoragePolicy:.notAllowed);client?.urlProtocol(self,didLoad:Data("{\"error\":\"CRM solo administradores\"}".utf8));client?.urlProtocolDidFinishLoading(self);return}
                let q=URLComponents(url:request.url!,resolvingAgainstBaseURL:false)?.queryItems ?? []
                let fileId=q.first{$0.name=="id"}?.value
                let command=request.httpMethod == "POST" ? try Self.body(request):.null
                if fileId == nil && command["action"].text != "save" && !(request.httpMethod == "POST" && command["action"].isNull) {
                    var data:JSONValue
                    if command["action"].text == "delete" {
                        guard let index=Self.contracts.firstIndex(where:{$0["id"]==command["id"]}),Self.contracts[index]["version"] == command["version"],command["confirmation"] == command["id"] else {throw URLError(.badServerResponse)}
                        Self.contracts.remove(at:index);data = .object(["ok":.bool(true)])
                    } else if command["action"].text == "link" {
                        guard let index=Self.contracts.firstIndex(where:{$0["id"].text==command["id"].text}),Self.contracts[index]["version"] == command["version"] else {throw URLError(.badServerResponse)}
                        Self.contracts[index]["showId"]=command["showId"];Self.contracts[index]["showTitle"] = .string(CRMFixture.shows.first{$0["id"]==command["showId"]}?["title"].text ?? "");Self.contracts[index]["version"] = .number(command["version"].number+1);data = .object(["ok":.bool(true)])
                    } else if q.first(where:{$0.name=="view"})?.value == "shows" {data = .object(["shows":.array(CRMFixture.shows),"next":.null])}
                    else {data = .object(["contracts":.array(Self.contracts),"next":.null])}
                    let response=HTTPURLResponse(url:request.url!,statusCode:200,httpVersion:nil,headerFields:["Content-Type":"application/json"])!;client?.urlProtocol(self,didReceive:response,cacheStoragePolicy:.notAllowed);client?.urlProtocol(self,didLoad:try JSONEncoder().encode(data));client?.urlProtocolDidFinishLoading(self);return
                }
                let input=command["action"].text == "save" ? command["input"]:command;var draft=ContractDraft();draft.municipality=input["municipality"].text;draft.eventDate=input["eventDate"].text
                let existing=Self.contracts.first{$0["id"].text==fileId}
                if fileId != nil && existing == nil {
                    let response=HTTPURLResponse(url:request.url!,statusCode:404,httpVersion:nil,headerFields:["Content-Type":"application/json"])!;client?.urlProtocol(self,didReceive:response,cacheStoragePolicy:.notAllowed);client?.urlProtocol(self,didLoad:Data("{\"error\":\"Contrato no disponible\"}".utf8));client?.urlProtocolDidFinishLoading(self);return
                }
                let filename=existing?["filename"].text ?? draft.filename
                if command["action"].text == "save" && !Self.contracts.contains(where:{$0["id"]==command["id"]}) {Self.contracts.insert(.object(["id":command["id"],"filename":.string(filename),"municipality":input["municipality"],"company":input["company"],"eventDate":input["eventDate"],"price":input["price"],"showId":command["showId"],"showTitle":.string(CRMFixture.shows.first{$0["id"]==command["showId"]}?["title"].text ?? ""),"version":.number(1)]),at:0)}
                let name=filename.addingPercentEncoding(withAllowedCharacters:.urlPathAllowed)!
                let response=HTTPURLResponse(url:request.url!,statusCode:200,httpVersion:nil,headerFields:["Content-Type":"application/pdf","Content-Disposition":"attachment; filename*=UTF-8''"+name])!
                client?.urlProtocol(self,didReceive:response,cacheStoragePolicy:.notAllowed);client?.urlProtocol(self,didLoad:Data(base64Encoded:Self.pdf)!);client?.urlProtocolDidFinishLoading(self);return
            }
            if request.url?.path == "/api/crm/file" {
                Self.lock.lock();defer {Self.lock.unlock()}
                let q=URLComponents(url:request.url!,resolvingAgainstBaseURL:false)!.queryItems ?? [],id=q.first{$0.name=="file"}?.value ?? ""
                guard !Self.reader,let data=CRMFixture.bytes[id] else {throw URLError(.fileDoesNotExist)}
                let response=HTTPURLResponse(url:request.url!,statusCode:200,httpVersion:nil,headerFields:["Content-Type":try NoticeUpload.mime(data)])!
                client?.urlProtocol(self,didReceive:response,cacheStoragePolicy:.notAllowed);client?.urlProtocol(self,didLoad:data);client?.urlProtocolDidFinishLoading(self);return
            }
            if request.url?.path == "/api/expenses/file" {
                Self.lock.lock();defer { Self.lock.unlock() };let q=URLComponents(url:request.url!,resolvingAgainstBaseURL:false)!.queryItems ?? [],id=q.first { $0.name == "file" }?.value ?? "";guard let bytes=Self.attachments[id] else { throw URLError(.fileDoesNotExist) };let response=HTTPURLResponse(url:request.url!,statusCode:200,httpVersion:nil,headerFields:["Content-Type":try NoticeUpload.mime(bytes)])!;client?.urlProtocol(self,didReceive:response,cacheStoragePolicy:.notAllowed);client?.urlProtocol(self,didLoad:bytes);client?.urlProtocolDidFinishLoading(self);return
            }
            if request.url?.path == "/api/notices/file" {
                Self.lock.lock(); defer { Self.lock.unlock() }; let q = URLComponents(url:request.url!,resolvingAgainstBaseURL:false)!.queryItems ?? []; let notice = q.first { $0.name == "id" }?.value ?? "", id = q.first { $0.name == "file" }?.value ?? ""
                let viewer=Self.reader ? "22222222-2222-4222-8222-222222222222" : "11111111-1111-4111-8111-111111111111"
                let item=(Self.boardingFixtures+Self.alerts).first { $0["id"].text==notice }
                guard item?["kind"].text != "boarding_pass" || item?["recipients"].elements.contains(.string(viewer)) == true else { throw URLError(.fileDoesNotExist) }
                let codePDF:Data?
                if ProcessInfo.processInfo.arguments.contains("--uitest-wallet-menu"),id.hasPrefix("boarding-fixture-") { codePDF=try UITestBackend.boardingWalletPDF(departureTime: ProcessInfo.processInfo.arguments.contains("--uitest-boarding-card-midnight") ? "00:30":"18:45") }
                else { codePDF=ProcessInfo.processInfo.arguments.contains("--uitest-boarding-code") && id.hasPrefix("boarding-fixture-") ? try UITestBackend.boardingCodePDF():nil }
                guard !Self.deletedNotices.contains(notice), let bytes = Self.attachments[id] ?? codePDF ?? (id.hasPrefix("boarding-fixture-") ? Data(base64Encoded:Self.pdf) : nil) else { throw URLError(.fileDoesNotExist) }
                let reply = HTTPURLResponse(url:request.url!,statusCode:200,httpVersion:nil,headerFields:["Content-Type":try NoticeUpload.mime(bytes)])!; client?.urlProtocol(self,didReceive:reply,cacheStoragePolicy:.notAllowed); client?.urlProtocol(self,didLoad:bytes); client?.urlProtocolDidFinishLoading(self); return
            }
            if request.url?.path == "/api/notices/pdf" {
                let reply = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/pdf"])!
                client?.urlProtocol(self, didReceive: reply, cacheStoragePolicy: .notAllowed)
                client?.urlProtocol(self, didLoad: Data(base64Encoded: Self.pdf)!)
                client?.urlProtocolDidFinishLoading(self); return
            }
            let (status, body) = try Self.response(request)
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: try JSONEncoder().encode(body))
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {responseLock.lock();stopped=true;responseLock.unlock();delayedResponse?.cancel()}
    static func body(_ request: URLRequest) throws -> JSONValue {
        var bytes = request.httpBody ?? Data()
        if bytes.isEmpty, let stream = request.httpBodyStream {
            stream.open(); defer { stream.close() }; var buffer = [UInt8](repeating: 0, count: 4096)
            while true { let count = stream.read(&buffer, maxLength: buffer.count); if count <= 0 { break }; bytes.append(contentsOf: buffer.prefix(count)) }
        }
        return try JSONDecoder().decode(JSONValue.self, from: bytes)
    }
    static var user: JSONValue {
        let arguments=ProcessInfo.processInfo.arguments
        var user: JSONValue = .object(["id": .string("fixture-user"), "username": .string("simulado"), "email": .string("test@example.invalid"), "displayName": .string("Cuenta simulada"), "itinerariesOnly":.bool(arguments.contains("--uitest-itineraries-only")), "isOwner": .bool(!reader), "permissions": .array([])])
        if arguments.contains("--uitest-media-manager") {user["username"] = .string("anderson")}
        if arguments.contains("--uitest-media-only") {user["mediaOnly"] = .bool(true);user["itinerariesOnly"] = .bool(true);user["isOwner"] = .bool(false);user["displayName"] = .string("Anderson ficticio")}
        if let selection=arguments.first(where:{$0.hasPrefix("--uitest-sections=")}) {
            let sections=selection.dropFirst("--uitest-sections=".count).split(separator:",").map(String.init)
            user["sections"] = .array(sections.map(JSONValue.string));user["isOwner"] = .bool(false)
            user["mediaOnly"] = .bool(sections.contains("media") && !sections.contains("payroll"));user["itinerariesOnly"] = .bool(!sections.contains("payroll"))
        }
        return user
    }
    static func response(_ request: URLRequest) throws -> (Int, JSONValue) {
        lock.lock(); defer { lock.unlock() }
        let parts = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!
        let viewer = reader ? "22222222-2222-4222-8222-222222222222" : "11111111-1111-4111-8111-111111111111"
        let visible = ([itinerary] + boardingFixtures + alerts).map { overrides[$0["id"].text] ?? $0 }.filter { !(ProcessInfo.processInfo.arguments.contains("--uitest-boarding-tomorrow") && ["boarding-fixture-0","boarding-fixture-1"].contains($0["id"].text)) && !deletedNotices.contains($0["id"].text) && ($0["kind"].text != "boarding_pass" || $0["recipients"].elements.contains(.string(viewer))) }
        if parts.path == "/api/music" {
            let sections = ["warmup", "tracks", "demos", "studio"]
            let names = ["Calentamiento vocal", "Árbol", "Maqueta nueva", "Sesión estudio"]
            let tracks = sections.enumerated().map { index, section in JSONValue.object(["id":.string("00000000-0000-4000-8000-00000000000\(index)"),"section":.string(section),"title":.string(names[index]),"filename":.string(names[index]+".wav"),"mimeType":.string("audio/wav"),"size":.number(128),"revision":.string("fixture-music-revision"),"createdAt":.string("2026-10-19T12:00:00Z")]) }
            return (200, .object(["tracks":.array(tracks),"canUpload":.bool(user["isOwner"].flag || user["sections"].elements.contains(.string("musicUpload"))),"canDelete":user["isOwner"]]))
        }
        if parts.path == "/api/media/playback" { return (200,.object(["ready":.bool(true),"url":.string("https://ui-fixture.example.invalid/api/media/playback?lease=fixture&asset=manifest/video.m3u8")])) }
        if parts.path == "/api/media" || parts.path == "/api/media/upload" || parts.path == "/api/media/shares" { return try MediaFixture.response(request) }
        if parts.path == "/api/crm" {return try CRMFixture.response(request,reader:reader)}
        if parts.path == "/api/expenses" {
            if request.httpMethod == "POST" {
                var input=try body(request)
                if parts.queryItems?.contains(where: { $0.name == "review" }) == true {
                    guard !reader,let index=expenses.firstIndex(where: { $0["id"] == input["id"] }) else { return (403,.object(["error":.string("No autorizado")])) }
                    if expenses[index]["status"].text == "pending" { expenses[index]["status"] = .string(input["decision"].text == "approve" ? "approved" : "rejected");expenses[index]["reviewNote"]=input["reason"];expenses[index]["employeeId"]=input["employeeId"];expenses[index]["periodId"]=input["periodId"] }
                    return (200,.object(["ok":.bool(true)]))
                }
                let id=input["id"].text
                if !expenses.contains(where: { $0["id"].text == id }) {
                    let files=try input["files"].elements.map { file -> JSONValue in guard let data=Data(base64Encoded:file["data"].text) else { throw APIError.message("Archivo inválido") };let fid=UUID().uuidString.lowercased();attachments[fid]=data;return .object(["id":.string(fid),"filename":file["filename"],"mimeType":.string(try NoticeUpload.mime(data)),"size":.number(Double(data.count))]) }
                    input["attachments"] = .array(files);input["userId"] = .string(viewer);input["name"] = .string("Cuenta simulada");input["status"] = .string("pending");input["version"] = .number(1);input["reviewNote"] = .string("");input["periodId"] = .string("");input["employeeId"] = .string("");expenses.append(input)
                }
                return (200,.object(["id":.string(id)]))
            }
            return (200,.object(["expenses":.array(expenses),"nextCursor":.string(""),"reviewer":.bool(!reader),"employees":.array([.object(["id":.string("music"),"name":.string("Música simulada")])]),"periods":.array([.object(["id":.string("fixture-period"),"name":.string("Quincena simulada")])])]))
        }
        if parts.path == "/api/notices/publish" {
            guard !reader else { return (403,.object(["error":.string("Solo Camilo puede publicar.")])) }
            guard request.value(forHTTPHeaderField:"Origin") == UITestBackend.base.absoluteString, request.value(forHTTPHeaderField:"Cookie")?.hasPrefix("__Host-jac_session=") == true else { return (403,.object(["error":.string("Sesión requerida.")])) }
            var item = try body(request); let id = item["id"].text
            if deletedNotices.contains(id) { return (410,.object(["error":.string("Aviso eliminado.")])) }
            if parts.queryItems?.contains(where: { $0.name == "update" }) == true, var existing=visible.first(where: { $0["id"].text == id }) {
                existing["title"]=item["title"];existing["body"]=item["body"];existing["revision"] = .number(existing["revision"].number+1);existing["changeSummary"]=item["summary"];existing["confirmed"] = .bool(false);existing["filename"] = .string("")
                existing["attachments"] = .array(try item["files"].elements.map { file in let bytes=Data(base64Encoded:file["data"].text)!;let fid=UUID().uuidString.lowercased();attachments[fid]=bytes;return .object(["id":.string(fid),"filename":file["filename"],"mimeType":.string(try NoticeUpload.mime(bytes)),"size":.number(Double(bytes.count))]) });overrides[id]=existing;return (200,.object(["id":.string(id)]))
            }
            if !alerts.contains(where: { $0["id"].text == id }) {
                let files = try item["files"].elements.map { file -> JSONValue in
                    guard let data = Data(base64Encoded:file["data"].text) else { throw APIError.message("Adjunto inválido") }; let fid = UUID().uuidString.lowercased(); attachments[fid] = data
                    return .object(["id":.string(fid),"filename":file["filename"],"mimeType":.string(try NoticeUpload.mime(data)),"size":.number(Double(data.count))])
                }
                item["attachments"] = .array(files); item["files"] = .null; item["filename"] = .string(""); item["size"] = .number(0); item["createdAt"] = .string("2026-10-07T12:00:00Z"); item["read"] = .bool(false); alerts.append(item)
            }
            return (200,.object(["id":.string(id)]))
        }
        if parts.path == "/api/notices/recipients" {
            let actor=try user.decoded(PayrollUser.self)
            guard request.httpMethod == "GET",actor.isOwner,actor.hasSection(.crm) else {
                return (403,.object(["error":.string("Sin permiso para administrar destinatarios.")]))
            }
            let users:[JSONValue]=[
                .object(["id":.string("11111111-1111-4111-8111-111111111111"),"name":.string("Camilo simulado")]),
                .object(["id":.string("22222222-2222-4222-8222-222222222222"),"name":.string("Luisa simulada")]),
                .object(["id":.string("77777777-7777-4777-8777-777777777777"),"name":.string("Jhon Alex simulado"),"ready":.bool(false)]),
                .object(["id":.string("88888888-8888-4888-8888-888888888888"),"name":.string("Alex Zuluaga simulado"),"ready":.bool(false)]),
            ]
            return (200,.object(["users":.array(users),"boardingUsers":.array(users)]))
        }
        if parts.path == "/api/notices/wallet", ProcessInfo.processInfo.arguments.contains("--uitest-wallet-menu") {
            // This flow stops at reviewing/editing data. Any automatic signing
            // request is a regression; the fixture never fabricates a PKPass.
            precondition(request.httpMethod == "GET", "Wallet UI fixture must not create a pass before an explicit add action.")
            return (200,.object(["configured":.bool(true),"version":.number(1),"passTypeId":.string("pass.co.jacmusic.fixture"),"expiresAt":.string("2090-01-01T00:00:00Z")]))
        }
        if parts.path == "/api/notices" {
            if request.httpMethod == "POST" {
                let command = try body(request)
                if command["action"].text == "confirm",var item=visible.first(where: { $0["id"] == command["id"] }) { item["confirmed"] = .bool(true);item["receipts"] = .array([.object(["userId":.string(viewer),"name":.string("Cuenta simulada"),"confirmed":.bool(true),"confirmedAt":.string("2026-10-08T12:00:00Z")])]);overrides[item["id"].text]=item;return (200,.object(["ok":.bool(true)])) }
                if command["action"].text == "read", readsToCancel.remove("/api/notices?read") != nil { throw URLError(.cancelled) }
                if ["deleteAlert","deleteItinerary","deleteBoardingPass"].contains(command["action"].text) {
                    guard !reader else { return (403,.object(["error":.string("Solo Camilo puede eliminar.")])) }
                    guard command["confirmation"] == command["id"] else { return (400,.object(["error":.string("Confirma el aviso.")])) }
                    if command["action"].text == "deleteBoardingPass",let item=boardingFixtures.first(where:{$0["id"] == command["id"]}),!item["recipients"].elements.contains(.string(viewer)) { return (404,.object(["error":.string("Pase no disponible.")])) }
                    deletedNotices.insert(command["id"].text)
                }
                if command["action"].text == "alert" {
                    guard !reader else { return (403, .object(["error": .string("Solo Camilo puede crear alertas.")])) }
                    var item = command["alert"]; item["kind"] = .string("alert"); item["filename"] = .string(""); item["size"] = .number(0); item["createdAt"] = .string("2026-10-07T12:00:00Z"); item["read"] = .bool(false)
                    if !alerts.contains(where: { $0["id"] == item["id"] }) { alerts.append(item) }
                }
                return (200, .object(["ok": .bool(true)]))
            }
            if let id = parts.queryItems?.first(where: { $0.name == "item" })?.value {
                guard let item = visible.first(where: { $0["id"].text == id }) else { return (404, .object(["error": .string("El aviso no está disponible.")])) }
                return (200, .object(["item": item]))
            }
            let boarding=parts.queryItems?.first { $0.name=="boarding" }?.value
            let records=boarding == nil ? visible.filter { $0["kind"].text != "boarding_pass" } : visible.filter { $0["kind"].text == "boarding_pass" && (boarding == "history" ? $0["travelDate"].text < BoardingClock.today() : $0["travelDate"].text >= BoardingClock.today()) }.sorted { $0["travelDate"].text < $1["travelDate"].text }
            return (200, .object(["notices":.array(records),"today":.string(BoardingClock.today()),"nextCursor":.string(""),"settings":.object(["version":.number(0),"slackConnected":.bool(true),"appleConfigured":.bool(true),"webPublicKey":.string("")]),"users":reader ? .array([]) : .array([.object(["id":.string("11111111-1111-4111-8111-111111111111"),"name":.string("Camilo simulado")]),.object(["id":.string("22222222-2222-4222-8222-222222222222"),"name":.string("Luisa simulada")]),.object(["id":.string("77777777-7777-4777-8777-777777777777"),"name":.string("Jhon Alex simulado"),"ready":.bool(false)]),.object(["id":.string("88888888-8888-4888-8888-888888888888"),"name":.string("Alex Zuluaga simulado"),"ready":.bool(false)])])]))
        }
        if parts.path == "/api/calendar" {
            if request.httpMethod == "POST" {
                let command = try body(request), action = command["action"].text
                guard request.value(forHTTPHeaderField: "Origin") == UITestBackend.base.absoluteString, request.value(forHTTPHeaderField: "Cookie")?.hasPrefix("__Host-jac_session=") == true else { return (403, .object(["error": .string("Inicia sesión con una cuenta autorizada para editar Agenda.")])) }
                guard ["createEvent", "updateEvent"].contains(action) else { return (403, .object(["error": .string("La conexión real a Google no forma parte de las pruebas.")])) }
                guard command["revision"].number == 1 else { return (409, .object(["error": .string("La conexión cambió. Actualiza Agenda.")])) }
                let old = agenda(CalendarClock.month(Date()))["upcoming"].elements.first { $0["id"] == command["eventId"] }
                if action == "updateEvent", old?["etag"] != command["etag"] { return (409, .object(["error": .string("Otra persona modificó este evento.")])) }
                var event = command["event"]; let id = action == "createEvent" ? "fixture-" + command["requestId"].text : command["eventId"].text
                event["id"] = .string(id); event["etag"] = .string("fixture-" + UUID().uuidString); event["editable"] = .bool(true); event["recurring"] = old?["recurring"] ?? .bool(false); event["url"] = .string(""); agendaChanges[id] = event
                return (200, .object(["event": event, "notice": .string(action == "createEvent" ? "Evento creado en Google Calendar." : "Evento actualizado en Google Calendar.")]))
            }
            if parts.queryItems?.first(where: { $0.name == "action" })?.value == "calendars" { return reader ? (403, .object(["error": .string("Solo Camilo puede elegir el calendario.")])) : (200, .object(["calendars": .array([agendaCalendar])])) }
            return (200, agenda(parts.queryItems?.first(where: { $0.name == "month" })?.value ?? CalendarClock.month(Date())))
        }
        if request.httpMethod == "POST" {
            let command = try body(request), action = command["action"].text
            if parts.path == "/api/auth" { return (200, .object(["ok": .bool(true)])) }
            if parts.path == "/api/mobile/payroll" {
                if reader { return (403, .object(["error": .string("Sin permiso para modificar la nómina.")])) }
                if action != "previewEdit", conflict { conflict = false; return (409, .object(["error": .string("Otra persona actualizó la nómina. Conserva tu formulario y actualiza.")])) }
                if Int(command["version"].number) != revision { return (409, .object(["error": .string("La nómina cambió. Actualiza antes de guardar.")])) }
                var next = state
                if ["edit", "previewEdit"].contains(action) { apply(command["edit"], to: &next) }
                else if action == "remove" {
                    let edit = command["edit"], collection = ["show": "shows", "showExpense": "showExpenses", "movement": "movements", "route": "routes"][edit["kind"].text] ?? ""
                    updatePeriod(edit["periodId"].text, in: &next) { p in p[collection] = .array(p[collection].elements.filter { $0["id"] != edit["id"] }) }
                } else if action == "close" {
                    let baseline = next
                    updatePeriod(command["periodId"].text, in: &next) { p in
                        var snapshot = calculation(baseline, p); snapshot["employees"] = p["calculationBase"]["employees"] == .null ? baseline["employees"] : p["calculationBase"]["employees"]
                        snapshot["closedAt"] = .string("2026-10-06T22:00:00Z"); snapshot["closedBy"] = .string("test@example.invalid"); p["snapshot"] = snapshot; p["status"] = .string("cerrada")
                    }
                } else if action == "reopen" {
                    updatePeriod(command["periodId"].text, in: &next) { p in
                        p["revisions"] = .array(p["revisions"].elements + [p["snapshot"]]); p["calculationBase"] = .object(["employees": p["snapshot"]["employees"], "settings": p["snapshot"]["settings"]]); p["snapshot"] = .null; p["ownerOnly"] = .bool(true); p["status"] = .string("abierta")
                    }
                } else if action == "deletePeriod" { next["periods"] = .array(next["periods"].elements.filter { $0["id"] != command["periodId"] }) }
                else if ["deleteEmployee", "restoreEmployee"].contains(action) {
                    next["employees"] = .array(next["employees"].elements.map { item in var e = item; if e["id"] == command["employeeId"] { e["active"] = .bool(false); e["deleted"] = .bool(action == "deleteEmployee") }; return e })
                }
                if action == "previewEdit" {
                    let edit = command["edit"], id = edit["kind"].text == "period" ? edit["record"]["id"].text : edit["periodId"].text
                    return (200, .object(["data": next, "version": .number(Double(revision)), "detail": detail(next, id: id)]))
                }
                state = next; revision += 1
                return (200, .object(["data": state, "version": .number(Double(revision))]))
            }
        }
        if parts.path == "/api/mobile/payroll" {
            if (try? user.decoded(PayrollUser.self).hasSection(.payroll)) == false { return (200, .object(["data": .object(["employees": .array([]), "periods": .array([]), "settings": .object(["company": .string("JAC")])]), "version": .number(Double(revision)), "user": user, "company": .string("JAC"), "periods": .array([]), "employees": .array([])])) }
            if let id = parts.queryItems?.first(where: { $0.name == "period" })?.value { return (200, detail(state, id: id)) }
            let periods = state["periods"].elements.map { p in JSONValue.object(["id": p["id"], "start": p["start"], "end": p["end"], "status": p["status"], "ownerOnly": .bool(p["ownerOnly"].flag), "showCount": .number(Double(p["shows"].elements.count)), "closedAt": p["snapshot"]["closedAt"]]) }
            return (200, .object(["data": state, "version": .number(Double(revision)), "user": user, "company": state["settings"]["company"], "periods": .array(periods), "employees": state["employees"]]))
        }
        if parts.path == "/api/users" { return (200, .object(["configured": .bool(true), "users": .array([])])) }
        if parts.path == "/api/payroll/email" { return (200, .object(["connection": .object(["sender": .string("test@example.invalid"), "configured": .bool(false), "connected": .bool(false), "error": .string(""), "callback": .string("https://ui-fixture.example.invalid/api/payroll/gmail/callback")]), "jobs": .array([]), "prepared": .bool(false)])) }
        return (404, .object(["error": .string("Ruta no prevista en las pruebas.")]))
    }
    static func updatePeriod(_ id: String, in state: inout JSONValue, update: (inout JSONValue) -> Void) {
        var periods = state["periods"].elements
        if let index = periods.firstIndex(where: { $0["id"].text == id }) { update(&periods[index]) }
        state["periods"] = .array(periods)
    }
    static func apply(_ edit: JSONValue, to state: inout JSONValue) {
        let kind = edit["kind"].text, record = edit["record"]
        if kind == "period" { var p = record; p["status"] = .string("abierta"); for key in ["shows", "movements", "routes", "hours", "excludedEmployees"] { p[key] = .array([]) }; state["periods"] = .array(state["periods"].elements + [p]); return }
        if kind == "settings" { state["settings"] = record; return }
        if ["employee", "concept"].contains(kind) { let key = kind == "employee" ? "employees" : "concepts"; state[key] = .array(state[key].elements.filter { $0["id"] != record["id"] } + [record]); return }
        updatePeriod(edit["periodId"].text, in: &state) { p in
            if kind == "periodSettings" { p["calculationBase"]["settings"] = record; return }
            if kind == "periodEmployee" { p["calculationBase"]["employees"] = .array(p["calculationBase"]["employees"].elements.map { $0["id"] == record["id"] ? record : $0 }); return }
            let key = ["show": "shows", "showExpense": "showExpenses", "movement": "movements", "route": "routes", "hours": "hours"][kind] ?? ""
            let id = kind == "hours" ? "employeeId" : "id"; p[key] = .array(p[key].elements.filter { $0[id] != record[id] } + [record])
        }
    }
    static func calculation(_ state: JSONValue, _ p: JSONValue) -> JSONValue {
        if p["status"].text == "cerrada" { return p["snapshot"] }
        // Fixed server response for UI tests; real calculations are tested in Node.
        var value: JSONValue = .object(["rows": .array([]), "sale": .number(0), "total": .number(0), "gross": .number(0), "deductions": .number(0), "reimbursements": .number(0), "company": state["settings"]["company"], "nit": state["settings"]["nit"], "settings": p["calculationBase"]["settings"] == .null ? state["settings"] : p["calculationBase"]["settings"]])
        if ProcessInfo.processInfo.arguments.contains("--uitest-commission") {
            // Canned server contract; financial formulas are tested in Node, not implemented in the app.
            value["camiloCommission"] = .object(["rate":.number(0.05),"sales":.number(10000000),"costs":.number(2000000),"promotionalCosts":.number(500000),"balance":.number(8000000),"base":.number(8000000),"amount":.number(400000),"shows":.array([]),"issues":.array([]),"unlinkedKilometers":.number(0)])
        }
        return value
    }
    static func detail(_ state: JSONValue, id: String) -> JSONValue {
        guard let p = state["periods"].elements.first(where: { $0["id"].text == id }) else { return .null }
        let employees = p["snapshot"]["employees"] == .null ? (p["calculationBase"]["employees"] == .null ? state["employees"] : p["calculationBase"]["employees"]) : p["snapshot"]["employees"]
        let drivers = employees.elements.filter { $0["category"].text == "conductores" }.map { JSONValue.object(["employeeId": $0["id"], "rate": $0["kmRate"]]) }
        let routes = p["shows"].elements.map { show in p["routes"].elements.first { $0["showId"] == show["id"] } ?? .object(["id": .string("route-"+show["id"].text), "showId": show["id"], "date": show["date"], "name": show["name"], "km": .number(0), "drivers": .array(drivers)]) }
        return .object(["version": .number(Double(revision)), "period": p, "employees": employees, "calculation": calculation(state,p), "closeIssues": .array([]), "editing": .object(["settings": state["settings"], "drivers": .array(drivers), "showRoutes": .array(routes), "concepts": state["concepts"]])])
    }
    static func initialState() -> JSONValue {
        func employee(_ id: String, name: String, category: String, salary: Double = 0, rate: Double = 0) -> JSONValue {
            .object(["id": .string(id), "name": .string(name), "email": .string(id+"@example.invalid"), "document": .string("PRUEBA"), "role": .string("Simulado"), "category": .string(category), "active": .bool(true), "showRate": .number(750000), "kmRate": .number(rate), "fixedService": .number(0), "withholding": .number(0.095), "ica": .number(0), "salary": .number(salary), "transport": .number(0), "pension": .bool(false), "health": .bool(true), "cycle": .string("quincenal"), "monthlyHalf": .number(2), "nonSalary": .number(0), "contributionBase": .number(1), "incomeTax": .number(0), "solidarity": .number(0)])
        }
        return .object(["employees": .array([employee("music", name: "Música simulada", category: "musicos"), employee("driver-a", name: "Conductor uno", category: "conductores", rate: 1000), employee("driver-b", name: "Conductor dos", category: "conductores", rate: 1250), employee("salary", name: "Dependiente simulado", category: "administracion", salary: 1500000)]), "settings": .object(["company": .string("Empresa simulada"), "nit": .string("PRUEBA"), "hourDivisor": .number(210), "hourFactors": .array([0.35,0.9,1.25,1.25,1.75,2.15,2.65].map { .number($0) })]), "concepts": .array([.object(["id": .string("test-concept"), "name": .string("Ensayo simulado"), "amount": .number(80000), "kind": .string("servicio")])]), "periods": .array([.object(["id": .string("fixture-period"), "start": .string("2025-09-16"), "end": .string("2025-09-30"), "status": .string("abierta"), "shows": .array([]), "movements": .array([]), "hours": .array([]), "routes": .array([]), "excludedEmployees": .array([])])])])
    }
    static let pdf = "JVBERi0xLjcKJYGBgYEKCjYgMCBvYmoKPDwKL0ZpbHRlciAvRmxhdGVEZWNvZGUKL0xlbmd0aCAxMTQKPj4Kc3RyZWFtCnicHYoxCgJBEATzfsXEgri7N9ezA2Kg3mFgIswHRE5RNFDE97tKUxQU/cQ6kOS31wWL3XT/TO/r6Ti35FVrsupSksQZRSX2yP9rlo6i2voDS3VTOgf2VpgbzrEk65q31nPDTOW4krghZhgCB3wBQnsaAAplbmRzdHJlYW0KZW5kb2JqCgo3IDAgb2JqCjw8Ci9GaWx0ZXIgL0ZsYXRlRGVjb2RlCi9UeXBlIC9PYmpTdG0KL04gNQovRmlyc3QgMjYKL0xlbmd0aCAzNjAKPj4Kc3RyZWFtCnic1VJRS8MwEH7Pr7hHfZCkade0Mgbb2irIUDZBUXzI2jAqI5E2lfnvvWs7xx7EZykfzd19l3zJfQEIkBBFEIJKIIJJKGECKghgOmX88evDAH/QO9MyfldXLbwiR8Aa3hhfus56CNhsxk7cpfZ673ZsaIKAyEfGQ+OqrjQNTIu8KIRQQog4QsRCyAz/S0SKkBhjTSa4RqhoBOZUKEQ4x1oxIFZDD9V77mTsz/GP3Jg42cCNkiH+OZfOyoc95F960hnjK1dl2hu4yK6lkHHQt0ShjF8u8Tkao737v5fr9dfO/nrDsznTeGnIjSEP9FPma9O6rilx7MQrHFZocWv2n8bXpb5SIk1Qp0pS9NhoDP58v303ZU+lMD/4m40nDUOCcitT1XrhDug+gV8YC8CXIA/OrXWeXNn70XpUQ1E8evRMMglifNNtfR9SMmB8oVvTSz3pRBG2dFVtd8Cfaju3bX1M0I7fConF1QplbmRzdHJlYW0KZW5kb2JqCgo4IDAgb2JqCjw8Ci9TaXplIDkKL1Jvb3QgMiAwIFIKL0luZm8gMyAwIFIKL0ZpbHRlciAvRmxhdGVEZWNvZGUKL1R5cGUgL1hSZWYKL0xlbmd0aCA0MAovVyBbIDEgMiAyIF0KL0luZGV4IFsgMCA5IF0KPj4Kc3RyZWFtCnicFcSxEQAgDAOxt8MdLeszE0MlWIWAbrMhKTlVWuKAeD9fGGHFA68KZW5kc3RyZWFtCmVuZG9iagoKc3RhcnR4cmVmCjY2NQolJUVPRg=="
    static var boardingFixtures: [JSONValue] { let dates=[BoardingClock.today(),BoardingClock.today(),BoardingClock.nextDay(BoardingClock.today()),"2020-10-10","2090-10-10"]
        return dates.enumerated().map { index,date in
            var item: JSONValue = .object(["id":.string("boarding-fixture-\(index)"),"kind":.string("boarding_pass"),"title":.string(index==3 ? "Pase anterior ficticio" : index==2 ? "Pase de mañana ficticio" : index==4 ? "Pase futuro ficticio" : "Pase de hoy ficticio \(index+1)"),"body":.string("Documento ficticio, sin viaje real"),"filename":.string(""),"size":.number(100),"createdAt":.string("2026-10-07T12:00:00Z"),"travelDate":.string(date),"read":.bool(false),"recipients":.array([.string("11111111-1111-4111-8111-111111111111")]),"attachments":.array([.object(["id":.string("boarding-fixture-\(index)-pdf"),"filename":.string("Camilo 16 de octubre Pereira-Bogota.pdf"),"mimeType":.string("application/pdf"),"size":.number(100)])])])
            if index == 0,
               ProcessInfo.processInfo.arguments.contains("--uitest-slack-boarding"),
               !ProcessInfo.processInfo.arguments.contains("--uitest-boarding-card-midnight") {
                item["boardingDetails"] = .object([
                    "seat": .string("14C"),
                    "departureTime": .string("18:45"),
                    "boardingTime": .string("18:05"),
                    "airline": .string("Aerolínea de prueba"),
                ])
            }
            return item
        }
    }
    static var itinerary: JSONValue { .object(["revision":.number(1),"confirmed":.bool(false),"id": .string("33333333-3333-4333-8333-333333333333"), "kind": .string("itinerary"), "title": .string("Itinerario simulado"), "body": .string(""), "filename": .string("Itinerario_simulado.pdf"), "size": .number(900), "createdAt": .string("2026-10-07T12:00:00Z"), "read": .bool(false)]) }
    static var agendaCalendar: JSONValue { .object(["id": .string("fixture-calendar"), "name": .string("Agenda simulada"), "timeZone": .string("America/Bogota"), "primary": .bool(true)]) }
    static func agenda(_ month: String) -> JSONValue {
        let today = CalendarClock.day(Date()), first = CalendarClock.date(month + "-01")!
        let offset = (CalendarClock.calendar.component(.weekday, from: first) + 5) % 7
        let start = CalendarClock.calendar.date(byAdding: .day, value: -offset, to: first)!
        let days = (0..<42).map { CalendarClock.day(CalendarClock.calendar.date(byAdding: .day, value: $0, to: start)!) }
        let event: JSONValue = agendaChanges["fixture-concert"] ?? .object(["id": .string("fixture-concert"), "title": .string(slowAgenda ? "Concierto actualizado" : "Concierto simulado"), "start": .string(today + "T19:00:00-05:00"), "end": .string(today + "T21:00:00-05:00"), "allDay": .bool(false), "location": .string("Teatro simulado"), "description": .string("Prueba sin eventos reales ni acceso a Google."), "url": .string(""), "etag": .string("fixture-v1"), "editable": .bool(true), "recurring": .bool(true)])
        let records = [event] + agendaChanges.filter { $0.key != "fixture-concert" }.map(\.value)
        return .object(["connection": .object(["configured": .bool(true), "connected": .bool(true), "email": .string("calendar@example.invalid"), "selected": agendaCalendar, "revision": .number(1), "writeAuthorized": .bool(true)]), "canEditEvents": .bool(!ProcessInfo.processInfo.arguments.contains("--uitest-itineraries-only") && !ProcessInfo.processInfo.arguments.contains(where:{$0.hasPrefix("--uitest-sections=")})), "month": .string(month), "monthLabel": .string(CalendarClock.dayLabel(month + "-01")), "days": .array(days.map(JSONValue.string)), "today": .string(today), "events": .array(days.contains(today) ? records : []), "upcoming": .array(records), "upcomingUntil": .string(CalendarClock.day(CalendarClock.calendar.date(byAdding: .day, value: 90, to: Date())!)), "updatedAt": .string(ISO8601DateFormatter().string(from: Date())), "timeZone": .string("America/Bogota")])
    }
}
// Native CRM fixtures: no real Calendar, Sheets, payments or contracts.
private enum CRMFixture {
    static let showID="77777777-7777-4777-8777-777777777777",contactID="88888888-8888-4888-8888-888888888888"
    static var contacts:[JSONValue]=[],shows:[JSONValue]=[],payments:[String:[JSONValue]]=[:],plans:[String:JSONValue]=[:],files:[String:[JSONValue]]=[:],bytes:[String:Data]=[:],attempts:[String:JSONValue]=[:]
    static func reset(){contacts=[.object(["id":.string(contactID),"version":.number(1),"name":.string("José · Empresario ficticio"),"company":.string("Eventos de prueba"),"phone":.string(""),"email":.string("contrato@example.invalid"),"city":.string("Pereira"),"note":.string("")])];shows=[show(id:showID,title:"PEREIRA · Show ficticio",sale:140000000)];payments=[:];plans=[:];files=[:];bytes=[:];attempts=[:];designShows()}
    static func designShows() {
        guard ProcessInfo.processInfo.arguments.contains("--uitest-crm-design") else{return}
        for (index,title) in ["MANIZALES · Fecha de prueba","VALLEDUPAR · Show promocional ficticio","SANTA ROSA · Show de prueba","MEDELLÍN · Presentación ficticia para comprobar títulos largos"].enumerated() {
            var s=show(id:"99999999-9999-4999-8999-99999999999\(index)",title:title,sale:90000000+Double(index)*10000000)
            s["showDate"] = .string(BoardingClock.today(CalendarClock.calendar.date(byAdding:.day,value:index+3,to:Date())!))
            s["entrepreneur"] = .string(index==3 ? "":"Empresario ficticio")
            if index==1 {s["sale"] = .number(0);s["balance"] = .number(0);s["promotional"] = .bool(true)}
            else if index==3 {s["sale"] = .null;s["balance"] = .null}
            else {s["paid"] = .number(20000000);s["balance"] = .number(s["sale"].number-20000000)}
            shows.append(s)
        }
    }

    static func show(id:String,title:String,sale:Double)->JSONValue{.object(["id":.string(id),"title":.string(title),"municipality":.string("Pereira"),"showDate":.string(BoardingClock.today(CalendarClock.calendar.date(byAdding:.day,value:1,to:Date())!)),"sale":.number(sale),"paid":.number(0),"balance":.number(sale),"receiptNext":.number(1),"entrepreneur":.string(""),"contactId":.null,"note":.string(""),"promotional":.bool(false),"sourceState":.string("present"),"status":.string("active"),"version":.number(1)])}
    static func tasks()->JSONValue{.array(zip(["contract","hotel","transport","itinerary"],["Contrato firmado","Hotel","Transporte","Itinerario"]).map{.object(["id":.string($0.0),"title":.string($0.1),"status":.string("pending"),"responsible":.string(""),"dueDate":.string(""),"note":.string("")])})}
    static func workspace(_ id:String)->JSONValue{let s=shows.first{$0["id"].text==id} ?? .null;var p=plans[id] ?? .object(["version":.number(0),"budget":.null,"tasks":tasks()]);p["readOnly"] = .bool(s["sourceState"].text=="deleted");p["advance"] = .object(["done":.bool(s["paid"].number>0),"amount":s["paid"]]);p["profit"] = .object(["issue":.string(""),"choices":.array([]),"actual":.object(["periodId":.string("fixture-period"),"start":.string(BoardingClock.today()),"end":.string(BoardingClock.today()),"sale":s["sale"],"musicians":.number(750000),"technical":.number(250000),"drivers":.number(100000),"expenses":.number(300000),"cost":.number(1400000),"profit":.number(s["sale"].number-1400000),"variance":.null,"commissionBase":.number(s["sale"].number-1400000),"periodCommission":.number(6930000),"closed":.bool(false),"promotional":s["promotional"]])]);return p}
    static func response(_ req:URLRequest,reader:Bool)throws ->(Int,JSONValue){guard !reader,!ProcessInfo.processInfo.arguments.contains("--uitest-itineraries-only") else{return(403,.object(["error":.string("CRM solo para administradores.")]))};let q=URLComponents(url:req.url!,resolvingAgainstBaseURL:false)!.queryItems ?? [];func value(_ k:String)->String{q.first{$0.name==k}?.value ?? ""}
        if req.httpMethod != "POST" { let id=value("id")
            if value("view")=="workspace"{return(200,workspace(id))}
            if value("view")=="contacts"{return(200,.object(["contacts":.array(contacts)]))}
            if value("view")=="contact"{return(200,.object(["contact":contacts.first{$0["id"].text==id} ?? .null,"shows":.array(shows.filter{$0["contactId"].text==id}),"files":.array(files[id] ?? [])]))}
            if value("view")=="weekly" {
                let day=ReceiptParser.civilDate(value("week")) ?? Date(),cal=CalendarClock.calendar,offset=(cal.component(.weekday,from:day)+5)%7
                let from=BoardingClock.today(cal.date(byAdding:.day,value:-offset,to:day)!),to=BoardingClock.today(cal.date(byAdding:.day,value:6-offset,to:day)!)
                let list=shows.filter{$0["sourceState"].text != "deleted" && $0["showDate"].text>=max(from,BoardingClock.today()) && $0["showDate"].text<=to}
                let recordedPayments: [JSONValue] = payments.values.flatMap { $0 }.filter {
                    $0["status"].text == "recorded" && $0["paymentDate"].text >= from && $0["paymentDate"].text <= to
                }
                let received: Double = recordedPayments.reduce(0.0) { $0 + $1["amount"].number }
                return(200,.object(["week":.object(["from":.string(from),"to":.string(to),"today":.string(BoardingClock.today())]),"shows":.array(list),"tasks":.array([]),"pending":.number(list.reduce(0){$0+$1["balance"].number}),"received":.number(received),"expensesRegistered":.number(300000),"costs":.number(list.contains{$0["id"].text==showID} ? 1400000:0),"unpriced":.number(0),"unknownCosts":.number(Double(list.filter{$0["id"].text != showID}.count))]))
            }
            if !id.isEmpty{return(200,.object(["show":shows.first{$0["id"].text==id} ?? .null,"payments":.array(payments[id] ?? [])]))}
            return(200,.object(["shows":.array(shows.filter{$0["sourceState"].text != "deleted"}),"contacts":.array(contacts),"calendar":.object(["ready":.bool(true),"revision":.number(1),"name":.string("Agenda ficticia")]),"sheets":.object(["connected":.bool(true),"ready":.bool(true),"pending":.number(0),"url":.string("")])]))
        }
        guard req.value(forHTTPHeaderField:"Origin")==UITestBackend.base.absoluteString,req.value(forHTTPHeaderField:"Cookie")?.hasPrefix("__Host-jac_session=")==true else{return(403,.object(["error":.string("Sesión y origen requeridos")]))}
        let body=try FixtureProtocol.body(req),r=body["record"],action=body["action"].text,id=r["id"].text
        func conflict()->(Int,JSONValue){(409,.object(["error":.string("El registro cambió. Recarga antes de guardar.")]))}
        func attached(_ owner:String,_ values:JSONValue)throws->[JSONValue]{try values.elements.map{f in let id=UUID().uuidString.lowercased();guard let data=Data(base64Encoded:f["data"].text)else{throw APIError.invalid("Archivo inválido")};bytes[id]=data;return .object(["id":.string(id),"filename":f["filename"],"mimeType":.string(try NoticeUpload.mime(data)),"size":.number(Double(data.count))])}}
        if action=="syncCalendar" || action=="syncSheets"{return(200,.object(["ok":.bool(true)]))}
        if action=="updateShow",let i=shows.firstIndex(where:{$0["id"].text==id}){guard shows[i]["version"]==r["version"] else{return conflict()};for k in ["sale","entrepreneur","contactId","note","promotional","status"]{shows[i][k]=r[k]};shows[i]["balance"] = .number(r["sale"].number-shows[i]["paid"].number);shows[i]["version"] = .number(r["version"].number+1);return(200,.object(["ok":.bool(true)]))}
        if action=="saveContact"{if let i=contacts.firstIndex(where:{$0["id"].text==id}){guard contacts[i]["version"]==r["version"] else{return conflict()};contacts[i]=r;contacts[i]["version"] = .number(r["version"].number+1)}else{var c=r;c["version"] = .number(1);contacts.append(c)};return(200,.object(["id":.string(id)]))}
        if action=="savePlan"{let id=r["showId"].text;guard (plans[id]?["version"] ?? .number(0))==r["version"] else{return conflict()};var p=r;p["version"] = .number(r["version"].number+1);plans[id]=p;return(200,.object(["ok":.bool(true)]))}
        if action=="addContactFiles"{if attempts[id] != nil{return(200,.object(["ok":.bool(true)]))};let cid=r["contactId"].text;guard let i=contacts.firstIndex(where:{$0["id"].text==cid}),contacts[i]["version"]==r["version"]else{return conflict()};files[cid,default:[]] += try attached(cid,r["files"]);contacts[i]["version"] = .number(r["version"].number+1);attempts[id]=r;return(200,.object(["ok":.bool(true)]))}
        if action=="addPayment"{if let prior=attempts[id]{return prior==r ? (200,.object(["ok":.bool(true)])):conflict()};let sid=r["showId"].text;guard let i=shows.firstIndex(where:{$0["id"].text==sid})else{return conflict()};var p=r;p["files"] = .array(try attached(sid,r["files"]));p["version"] = .number(1);p["status"] = .string("recorded");p["actor"] = .string("Persona ficticia");payments[sid,default:[]].append(p);shows[i]["paid"] = .number(shows[i]["paid"].number+r["amount"].number);shows[i]["balance"] = .number(shows[i]["sale"].number-shows[i]["paid"].number);attempts[id]=r;return(200,.object(["ok":.bool(true)]))}
        if action=="createShow"{let sid=id;if let s=shows.first(where:{$0["id"].text==sid}){return(200,.object(["show":s]))};var s=show(id:sid,title:r["event"]["title"].text,sale:r["sale"].number);for k in ["entrepreneur","contactId","note","promotional"]{s[k]=r[k]};s["showDate"] = .string(String(r["event"]["start"].text.prefix(10)));shows.append(s);if !r["firstPayment"].isNull {var p=r["firstPayment"];p["id"] = .string(id);p["showId"] = .string(sid);p["files"] = .array(try attached(sid,p["files"]));p["version"] = .number(1);p["status"] = .string("recorded");p["actor"] = .string("Persona ficticia");payments[sid]=[p];s["paid"]=p["amount"];s["balance"] = .number(s["sale"].number-p["amount"].number);shows[shows.count-1]=s};return(200,.object(["show":s]))}
        if action=="prepareDeleteShow"{var d=r;d["showId"] = .string(id);d["id"] = .string(UUID().uuidString.lowercased());d["revision"] = .number(1);d["etag"] = .string("fixture-etag");return(200,.object(["record":d,"event":.object(["title":shows.first{$0["id"].text==id}?["title"] ?? .string("Ficticio")])]))}
        if action=="deleteShow",let i=shows.firstIndex(where:{$0["id"]==r["showId"]}){shows[i]["sourceState"] = .string("deleted");return(200,.object(["ok":.bool(true)]))}
        return(400,.object(["error":.string("Acción ficticia no admitida")]))
    }
}

// Opt-in gallery fixtures never access Drive, a photo library, or production.
struct FixtureMediaPhotosWriter: MediaPhotosWriting {
    @MainActor func authorize() async throws {}
    @MainActor func save(_ document: ExportedDocument, item: MediaItem) async throws {
        guard FileManager.default.fileExists(atPath: document.url.path) else { throw APIError.invalid("Falta el archivo ficticio.") }
    }
}
enum MediaFixture {
    static let lock = NSRecursiveLock()
    static let notificationFolderID = "r2_22222222-2222-4222-8222-222222222222"
    static let photo = Data(base64Encoded: "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AHsAewB7AHsAewB740MA9gD2APYA9gD2APYA9gD2APYA9gD2APYA9k+A1vgQgBZAC6AF0AJoAbQAWgAtgBZAC6AF0AJoAbS30KAF0AJoAbQAWgAtgBZAC6AF0AJoAbQAWgAtgPYeGrYAWgAtgBZAC6AF0AJoAbQAWgAtgBZAC6AF0BofAtACaAG0AFoALYAWQAugBdACaAG0AFoA7RPgYHwIwAHAAcABwAHAAcABwAHAAcABwAHAAcABwAHA4RYaHAAcABwAHAAcABwAHAAcABwAHAAcABwAHAAcABzuoeEBwAHAAcABwAHAAcABwAHAAcABwAHAAcABwAHAwfgQgAOAA4ADgAOAA4ADgAOAA4ADgAOAA4ADgMMToDM+BKAD0AHoAHQAOgAdgA5AB6AD0AHoAHQAOgDdLTToAHQAOgAdgA5AB6AD0AHoAHQAOgAdgA5AB6C7h4YdgA5AB6AD0AHoAHQAOgAdgA5AB6AD0AHoAHTGhwB0ADoAHYAOQAegA9AB6AB0ADoAHYAOQPcEOBofAnAEcARwBHAEcARwBHAEcARwBHAEcARwBHAEcLyFBkcARwBHAEcARwBHAEcARwBHAEcARwBHAEcARwDHe2h4BHAEcARwBHAEcARwBHAEcARwBHAEcARwBHAEcDQ+BOAI4AjgCOAI4AjgCOAI4AjgCOAI4AjgCOD4BOiNDwHoAfQAegA9gB5AD6AH0APoAfQAegA9gB5AfwsNegA9gB5AD6AH0APoAfQAegA9gB5AD6AH0APo76FhD6AH0APoAfQAegA9gB5AD6AH0APoAfQAegC98SEAPYAeQA+gB9AD6AH0AHoAPYAeQA+gB9A/AU7GhwCcAJwAnACcAJwAnACcAJwAnACcAJwAnACcAJxuocEJwAnACcAJwAnACcAJwAnACcAJwAnACcAJwAnA6R4angCcAJwAnACcAJwAnACcAJwAnACcAJwAnACcAJyMDwE4ATgBOAE4ATgBOAE4ATgBOAE4ATgBOAE4PQHOxocAnAGcAZwBnAGcAZwBnAGcAZwBnAGcAZwBnAGcb6HBGcAZwBnAGcAZwBnAGcAZwBnAGcAZwBnAGcAZwPkeGp4BnAGcAZwBnAGcAZwBnAGcAZwBnAGcAZwBnAGcjQ8BOAM4AzgDOAM4AzgDOAM4AzgDOAM4AzgDOD8BLsaHAFwAXABcAFwAXABcAFwAXABcAFwAXABcAFwAXG6hwQXABcAFwAXABcAFwAXABcAFwAXABcAFwAXABcDlHhpeAFwAXABcAFwAXABcAFwAXABcAFwAXABcAFwAXIwPAbgAuAC4ALgAuAC4ALgAuAC4ALgAuAC4ALg8Aa7GhwBcAVwBXAFcAVwBXAFcAVwBXAFcAVwBXAFcAVxvocEVwBXAFcAVwBXAFcAVwBXAFcAVwBXAFcAVwBXA9R4aXgFcAVwBXAFcAVwBXAFcAVwBXAFcAVwBXAFcAVyNDwG4ArgCuAK4ArgCuAK4ArgCuAK4ArgCuAK4fu3xf8kbdaNikWSoAAAAAElFTkSuQmCC")!
    static let video = Data(base64Encoded: "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")!
    static var items: [String: [JSONValue]] = [:]
    static var files: [String: Data] = [:]
    static var uploads: [String: (JSONValue, Data)] = [:]
    static var sharedLinks: [JSONValue] = []
    static var deletedFolders=Set<String>()
    static let folder: JSONValue = .object(["id": .string("media-root"), "name": .string("Fotografía ficticia")])
    static var thumbnailAttempts: [String: Int] = [:]
    static var stabilityStarted = Date()
    static var stabilityFixture: Bool { ProcessInfo.processInfo.arguments.contains("--uitest-media-stability") }
    static func reset() {
        lock.lock(); defer { lock.unlock() }
        files = ["media-photo": photo, "media-video": video]; uploads = [:];deletedFolders=[];sharedLinks=[]
        thumbnailAttempts = [:]; stabilityStarted = Date()
        items = ["media-root": [item(id: "media-day", name: "2026-10-16 · PEREIRA", mime: "application/vnd.google-apps.folder", kind: "folder", size: 0)], "media-day": [item(id: "media-photo", name: "Foto ficticia.png", mime: "image/png", kind: "image", size: photo.count), item(id: "media-video", name: "Video ficticio.mov", mime: "video/quicktime", kind: "video", size: video.count)]]
        if ProcessInfo.processInfo.arguments.contains("--uitest-media-notification") {
            items[notificationFolderID] = [item(id: "notification-photo", name: "Foto de la notificación.png", mime: "image/png", kind: "image", size: photo.count)]
            files["notification-photo"] = photo
        }
        if ProcessInfo.processInfo.arguments.contains("--uitest-media-scroll") || stabilityFixture {
            items["media-day"] = (0..<(stabilityFixture ? 24 : 80)).map { index in
                let id = "media-scroll-\(index)"
                files[id] = photo
                var value = item(id: id, name: String(format: "Foto ficticia %03d.png", index), mime: "image/png", kind: "image", size: photo.count)
                if stabilityFixture, index == 5 { value["thumbnailAvailable"] = .bool(false) }
                return value
            }
        }
        if ProcessInfo.processInfo.arguments.contains("--uitest-media-slideshow") {
            // Trailing padding preserves the fictitious PNG while making each
            // streamed half large enough to flush URLSession's disk buffer.
            let second=ProcessInfo.processInfo.arguments.contains("--uitest-slow-photo-preview") ? photo+Data(repeating:0,count:1024*1024):photo
            items["media-day",default:[]].append(item(id:"media-photo-2",name:"Segunda foto ficticia.png",mime:"image/png",kind:"image",size:second.count));files["media-photo-2"]=second
        }
        if ProcessInfo.processInfo.arguments.contains("--uitest-media-two-folders") {
            var other=item(id:"media-other",name:"2026-10-17 · BOGOTÁ",mime:"application/vnd.google-apps.folder",kind:"folder",size:0);other["createdAt"] = .string("2026-10-17T12:00:00Z")
            items["media-root",default:[]].append(other);items["media-other"]=[item(id:"media-other-photo",name:"Otra foto ficticia.png",mime:"image/png",kind:"image",size:photo.count)];files["media-other-photo"]=photo
        }
    }
    static func item(id: String, name: String, mime: String, kind: String, size: Int) -> JSONValue { .object(["id": .string(id), "name": .string(name), "mimeType": .string(mime), "kind": .string(kind), "size": .number(Double(size)), "modifiedAt": .string("2026-10-16T12:00:00Z"), "createdAt": .string("2026-10-16T12:00:00Z"), "thumbnailAvailable": .bool(kind == "image")]) }
    static func bytes(_ request: URLRequest) throws -> Data {
        if let data = request.httpBody { return data }
        guard let stream = request.httpBodyStream else { return Data() }; stream.open(); defer { stream.close() }
        var result = Data(), buffer = [UInt8](repeating: 0, count: 4096)
        while true { let count = stream.read(&buffer, maxLength: buffer.count); if count < 0 { throw stream.streamError ?? URLError(.badServerResponse) }; if count == 0 { break }; result.append(contentsOf: buffer.prefix(count)) }
        return result
    }
    static var r2Fixture:Bool {ProcessInfo.processInfo.arguments.contains("--uitest-media-r2")}
    static func sourceID(_ id:String)->String {r2Fixture && id.hasPrefix("r2_media-") ? String(id.dropFirst(3)):id}
    static func r2Value(_ value:JSONValue)->JSONValue {
        guard r2Fixture else{return value}
        switch value {
        case .object(let fields):return .object(fields.mapValues{r2Value($0)})
        case .array(let entries):return .array(entries.map{r2Value($0)})
        case .string(let text):return text.hasPrefix("media-") ? .string("r2_"+text):value
        default:return value
        }
    }
    static func file(_ request: URLRequest) throws -> (Int, String, Data) {
        lock.lock(); defer { lock.unlock() }
        let q = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!.queryItems ?? [], id = sourceID(q.first { $0.name == "id" }?.value ?? "")
        guard let bytes = files[id] else { return (404, "application/json", Data("{\"error\":\"Archivo ficticio no encontrado\"}".utf8)) }
        let record = items.values.flatMap { $0 }.first { $0["id"].text == id }
        if stabilityFixture, q.contains(where: { $0.name == "thumbnail" }) {
            thumbnailAttempts[id, default: 0] += 1
            if id == "media-scroll-3" || (id == "media-scroll-0" && thumbnailAttempts[id] == 1) {
                return (404, "application/json", Data("{\"error\":\"Miniatura pendiente ficticia\"}".utf8))
            }
        }
        if q.contains(where: { $0.name == "metadata" }), let record { return (200, "application/json", try JSONEncoder().encode(JSONValue.object(["item": r2Value(record)]))) }
        if q.contains(where: { $0.name == "preview" }) {
            let data = NSMutableData()
            if let source = CGImageSourceCreateWithData(photo as CFData, nil), let image = CGImageSourceCreateImageAtIndex(source, 0, nil), let target = CGImageDestinationCreateWithData(data, "public.jpeg" as CFString, 1, nil) {
                CGImageDestinationAddImage(target, image, nil); if CGImageDestinationFinalize(target) { return (200, "image/jpeg", data as Data) }
            }
            return (503, "application/json", Data("{}".utf8))
        }
        let mime = record?["mimeType"].text ?? "image/png"
        return (200, q.contains { $0.name == "thumbnail" } ? "image/png" : mime, q.contains { $0.name == "thumbnail" } ? photo : bytes)
    }
    static func direct(_ request: URLRequest) throws -> Int {
        lock.lock(); defer { lock.unlock() }
        let id = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "upload_id" }?.value ?? ""
        guard var upload = uploads[id], request.httpMethod == "PUT", let range = request.value(forHTTPHeaderField: "Content-Range"), range.hasPrefix("bytes \(upload.1.count)-") else { return 400 }
        upload.1.append(try bytes(request)); uploads[id] = upload
        return upload.1.count == Int(upload.0["size"].number) ? 200 : 308
    }
    static func response(_ request: URLRequest) throws -> (Int, JSONValue) {
        lock.lock(); defer { lock.unlock() }
        let parts = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!, q = parts.queryItems ?? []
        let photographer = (try? FixtureProtocol.user.decoded(PayrollUser.self).canUploadMedia) == true
        let administrator = (try? FixtureProtocol.user.decoded(PayrollUser.self).canDeleteMedia) == true
        if parts.path == "/api/media", request.httpMethod == "GET" {
            let id = sourceID(q.first { $0.name == "folder" }?.value ?? "media-root"), selected: JSONValue = id == "media-root" ? folder : .object(["id": .string(id), "name": .string(id == "media-day" ? "2026-10-16 · PEREIRA" : id == "media-other" ? "2026-10-17 · BOGOTÁ" : "Carpeta ficticia")])
            if deletedFolders.contains(id){return (410,.object(["error":.string("Carpeta eliminada")]))}
            var feed:JSONValue = .object(["canDelete":.bool(administrator),"deletedFolders":.array(deletedFolders.map{.string($0)}),"pendingDeletions":.array([]),"connected": .bool(true), "canRead": .bool(true), "canUpload": .bool(photographer), "canConnect": .bool(!photographer), "root": folder, "folder": selected, "breadcrumbs": .array(id == "media-root" ? [folder] : [folder, selected]), "items": .array(items[id] ?? []), "nextPageToken": .string("")])
            if stabilityFixture {
                if id == "media-root", Date().timeIntervalSince(stabilityStarted) >= 25 {
                    var updated = items[id] ?? []
                    if !updated.isEmpty { updated[0]["name"] = .string("Carpeta actualizada \(Int((Date().timeIntervalSince(stabilityStarted) + 5) / 30))") }
                    feed["items"] = .array(updated)
                } else if id == "media-day" {
                    let all = items[id] ?? [], offset = Int(q.first { $0.name == "pageToken" }?.value ?? "") ?? 0
                    feed["items"] = .array(Array(all.dropFirst(offset).prefix(12)))
                    feed["nextPageToken"] = .string(offset + 12 < all.count ? String(offset + 12) : "")
                }
            }
            if r2Fixture {feed["provider"] = .string("r2");feed["collectionID"] = .string("jac-r2-new-20261016")}
            return (200,r2Value(feed))
        }
        if parts.path=="/api/media",request.httpMethod=="POST",let input=try? JSONDecoder().decode(JSONValue.self,from:bytes(request)),input["action"].text=="deleteFile" {
            guard administrator else{return(403,.object(["error":.string("Solo administradores")]))}
            let id=sourceID(input["id"].text)
            guard let parent=items.first(where:{$0.value.contains{$0["id"].text==id && $0["kind"].text != "folder"}})?.key,let selected=items[parent]?.first(where:{$0["id"].text==id}) else{return(404,.object(["error":.string("Foto no disponible")]))}
            guard input["revision"].text==selected["modifiedAt"].text else{return(409,.object(["error":.string("Revisión cambió")]))}
            files.removeValue(forKey:id);items[parent]?.removeAll{$0["id"].text==id}
            return(200,r2Value(.object(["id":.string(id),"parentId":.string(parent),"name":selected["name"],"removed":.number(1),"complete":.bool(true),"waiting":.bool(false)])))
        }
        if parts.path=="/api/media",request.httpMethod=="POST",let input=try? JSONDecoder().decode(JSONValue.self,from:bytes(request)),input["action"].text=="deleteFolder" {
            guard administrator else{return(403,.object(["error":.string("Solo administradores")]))}
            let target=input["id"].text;guard target != "media-root" else{return(400,.object(["error":.string("No eliminar raíz")]))}
            let parent=items.first(where:{$0.value.contains{$0["id"].text==target}})?.key ?? "media-root"
            var subtree=Set([target]);var changed=true
            while changed {changed=false;for id in Array(subtree){for child in items[id] ?? [] where child["kind"].text=="folder" {if subtree.insert(child["id"].text).inserted {changed=true}}}}
            for id in subtree {for file in items[id] ?? [] {files.removeValue(forKey:file["id"].text)};items.removeValue(forKey:id);deletedFolders.insert(id)}
            for key in Array(items.keys) {items[key]?.removeAll{subtree.contains($0["id"].text)}}
            return(200,.object(["id":.string(target),"parentId":.string(parent),"name":.string("Carpeta ficticia"),"removed":.number(2),"complete":.bool(true),"waiting":.bool(false)]))
        }
        guard photographer || request.url?.host == "mock.example.invalid" else { return (403, .object(["error": .string("Solo el fotógrafo puede subir archivos.")])) }
        if parts.path == "/api/media/shares" {
            if request.httpMethod == "GET" { return (200, .object(["links": .array(sharedLinks)])) }
            let input = try JSONDecoder().decode(JSONValue.self, from: bytes(request))
            if input["action"].text == "revoke" { sharedLinks.removeAll { $0["id"].text == input["id"].text }; return (200, .object(["revoked": .bool(true)])) }
            let link: JSONValue = .object(["id": input["id"], "url": .string("/compartir/" + String(repeating: "f", count: 43)), "createdAt": .string("2026-10-19T12:00:00Z"), "expiresAt": .string("2026-11-18T12:00:00Z")])
            sharedLinks.append(link); return (200, .object(["link": link]))
        }
        if parts.path == "/api/media", request.httpMethod == "POST" {
            let input = try JSONDecoder().decode(JSONValue.self, from: bytes(request)), id = "media-" + input["id"].text
            let name = input["name"].text
            if items[id] == nil { items[id] = []; items[input["parentId"].text, default: []].append(item(id: id, name: name, mime: "application/vnd.google-apps.folder", kind: "folder", size: 0)) }
            return (200, .object(["folder": .object(["id": .string(id), "name": .string(name)])]))
        }
        if parts.path == "/api/media/upload" {
            if parts.queryItems?.contains(where: { $0.name == "preview" }) == true { return (200, .object(["saved": .bool(true)])) }
            if q.contains(where: { $0.name == "thumbnail" && $0.value == "1" }) { return (200, .object(["saved": .bool(true)])) }
            var id = ""
            if request.httpMethod == "PUT" {
                id = q.first { $0.name == "id" }?.value ?? ""
                guard var upload = uploads[id], Int(q.first { $0.name == "offset" }?.value ?? "") == upload.1.count else { return (409, .object(["error": .string("Desfase ficticio")])) }
                upload.1.append(try bytes(request)); uploads[id] = upload
                if upload.1.count == Int(upload.0["size"].number), files[id] == nil { files[id] = upload.1; items[upload.0["parentId"].text, default: []].append(item(id: id, name: upload.0["filename"].text, mime: upload.0["mimeType"].text, kind: upload.0["mimeType"].text.hasPrefix("video/") ? "video" : "image", size: upload.1.count)) }
            } else {
                let input = try JSONDecoder().decode(JSONValue.self, from: bytes(request)); id = input["id"].text
                if input["action"].text == "start", uploads[id] == nil { uploads[id] = (input, Data()) }
            }
            guard let upload = uploads[id] else { return (404, .object(["error": .string("Subida ficticia no encontrada")])) }
            let complete = upload.1.count == Int(upload.0["size"].number)
            if complete, files[id] == nil { files[id] = upload.1; items[upload.0["parentId"].text, default: []].append(item(id: id, name: upload.0["filename"].text, mime: upload.0["mimeType"].text, kind: upload.0["mimeType"].text.hasPrefix("video/") ? "video" : "image", size: upload.1.count)) }
            var state: JSONValue = .object(["id": .string(id), "offset": .number(Double(upload.1.count)), "chunkSize": .number(8.0 * 1024 * 1024), "complete": .bool(complete)])
            if !complete { state["uploadURL"] = .string("https://www.googleapis.com/upload/drive/v3/files?upload_id=" + id) }
            return (200, state)
        }
        return (404, .object(["error": .string("Ruta ficticia no prevista")]))
    }
}

#endif
