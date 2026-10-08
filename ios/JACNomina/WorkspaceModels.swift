import Foundation

// Keeps server records intact. Historical snapshots never round-trip through a
// partial Swift model when editing another record; edits are applied on server.
enum JSONValue: Codable, Equatable {
    case object([String: JSONValue]), array([JSONValue]), string(String), number(Double), bool(Bool), null
    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let value = try? c.decode(Bool.self) { self = .bool(value) }
        else if let value = try? c.decode(Double.self) { self = .number(value) }
        else if let value = try? c.decode(String.self) { self = .string(value) }
        else if let value = try? c.decode([JSONValue].self) { self = .array(value) }
        else { self = .object(try c.decode([String: JSONValue].self)) }
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .object(let value): try c.encode(value)
        case .array(let value): try c.encode(value)
        case .string(let value): try c.encode(value)
        case .number(let value): try c.encode(value)
        case .bool(let value): try c.encode(value)
        case .null: try c.encodeNil()
        }
    }
    var fields: [String: JSONValue] { if case .object(let value) = self { return value }; return [:] }
    var elements: [JSONValue] { if case .array(let value) = self { return value }; return [] }
    var text: String { if case .string(let value) = self { return value }; return "" }
    var number: Double { if case .number(let value) = self { return value }; return 0 }
    var flag: Bool { if case .bool(let value) = self { return value }; return false }
    subscript(_ key: String) -> JSONValue {
        get { fields[key] ?? .null }
        set { var object = fields; object[key] = newValue; self = .object(object) }
    }
    func decoded<T: Decodable>(_ type: T.Type) throws -> T { try JSONDecoder().decode(type, from: JSONEncoder().encode(self)) }
}

struct PayrollEnvelope: Decodable {
    let data: JSONValue
    let version: Int
    let mailNotice: String?
}

struct PayrollWorkspace: Codable {
    let data: JSONValue
    let version: Int
    let user: PayrollUser
    let company: String
    let periods: [PeriodSummary]
    let employees: [Employee]
    var overview: PayrollOverview { PayrollOverview(version: version, company: company, user: user, periods: periods, employees: employees) }
    init(envelope: PayrollEnvelope, user: PayrollUser) throws {
        data = envelope.data; version = envelope.version; self.user = user
        company = data["settings"]["company"].text
        employees = try data["employees"].decoded([Employee].self)
        periods = data["periods"].elements.map { p in
            PeriodSummary(id: p["id"].text, start: p["start"].text, end: p["end"].text, status: p["status"].text,
                          showCount: p["shows"].elements.count, ownerOnly: p["ownerOnly"].flag,
                          closedAt: p["snapshot"]["closedAt"].text.isEmpty ? nil : p["snapshot"]["closedAt"].text)
        }
    }
    func record(_ collection: String, id: String) -> JSONValue? { data[collection].elements.first { $0["id"].text == id } }
}

enum PayrollEditorKind: String {
    case period, employee, concept, settings, show, movement, hours, route, periodEmployee, periodSettings
    var title: String {
        switch self {
        case .period: return "Nueva quincena"
        case .employee: return "Persona y condiciones"
        case .concept: return "Concepto reutilizable"
        case .settings: return "Parámetros de nómina"
        case .show: return "Show y honorarios"
        case .movement: return "Novedad"
        case .hours: return "Horas y salarios"
        case .route: return "Kilometraje"
        case .periodEmployee: return "Condiciones de este corte"
        case .periodSettings: return "Parámetros de este corte"
        }
    }
}

struct PayrollEdit: Codable {
    let kind: String
    var periodId: String?
    var record: JSONValue?
    var id: String?
    var value: JSONValue {
        var fields: [String: JSONValue] = ["kind": .string(kind)]
        if let periodId { fields["periodId"] = .string(periodId) }
        if let record { fields["record"] = record }
        if let id { fields["id"] = .string(id) }
        return .object(fields)
    }
}

