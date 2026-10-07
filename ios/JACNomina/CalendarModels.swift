import Foundation
import CryptoKit
import Combine
import Network

struct AgendaCalendar: Codable, Identifiable {
    let id: String
    let name: String
    let timeZone: String
    let primary: Bool
}
struct AgendaConnection: Codable {
    let configured: Bool
    let connected: Bool
    let email: String
    let selected: AgendaCalendar?
    let revision: Int
    let writeAuthorized: Bool?
}
struct AgendaEvent: Codable, Identifiable {
    let id: String
    let title: String
    let start: String
    let end: String
    let allDay: Bool
    let location: String
    let description: String
    let url: String
    let etag: String?
    let editable: Bool?
    let recurring: Bool?
    init(id: String, title: String, start: String, end: String, allDay: Bool, location: String, description: String, url: String, etag: String? = nil, editable: Bool? = nil, recurring: Bool? = nil) {
        self.id = id; self.title = title; self.start = start; self.end = end; self.allDay = allDay; self.location = location; self.description = description; self.url = url; self.etag = etag; self.editable = editable; self.recurring = recurring
    }
    var firstDay: String { allDay ? start : CalendarClock.day(CalendarClock.instant(start) ?? .distantPast) }
    var timeLabel: String {
        guard !allDay, let from = CalendarClock.instant(start), let to = CalendarClock.instant(end) else { return "Todo el día" }
        let endDay = CalendarClock.day(from) == CalendarClock.day(to) ? "" : CalendarClock.dayLabel(CalendarClock.day(to)) + ", "
        return CalendarClock.time(from) + " – " + endDay + CalendarClock.time(to)
    }
    var googleURL: URL? {
        guard let u = URL(string: url), u.scheme == "https", ["calendar.google.com", "www.google.com"].contains(u.host ?? ""), u.user == nil, u.password == nil, u.port == nil, u.path.hasPrefix("/calendar/") else { return nil }
        return u
    }
    func occurs(on day: String) -> Bool {
        if allDay { return start <= day && end > day }
        guard let from = CalendarClock.instant(start), let to = CalendarClock.instant(end), let date = CalendarClock.date(day), let next = CalendarClock.calendar.date(byAdding: .day, value: 1, to: date) else { return false }
        return from < next && to > date
    }
}
struct AgendaData: Codable {
    let connection: AgendaConnection
    let month: String
    let monthLabel: String
    let days: [String]
    let today: String
    let events: [AgendaEvent]
    let upcoming: [AgendaEvent]
    let upcomingUntil: String
    let updatedAt: String
    let timeZone: String
    let canEditEvents: Bool?
}

struct SavedAgenda: Codable {
    let data: AgendaData
    let receivedAt: Date
}
struct AgendaOfflineRecord: Codable {
    let schema: Int
    let user: PayrollUser
    var months: [SavedAgenda]
    var latest: SavedAgenda? { months.max { $0.receivedAt < $1.receivedAt } }
    func month(_ month: String) -> SavedAgenda? { months.first { $0.data.month == month } }
}

struct AgendaCacheScope {
    let id: String
    let key: SymmetricKey
    init(origin: String, token: String) {
        let salt = Data(("co.jacmusic.nomina.agenda.v1:" + origin).utf8)
        id = SHA256.hash(data: salt + Data(token.utf8)).map { String(format: "%02x", $0) }.joined()
        key = HKDF<SHA256>.deriveKey(inputKeyMaterial: SymmetricKey(data: Data(token.utf8)), salt: salt, info: Data("offline-agenda".utf8), outputByteCount: 32)
    }
}

