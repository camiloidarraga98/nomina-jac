#if DEBUG
import Foundation

// Opt-in UI fixtures use .invalid URLs and an ephemeral protocol. They are
// excluded from Release and never read or write the real payroll or Keychain.
enum UITestBackend {
    static let base = URL(string: "https://ui-fixture.example.invalid")!
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
        let vault = FixtureSession(); if reader { vault.token = String(repeating: "r", count: 43) }
        return PayrollClient(baseURL: base, vault: vault, configuration: configuration, agendaCache: cache, offlineCache: contentCache ?? content, automaticallyDownloadOffline: downloadOffline ?? persistent)
    }
}
private final class FixtureSession: SessionStoring {
    var token: String? = String(repeating: "f", count: 43)
    func load() throws -> String? { token }
    func save(_ token: String) throws { self.token = token }
    func clear() throws { token = nil }
}
private final class FixtureProtocol: URLProtocol {
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
    static var readsToCancel = Set<String>()
    static var offline = false
    static var slowAgenda = false
    static var slowedWorkspace = false
    static func reset(reader: Bool, conflict: Bool, cancelledReads: Bool, offline: Bool, slowAgenda: Bool) { lock.lock(); defer { lock.unlock() }; state = initialState();CRMFixture.reset(); revision = 1; self.reader = reader; self.conflict = conflict; self.offline = offline; self.slowAgenda = slowAgenda; slowedWorkspace = false; agendaChanges = [:]; overrides=[:];expenses=[];alerts = []; deletedNotices = []; attachments = [:]; readsToCancel = cancelledReads ? ["/api/mobile/payroll?period", "/api/calendar", "/api/notices", "/api/notices?read", "/api/payroll/email", "/api/users"] : [] }
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
        do {
            guard request.url?.host == "ui-fixture.example.invalid" else { throw URLError(.unsupportedURL) }
            if Self.offline { throw URLError(.notConnectedToInternet) }
            if ProcessInfo.processInfo.arguments.contains("--uitest-slow-content"), request.url?.path == "/api/mobile/payroll", request.url?.query?.contains("workspace=1") == true {
                Self.lock.lock(); let delay = !Self.slowedWorkspace; Self.slowedWorkspace = true; Self.lock.unlock()
                if delay { Thread.sleep(forTimeInterval: 8) }
            }
            if Self.slowAgenda, request.url?.path == "/api/calendar", request.httpMethod == "GET" { Thread.sleep(forTimeInterval: 3) }
            if Self.cancelRead(request) { throw URLError(.cancelled) }
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
                guard !Self.deletedNotices.contains(notice), let bytes = Self.attachments[id] ?? (id.hasPrefix("boarding-fixture-") ? Data(base64Encoded:Self.pdf) : nil) else { throw URLError(.fileDoesNotExist) }
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
    override func stopLoading() {}
    static func body(_ request: URLRequest) throws -> JSONValue {
        var bytes = request.httpBody ?? Data()
        if bytes.isEmpty, let stream = request.httpBodyStream {
            stream.open(); defer { stream.close() }; var buffer = [UInt8](repeating: 0, count: 4096)
            while true { let count = stream.read(&buffer, maxLength: buffer.count); if count <= 0 { break }; bytes.append(contentsOf: buffer.prefix(count)) }
        }
        return try JSONDecoder().decode(JSONValue.self, from: bytes)
    }
    static var user: JSONValue { .object(["id": .string("fixture-user"), "username": .string("simulado"), "email": .string("test@example.invalid"), "displayName": .string("Cuenta simulada"), "itinerariesOnly":.bool(ProcessInfo.processInfo.arguments.contains("--uitest-itineraries-only")), "isOwner": .bool(!reader), "permissions": .array([])]) }
    static func response(_ request: URLRequest) throws -> (Int, JSONValue) {
        lock.lock(); defer { lock.unlock() }
        let parts = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!
        let viewer = reader ? "22222222-2222-4222-8222-222222222222" : "11111111-1111-4111-8111-111111111111"
        let visible = ([itinerary] + boardingFixtures + alerts).map { overrides[$0["id"].text] ?? $0 }.filter { !(ProcessInfo.processInfo.arguments.contains("--uitest-boarding-tomorrow") && ["boarding-fixture-0","boarding-fixture-1"].contains($0["id"].text)) && !deletedNotices.contains($0["id"].text) && ($0["kind"].text != "boarding_pass" || $0["recipients"].elements.contains(.string(viewer))) }
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
        return dates.enumerated().map { index,date in .object(["id":.string("boarding-fixture-\(index)"),"kind":.string("boarding_pass"),"title":.string(index==3 ? "Pase anterior ficticio" : index==2 ? "Pase de mañana ficticio" : index==4 ? "Pase futuro ficticio" : "Pase de hoy ficticio \(index+1)"),"body":.string("Documento ficticio, sin viaje real"),"filename":.string(""),"size":.number(100),"createdAt":.string("2026-10-07T12:00:00Z"),"travelDate":.string(date),"read":.bool(false),"recipients":.array([.string("11111111-1111-4111-8111-111111111111")]),"attachments":.array([.object(["id":.string("boarding-fixture-\(index)-pdf"),"filename":.string("Camilo 16 de octubre Pereira-Bogota.pdf"),"mimeType":.string("application/pdf"),"size":.number(100)])])]) }
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
        return .object(["connection": .object(["configured": .bool(true), "connected": .bool(true), "email": .string("calendar@example.invalid"), "selected": agendaCalendar, "revision": .number(1), "writeAuthorized": .bool(true)]), "canEditEvents": .bool(!ProcessInfo.processInfo.arguments.contains("--uitest-itineraries-only")), "month": .string(month), "monthLabel": .string(CalendarClock.dayLabel(month + "-01")), "days": .array(days.map(JSONValue.string)), "today": .string(today), "events": .array(days.contains(today) ? records : []), "upcoming": .array(records), "upcomingUntil": .string(CalendarClock.day(CalendarClock.calendar.date(byAdding: .day, value: 90, to: Date())!)), "updatedAt": .string(ISO8601DateFormatter().string(from: Date())), "timeZone": .string("America/Bogota")])
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
                let received=payments.values.flatMap{$0}.filter{$0["status"].text=="recorded" && $0["paymentDate"].text>=from && $0["paymentDate"].text<=to}.reduce(0){$0+$1["amount"].number}
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

#endif
