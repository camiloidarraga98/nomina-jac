#if os(iOS) && DEBUG
import Foundation
import CryptoKit

/// An isolated, on-device rehearsal. This identifier is only a Keychain/storage namespace.
@MainActor
final class DeviceAttendancePilot {
    static let origin = URL(string: "https://asistencia-dispositivo.invalid")!
    static let shared = DeviceAttendancePilot()
    static let account = "d32c771b-d5ef-4815-98fc-339a811080e4"
    private let certificate = KeychainSessionStore(account: "attendance-device-demo-authorization")
    private var grant: (session: String, ticket: String, expires: Date)?
    private let clock: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
    private typealias Row = [String: Any]
    private struct Ledger: Codable {
        var people = [
            Person(id: UUID().uuidString.lowercased(), code: "DEMO-01", name: "Empleado de prueba 1"),
            Person(id: UUID().uuidString.lowercased(), code: "DEMO-02", name: "Empleado de prueba 2")
        ]
        var punches = [Punch]()
        var reviews = [Review]()
    }
    private struct Person: Codable {
        let id, code, name: String
        var active = true
        var revision = 1
        var row: Row { ["id":id, "code":code, "name":name, "active":active, "revision":revision] }
    }
    private struct Punch: Codable {
        let id, employee, device, movement, deviceTime, storedAt: String
        let possibleDuplicate, clockDifference: Bool
    }
    private struct Review: Codable {
        let id, punch, action, reason, movement, deviceTime, recordedAt: String
        let revision: Int
        var row: Row {
            ["id":id, "punch":punch, "action":action, "reason":reason, "movement":movement,
             "device_time":deviceTime, "recorded_at":recordedAt, "revision":revision, "operator_name":"Operador de prueba"]
        }
    }
    private struct Problem: Error {
        let status: Int
        let message: String
        init(_ status: Int, _ message: String) { self.status = status; self.message = message }
    }
    private func fingerprint(_ token: String) -> String {
        SHA256.hash(data: Data(token.utf8)).map { String(format: "%02x", $0) }.joined()
    }
    private func newToken() -> String {
        SymmetricKey(size: .bits256).withUnsafeBytes { Data($0).base64EncodedString() }
            .replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }
    func login(username: String, password: String, persistent: Bool) throws -> String {
        guard username == "admin", password == "admin" else { throw APIError.unauthorized }
        let token = newToken()
        let expiry = persistent ? Date.distantFuture : Date().addingTimeInterval(12 * 3600)
        try certificate.save(fingerprint(token) + "|" + String(expiry.timeIntervalSince1970))
        grant = nil
        return token
    }
    func authorized(_ token: String) throws -> Bool {
        guard let parts = try certificate.load()?.split(separator: "|"), parts.count == 2,
              let expires = Double(parts[1]) else { return false }
        return parts[0] == fingerprint(token) && Date().timeIntervalSince1970 < expires
    }
    func logout(_ token: String) throws {
        if try authorized(token) { try certificate.clear(); grant = nil }
    }

