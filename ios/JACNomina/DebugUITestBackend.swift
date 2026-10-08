#if DEBUG
import Foundation

// Opt-in UI fixtures use .invalid URLs and an ephemeral protocol. They are
// excluded from Release and never read or write the real payroll or Keychain.
enum UITestBackend {
    static let base = URL(string: "https://ui-fixture.example.invalid")!
    @MainActor static func client(reader: Bool = false, conflict: Bool = false, cancelledReads: Bool = false, offline: Bool = false, slowAgenda: Bool = false, persistentAgenda: Bool = false, resetAgenda: Bool = false) -> PayrollClient {
        FixtureProtocol.reset(reader: reader, conflict: conflict, cancelledReads: cancelledReads, offline: offline, slowAgenda: slowAgenda)
        let configuration = URLSessionConfiguration.ephemeral; configuration.protocolClasses = [FixtureProtocol.self]
        let cache = AgendaOfflineCache(root: persistentAgenda ? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("JACAgendaUITest") : FileManager.default.temporaryDirectory.appendingPathComponent("agenda-fixture-" + UUID().uuidString))
        if resetAgenda { try? FileManager.default.removeItem(at: cache.root) }
        return PayrollClient(baseURL: base, vault: FixtureSession(), configuration: configuration, agendaCache: cache)
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
    static var alerts: [JSONValue] = []
    static var deletedNotices = Set<String>()
    static var attachments: [String: Data] = [:]
    static var readsToCancel = Set<String>()
    static var offline = false
    static var slowAgenda = false
    static func reset(reader: Bool, conflict: Bool, cancelledReads: Bool, offline: Bool, slowAgenda: Bool) { lock.lock(); defer { lock.unlock() }; state = initialState(); revision = 1; self.reader = reader; self.conflict = conflict; self.offline = offline; self.slowAgenda = slowAgenda; agendaChanges = [:]; alerts = []; deletedNotices = []; attachments = [:]; readsToCancel = cancelledReads ? ["/api/mobile/payroll?period", "/api/calendar", "/api/notices", "/api/notices?read", "/api/payroll/email", "/api/users"] : [] }
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
            if Self.slowAgenda, request.url?.path == "/api/calendar", request.httpMethod == "GET" { Thread.sleep(forTimeInterval: 3) }
            if Self.cancelRead(request) { throw URLError(.cancelled) }
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
        let visible = ([itinerary] + boardingFixtures + alerts).filter { !(ProcessInfo.processInfo.arguments.contains("--uitest-boarding-tomorrow") && ["boarding-fixture-0","boarding-fixture-1"].contains($0["id"].text)) && !deletedNotices.contains($0["id"].text) && ($0["kind"].text != "boarding_pass" || $0["recipients"].elements.contains(.string(viewer))) }
        if parts.path == "/api/notices/publish" {
            guard !reader else { return (403,.object(["error":.string("Solo Camilo puede publicar.")])) }
            guard request.value(forHTTPHeaderField:"Origin") == UITestBackend.base.absoluteString, request.value(forHTTPHeaderField:"Cookie")?.hasPrefix("__Host-jac_session=") == true else { return (403,.object(["error":.string("Sesión requerida.")])) }
            var item = try body(request); let id = item["id"].text
            if deletedNotices.contains(id) { return (410,.object(["error":.string("Aviso eliminado.")])) }
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
                    let edit = command["edit"], collection = ["show": "shows", "movement": "movements", "route": "routes"][edit["kind"].text] ?? ""
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
            let key = ["show": "shows", "movement": "movements", "route": "routes", "hours": "hours"][kind] ?? ""
            let id = kind == "hours" ? "employeeId" : "id"; p[key] = .array(p[key].elements.filter { $0[id] != record[id] } + [record])
        }
    }
    static func calculation(_ state: JSONValue, _ p: JSONValue) -> JSONValue {
        if p["status"].text == "cerrada" { return p["snapshot"] }
        // Fixed server response for UI tests; real calculations are tested in Node.
        return .object(["rows": .array([]), "sale": .number(0), "total": .number(0), "gross": .number(0), "deductions": .number(0), "reimbursements": .number(0), "company": state["settings"]["company"], "nit": state["settings"]["nit"], "settings": p["calculationBase"]["settings"] == .null ? state["settings"] : p["calculationBase"]["settings"]])
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
    static var itinerary: JSONValue { .object(["id": .string("33333333-3333-4333-8333-333333333333"), "kind": .string("itinerary"), "title": .string("Itinerario simulado"), "body": .string(""), "filename": .string("Itinerario_simulado.pdf"), "size": .number(900), "createdAt": .string("2026-10-07T12:00:00Z"), "read": .bool(false)]) }
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
#endif
