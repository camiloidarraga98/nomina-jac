import Foundation

enum JACSection: String, CaseIterable, Codable {
    case payroll, calendar, itineraries, alerts, boarding, media, mediaUpload, crm
    var title: String { switch self { case .payroll: "Nómina"; case .calendar: "Agenda"; case .itineraries: "Itinerarios"; case .alerts: "Alertas"; case .boarding: "Pases de abordar"; case .media: "Fotografía · consultar"; case .mediaUpload: "Fotografía · subir y crear carpetas"; case .crm: "CRM · solo administradores" } }
}
struct PayrollUser: Codable, Equatable {
    let id: String
    let email: String
    let username: String
    let displayName: String
    let isOwner: Bool
    let permissions: [String]
    var itinerariesOnly: Bool? = nil
    var mediaOnly: Bool? = nil
    var sections: [String]? = nil

    func hasSection(_ section: JACSection) -> Bool {
        if isOwner && mediaOnly != true && itinerariesOnly != true { return true }
        if let sections { return sections.allSatisfy {JACSection(rawValue:$0) != nil} && sections.contains(section.rawValue) && (section != .crm || isOwner) && (section != .mediaUpload || sections.contains(JACSection.media.rawValue)) }
        if section == .crm { return false }
        if mediaOnly == true { return section == .media || section == .mediaUpload }
        if itinerariesOnly == true { return [.calendar,.itineraries,.alerts,.boarding].contains(section) }
        return [.payroll,.calendar,.itineraries,.alerts,.boarding].contains(section)
    }
    var canReadMedia: Bool { hasSection(.media) }
    var canUploadMedia: Bool { hasSection(.mediaUpload) }
    var hasNotices: Bool { hasSection(.itineraries) || hasSection(.alerts) || hasSection(.boarding) }
    var onlyMedia: Bool { canReadMedia && !JACSection.allCases.contains { $0 != .media && $0 != .mediaUpload && hasSection($0) } }
    func permitsNotice(_ kind: String) -> Bool { kind == "boarding_pass" ? hasSection(.boarding) : kind == "itinerary" ? hasSection(.itineraries) : kind == "alert" && hasSection(.alerts) }
    var firstDestination: String { hasSection(.payroll) ? "payroll" : hasSection(.calendar) ? "agenda" : hasSection(.itineraries) || hasSection(.boarding) ? "itineraries" : hasSection(.alerts) ? "alerts" : canReadMedia ? "media" : "account" }
    func can(_ permission: String) -> Bool { hasSection(.payroll) && (isOwner || permissions.contains(permission)) }
}

struct PayrollOverview: Codable {
    let version: Int
    let company: String
    let user: PayrollUser
    let periods: [PeriodSummary]
    let employees: [Employee]
}

struct PeriodSummary: Codable, Identifiable {
    let id: String
    let start: String
    let end: String
    let status: String
    let showCount: Int
    let ownerOnly: Bool
    let closedAt: String?
    var isClosed: Bool { status == "cerrada" }
    var title: String { PayrollFormat.period(start: start, end: end) }
}

struct PeriodDetail: Decodable {
    let version: Int
    let period: PayrollPeriod
    let employees: [Employee]
    let calculation: PayrollCalculation
    let closeIssues: [String]
    let record: JSONValue
    let editing: JSONValue?

    private enum CodingKeys: String, CodingKey { case version, period, employees, calculation, closeIssues, editing }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decode(Int.self, forKey: .version)
        period = try c.decode(PayrollPeriod.self, forKey: .period)
        record = try c.decode(JSONValue.self, forKey: .period)
        employees = try c.decode([Employee].self, forKey: .employees)
        calculation = try c.decode(PayrollCalculation.self, forKey: .calculation)
        closeIssues = try c.decode([String].self, forKey: .closeIssues)
        editing = try c.decodeIfPresent(JSONValue.self, forKey: .editing)
    }

    func employeeName(_ id: String) -> String {
        employees.first(where: { $0.id == id })?.name ?? "Persona no disponible"
    }
}

struct Employee: Codable, Identifiable {
    let id: String
    let name: String
    let document: String
    let role: String
    let category: String
    let active: Bool
    let showRate: Double
    let kmRate: Double
    let fixedService: Double
    let salary: Double
    let transport: Double
    let pension: Bool
    let health: Bool
    let cycle: String
    let deleted: Bool?
    let email: String?
    var categoryName: String { PayrollFormat.category(category) }
}

struct PayrollPeriod: Decodable, Identifiable {
    let id: String
    let start: String
    let end: String
    let status: String
    let shows: [PayrollShow]
    let movements: [PayrollMovement]
    let hours: [PayrollHours]
    let routes: [PayrollRoute]
    let ownerOnly: Bool?
    var isClosed: Bool { status == "cerrada" }
    var title: String { PayrollFormat.period(start: start, end: end) }
}

