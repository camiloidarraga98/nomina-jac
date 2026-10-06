#if DEBUG
import Foundation

// Opt-in UI fixtures use .invalid URLs and an ephemeral protocol. They are
// excluded from Release and never read or write the real payroll or Keychain.
enum UITestBackend {
    static let base = URL(string: "https://ui-fixture.example.invalid")!
    @MainActor static func client(reader: Bool = false, conflict: Bool = false) -> PayrollClient {
        FixtureProtocol.reset(reader: reader, conflict: conflict)
        let configuration = URLSessionConfiguration.ephemeral; configuration.protocolClasses = [FixtureProtocol.self]
        return PayrollClient(baseURL: base, vault: FixtureSession(), configuration: configuration)
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
    static func reset(reader: Bool, conflict: Bool) { lock.lock(); defer { lock.unlock() }; state = initialState(); revision = 1; self.reader = reader; self.conflict = conflict; agendaChanges = [:] }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            guard request.url?.host == "ui-fixture.example.invalid" else { throw URLError(.unsupportedURL) }
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
    static var user: JSONValue { .object(["id": .string("fixture-user"), "username": .string("simulado"), "email": .string("test@example.invalid"), "displayName": .string("Cuenta simulada"), "isOwner": .bool(!reader), "permissions": .array([])]) }
    static func response(_ request: URLRequest) throws -> (Int, JSONValue) {
        lock.lock(); defer { lock.unlock() }
        let parts = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!
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
    static var agendaCalendar: JSONValue { .object(["id": .string("fixture-calendar"), "name": .string("Agenda simulada"), "timeZone": .string("America/Bogota"), "primary": .bool(true)]) }
    static func agenda(_ month: String) -> JSONValue {
        let today = CalendarClock.day(Date()), first = CalendarClock.date(month + "-01")!
        let offset = (CalendarClock.calendar.component(.weekday, from: first) + 5) % 7
        let start = CalendarClock.calendar.date(byAdding: .day, value: -offset, to: first)!
        let days = (0..<42).map { CalendarClock.day(CalendarClock.calendar.date(byAdding: .day, value: $0, to: start)!) }
        let event: JSONValue = agendaChanges["fixture-concert"] ?? .object(["id": .string("fixture-concert"), "title": .string("Concierto simulado"), "start": .string(today + "T19:00:00-05:00"), "end": .string(today + "T21:00:00-05:00"), "allDay": .bool(false), "location": .string("Teatro simulado"), "description": .string("Prueba sin eventos reales ni acceso a Google."), "url": .string(""), "etag": .string("fixture-v1"), "editable": .bool(true), "recurring": .bool(true)])
        let records = [event] + agendaChanges.filter { $0.key != "fixture-concert" }.map(\.value)
        return .object(["connection": .object(["configured": .bool(true), "connected": .bool(true), "email": .string("calendar@example.invalid"), "selected": agendaCalendar, "revision": .number(1), "writeAuthorized": .bool(true)]), "canEditEvents": .bool(true), "month": .string(month), "monthLabel": .string(CalendarClock.dayLabel(month + "-01")), "days": .array(days.map(JSONValue.string)), "today": .string(today), "events": .array(days.contains(today) ? records : []), "upcoming": .array(records), "upcomingUntil": .string(CalendarClock.day(CalendarClock.calendar.date(byAdding: .day, value: 90, to: Date())!)), "updatedAt": .string(ISO8601DateFormatter().string(from: Date())), "timeZone": .string("America/Bogota")])
    }
}
#endif
