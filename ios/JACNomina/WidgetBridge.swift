#if os(iOS)
import Foundation
import CryptoKit
import WidgetKit
import BackgroundTasks
import UIKit

/// Orchestrates authenticated reads in the app. The shared actor performs all
/// encoding and file I/O; neither a scroll render nor the extension fetches it.
@MainActor
final class JACWidgetBridge {
    static let shared = JACWidgetBridge()
    static let backgroundTaskIdentifier = "co.jacmusic.nomina.widget-refresh"
    private let snapshots: JACWidgetSnapshotStore
    private let protectedDataAvailable: @MainActor () -> Bool
    private var owner: String?
    private weak var preparedClient: PayrollClient?
    private var preparedUser: PayrollUser?
    private var generation = 0
    private var activeRequest: UUID?
    private var lastRefresh = Date.distantPast
    private var lastCalendarEvents: [JACWidgetEvent]?
    private var lastCalendarPublish = Date.distantPast
    private var lastCalendarSource: [JACWidgetSourceEvent]?
    private var lastCalendarContext: String?
    private let refreshInterval: TimeInterval = 15 * 60
    private let renewalInterval: TimeInterval = 60 * 60

    init(snapshots: JACWidgetSnapshotStore = JACWidgetSnapshotStore(), protectedDataAvailable: @escaping @MainActor () -> Bool = { UIApplication.shared.isProtectedDataAvailable }) {
        self.snapshots = snapshots; self.protectedDataAvailable = protectedDataAvailable
    }

    func scheduleBackgroundRefresh() {
        guard owner != nil else { return }
        let request = BGAppRefreshTaskRequest(identifier: Self.backgroundTaskIdentifier)
        request.earliestBeginDate = Date().addingTimeInterval(refreshInterval)
        // iOS decides whether and when the opportunity is granted. A simulator
        // or a device with Background App Refresh disabled may reject scheduling.
        try? BGTaskScheduler.shared.submit(request)
    }

