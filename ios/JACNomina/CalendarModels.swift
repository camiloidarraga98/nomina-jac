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

struct AgendaCacheScope: @unchecked Sendable {
    let id: String
    let key: SymmetricKey
    init(origin: String, token: String) {
        JACPerformanceDiagnostics.record(.keyDerivation)
        let salt = Data(("co.jacmusic.nomina.agenda.v1:" + origin).utf8)
        id = SHA256.hash(data: salt + Data(token.utf8)).map { String(format: "%02x", $0) }.joined()
        key = HKDF<SHA256>.deriveKey(inputKeyMaterial: SymmetricKey(data: Data(token.utf8)), salt: salt, info: Data("offline-agenda".utf8), outputByteCount: 32)
    }
}

// Only calendar data and the minimal account identity are persisted. The key
// derives from the session kept in Keychain and is never written to this file.
final class AgendaOfflineCache: @unchecked Sendable {
    private let lock = NSRecursiveLock()
    private let epochLock = NSLock()
    private var epochs: [String: Int] = [:]
    let root: URL
    private let beforeSave: (@Sendable () -> Void)?
    static let maximumBytes = 4 * 1024 * 1024
    init(root: URL? = nil, beforeSave: (@Sendable () -> Void)? = nil) {
        self.beforeSave = beforeSave
        self.root = root ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("JACAgendaOffline", isDirectory: true)
    }
    func file(_ scope: AgendaCacheScope) -> URL { root.appendingPathComponent(scope.id + ".sealed") }
    func epoch(_ scope: AgendaCacheScope) -> Int { epochLock.lock(); defer { epochLock.unlock() }; return epochs[scope.id, default: 0] }
    private func advanceEpoch(_ id: String) { epochLock.lock(); defer { epochLock.unlock() }; epochs[id, default: 0] += 1 }
    func invalidatePendingWrites(_ scope: AgendaCacheScope) { advanceEpoch(scope.id) }
    func load(_ scope: AgendaCacheScope) -> AgendaOfflineRecord? {
        lock.lock(); defer { lock.unlock() }; JACPerformanceDiagnostics.record(.diskRead)
        guard let bytes = try? Data(contentsOf: file(scope)), bytes.count <= Self.maximumBytes + 1024,
              let box = try? AES.GCM.SealedBox(combined: bytes),
              let decoded = try? AES.GCM.open(box, using: scope.key) else { return nil }
        JACPerformanceDiagnostics.record(.jsonDecode)
        guard let record = try? JSONDecoder().decode(AgendaOfflineRecord.self, from: decoded), record.schema == 1, !record.months.isEmpty, record.months.count <= 6 else { return nil }
        return record
    }
    func save(_ record: AgendaOfflineRecord, scope: AgendaCacheScope, expectedEpoch: Int? = nil) throws {
        beforeSave?()
        lock.lock(); defer { lock.unlock() }
        if let expectedEpoch, expectedEpoch != epoch(scope) { throw CancellationError() }
        JACPerformanceDiagnostics.record(.jsonEncode)
        let bytes = try JSONEncoder().encode(record)
        guard bytes.count <= Self.maximumBytes else { throw APIError.message("La agenda supera el tamaño de la copia local.") }
        let sealed = try AES.GCM.seal(bytes, using: scope.key).combined!
        let manager = FileManager.default
        try manager.createDirectory(at: root, withIntermediateDirectories: true, attributes: JACFileSecurity.directoryAttributes)
        try manager.setAttributes(JACFileSecurity.directoryAttributes, ofItemAtPath: root.path)
        var folder = root, values = URLResourceValues(); values.isExcludedFromBackup = true
        try folder.setResourceValues(values)
        let target = file(scope)
        JACPerformanceDiagnostics.record(.diskWrite)
        try sealed.write(to: target, options: JACFileSecurity.writeOptions)
        try manager.setAttributes(JACFileSecurity.fileAttributes, ofItemAtPath: target.path)
    }
    func remove(_ scope: AgendaCacheScope) { advanceEpoch(scope.id); lock.lock(); defer { lock.unlock() }; JACPerformanceDiagnostics.record(.diskWrite); try? FileManager.default.removeItem(at: file(scope)) }
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

// Shared read-only cache. Each response and the index are authenticated and
// encrypted with a session-derived key; no password/token is stored on disk.
struct OfflineResponse: Codable, Sendable {
    let key: String
    let url: String
    let headers: [String: String]
    let data: Data
    let receivedAt: Date
    let revision: Int
    var response: HTTPURLResponse? { URL(string: url).flatMap { HTTPURLResponse(url: $0, statusCode: 200, httpVersion: nil, headerFields: headers.merging(["X-JAC-Offline": "1"]) { _, new in new }) } }
}
final class OfflineResponseCache: @unchecked Sendable {
    struct Entry: Codable, Sendable {
        let key: String; let url: String; let size: Int; let revision: Int
    }
    let root: URL
    // Optional fixture I/O boundary for deterministic cancellation tests. The
    // application never installs a hook; no callback runs while holding a lock.
    private let beforeBatch: (@Sendable () -> Void)?
    static let maximumBytes = 512 * 1024 * 1024
    static let maximumEntryBytes = 16 * 1024 * 1024
    // A transaction holds one lock and writes the index once. Plain responses
    // intentionally are not memoized here: explicit disk loads authenticate the
    // current file, including after external corruption.
    private let lock = NSRecursiveLock()
    private let epochLock = NSLock()
    private var epochs: [String: Int] = [:]
    private var revisions: [String: Int] = [:]
    init(root: URL? = nil, beforeBatch: (@Sendable () -> Void)? = nil) {
        self.beforeBatch = beforeBatch
        self.root = root ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("JACOfflineContent", isDirectory: true)
    }
    static func scope(origin: String, token: String) -> AgendaCacheScope { AgendaCacheScope(origin: origin + "/offline-content-v1", token: token) }
    private func folder(_ scope: AgendaCacheScope) -> URL { root.appendingPathComponent(scope.id, isDirectory: true) }
    func file(_ scope: AgendaCacheScope, key: String) -> URL {
        folder(scope).appendingPathComponent(SHA256.hash(data: Data(key.utf8)).map { String(format: "%02x", $0) }.joined() + ".sealed")
    }
    func epoch(_ scope: AgendaCacheScope) -> Int { epochLock.lock(); defer { epochLock.unlock() }; return epochs[scope.id, default: 0] }
    func memoryRevision(_ scope: AgendaCacheScope) -> Int { epochLock.lock(); defer { epochLock.unlock() }; return revisions[scope.id, default: 0] }
    private func advanceRevision(_ id: String) { epochLock.lock(); defer { epochLock.unlock() }; revisions[id, default: 0] += 1 }
    private func advanceEpoch(_ id: String) { epochLock.lock(); defer { epochLock.unlock() }; epochs[id, default: 0] += 1; revisions[id, default: 0] += 1 }
    private func read<T: Decodable>(_ type: T.Type, scope: AgendaCacheScope, key: String) -> T? {
        let path = file(scope, key: key)
        JACPerformanceDiagnostics.record(.diskRead)
        guard let size = try? path.resourceValues(forKeys: [.fileSizeKey]).fileSize, size <= Self.maximumEntryBytes * 2,
              let bytes = try? Data(contentsOf: path), let box = try? AES.GCM.SealedBox(combined: bytes),
              let plain = try? AES.GCM.open(box, using: scope.key, authenticating: Data(key.utf8)) else { return nil }
        JACPerformanceDiagnostics.record(.jsonDecode)
        return try? JSONDecoder().decode(type, from: plain)
    }
    private func write<T: Encodable>(_ value: T, scope: AgendaCacheScope, key: String) throws {
        let manager = FileManager.default, directory = folder(scope)
        try manager.createDirectory(at: directory, withIntermediateDirectories: true, attributes: JACFileSecurity.directoryAttributes)
        try manager.setAttributes(JACFileSecurity.directoryAttributes, ofItemAtPath: directory.path)
        try manager.setAttributes(JACFileSecurity.directoryAttributes, ofItemAtPath: root.path)
        var excluded = root, values = URLResourceValues(); values.isExcludedFromBackup = true; try excluded.setResourceValues(values)
        JACPerformanceDiagnostics.record(.jsonEncode)
        let bytes = try AES.GCM.seal(JSONEncoder().encode(value), using: scope.key, authenticating: Data(key.utf8)).combined!
        JACPerformanceDiagnostics.record(.diskWrite)
        if key == "index-v1" { JACPerformanceDiagnostics.record(.indexWrite) }
        try bytes.write(to: file(scope, key: key), options: JACFileSecurity.writeOptions)
        try manager.setAttributes(JACFileSecurity.fileAttributes, ofItemAtPath:file(scope,key:key).path)
    }
    func entries(_ scope: AgendaCacheScope) -> [Entry] { lock.lock(); defer { lock.unlock() }; return read([Entry].self, scope: scope, key: "index-v1") ?? [] }
    func load(_ scope: AgendaCacheScope, key: String) -> OfflineResponse? {
        lock.lock(); defer { lock.unlock() }
        guard let record = read(OfflineResponse.self, scope: scope, key: key), record.key == key, record.data.count <= Self.maximumEntryBytes else { return nil }
        return record
    }
    @discardableResult func save(_ record: OfflineResponse, scope: AgendaCacheScope) throws -> Bool { try saveBatch([record], scope: scope) }
    // Ignoring receivedAt avoids rewriting identical polling results. Epochs
    // ensure a queued background write cannot resurrect a revoked/deleted copy.
    @discardableResult func saveBatch(_ records: [OfflineResponse], scope: AgendaCacheScope, expectedEpoch: Int? = nil, removing: ((Entry) -> Bool)? = nil) throws -> Bool {
        beforeBatch?()
        lock.lock(); defer { lock.unlock() }
        if let expectedEpoch, expectedEpoch != epoch(scope) { throw CancellationError() }
        guard records.allSatisfy({ $0.data.count <= Self.maximumEntryBytes }) else { throw APIError.message("Este archivo supera el tamaño de la copia sin conexión.") }
        let original = entries(scope), removed = removing.map { original.filter($0) } ?? []
        var index = original.filter { entry in !removed.contains(where: { $0.key == entry.key }) }
        var writes: [OfflineResponse] = [], changed = !removed.isEmpty
        // Validate limits and revision ordering before changing any files.
        for record in records {
            if let previous = load(scope, key: record.key) {
                if previous.data == record.data && previous.headers == record.headers && previous.revision == record.revision {
                    if !index.contains(where: { $0.key == record.key && $0.url == record.url && $0.size == record.data.count && $0.revision == record.revision }) {
                        index.removeAll { $0.key == record.key }
                        index.append(Entry(key: record.key, url: record.url, size: record.data.count, revision: record.revision)); changed = true
                    }
                    continue
                }
                if previous.revision > record.revision { continue }
                JACPerformanceDiagnostics.record(.jsonDecode); JACPerformanceDiagnostics.record(.jsonDecode)
                if let old = try? JSONDecoder().decode(JSONValue.self, from: previous.data), let new = try? JSONDecoder().decode(JSONValue.self, from: record.data), old["version"].number > new["version"].number { continue }
            }
            let remaining = index.filter { $0.key != record.key }
            guard remaining.count < 4096, remaining.reduce(0, { $0 + $1.size }) + record.data.count <= Self.maximumBytes else { throw APIError.message("La copia sin conexión está llena. Algunos archivos necesitan internet.") }
            index = remaining + [Entry(key: record.key, url: record.url, size: record.data.count, revision: record.revision)]
            writes.append(record); changed = true
        }
        guard changed else { return false }
        for entry in removed { JACPerformanceDiagnostics.record(.diskWrite); try? FileManager.default.removeItem(at: file(scope, key: entry.key)) }
        for record in writes { try write(record, scope: scope, key: record.key) }
        try write(index, scope: scope, key: "index-v1")
        advanceRevision(scope.id)
        return true
    }
    func remove(_ scope: AgendaCacheScope, matching: (Entry) -> Bool) {
        advanceEpoch(scope.id)
        lock.lock(); defer { lock.unlock() }
        let index = entries(scope), removed = index.filter(matching)
        guard !removed.isEmpty else { return }
        for entry in removed { JACPerformanceDiagnostics.record(.diskWrite); try? FileManager.default.removeItem(at: file(scope, key: entry.key)) }
        try? write(index.filter { !matching($0) }, scope: scope, key: "index-v1")
    }
    func clear(_ scope: AgendaCacheScope) {
        advanceEpoch(scope.id)
        lock.lock(); defer { lock.unlock() }
        JACPerformanceDiagnostics.record(.diskWrite)
        try? FileManager.default.removeItem(at: folder(scope))
    }
    func removeOtherSessions(_ scope: AgendaCacheScope) {
        lock.lock(); defer { lock.unlock() }
        JACPerformanceDiagnostics.record(.diskRead)
        for path in (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? [] where path.lastPathComponent != scope.id {
            advanceEpoch(path.lastPathComponent); JACPerformanceDiagnostics.record(.diskWrite); try? FileManager.default.removeItem(at: path)
        }
    }
}