struct PayrollEditorSession: Identifiable {
    let id = UUID()
    let kind: PayrollEditorKind
    let workspace: PayrollWorkspace
    let detail: PeriodDetail?
    let record: JSONValue
    var periodID: String? { detail?.period.id }
    var version: Int { detail?.version ?? workspace.version }
    var employees: [Employee] { detail?.employees ?? workspace.employees }
    var activeEmployees: [Employee] { employees.filter { $0.active && $0.deleted != true } }
    var concepts: [JSONValue] { workspace.data["concepts"].elements }
    func command(_ record: JSONValue) -> JSONValue {
        .object(["action": .string("edit"), "version": .number(Double(version)), "edit": PayrollEdit(kind: kind.rawValue, periodId: periodID, record: record).value])
    }
    static func newRecord(_ kind: PayrollEditorKind, workspace: PayrollWorkspace, detail: PeriodDetail? = nil, employeeID: String? = nil) -> JSONValue {
        let employees = (detail?.employees ?? workspace.employees).filter { $0.active && $0.deleted != true }
        let id = UUID().uuidString
        switch kind {
        case .period:
            return newPeriod(month: Date(), half: 1, id: id)
        case .employee:
            return .object(["id": .string(id), "name": .string(""), "email": .string(""), "document": .string(""), "role": .string(""), "category": .string("musicos"), "active": .bool(true), "showRate": .number(750000), "kmRate": .number(0), "fixedService": .number(0), "withholding": .number(0.06), "ica": .number(0.01), "salary": .number(0), "transport": .number(0), "pension": .bool(true), "health": .bool(true), "cycle": .string("quincenal"), "monthlyHalf": .number(2), "nonSalary": .number(0), "contributionBase": .number(1), "incomeTax": .number(0), "solidarity": .number(0)])
        case .concept:
            return .object(["id": .string(id), "name": .string(""), "kind": .string("servicio"), "amount": .number(80000)])
        case .show:
            let excluded = Set(detail?.record["excludedEmployees"].elements.map(\.text) ?? [])
            let participants = employees.filter { ["musicos", "tecnica"].contains($0.category) && !excluded.contains($0.id) }
            return .object(["id": .string(id), "date": .string(detail?.period.start ?? ""), "name": .string(""), "sale": .number(0), "participants": .array(participants.map { .object(["employeeId": .string($0.id), "amount": .number($0.showRate)]) })])
        case .movement:
            let concept = workspace.data["concepts"].elements.first ?? .object([:])
            return .object(["id": .string(id), "employeeId": .string(employees.first?.id ?? ""), "concept": .string(concept["name"].text), "kind": .string(concept["kind"].text.isEmpty ? "servicio" : concept["kind"].text), "amount": .number(concept["amount"].number), "quantity": .number(1), "note": .string("")])
        case .hours:
            let employee = employees.first { $0.id == employeeID }
            return .object(["employeeId": .string(employeeID ?? ""), "counts": .array(Array(repeating: .number(0), count: 7)), "days": .number(employee?.cycle == "mensual" ? 30 : 15), "vacations": .number(0), "note": .string("")])
        case .route:
            return .object(["id": .string(id), "kind": .string("extra"), "date": .string(detail?.period.start ?? ""), "name": .string(""), "km": .number(0), "drivers": detail?.editing?["drivers"] ?? .array([])])
        default: return .object([:])
        }
    }
    static func newPeriod(month: Date, half: Int, id: String) -> JSONValue {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(identifier: "America/Bogota")!
        let c = calendar.dateComponents([.year, .month], from: month)
        let days = calendar.range(of: .day, in: .month, for: month)?.count ?? 30
        let prefix = String(format: "%04d-%02d", c.year ?? 2026, c.month ?? 1)
        return .object(["id": .string(id), "start": .string(prefix + (half == 1 ? "-01" : "-16")), "end": .string(prefix + (half == 1 ? "-15" : String(format: "-%02d", days)))])
    }
}

struct PayrollPreview: Decodable { let data: JSONValue; let version: Int; let detail: PeriodDetail? }
struct OperationNotice: Decodable { let notice: String? }
struct UserDirectory: Decodable { let configured: Bool; let users: [ManagedUser] }
struct ManagedUser: Codable, Identifiable {
    let id: String; var username: String; var email: String; var name: String
    let owner: Bool; var active: Bool; var permissions: [String]; let version: Int; let ready: Bool
}
struct InvitationResult: Decodable { let activationPath: String; let notice: String }
struct GmailStart: Decodable { let url: URL; let nonce: String }
struct PayrollMail: Decodable {
    struct Connection: Decodable { let sender: String; let configured: Bool; let connected: Bool; let error: String; let callback: String }
    struct Job: Decodable, Identifiable {
        let id: String; let employeeId: String; let name: String; let email: String
        let status: String; let attempts: Int; let error: String; let sentAt: String?
    }
    let connection: Connection; let jobs: [Job]; let prepared: Bool
}