    func refreshInBackground(client: PayrollClient) async {
        // The main session remains WhenUnlocked. An ordinary locked-phone
        // opportunity must not query Keychain or erase a still-bounded widget.
        guard !Task.isCancelled else { return }
        guard protectedDataAvailable() else { scheduleBackgroundRefresh(); return }
        defer {
            if let user = client.accessUser, user.hasSection(.calendar) || user.canReadMedia {
                scheduleBackgroundRefresh()
            } else {
                BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: Self.backgroundTaskIdentifier)
            }
        }
        var initialMarker: String?
        do {
            initialMarker = try client.widgetSessionMarker()
            let workspace = try await client.workspace(forceNetwork: true)
            try Task.checkCancellation()
            guard protectedDataAvailable(), !client.usingOfflineCopy else { return }
            await refresh(client: client, user: workspace.user, force: true)
        } catch {
            guard protectedDataAvailable(), !SessionStoreFailure.isProtectedDataUnavailable(error) else { return }
            if Self.denied(error) {
                var latestMarker: String?
                do { latestMarker = try client.widgetSessionMarker() }
                catch { if !protectedDataAvailable() || SessionStoreFailure.isProtectedDataUnavailable(error) { return } }
                if latestMarker == nil || latestMarker == initialMarker { invalidate() }
            }
            // Transient network or protected-data failures retain only the
            // existing snapshot, without extending its expiration.
        }
    }

    func refresh(client: PayrollClient, user: PayrollUser, agenda: AgendaData? = nil, force: Bool = false) async {
        guard !Task.isCancelled else { return }
        // A skipped refresh neither reads credentials nor publishes private
        // data. Actual refreshes and calendar publications still revalidate.
        if !force, prepared(for: client, user: user), Date().timeIntervalSince(lastRefresh) < refreshInterval {
            if let agenda, user.hasSection(.calendar) { await publishCalendar(client: client, user: user, data: agenda) }
            return
        }
        guard let currentOwner = await prepare(client: client, user: user) else { return }
        let currentGeneration = generation
        if !user.hasSection(.calendar) { await clearCalendar() }
        if !user.canReadMedia { await reloadIfChanged { await snapshots.publishPhotography(nil, owner: currentOwner) } }
        if let agenda, user.hasSection(.calendar) { await publishCalendar(client: client, user: user, data: agenda) }
        guard !Task.isCancelled, current(client, user: user, owner: currentOwner, generation: currentGeneration),
              !client.usingOfflineCopy, activeRequest == nil,
              force || Date().timeIntervalSince(lastRefresh) >= refreshInterval else { return }
        let request = UUID(); activeRequest = request
        defer { if activeRequest == request { activeRequest = nil } }
        do {
            if user.hasSection(.calendar), agenda?.month != CalendarClock.month(Date()) {
                do {
                    let feed = try await client.agenda(month: CalendarClock.month(Date()))
                    try Task.checkCancellation()
                    guard current(client, user: user, owner: currentOwner, generation: currentGeneration), !client.usingOfflineCopy else { return }
                    await publishCalendar(client: client, user: user, data: feed)
                } catch {
                    if Self.denied(error) || error is CancellationError { throw error }
                    // Calendar and Photography remain independently useful.
                }
            }
            if user.canReadMedia {
                let recent = try await client.widgetLatestPhotos()
                try Task.checkCancellation()
                guard current(client, user: user, owner: currentOwner, generation: currentGeneration), !client.usingOfflineCopy else { return }
                var photos: [JACWidgetPhoto] = [], totalBytes = 0
                for photo in recent.items.prefix(8) where photo.kind == "image" && photo.thumbnailAvailable {
                    try Task.checkCancellation()
                    guard photos.count < 4, current(client, user: user, owner: currentOwner, generation: currentGeneration) else { break }
                    guard JACWidgetRoute.validFolder(photo.parentId), photo.id.hasPrefix("r2_"),
                          let created = photo.createdAt.flatMap(CalendarClock.instant) else { continue }
                    do {
                        let image = try await client.mediaThumbnail(photo.mediaItem)
                        try Task.checkCancellation()
                        // Even a cached thumbnail must still identify a live,
                        // authorised file before another process can display it.
                        try await client.validateMediaItem(photo.mediaItem)
                        guard current(client, user: user, owner: currentOwner, generation: currentGeneration), !client.usingOfflineCopy else { return }
                        guard image.count <= JACWidgetShared.maximumImageBytes, totalBytes + image.count <= 2 * 1024 * 1024 else { continue }
                        totalBytes += image.count
                        photos.append(JACWidgetPhoto(id: photo.id, folderID: photo.parentId, createdAt: created, imageData: image))
                    } catch {
                        if Self.denied(error) || error is CancellationError { throw error }
                        // An absent or unfinished thumbnail does not request an
                        // original or invalidate other photographs.
                    }
                }
                guard current(client, user: user, owner: currentOwner, generation: currentGeneration), !Task.isCancelled else { return }
                let now = Date(), previous = await snapshots.read(now: now)
                let content: JACWidgetPhotographyContent
                if let saved = previous?.photography, saved.photos == photos,
                   now.timeIntervalSince(saved.updatedAt) < renewalInterval {
                    content = saved
                } else {
                    content = JACWidgetPhotographyContent(updatedAt: now, expiresAt: now.addingTimeInterval(JACWidgetShared.maximumLifetime), photos: photos)
                }
                guard current(client, user: user, owner: currentOwner, generation: currentGeneration) else { return }
                let changed = await snapshots.publishPhotography(content, owner: currentOwner)
                await finishWrite(changed, client: client, user: user, owner: currentOwner, generation: currentGeneration)
            }
            if current(client, user: user, owner: currentOwner, generation: currentGeneration) { lastRefresh = Date() }
        } catch {
            if Self.denied(error) {
                if owner == currentOwner { reset() }
                await reloadIfChanged { await snapshots.clear(ifOwner: currentOwner) }
            }
        }
    }

    func publishCalendar(client: PayrollClient, user: PayrollUser, data: AgendaData) async {
        let source = (data.events + data.upcoming).map(JACWidgetSourceEvent.init)
        let context = data.month + ":" + String(data.connection.revision) + ":" + (data.connection.selected?.id ?? "")
        if prepared(for: client, user: user), user.hasSection(.calendar), data.connection.connected,
           data.connection.selected != nil, lastCalendarContext == context, lastCalendarSource == source,
           Date().timeIntervalSince(lastCalendarPublish) < renewalInterval { return }
        guard let currentOwner = await prepare(client: client, user: user) else { return }
        let currentGeneration = generation
        guard user.hasSection(.calendar), data.connection.connected, data.connection.selected != nil else { await clearCalendar(); return }
        guard data.month == CalendarClock.month(Date()), !client.usingOfflineCopy,
              let updated = CalendarClock.instant(data.updatedAt),
              updated <= Date().addingTimeInterval(300), updated.addingTimeInterval(JACWidgetShared.maximumLifetime) > Date() else { return }
        let projection = Task.detached(priority: .utility) { Self.events(source, now: Date()) }
        let events = await withTaskCancellationHandler { await projection.value } onCancel: { projection.cancel() }
        guard !Task.isCancelled else { return }
        if lastCalendarEvents == events, Date().timeIntervalSince(lastCalendarPublish) < renewalInterval { return }
        let previous = await snapshots.read()
        let content: JACWidgetCalendarContent
        if let saved = previous?.calendar, saved.events == events,
           updated.timeIntervalSince(saved.updatedAt) < renewalInterval {
            content = saved
        } else {
            content = JACWidgetCalendarContent(updatedAt: updated, expiresAt: updated.addingTimeInterval(JACWidgetShared.maximumLifetime), events: events)
        }
        guard current(client, user: user, owner: currentOwner, generation: currentGeneration), !Task.isCancelled else { return }
        let changed = await snapshots.publishCalendar(content, owner: currentOwner)
        await finishWrite(changed, client: client, user: user, owner: currentOwner, generation: currentGeneration)
        if current(client, user: user, owner: currentOwner, generation: currentGeneration) {
            lastCalendarEvents = events; lastCalendarPublish = content.updatedAt
            lastCalendarSource = source; lastCalendarContext = context
        }
    }

    func clearCalendar() async {
        let previousOwner = owner
        lastCalendarEvents = nil; lastCalendarPublish = .distantPast
        lastCalendarSource = nil; lastCalendarContext = nil
        guard let previousOwner else { return }
        await reloadIfChanged { await snapshots.publishCalendar(nil, owner: previousOwner) }
    }

    func clear() async {
        let previousOwner = owner
        reset()
        await purge(previousOwner: previousOwner, generation: generation)
    }

    /// Synchronous session-invalidation hook; old asynchronous work immediately
    /// loses its generation before protected-file removal is scheduled.
    func invalidate() {
        let previousOwner = owner
        reset()
        let currentGeneration = generation
        Task { await purge(previousOwner: previousOwner, generation: currentGeneration) }
    }

    private func purge(previousOwner: String?, generation expectedGeneration: Int) async {
        guard generation == expectedGeneration else { return }
        if let previousOwner {
            await reloadIfChanged { await snapshots.clear(ifOwner: previousOwner) }
        } else {
            let saved = await snapshots.read()
            guard generation == expectedGeneration, let saved else { return }
            await reloadIfChanged { await snapshots.clear(ifOwner: saved.owner) }
        }
    }

    private func reset() {
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: Self.backgroundTaskIdentifier)
        generation += 1; owner = nil; activeRequest = nil; lastRefresh = .distantPast
        preparedClient = nil; preparedUser = nil
        lastCalendarEvents = nil; lastCalendarPublish = .distantPast
        lastCalendarSource = nil; lastCalendarContext = nil
    }
    private func prepare(client: PayrollClient, user: PayrollUser) async -> String? {
        guard protectedDataAvailable() else { return nil }
        guard let activeUser = client.accessUser else { await clear(); return nil }
        guard activeUser == user else { return nil }
        let marker: String
        do { marker = try client.widgetSessionMarker() }
        catch {
            if protectedDataAvailable(), !SessionStoreFailure.isProtectedDataUnavailable(error) { await clear() }
            return nil
        }
        let value = SHA256.hash(data: Data(marker.utf8)).map { String(format: "%02x", $0) }.joined()
        if owner != value {
            generation += 1; owner = value; activeRequest = nil; lastRefresh = .distantPast
            lastCalendarEvents = nil; lastCalendarPublish = .distantPast
            lastCalendarSource = nil; lastCalendarContext = nil
            preparedClient = nil; preparedUser = nil
            let changed = await snapshots.activate(owner: value)
            if changed { WidgetCenter.shared.reloadTimelines(ofKind: JACWidgetShared.kind) }
        } else if await snapshots.read() == nil {
            // Recover after a truncated cache or a temporarily unavailable
            // protected container without requiring a sign-out/sign-in cycle.
            guard owner == value, (try? client.widgetSessionMarker()) == marker else { return nil }
            let changed = await snapshots.activate(owner: value)
            if changed { WidgetCenter.shared.reloadTimelines(ofKind: JACWidgetShared.kind) }
        }
        guard owner == value, let latest = try? client.widgetSessionMarker(), latest == marker else { return nil }
        preparedClient = client; preparedUser = user
        return value
    }
    private func prepared(for client: PayrollClient, user: PayrollUser) -> Bool {
        owner != nil && preparedClient === client && preparedUser == user && client.accessUser == user
    }
    private func current(_ client: PayrollClient, user: PayrollUser, owner expectedOwner: String, generation expectedGeneration: Int) -> Bool {
        guard protectedDataAvailable(), owner == expectedOwner, generation == expectedGeneration, client.accessUser == user,
              let marker = try? client.widgetSessionMarker() else { return false }
        let currentOwner = SHA256.hash(data: Data(marker.utf8)).map { String(format: "%02x", $0) }.joined()
        return currentOwner == expectedOwner
    }
    private func finishWrite(_ changed: Bool, client: PayrollClient, user: PayrollUser, owner expectedOwner: String, generation expectedGeneration: Int) async {
        guard protectedDataAvailable() else { return }
        if !current(client, user: user, owner: expectedOwner, generation: expectedGeneration) {
            guard protectedDataAvailable() else { return }
            do { _ = try client.widgetSessionMarker() }
            catch { if SessionStoreFailure.isProtectedDataUnavailable(error) { return } }
            await reloadIfChanged { await snapshots.clear(ifOwner: expectedOwner) }
        } else if changed { WidgetCenter.shared.reloadTimelines(ofKind: JACWidgetShared.kind) }
    }
    private func reloadIfChanged(_ operation: () async -> Bool) async {
        if await operation() { WidgetCenter.shared.reloadTimelines(ofKind: JACWidgetShared.kind) }
    }
    private static func denied(_ error: Error) -> Bool {
        guard let value = error as? APIError else { return false }
        switch value { case .unauthorized, .forbidden: return true; default: return false }
    }
    nonisolated static func events(_ feed: AgendaData, now: Date = Date()) -> [JACWidgetEvent] {
        events((feed.events + feed.upcoming).map(JACWidgetSourceEvent.init), now: now)
    }
    nonisolated private static func events(_ source: [JACWidgetSourceEvent], now: Date) -> [JACWidgetEvent] {
        var found = Set<String>()
        var candidates: [JACWidgetEvent] = []
        for item in source {
            if Task.isCancelled { break }
            guard !found.contains(item.id),
                  let start = item.allDay ? CalendarClock.date(item.start) : CalendarClock.instant(item.start),
                  let end = item.allDay ? CalendarClock.date(item.end) : CalendarClock.instant(item.end), end >= start else { continue }
            let title = item.title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty, title.count <= 300 else { continue }
            found.insert(item.id)
            candidates.append(JACWidgetEvent(id: item.id, title: title, start: start, end: end, allDay: item.allDay))
        }
        let chronological: (JACWidgetEvent, JACWidgetEvent) -> Bool = {
            $0.start == $1.start ? $0.id < $1.id : $0.start < $1.start
        }
        // Past events must not exhaust the small snapshot before any upcoming
        // show is included. Keep the nearest active/future events first, then
        // fill the remaining budget with this month's most recent past dates.
        let upcoming = candidates.filter { $0.end > now }.sorted(by: chronological)
        let monthStart = CalendarClock.date(CalendarClock.month(now) + "-01") ?? now
        let past = candidates.filter { $0.end <= now && $0.end > monthStart }
            .sorted { $0.start == $1.start ? $0.id < $1.id : $0.start > $1.start }
        return Array((upcoming + past).prefix(64)).sorted(by: chronological)
    }
}

private struct JACWidgetSourceEvent: Sendable, Equatable {
    let id, title, start, end: String
    let allDay: Bool
    init(_ event: AgendaEvent) {
        id = event.id; title = event.title; start = event.start; end = event.end; allDay = event.allDay
    }
}
#endif