    func operation(_ command: String, data: Data?, token: String, ticket: String?) throws -> (Data, Int) {
        do {
            guard try authorized(token) else { throw Problem(401, "Vuelve a entrar en el piloto de este dispositivo.") }
            var body = Row()
            if let data {
                guard let input = try JSONSerialization.jsonObject(with: data) as? Row else { throw invalid }
                body = input
            }
            let result = try perform(command, body: body, token: token, ticket: ticket)
            return (try JSONSerialization.data(withJSONObject: result), 200)
        } catch let issue as Problem {
            return (try JSONSerialization.data(withJSONObject: ["error": issue.message]), issue.status)
        }
    }
    private func perform(_ command: String, body: Row, token: String, ticket: String?) throws -> Row {
        if command == "unlock" {
            // This separate fixture credential exists only in development builds with synthetic records.
            guard body["password"] as? String == "gestion-demo" else { throw Problem(403, "La clave de supervisión de prueba es incorrecta.") }
            let value = newToken(), expires = Date().addingTimeInterval(300)
            grant = (token, value, expires)
            return ["ticket":value, "expires":clock.string(from: expires), "name":"Operador de prueba"]
        }
        if !["session", "punch", "status"].contains(command) {
            guard let current = grant, current.session == token, current.ticket == ticket, current.expires > Date() else {
                throw Problem(403, "Ingresa la clave de supervisión.")
            }
        }
        if command == "lock" { grant = nil; return ["ok":true] }

        let file = try AttendanceStorage.directory().appendingPathComponent("piloto-en-dispositivo-v1.json")
        var ledger: Ledger
        if FileManager.default.fileExists(atPath: file.path) {
            ledger = try JSONDecoder().decode(Ledger.self, from: Data(contentsOf: file))
        } else {
            ledger = Ledger()
            try JSONEncoder().encode(ledger).write(to: file, options: JACFileSecurity.writeOptions)
        }
        let result: Row
        switch command {
        case "session":
            return ["id":Self.account, "role":"kiosk", "name":"Kiosco de prueba", "mode":"device",
                    "people":ledger.people.filter(\.active).map(\.row)]
        case "management":
            return ["people":ledger.people.map(\.row), "punches":ledger.punches.reversed().map { detail($0, ledger) },
                    "audit":ledger.reviews.map(\.row)]
        case "status":
            guard let ids = body["ids"] as? [String], ids.count <= 30 else { throw invalid }
            return ["records":ledger.punches.filter { ids.contains($0.id) }.map { ["id":$0.id, "state":state($0, ledger)] }]
        case "people":
            guard let rows = body["people"] as? [Row], (1...30).contains(rows.count) else { throw invalid }
            for row in rows {
                let id = try uuid(row, "id"), code = try string(row, "code", limit: 32), name = try string(row, "name", limit: 80)
                guard code.range(of: #"^[A-Za-z0-9_-]+$"#, options: .regularExpression) != nil else { throw invalid }
                guard !ledger.people.contains(where: { $0.id == id || $0.code.caseInsensitiveCompare(code) == .orderedSame }) else {
                    throw Problem(409, "Ya existe ese identificador interno.")
                }
                ledger.people.append(Person(id: id, code: code, name: name))
            }
            result = ["ok":true]
        case "retire":
            let id = try uuid(body, "id")
            guard let index = ledger.people.firstIndex(where: { $0.id == id && $0.active && $0.revision == body["revision"] as? Int }) else {
                throw Problem(409, "El empleado cambió. Actualiza el listado.")
            }
            if ledger.punches.contains(where: { $0.employee == id }) {
                ledger.people[index].active = false
                ledger.people[index].revision += 1
                result = ["status":"inactive"]
            } else {
                ledger.people.remove(at: index)
                result = ["status":"deleted"]
            }
        case "punch": result = try record(body, in: &ledger)
        case "review": result = try review(body, in: &ledger)
        default: throw Problem(404, "Esta operación no está disponible en la prueba local.")
        }
        try JSONEncoder().encode(ledger).write(to: file, options: JACFileSecurity.writeOptions)
        return result
    }
    private var invalid: Problem { Problem(400, "Revisa los datos de la operación.") }
    private func string(_ body: Row, _ key: String, limit: Int) throws -> String {
        guard let value = (body[key] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty, value.count <= limit else { throw invalid }
        return value
    }
    private func uuid(_ row: Row, _ key: String) throws -> String {
        guard let value = row[key] as? String, UUID(uuidString: value) != nil else { throw invalid }
        return value.lowercased()
    }
    private func movementAndTime(_ input: Row) throws -> (String, String, Date) {
        guard let move = input["movement"] as? String, ["entry", "exit"].contains(move),
              let time = input["device_time"] as? String, let date = clock.date(from: time) else { throw invalid }
        return (move, time, date)
    }
    private func state(_ punch: Punch, _ ledger: Ledger) -> String {
        ledger.reviews.last { $0.punch == punch.id }?.action == "approve" ? "approved" : "pending"
    }
    private func detail(_ punch: Punch, _ ledger: Ledger) -> Row {
        let last = ledger.reviews.last { $0.punch == punch.id }
        return ["id":punch.id, "name":ledger.people.first { $0.id == punch.employee }?.name ?? "",
                "movement":punch.movement, "effective_movement":last?.movement ?? punch.movement,
                "device_time":punch.deviceTime, "effective_time":last?.deviceTime ?? punch.deviceTime,
                "stored_at":punch.storedAt, "method":"supervised", "review_state":state(punch, ledger),
                "revision":last?.revision ?? 0, "possible_duplicate":punch.possibleDuplicate, "clock_difference":punch.clockDifference]
    }
    private func record(_ input: Row, in ledger: inout Ledger) throws -> Row {
        guard input["account"] as? String == Self.account, input["method"] as? String == "supervised" else { throw invalid }
        let id = try uuid(input, "id"), employee = try uuid(input, "employee"), device = try uuid(input, "device")
        let (move, time, date) = try movementAndTime(input)
        let punch: Punch
        if let previous = ledger.punches.first(where: { $0.id == id }) {
            guard previous.employee == employee, previous.device == device, previous.movement == move,
                  previous.deviceTime == time else { throw Problem(409, "Existe otra marcación con ese identificador.") }
            punch = previous
        } else {
            guard ledger.people.contains(where: { $0.id == employee && $0.active }) else { throw Problem(409, "El empleado está inactivo.") }
            let duplicate = ledger.punches.contains { prior in
                guard prior.employee == employee, prior.movement == move, let earlier = clock.date(from: prior.deviceTime) else { return false }
                return abs(earlier.timeIntervalSince(date)) <= 90
            }
            let now = Date()
            punch = Punch(id: id, employee: employee, device: device, movement: move, deviceTime: time,
                          storedAt: clock.string(from: now), possibleDuplicate: duplicate, clockDifference: abs(now.timeIntervalSince(date)) > 300)
            ledger.punches.append(punch)
        }
        return ["id":id, "stored_at":punch.storedAt, "state":state(punch, ledger),
                "possible_duplicate":punch.possibleDuplicate, "clock_difference":punch.clockDifference]
    }
    private func review(_ input: Row, in ledger: inout Ledger) throws -> Row {
        let id = try uuid(input, "id"), punchID = try uuid(input, "punch"), reason = try string(input, "reason", limit: 400)
        let (move, time, _) = try movementAndTime(input)
        guard let revision = input["revision"] as? Int, let action = input["action"] as? String,
              ["approve", "correct"].contains(action), reason.count >= 3,
              let punch = ledger.punches.first(where: { $0.id == punchID }) else { throw invalid }
        let conflict = Problem(409, "La revisión cambió. Actualiza el registro.")
        if let previous = ledger.reviews.first(where: { $0.id == id }) {
            guard previous.punch == punchID, previous.revision - 1 == revision, previous.action == action,
                  previous.reason == reason, previous.movement == move, previous.deviceTime == time else { throw conflict }
            return ["ok":true]
        }
        let last = ledger.reviews.last { $0.punch == punchID }
        guard revision == (last?.revision ?? 0) else { throw conflict }
        if action == "approve" {
            guard last?.action != "approve", move == (last?.movement ?? punch.movement), time == (last?.deviceTime ?? punch.deviceTime) else { throw conflict }
        }
        ledger.reviews.append(Review(id: id, punch: punchID, action: action, reason: reason, movement: move,
                                     deviceTime: time, recordedAt: clock.string(from: Date()), revision: revision + 1))
        return ["ok":true]
    }
}
#endif