// Only calendar data and the minimal account identity are persisted. The key
// derives from the session kept in Keychain and is never written to this file.
final class AgendaOfflineCache {
    let root: URL
    static let maximumBytes = 4 * 1024 * 1024
    init(root: URL? = nil) {
        self.root = root ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("JACAgendaOffline", isDirectory: true)
    }
    func file(_ scope: AgendaCacheScope) -> URL { root.appendingPathComponent(scope.id + ".sealed") }
    func load(_ scope: AgendaCacheScope) -> AgendaOfflineRecord? {
        guard let bytes = try? Data(contentsOf: file(scope)), bytes.count <= Self.maximumBytes + 1024,
              let box = try? AES.GCM.SealedBox(combined: bytes),
              let decoded = try? AES.GCM.open(box, using: scope.key),
              let record = try? JSONDecoder().decode(AgendaOfflineRecord.self, from: decoded),
              record.schema == 1, !record.months.isEmpty, record.months.count <= 6 else { return nil }
        return record
    }
    func save(_ record: AgendaOfflineRecord, scope: AgendaCacheScope) throws {
        let bytes = try JSONEncoder().encode(record)
        guard bytes.count <= Self.maximumBytes else { throw APIError.message("La agenda supera el tamaño de la copia local.") }
        let sealed = try AES.GCM.seal(bytes, using: scope.key).combined!
        let manager = FileManager.default
        try manager.createDirectory(at: root, withIntermediateDirectories: true, attributes: [.protectionKey: FileProtectionType.complete])
        try manager.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: root.path)
        var folder = root, values = URLResourceValues(); values.isExcludedFromBackup = true
        try folder.setResourceValues(values)
        let target = file(scope)
        try sealed.write(to: target, options: [.atomic, .completeFileProtection])
        try manager.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: target.path)
    }
    func remove(_ scope: AgendaCacheScope) { try? FileManager.default.removeItem(at: file(scope)) }
    static func isUnavailable(_ error: Error) -> Bool {
        guard let error = error as? URLError else { return false }
        return [.notConnectedToInternet, .timedOut, .cannotConnectToHost, .cannotFindHost, .dnsLookupFailed, .networkConnectionLost, .internationalRoamingOff, .dataNotAllowed].contains(error.code)
    }
}

@MainActor final class AgendaConnectivity: ObservableObject {
    @Published private(set) var connected: Bool?
    private let monitor = NWPathMonitor()
    init() {
        monitor.pathUpdateHandler = { [weak self] path in Task { @MainActor [weak self] in self?.connected = path.status == .satisfied } }
        monitor.start(queue: DispatchQueue(label: "co.jacmusic.nomina.agenda.network"))
    }
    deinit { monitor.cancel() }
}
struct AgendaCalendars: Decodable { let calendars: [AgendaCalendar] }
struct AgendaMutation: Decodable { let connection: AgendaConnection; let notice: String }
struct AgendaStart: Decodable { let url: URL; let nonce: String }
struct AgendaEventMutation: Decodable { let event: AgendaEvent; let notice: String }
struct AgendaEventDraft: Codable {
    let title: String
    let start: String
    let end: String
    let allDay: Bool
    let location: String
    let description: String
    var value: JSONValue { .object(["title": .string(title), "start": .string(start), "end": .string(end), "allDay": .bool(allDay), "location": .string(location), "description": .string(description)]) }
}

enum CalendarClock {
    static func eventsByDay(_ events: [AgendaEvent], days: [String]) -> [String: [AgendaEvent]] {
        let windows = days.compactMap { day -> (String, Date, Date)? in
            guard let start = date(day), let end = calendar.date(byAdding: .day, value: 1, to: start) else { return nil }
            return (day, start, end)
        }
        var grouped: [String: [AgendaEvent]] = [:]
        for event in events {
            if event.allDay { for day in days where event.start <= day && event.end > day { grouped[day, default: []].append(event) } }
            else if let start = instant(event.start), let end = instant(event.end) { for (day, from, to) in windows where start < to && end > from { grouped[day, default: []].append(event) } }
        }
        return grouped
    }
    static var calendar: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "America/Bogota")!; c.locale = Locale(identifier: "es_CO"); c.firstWeekday = 2; return c }
    private static func formatter(_ pattern: String) -> DateFormatter { let f = DateFormatter(); f.locale = Locale(identifier: "es_CO"); f.calendar = calendar; f.timeZone = calendar.timeZone; f.dateFormat = pattern; return f }
    static func day(_ date: Date) -> String { formatter("yyyy-MM-dd").string(from: date) }
    static func month(_ date: Date) -> String { formatter("yyyy-MM").string(from: date) }
    static func date(_ day: String) -> Date? { formatter("yyyy-MM-dd").date(from: day) }
    static func dayLabel(_ day: String) -> String { date(day).map { formatter("EEEE d 'de' MMMM").string(from: $0) } ?? day }
    static func time(_ date: Date) -> String { formatter("h:mm a").string(from: date) }
    static func instant(_ value: String) -> Date? {
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = f.date(from: value) { return date }
        f.formatOptions = [.withInternetDateTime]; return f.date(from: value)
    }
    static func shift(_ month: String, by offset: Int) -> String? { guard let day = date(month + "-01"), let shifted = calendar.date(byAdding: .month, value: offset, to: day) else { return nil }; return self.month(shifted) }
}
