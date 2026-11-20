#if os(iOS) && DEBUG
import Foundation
import CryptoKit
import UIKit

/// An isolated, on-device rehearsal. This identifier is only a Keychain/storage namespace.
@MainActor
final class DeviceAttendancePilot {
    static let origin = URL(string: "https://asistencia-dispositivo.invalid")!
    static let shared = DeviceAttendancePilot()
    static let account = "d32c771b-d5ef-4815-98fc-339a811080e4"
    private let certificate = KeychainSessionStore(account: "attendance-device-demo-authorization")
    private let faceKey = KeychainSessionStore(account: "attendance-device-face-key-v1")
    private var grant: (session: String, ticket: String, expires: Date)?
    private let clock: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
    private init() {
        NotificationCenter.default.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.grant = nil }
        }
    }
    private typealias Row = [String: Any]
    private struct Ledger: Codable {
        var people = [
            Person(id: UUID().uuidString.lowercased(), code: "DEMO-01", name: "Empleado de prueba 1"),
            Person(id: UUID().uuidString.lowercased(), code: "DEMO-02", name: "Empleado de prueba 2")
        ]
        var punches = [Punch]()
        var reviews = [Review]()
    }
    private struct FaceReference: Codable {
        let sealed: Data
        let expires: Date
    }
    private struct Person: Codable {
        let id, code, name: String
        var active = true
        var revision = 1
        var face: FaceReference?
        var row: Row { ["id":id, "code":code, "name":name, "active":active, "revision":revision, "hasFace":face != nil] }
    }
    private struct Punch: Codable {
        let id, employee, device, movement, deviceTime, storedAt: String
        let possibleDuplicate, clockDifference: Bool
        var method: String?
        var recordedMethod: String { method ?? "supervised" }
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
        if !["session", "punch", "status", "device-recent"].contains(command) {
            try requireOperator(token, ticket)
        }
        if command == "lock" { grant = nil; return ["ok":true] }

        var ledger = try loadLedger()
        let result: Row
        switch command {
        case "session":
            return ["id":Self.account, "role":"kiosk", "name":"Kiosco de prueba", "mode":"device", "faceCamera":AttendanceFaceCamera.frontCamera != nil,
                    "people":ledger.people.filter(\.active).map(\.row)]
        case "device-recent":
            return ["records":ledger.punches.suffix(12).reversed().map { punch -> Row in
                var row = receipt(punch, ledger)
                row["employee"] = punch.employee
                row["movement"] = punch.movement
                row["device_time"] = punch.deviceTime
                row["personName"] = ledger.people.first { $0.id == punch.employee }?.name ?? ""
                return row
            }]
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
                ledger.people[index].face = nil
                ledger.people[index].active = false
                ledger.people[index].revision += 1
                result = ["status":"inactive"]
            } else {
                ledger.people.remove(at: index)
                result = ["status":"deleted"]
            }
        case "face-remove":
            let i = try personIndex(body, ledger)
            ledger.people[i].face = nil
            ledger.people[i].revision += 1
            result = ["ok":true]
        case "punch":
            guard body["method"] as? String == "supervised" else { throw invalid }
            result = try record(body, method: "supervised", in: &ledger)
        case "review": result = try review(body, in: &ledger)
        default: throw Problem(404, "Esta operación no está disponible en la prueba local.")
        }
        try saveLedger(ledger)
        return result
    }
    private func requireOperator(_ token: String, _ ticket: String?) throws {
        guard let current = grant, current.session == token, current.ticket == ticket, current.expires > Date() else {
            throw Problem(403, "Ingresa la clave de supervisión.")
        }
    }
    private func ledgerFile() throws -> URL {
        try AttendanceStorage.directory().appendingPathComponent("piloto-en-dispositivo-v1.json")
    }
    private func saveLedger(_ ledger: Ledger) throws {
        try JSONEncoder().encode(ledger).write(to: ledgerFile(), options: JACFileSecurity.writeOptions)
    }
    private func loadLedger() throws -> Ledger {
        let file = try ledgerFile()
        guard FileManager.default.fileExists(atPath: file.path) else {
            let ledger = Ledger()
            try saveLedger(ledger)
            return ledger
        }
        var ledger = try JSONDecoder().decode(Ledger.self, from: Data(contentsOf: file))
        let now = Date()
        var expired = false
        for i in ledger.people.indices {
            if let face = ledger.people[i].face, face.expires <= now {
                ledger.people[i].face = nil
                ledger.people[i].revision += 1
                expired = true
            }
        }
        if expired { try saveLedger(ledger) }
        return ledger
    }
    private func keyForFace(create: Bool) throws -> SymmetricKey {
        if let saved = try faceKey.load(), let bytes = Data(base64Encoded: saved), bytes.count == 32 {
            return SymmetricKey(data: bytes)
        }
        guard create else { throw Problem(409, "Registra el rostro de nuevo en este dispositivo.") }
        let key = SymmetricKey(size: .bits256)
        try faceKey.save(key.withUnsafeBytes { Data($0).base64EncodedString() })
        return key
    }
    private func personIndex(_ body: Row, _ ledger: Ledger) throws -> Int {
        let id = try uuid(body, "employee")
        guard let i = ledger.people.firstIndex(where: { $0.id == id && $0.active }),
              body["revision"] as? Int == ledger.people[i].revision else {
            throw Problem(409, "La ficha cambió. Actualiza el listado.")
        }
        return i
    }

    /// Only camera output from native code enters this operation. The bridge never receives a template.
    func captureFace(_ command: String, data: Data, token: String, ticket: String?,
                     capture: (String) async throws -> AttendanceFaceSignature) async throws -> (Data, Int) {
        do {
            guard try authorized(token) else { throw Problem(401, "Vuelve a entrar en el piloto.") }
            guard let body = try JSONSerialization.jsonObject(with: data) as? Row,
                  ["face-enroll", "face-punch"].contains(command) else { throw invalid }
            let enroll = command == "face-enroll"
            if enroll {
                try requireOperator(token, ticket)
                guard body["consent"] as? Bool == true else { throw Problem(400, "Hace falta el consentimiento del participante.") }
            }
            let initial = try loadLedger()
            if !enroll {
                if let previous = try existingFacePunch(body, in: initial) { return try encoded(previous) }
            }
            let person = initial.people[try personIndex(body, initial)]
            guard enroll || person.face != nil else { throw Problem(409, "Este empleado aún no tiene referencia en este dispositivo.") }
            let sample = try await capture(person.name)
            guard try authorized(token) else { throw Problem(401, "La sesión cambió durante la captura.") }
            if enroll { try requireOperator(token, ticket) }
            var ledger = try loadLedger()
            let i = try personIndex(body, ledger)
            let binding = Data(person.id.utf8)
            let result: Row
            if enroll {
                let box = try AES.GCM.seal(JSONEncoder().encode(sample), using: keyForFace(create: true), authenticating: binding)
                guard let bytes = box.combined else { throw invalid }
                ledger.people[i].face = FaceReference(sealed: bytes, expires: Date().addingTimeInterval(30 * 86400))
                ledger.people[i].revision += 1
                result = ["ok":true]
            } else {
                if let previous = try existingFacePunch(body, in: ledger) { return try encoded(previous) }
                guard let face = ledger.people[i].face else { throw Problem(409, "La referencia ya no está disponible.") }
                let reference: AttendanceFaceSignature
                do {
                    let data = try AES.GCM.open(AES.GCM.SealedBox(combined: face.sealed), using: keyForFace(create: false), authenticating: binding)
                    reference = try JSONDecoder().decode(AttendanceFaceSignature.self, from: data)
                } catch { throw Problem(409, "No se pudo abrir la referencia. Puedes volver a registrarla o elegir supervisión.") }
                result = try record(body, method: reference.resembles(sample) ? "visual_match" : "visual_review", in: &ledger)
            }
            try saveLedger(ledger)
            return try encoded(result)
        } catch let issue as Problem {
            return (try JSONSerialization.data(withJSONObject: ["error":issue.message]), issue.status)
        }
    }
    private func encoded(_ row: Row) throws -> (Data, Int) {
        (try JSONSerialization.data(withJSONObject: row), 200)
    }
    private func existingFacePunch(_ body: Row, in ledger: Ledger) throws -> Row? {
        let id = try uuid(body, "id"), employee = try uuid(body, "employee"), device = try uuid(body, "device")
        let (move, time, _) = try movementAndTime(body)
        guard body["account"] as? String == Self.account else { throw invalid }
        guard let previous = ledger.punches.first(where: { $0.id == id }) else { return nil }
        guard previous.employee == employee, previous.device == device, previous.movement == move,
              previous.deviceTime == time, ["visual_match", "visual_review"].contains(previous.recordedMethod) else {
            throw Problem(409, "Existe otra marcación con ese identificador.")
        }
        return receipt(previous, ledger)
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
        if let last = ledger.reviews.last(where: { $0.punch == punch.id }) {
            return last.action == "approve" ? "approved" : "pending"
        }
        return punch.recordedMethod == "visual_match" ? "visual_match" : "pending"
    }
    private func detail(_ punch: Punch, _ ledger: Ledger) -> Row {
        let last = ledger.reviews.last { $0.punch == punch.id }
        return ["id":punch.id, "name":ledger.people.first { $0.id == punch.employee }?.name ?? "",
                "movement":punch.movement, "effective_movement":last?.movement ?? punch.movement,
                "device_time":punch.deviceTime, "effective_time":last?.deviceTime ?? punch.deviceTime,
                "stored_at":punch.storedAt, "method":punch.recordedMethod, "review_state":state(punch, ledger),
                "revision":last?.revision ?? 0, "possible_duplicate":punch.possibleDuplicate, "clock_difference":punch.clockDifference]
    }
    private func record(_ input: Row, method: String, in ledger: inout Ledger) throws -> Row {
        guard input["account"] as? String == Self.account else { throw invalid }
        let id = try uuid(input, "id"), employee = try uuid(input, "employee"), device = try uuid(input, "device")
        let (move, time, date) = try movementAndTime(input)
        let punch: Punch
        if let previous = ledger.punches.first(where: { $0.id == id }) {
            guard previous.employee == employee, previous.device == device, previous.movement == move,
                  previous.deviceTime == time, previous.recordedMethod == method else { throw Problem(409, "Existe otra marcación con ese identificador.") }
            punch = previous
        } else {
            guard ledger.people.contains(where: { $0.id == employee && $0.active }) else { throw Problem(409, "El empleado está inactivo.") }
            let duplicate = ledger.punches.contains { prior in
                guard prior.employee == employee, prior.movement == move, let earlier = clock.date(from: prior.deviceTime) else { return false }
                return abs(earlier.timeIntervalSince(date)) <= 90
            }
            let now = Date()
            punch = Punch(id: id, employee: employee, device: device, movement: move, deviceTime: time,
                          storedAt: clock.string(from: now), possibleDuplicate: duplicate, clockDifference: abs(now.timeIntervalSince(date)) > 300, method: method)
            ledger.punches.append(punch)
        }
        return receipt(punch, ledger)
    }
    private func receipt(_ punch: Punch, _ ledger: Ledger) -> Row {
        ["id":punch.id, "stored_at":punch.storedAt, "method":punch.recordedMethod, "state":state(punch, ledger),
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