struct PayrollShow: Decodable, Identifiable {
    struct Participant: Decodable { let employeeId: String; let amount: Double }
    let id: String
    let date: String
    let name: String
    let sale: Double
    var promotional: Bool? = nil
    let participants: [Participant]
}

struct PayrollMovement: Decodable, Identifiable {
    let id: String
    let employeeId: String
    let concept: String
    let kind: String
    let quantity: Double
    let amount: Double
    let note: String
}

struct PayrollHours: Decodable {
    let employeeId: String
    let counts: [Double]
    let days: Double
    let vacations: Double
    let note: String
}

struct PayrollRoute: Decodable, Identifiable {
    struct Driver: Decodable { let employeeId: String; let rate: Double }
    let id: String
    let date: String
    let name: String
    let km: Double
    let kind: String?
    let showId: String?
    let drivers: [Driver]?
    let employeeId: String?
    let rate: Double?
    var participants: [Driver] {
        if let drivers { return drivers }
        if let employeeId, let rate { return [Driver(employeeId: employeeId, rate: rate)] }
        return []
    }
}

struct PayrollCommissionShow: Decodable, Identifiable {
    let id: String; let name: String; let date: String; let promotional: Bool
    let sale: Double; let musicians: Double; let technical: Double; let drivers: Double
    let expenses: Double; let cost: Double; let deductible: Double
}
struct PayrollCamiloCommission: Decodable {
    let rate: Double; let sales: Double; let costs: Double; let promotionalCosts: Double
    let balance: Double; let base: Double; let amount: Double?
    let shows: [PayrollCommissionShow]; let issues: [String]; let unlinkedKilometers: Double
}
struct PayrollCalculation: Decodable {
    var camiloCommission: PayrollCamiloCommission? = nil
    let rows: [PayrollPayment]
    let sale: Double
    let total: Double
    let gross: Double
    let deductions: Double
    let reimbursements: Double
    let company: String
    let nit: String
    let closedAt: String?
}

struct PayrollPayment: Decodable {
    let employeeId: String
    let name: String
    let document: String
    let role: String
    let category: String
    let gross: Double
    let reimbursements: Double
    let deductions: Double
    let net: Double
    let items: [PayrollItem]
}

struct PayrollItem: Decodable {
    let concept: String
    let quantity: Double
    let rate: Double
    let amount: Double
    let kind: String
    let reference: String?
}

enum DocumentFormat: String, CaseIterable, Identifiable {
    case pdf, slips, xlsx, zip
    var id: String { rawValue }
    var title: String {
        switch self {
        case .pdf: return "Resumen PDF"
        case .slips: return "Todos los desprendibles PDF"
        case .xlsx: return "Excel de nómina"
        case .zip: return "Desprendibles en ZIP"
        }
    }
    var fileExtension: String {
        switch self { case .pdf, .slips: return "pdf"; case .xlsx: return "xlsx"; case .zip: return "zip" }
    }
}

enum PayrollFormat {
    static func money(_ value: Double) -> String {
        value.formatted(.currency(code: "COP").precision(.fractionLength(0)).locale(Locale(identifier: "es_CO")))
    }
    static func number(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...2)).locale(Locale(identifier: "es_CO")))
    }
    static func date(_ iso: String) -> String {
        let parser = DateFormatter()
        parser.locale = Locale(identifier: "en_US_POSIX")
        parser.timeZone = TimeZone(secondsFromGMT: 0)
        parser.dateFormat = "yyyy-MM-dd"
        guard let date = parser.date(from: iso) else { return iso }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "es_CO")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "d MMM yyyy"
        return formatter.string(from: date)
    }
    static func period(start: String, end: String) -> String {
        "\(date(start)) – \(date(end))"
    }
    static func timestamp(_ iso: String) -> String {
        let parser = ISO8601DateFormatter(); parser.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let date = parser.date(from: iso) ?? ISO8601DateFormatter().date(from: iso)
        guard let date else { return iso }
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "es_CO"); formatter.timeZone = TimeZone(identifier: "America/Bogota"); formatter.dateFormat = "dd/MM/yyyy HH:mm"
        return formatter.string(from: date)
    }
    static func category(_ value: String) -> String {
        ["musicos": "Músicos", "tecnica": "Técnica", "conductores": "Conductores", "administracion": "Dependientes", "comision": "Comisiones y otros"][value] ?? value
    }
    static let hourNames = ["Recargo nocturno", "Recargo dominical diurno", "Recargo dominical nocturno", "Extra diurna", "Extra nocturna", "Extra dominical diurna", "Extra dominical nocturna"]
    static let permissionNames = ["payroll": "Registrar nómina", "staff": "Modificar personal", "rules": "Modificar conceptos", "close": "Cerrar quincenas", "modifyClosed": "Modificar cierres", "send": "Enviar desprendibles", "export": "Descargar documentos"]
}
