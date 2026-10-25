import Foundation

// This file is compiled into the app and its WidgetKit extension. It contains
// only presentation data: no session, cookie, API credential or original file.
enum JACWidgetShared {
    static let appGroup = "group.co.jacmusic.nomina.widgets"
    static let kind = "JACHome"
    static let directoryName = "JACWidgets"
    static let snapshotFilename = "snapshot-v1.json"
    static let maximumSnapshotBytes = 4 * 1024 * 1024
    static let maximumImageBytes = 512 * 1024
    static let maximumLifetime: TimeInterval = 24 * 60 * 60

    static func containerURL() -> URL? {
        #if os(iOS)
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup)
        #else
        nil
        #endif
    }
}

struct JACWidgetEvent: Codable, Equatable, Sendable {
    let id: String
    let title: String
    let start: Date
    let end: Date
    let allDay: Bool
}

struct JACWidgetPhoto: Codable, Equatable, Sendable {
    let id: String
    let folderID: String
    let createdAt: Date
    let imageData: Data
}

struct JACWidgetCalendarContent: Codable, Equatable, Sendable {
    let updatedAt: Date
    let expiresAt: Date
    let events: [JACWidgetEvent]
}

struct JACWidgetPhotographyContent: Codable, Equatable, Sendable {
    let updatedAt: Date
    let expiresAt: Date
    let photos: [JACWidgetPhoto]
}

struct JACWidgetSnapshot: Codable, Equatable, Sendable {
    var schema: Int = 1
    let owner: String
    var calendar: JACWidgetCalendarContent?
    var photography: JACWidgetPhotographyContent?

    init(owner: String, calendar: JACWidgetCalendarContent? = nil, photography: JACWidgetPhotographyContent? = nil) {
        self.owner = owner
        self.calendar = calendar
        self.photography = photography
    }
}

