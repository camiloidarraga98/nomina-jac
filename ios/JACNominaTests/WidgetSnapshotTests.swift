import XCTest
#if os(iOS)
@testable import JACNomina
#else
@testable import JACMac
#endif

final class WidgetSnapshotTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_792_944_000)
    private let owner = String(repeating: "a", count: 64)
    private let otherOwner = String(repeating: "b", count: 64)
    private let photoID = "r2_11111111-1111-4111-8111-111111111111"
    private let folderID = "r2_22222222-2222-4222-8222-222222222222"
    private let png = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+a9QAAAABJRU5ErkJggg==")!

    private func temporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("JAC-widget-tests-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return directory
    }
    private func snapshot(owner: String? = nil) -> JACWidgetSnapshot {
        JACWidgetSnapshot(owner: owner ?? self.owner,
            calendar: JACWidgetCalendarContent(updatedAt: now, expiresAt: now.addingTimeInterval(3600), events: [
                JACWidgetEvent(id: "fixture-event", title: "Concierto ficticio", start: now.addingTimeInterval(1800), end: now.addingTimeInterval(5400), allDay: false)
            ]),
            photography: JACWidgetPhotographyContent(updatedAt: now, expiresAt: now.addingTimeInterval(7200), photos: [
                JACWidgetPhoto(id: photoID, folderID: folderID, createdAt: now, imageData: png)
            ]))
    }
    private func file(_ directory: URL) -> URL {
        directory.appendingPathComponent(JACWidgetShared.directoryName, isDirectory: true).appendingPathComponent(JACWidgetShared.snapshotFilename)
    }

    private func agenda(events: [AgendaEvent], upcoming: [AgendaEvent], at date: Date) -> AgendaData {
        let calendar = AgendaCalendar(id: "widget-fixture", name: "Agenda ficticia", timeZone: "America/Bogota", primary: true)
        let connection = AgendaConnection(configured: true, connected: true, email: "fixture@example.invalid", selected: calendar, revision: 1, writeAuthorized: false)
        return AgendaData(connection: connection, month: CalendarClock.month(date), monthLabel: "Mes de prueba", days: [], today: CalendarClock.day(date), events: events, upcoming: upcoming, upcomingUntil: "", updatedAt: ISO8601DateFormatter().string(from: date), timeZone: "America/Bogota", canEditEvents: false)
    }
    private func event(_ id: String, start: Date) -> AgendaEvent {
        let formatter = ISO8601DateFormatter()
        return AgendaEvent(id: id, title: "Evento " + id, start: formatter.string(from: start), end: formatter.string(from: start.addingTimeInterval(1800)), allDay: false, location: "", description: "", url: "")
    }

    func testBusyCalendarKeepsUpcomingEventsBeforePastMonthHistory() {
        let past = (1...70).map { event("past-\($0)", start: now.addingTimeInterval(-Double($0) * 3600)) }
        let future = (1...3).map { event("future-\($0)", start: now.addingTimeInterval(Double($0) * 3600)) }
        let feed = agenda(events: past, upcoming: future + [future[0]], at: now)
        let selected = JACWidgetBridge.events(feed, now: now)
        XCTAssertEqual(selected.count, 64)
        XCTAssertEqual(Set(selected.map(\.id)).count, 64)
        for item in future { XCTAssertTrue(selected.contains { $0.id == item.id }) }
        XCTAssertTrue(selected.contains { $0.id == "past-1" })
        XCTAssertFalse(selected.contains { $0.id == "past-70" })
        XCTAssertEqual(selected.map(\.start), selected.map(\.start).sorted())
        let manyFuture = (0..<70).map { event("upcoming-\($0)", start: now.addingTimeInterval(Double($0 + 1) * 3600)) }
        let full = JACWidgetBridge.events(agenda(events: past, upcoming: manyFuture, at: now), now: now)
        XCTAssertEqual(full.count, 64)
        XCTAssertTrue(full.contains { $0.id == "upcoming-0" })
        XCTAssertTrue(full.contains { $0.id == "upcoming-63" })
        XCTAssertFalse(full.contains { $0.id == "upcoming-64" })
        XCTAssertFalse(full.contains { $0.id.hasPrefix("past-") })
    }

    @MainActor func testBridgeRejectsCalendarPublicationAfterTheSessionIsRemoved() async throws {
        let directory = try temporaryDirectory(), snapshots = JACWidgetSnapshotStore(directory: directory)
        let bridge = JACWidgetBridge(snapshots: snapshots), client = UITestBackend.client(downloadOffline: false)
        let workspace = try await client.workspace()
        defer { try? client.clearSession() }
        let fresh = Date(), feed = agenda(events: [event("next", start: fresh.addingTimeInterval(3600))], upcoming: [], at: fresh)
        await bridge.publishCalendar(client: client, user: workspace.user, data: feed)
        let visible = await snapshots.read()
        XCTAssertEqual(visible?.calendar?.events.first?.id, "next")
        try client.clearSession()
        await bridge.publishCalendar(client: client, user: workspace.user, data: feed)
        let afterLogout = await snapshots.read()
        XCTAssertNil(afterLogout, "An old authorized result cannot republish a widget after logout.")
    }

    @MainActor func testThrottledWidgetRefreshAndUnchangedCalendarPerformNoSessionReads() async throws {
        let snapshots = JACWidgetSnapshotStore(directory: try temporaryDirectory()), bridge = JACWidgetBridge(snapshots: snapshots)
        let client = UITestBackend.client(downloadOffline: false), workspace = try await client.workspace()
        defer { try? client.clearSession() }
        var json = try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(workspace))
        json["user"]["isOwner"] = .bool(false)
        json["user"]["sections"] = .array([.string("calendar")])
        let restricted = try json.decoded(PayrollWorkspace.self)
        client.rememberWorkspace(restricted)
        let fresh = Date(), feed = agenda(events: [event("next", start: fresh.addingTimeInterval(3600))], upcoming: [], at: fresh)
        await bridge.refresh(client: client, user: restricted.user, agenda: feed)
        let visible = await snapshots.read()
        XCTAssertEqual(visible?.calendar?.events.first?.id, "next")
        let baseline = JACPerformanceDiagnostics.snapshot()
        for _ in 0..<100 {
            await bridge.refresh(client: client, user: restricted.user)
            await bridge.publishCalendar(client: client, user: restricted.user, data: feed)
        }
        let sample = JACPerformanceDiagnostics.snapshot().delta(from: baseline)
        XCTAssertEqual(sample.count(.sessionRead), 0, "Skipped refreshes must not query Keychain or renew a private snapshot.")
        XCTAssertEqual(sample.mainThreadExpensiveOperations, 0)
        try client.clearSession()
        await bridge.publishCalendar(client: client, user: restricted.user, data: feed)
        let revoked = await snapshots.read()
        XCTAssertNil(revoked, "The memory preflight must never publish after session removal.")
    }

    @MainActor func testLockedBackgroundOpportunityDoesNotReadSessionOrEraseSnapshot() async throws {
        let directory = try temporaryDirectory(), snapshots = JACWidgetSnapshotStore(directory: directory), value = snapshot()
        let written = await snapshots.write(value)
        XCTAssertTrue(written)
        let client = UITestBackend.client(downloadOffline: false)
        let bridge = JACWidgetBridge(snapshots: snapshots, protectedDataAvailable: { false })
        let originalBytes = try Data(contentsOf: file(directory))
        let baseline = JACPerformanceDiagnostics.snapshot()
        await bridge.refreshInBackground(client: client)
        let sample = JACPerformanceDiagnostics.snapshot().delta(from: baseline)
        XCTAssertEqual(sample.count(.sessionRead), 0, "A locked-phone background opportunity must not query WhenUnlocked credentials.")
        XCTAssertEqual(sample.mainThreadExpensiveOperations, 0)
        XCTAssertEqual(try Data(contentsOf: file(directory)), originalBytes, "Locking does not renew, replace or erase a previously authorized snapshot.")
        let retained = await snapshots.read(now: now)
        XCTAssertEqual(retained, value)
        let expired = await snapshots.read(now: now.addingTimeInterval(7200))
        XCTAssertNil(expired?.calendar); XCTAssertNil(expired?.photography)
    }

    func testWidgetLinksOnlyAcceptAuthorizedAppRoutesWithoutCredentials() throws {
        let calendar = JACWidgetRoute.calendar
        let photograph = JACWidgetRoute.photography(folderID: folderID)
        XCTAssertEqual(JACWidgetRoute(url: calendar.url), calendar)
        XCTAssertEqual(JACWidgetRoute(url: photograph.url), photograph)
        XCTAssertEqual(JACWidgetRoute(url: JACWidgetRoute.photography(folderID: "jac_r2_root").url), .photography(folderID: "jac_r2_root"))
        XCTAssertEqual(JACWidgetRoute(url: JACWidgetRoute.photography(folderID: nil).url), .photography(folderID: nil))
        for value in [
            "https://widget/calendar", "jacnomina://other/calendar", "jacnomina://widget/calendar?token=secret",
            "jacnomina://widget/calendar#ignored", "jacnomina://user@widget/calendar", "jacnomina://widget:123/calendar",
            "jacnomina://widget/fotografia?folder=../private", "jacnomina://widget/fotografia?folder=",
            "jacnomina://widget/fotografia?folder=jac_r2_root&folder=jac_r2_root", "jacnomina://widget/fotografia?access=secret"
        ] {
            XCTAssertNil(JACWidgetRoute(url: try XCTUnwrap(URL(string: value))), value)
        }
    }

    func testProtectedSnapshotRoundTripsWithoutCredentialsAndDeduplicatesWrites() async throws {
        let directory = try temporaryDirectory(), store = JACWidgetSnapshotStore(directory: directory), value = snapshot()
        let firstWrite = await store.write(value)
        XCTAssertTrue(firstWrite)
        let restored = await store.read(now: now)
        XCTAssertEqual(restored, value)
        let attributes = try FileManager.default.attributesOfItem(atPath: file(directory).path)
        let repeatWrite = await store.write(value)
        XCTAssertFalse(repeatWrite)
        XCTAssertEqual(try FileManager.default.attributesOfItem(atPath: file(directory).path)[.modificationDate] as? Date, attributes[.modificationDate] as? Date)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: file(directory))) as? [String: Any])
        XCTAssertEqual(Set(json.keys), ["schema", "owner", "calendar", "photography"])
        XCTAssertNil(json["token"]); XCTAssertNil(json["cookie"]); XCTAssertNil(json["session"])
        XCTAssertEqual((attributes[.posixPermissions] as? NSNumber)?.intValue, 0o600)
        let folder = directory.appendingPathComponent(JACWidgetShared.directoryName, isDirectory: true)
        let directoryAttributes = try FileManager.default.attributesOfItem(atPath: folder.path)
        XCTAssertEqual((directoryAttributes[.posixPermissions] as? NSNumber)?.intValue, 0o700)
    }

    func testSharedSnapshotDataProtectionOnPhysicaliPhone() async throws {
        #if targetEnvironment(simulator)
        throw XCTSkip("CoreSimulator no expone NSFileProtectionKey ni reproduce el cifrado del iPhone. Esta comprobación se conserva para un dispositivo físico.")
        #elseif os(iOS)
        let directory = try temporaryDirectory(), store = JACWidgetSnapshotStore(directory: directory)
        let written = await store.write(snapshot())
        XCTAssertTrue(written)
        let attributes = try FileManager.default.attributesOfItem(atPath: file(directory).path)
        let protection = (attributes[.protectionKey] as? FileProtectionType)?.rawValue ?? attributes[.protectionKey] as? String
        XCTAssertEqual(protection, FileProtectionType.completeUntilFirstUserAuthentication.rawValue)
        let folder = directory.appendingPathComponent(JACWidgetShared.directoryName, isDirectory: true)
        let directoryAttributes = try FileManager.default.attributesOfItem(atPath: folder.path)
        let directoryProtection = (directoryAttributes[.protectionKey] as? FileProtectionType)?.rawValue ?? directoryAttributes[.protectionKey] as? String
        XCTAssertEqual(directoryProtection, FileProtectionType.completeUntilFirstUserAuthentication.rawValue)
        #else
        throw XCTSkip("La comprobación de Data Protection requiere un iPhone físico con iOS.")
        #endif
    }

    func testPermissionAndAccountReplacementCannotRetainPreviousPhotos() async throws {
        let directory = try temporaryDirectory(), store = JACWidgetSnapshotStore(directory: directory)
        _ = await store.write(snapshot())
        let changed = await store.write(JACWidgetSnapshot(owner: otherOwner, calendar: snapshot().calendar))
        XCTAssertTrue(changed)
        let next = await store.read(now: now)
        XCTAssertEqual(next?.owner, otherOwner)
        XCTAssertNil(next?.photography)
        let staleClear = await store.clear(ifOwner: owner)
        XCTAssertFalse(staleClear, "A delayed cleanup from the old account cannot remove the new account's snapshot.")
        let retained = await store.read(now: now)
        XCTAssertEqual(retained?.owner, otherOwner)
        let anotherProcess = JACWidgetSnapshotStore(directory: directory)
        _ = await store.clear()
        let afterLogout = await anotherProcess.read(now: now)
        XCTAssertNil(afterLogout, "A second reader must consult the shared file after logout.")
        let clearedAgain = await store.clear()
        XCTAssertFalse(clearedAgain)
    }

    func testIndependentPublicationsMergeAtomicallyAndLateOldOwnerCannotRestoreData() async throws {
        let store = JACWidgetSnapshotStore(directory: try temporaryDirectory()), fresh = Date()
        let calendar = JACWidgetCalendarContent(updatedAt: fresh, expiresAt: fresh.addingTimeInterval(3600), events: snapshot().calendar!.events)
        let photographs = JACWidgetPhotographyContent(updatedAt: fresh, expiresAt: fresh.addingTimeInterval(3600), photos: snapshot().photography!.photos)
        _ = await store.activate(owner: owner)
        _ = await store.publishCalendar(calendar, owner: owner)
        _ = await store.publishPhotography(photographs, owner: owner)
        let combined = await store.read(now: fresh)
        XCTAssertEqual(combined?.calendar, calendar); XCTAssertEqual(combined?.photography, photographs)
        _ = await store.publishCalendar(nil, owner: owner)
        let mediaOnly = await store.read(now: fresh)
        XCTAssertNil(mediaOnly?.calendar); XCTAssertEqual(mediaOnly?.photography, photographs)
        _ = await store.activate(owner: otherOwner)
        let staleCalendar = await store.publishCalendar(calendar, owner: owner)
        let stalePhotos = await store.publishPhotography(photographs, owner: owner)
        XCTAssertFalse(staleCalendar); XCTAssertFalse(stalePhotos)
        let replacement = await store.read(now: fresh)
        XCTAssertEqual(replacement?.owner, otherOwner)
        XCTAssertNil(replacement?.calendar); XCTAssertNil(replacement?.photography)
        _ = await store.publishCalendar(calendar, owner: otherOwner)
        let current = await store.read(now: fresh)
        XCTAssertEqual(current?.calendar, calendar)
        XCTAssertNil(current?.photography)
    }

    func testExpiryAppliesIndependentlyAndFutureClockCannotRevealAStaleSection() async throws {
        let store = JACWidgetSnapshotStore(directory: try temporaryDirectory())
        _ = await store.write(snapshot())
        let partlyExpired = await store.read(now: now.addingTimeInterval(3600))
        XCTAssertNil(partlyExpired?.calendar)
        XCTAssertNotNil(partlyExpired?.photography)
        let allExpired = await store.read(now: now.addingTimeInterval(7200))
        XCTAssertNil(allExpired?.calendar); XCTAssertNil(allExpired?.photography)
        let earlierClock = await store.read(now: now.addingTimeInterval(-301))
        XCTAssertNil(earlierClock?.calendar); XCTAssertNil(earlierClock?.photography)
    }

    func testCorruptUnknownAndOversizedSnapshotsFailClosed() async throws {
        let directory = try temporaryDirectory(), store = JACWidgetSnapshotStore(directory: directory)
        _ = await store.write(snapshot())
        try Data("{broken".utf8).write(to: file(directory), options: .atomic)
        let broken = await store.read(now: now)
        XCTAssertNil(broken)
        var unsupported = snapshot(); unsupported.schema = 2
        try JSONEncoder().encode(unsupported).write(to: file(directory), options: .atomic)
        let unknown = await store.read(now: now)
        XCTAssertNil(unknown)
        try Data(count: JACWidgetShared.maximumSnapshotBytes + 1).write(to: file(directory), options: .atomic)
        let oversized = await store.read(now: now)
        XCTAssertNil(oversized)
        _ = await store.write(snapshot())
        let invalidReplacement = JACWidgetSnapshot(owner: "an-actual-account-name")
        let invalidated = await store.write(invalidReplacement)
        XCTAssertTrue(invalidated)
        let absent = await store.read(now: now)
        XCTAssertNil(absent)
    }

    func testExternalPathsInvalidImagesAndUnboundedContentAreRejected() async throws {
        let store = JACWidgetSnapshotStore(directory: try temporaryDirectory())
        for badFolder in ["../other/private.jpg", "https://photos.example.invalid/original", "r2_not-an-id"] {
            var value = snapshot()
            value.photography = JACWidgetPhotographyContent(updatedAt: now, expiresAt: now.addingTimeInterval(3600), photos: [
                JACWidgetPhoto(id: photoID, folderID: badFolder, createdAt: now, imageData: png)
            ])
            _ = await store.write(value)
            let result = await store.read(now: now)
            XCTAssertNil(result)
        }
        var value = snapshot()
        value.photography = JACWidgetPhotographyContent(updatedAt: now, expiresAt: now.addingTimeInterval(3600), photos: [
            JACWidgetPhoto(id: photoID, folderID: "jac_r2_root", createdAt: now, imageData: Data("not an image".utf8))
        ])
        _ = await store.write(value)
        let invalidImage = await store.read(now: now)
        XCTAssertNil(invalidImage)
        value.calendar = JACWidgetCalendarContent(updatedAt: now, expiresAt: now.addingTimeInterval(JACWidgetShared.maximumLifetime + 1), events: [])
        _ = await store.write(value)
        let excessiveLife = await store.read(now: now)
        XCTAssertNil(excessiveLife)
        let noGroup = JACWidgetSnapshotStore(directory: nil)
        let unavailable = await noGroup.write(snapshot())
        XCTAssertFalse(unavailable)
        let unavailableRead = await noGroup.read(now: now)
        XCTAssertNil(unavailableRead)
    }

    func testWritesCannotExceedThePhotoAndEventBudgets() async throws {
        let store = JACWidgetSnapshotStore(directory: try temporaryDirectory())
        var large = Data([0xFF, 0xD8, 0xFF])
        large.append(Data(count: JACWidgetShared.maximumImageBytes))
        var value = snapshot()
        value.photography = JACWidgetPhotographyContent(updatedAt: now, expiresAt: now.addingTimeInterval(3600), photos: [
            JACWidgetPhoto(id: photoID, folderID: folderID, createdAt: now, imageData: large)
        ])
        _ = await store.write(value)
        let excessiveImage = await store.read(now: now)
        XCTAssertNil(excessiveImage)
        value = snapshot()
        value.photography = JACWidgetPhotographyContent(updatedAt: now, expiresAt: now.addingTimeInterval(3600), photos: (0..<9).map { _ in
            JACWidgetPhoto(id: "r2_" + UUID().uuidString, folderID: folderID, createdAt: now, imageData: png)
        })
        _ = await store.write(value)
        let excessivePhotos = await store.read(now: now)
        XCTAssertNil(excessivePhotos)
        value = snapshot()
        value.calendar = JACWidgetCalendarContent(updatedAt: now, expiresAt: now.addingTimeInterval(3600), events: (0..<65).map { index in
            JACWidgetEvent(id: "fixture-\(index)", title: "Evento ficticio", start: now, end: now.addingTimeInterval(3600), allDay: false)
        })
        _ = await store.write(value)
        let excessiveEvents = await store.read(now: now)
        XCTAssertNil(excessiveEvents)
    }
}