/// Disk and JSON work execute on this actor, never from a SwiftUI view body.
/// Reads intentionally consult the shared file again so an extension cannot
/// retain a previous account after the app clears or replaces its snapshot.
actor JACWidgetSnapshotStore {
    private let baseDirectory: URL?
    private var directory: URL? { baseDirectory?.appendingPathComponent(JACWidgetShared.directoryName, isDirectory: true) }
    private var file: URL? { directory?.appendingPathComponent(JACWidgetShared.snapshotFilename) }

    init(directory: URL? = JACWidgetShared.containerURL()) {
        self.baseDirectory = directory?.isFileURL == true ? directory : nil
    }

    func read(now: Date = Date()) -> JACWidgetSnapshot? {
        guard let raw = readBytes(), var snapshot = try? JSONDecoder().decode(JACWidgetSnapshot.self, from: raw), Self.valid(snapshot) else { return nil }
        if let value = snapshot.calendar, !Self.fresh(value.updatedAt, until: value.expiresAt, now: now) { snapshot.calendar = nil }
        if let value = snapshot.photography, !Self.fresh(value.updatedAt, until: value.expiresAt, now: now) { snapshot.photography = nil }
        return snapshot
    }

    /// Only the app's current-account activation may replace an owner. A
    /// returning worker must use publishCalendar/Photography with that owner.
    func activate(owner: String) -> Bool {
        if read()?.owner == owner { return false }
        return write(JACWidgetSnapshot(owner: owner))
    }

    func publishCalendar(_ content: JACWidgetCalendarContent?, owner: String) -> Bool {
        guard var snapshot = read(), snapshot.owner == owner else { return false }
        snapshot.calendar = content
        return write(snapshot)
    }

    func publishPhotography(_ content: JACWidgetPhotographyContent?, owner: String) -> Bool {
        guard var snapshot = read(), snapshot.owner == owner else { return false }
        snapshot.photography = content
        return write(snapshot)
    }

    /// True means the visible shared snapshot changed, including fail-closed
    /// removal of an invalid replacement. The app can then reload its widget.
    func write(_ snapshot: JACWidgetSnapshot) -> Bool {
        guard Self.valid(snapshot) else { return clear() }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let bytes = try? encoder.encode(snapshot), bytes.count <= JACWidgetShared.maximumSnapshotBytes else { return clear() }
        guard let directory, let file, safeBase() else { return false }
        if readBytes() == bytes { return false }
        do {
            var attributes: [FileAttributeKey: Any] = [.posixPermissions: 0o700]
            #if os(iOS)
            attributes[.protectionKey] = FileProtectionType.completeUntilFirstUserAuthentication
            #endif
            if FileManager.default.fileExists(atPath: directory.path) {
                guard isDirectory(directory) else { return false }
            } else {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false, attributes: attributes)
            }
            try FileManager.default.setAttributes(attributes, ofItemAtPath: directory.path)
            #if os(iOS)
            try bytes.write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            #else
            try bytes.write(to: file, options: .atomic)
            #endif
            var fileAttributes: [FileAttributeKey: Any] = [.posixPermissions: 0o600]
            #if os(iOS)
            fileAttributes[.protectionKey] = FileProtectionType.completeUntilFirstUserAuthentication
            #endif
            try FileManager.default.setAttributes(fileAttributes, ofItemAtPath: file.path)
            var url = directory, values = URLResourceValues()
            values.isExcludedFromBackup = true
            try url.setResourceValues(values)
            return true
        } catch {
            return clear()
        }
    }

    @discardableResult func clear(ifOwner expectedOwner: String? = nil) -> Bool {
        guard safeBase(), let directory, isDirectory(directory), let file,
              FileManager.default.fileExists(atPath: file.path) else { return false }
        if let expectedOwner {
            guard let bytes = readBytes(), let existing = try? JSONDecoder().decode(JACWidgetSnapshot.self, from: bytes),
                  existing.owner == expectedOwner else { return false }
        }
        do { try FileManager.default.removeItem(at: file); return true }
        catch { return false }
    }

    private func readBytes() -> Data? {
        guard safeBase(), let directory, isDirectory(directory), let file,
              let attributes = try? FileManager.default.attributesOfItem(atPath: file.path),
              attributes[.type] as? FileAttributeType == .typeRegular,
              let size = attributes[.size] as? NSNumber,
              size.intValue >= 0, size.intValue <= JACWidgetShared.maximumSnapshotBytes,
              let bytes = try? Data(contentsOf: file), bytes.count <= JACWidgetShared.maximumSnapshotBytes else { return nil }
        return bytes
    }

    private func safeBase() -> Bool {
        guard let baseDirectory else { return false }
        return isDirectory(baseDirectory)
    }
    private func isDirectory(_ url: URL) -> Bool {
        guard url.isFileURL, let attributes = try? FileManager.default.attributesOfItem(atPath: url.path) else { return false }
        return attributes[.type] as? FileAttributeType == .typeDirectory
    }

    private static func fresh(_ updated: Date, until expiry: Date, now: Date) -> Bool {
        now.timeIntervalSinceReferenceDate.isFinite && updated <= now.addingTimeInterval(300) && now < expiry
    }
    private static func validDates(_ updated: Date, _ expiry: Date) -> Bool {
        updated.timeIntervalSinceReferenceDate.isFinite && expiry.timeIntervalSinceReferenceDate.isFinite && expiry > updated && expiry.timeIntervalSince(updated) <= JACWidgetShared.maximumLifetime
    }
    private static func text(_ value: String, maximum: Int) -> Bool {
        !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && value.count <= maximum && !value.unicodeScalars.contains {
            ($0.value < 32 && $0.value != 9 && $0.value != 10) || $0.value == 127 || (0x202A...0x202E).contains($0.value) || (0x2066...0x2069).contains($0.value)
        }
    }
    private static func mediaID(_ value: String) -> Bool {
        guard value.hasPrefix("r2_"), value.count == 39 else { return false }
        return UUID(uuidString: String(value.dropFirst(3))) != nil
    }
    private static func image(_ data: Data) -> Bool {
        guard !data.isEmpty, data.count <= JACWidgetShared.maximumImageBytes else { return false }
        if data.starts(with: [0xFF, 0xD8, 0xFF]) || data.starts(with: [137, 80, 78, 71, 13, 10, 26, 10]) { return true }
        if data.starts(with: Array("GIF87a".utf8)) || data.starts(with: Array("GIF89a".utf8)) { return true }
        return data.count >= 12 && data.starts(with: Array("RIFF".utf8)) && data.dropFirst(8).starts(with: Array("WEBP".utf8))
    }
    private static func valid(_ snapshot: JACWidgetSnapshot) -> Bool {
        guard snapshot.schema == 1, snapshot.owner.range(of: "^[a-f0-9]{64}$", options: .regularExpression) != nil else { return false }
        if let content = snapshot.calendar {
            guard validDates(content.updatedAt, content.expiresAt), content.events.count <= 64,
                  Set(content.events.map(\.id)).count == content.events.count else { return false }
            for event in content.events {
                guard text(event.id, maximum: 300), text(event.title, maximum: 300),
                      event.start.timeIntervalSinceReferenceDate.isFinite, event.end.timeIntervalSinceReferenceDate.isFinite,
                      event.end >= event.start else { return false }
            }
        }
        if let content = snapshot.photography {
            guard validDates(content.updatedAt, content.expiresAt), content.photos.count <= 8,
                  Set(content.photos.map(\.id)).count == content.photos.count else { return false }
            for photo in content.photos {
                guard mediaID(photo.id), photo.folderID == "jac_r2_root" || mediaID(photo.folderID),
                      photo.createdAt.timeIntervalSinceReferenceDate.isFinite, image(photo.imageData) else { return false }
            }
        }
        return true
    }
}
