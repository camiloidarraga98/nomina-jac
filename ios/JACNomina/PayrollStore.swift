import Foundation
import Combine

@MainActor
final class PayrollStore: ObservableObject {
    @Published private(set) var overview: PayrollOverview?
    @Published private(set) var workspace: PayrollWorkspace?
    @Published private(set) var restoring = true
    @Published private(set) var busy = false
    @Published var error: String?
    @Published private(set) var notice: String?
    @Published private(set) var pending: PendingPayrollChange?
    @Published private(set) var savedAgenda: AgendaOfflineRecord?
    @Published private(set) var agendaStorageWarning: String?
    private var savedAgendaScope: String?
    @Published private(set) var hasSavedSession = false
    private var clientChanges: AnyCancellable?
    private var offlineChanges: AnyCancellable?
    @Published private(set) var offlineMode = false
    private var automaticallyRefreshing = false
    var isOffline: Bool { offlineMode || isAgendaOnly }
    var cacheRevision: Int { client.cacheRevision }
    let client: PayrollClient

    init(client: PayrollClient? = nil) {
        let client = client ?? PayrollClient(); self.client = client
        hasSavedSession = (try? client.hasSession()) == true
        if hasSavedSession { restoring = false }
        if let cached = client.cachedWorkspace() {
            workspace = cached; overview = cached.overview
            client.beginOfflineRestore(); restoring = false
        }
        client.onSessionInvalidated = { [weak self] in
            guard let self else { return }
            self.forgetAgenda(); self.overview = nil; self.workspace = nil; self.pending = nil; self.notice = nil; self.hasSavedSession = false
        }
        offlineChanges = client.$usingOfflineCopy.removeDuplicates().sink { [weak self] value in self?.offlineMode = value }
        clientChanges = client.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }
        if let record = client.cachedAgenda(), overview == nil || overview?.user.id == record.user.id {
            savedAgenda = record; savedAgendaScope = (try? client.agendaScope())?.id
            // Older installations may have only the calendar cache. Keep that
            // fallback while the new complete copy downloads for the first time.
            if overview == nil { overview = PayrollOverview(version: 0, company: "JAC", user: record.user, periods: [], employees: []) }
            restoring = false
        }
    }
    var isAgendaOnly: Bool { overview != nil && workspace == nil }
    func cachedAgenda(month: String, userID: String) -> SavedAgenda? {
        guard overview?.user.hasSection(.calendar) != false, savedAgenda?.user.id == userID, savedAgendaScope == (try? client.agendaScope())?.id else { return nil }
        return savedAgenda?.month(month)
    }
    var preferredAgendaMonth: String {
        let current = CalendarClock.month(Date())
        return savedAgenda?.month(current) != nil ? current : savedAgenda?.latest?.data.month ?? current
    }
    func forgetAgenda() {
        client.clearCachedAgenda(); savedAgenda = nil; savedAgendaScope = nil; agendaStorageWarning = nil
    }
    func rememberAgenda(_ data: AgendaData, userID: String, scope: AgendaCacheScope) throws {
        guard let user = overview?.user, user.id == userID, scope.id == (try client.agendaScope())?.id else { throw CancellationError() }
        guard data.connection.connected, data.connection.selected != nil else { forgetAgenda(); return }
        var months = savedAgenda?.user.id == userID && savedAgendaScope == scope.id ? savedAgenda?.months ?? [] : []
        if let previous = savedAgenda?.latest?.data.connection, !months.isEmpty {
            guard data.connection.revision >= previous.revision else { throw CancellationError() }
            if data.connection.revision != previous.revision || data.connection.selected?.id != previous.selected?.id { months = []; client.clearCachedAgenda() }
        }
        if let previous = months.first(where: { $0.data.month == data.month }),
           let old = CalendarClock.instant(previous.data.updatedAt), let new = CalendarClock.instant(data.updatedAt), new < old { throw CancellationError() }
        months.removeAll { $0.data.month == data.month }
        months.insert(SavedAgenda(data: data, receivedAt: Date()), at: 0)
        var record = AgendaOfflineRecord(schema: 1, user: user, months: Array(months.prefix(6)))
        while record.months.count > 1 {
            guard try JSONEncoder().encode(record).count > AgendaOfflineCache.maximumBytes else { break }
            record.months.removeLast()
        }
        savedAgenda = record; savedAgendaScope = scope.id
        do { try client.saveAgenda(record, scope: scope); agendaStorageWarning = nil }
        catch { agendaStorageWarning = "Puedes consultar esta agenda, pero no se pudo guardar su copia para la próxima apertura." }
    }
    func restore() async {
        defer { restoring = false }
        TemporaryDocuments.clear()
        do { if try client.hasSession() { try await refreshAutomatically() } }
        catch { if !AgendaOfflineCache.isUnavailable(error) { reportReadFailure(error) } }
    }
    func signIn(username: String, password: String, keepSignedIn: Bool = false) async {
        guard !username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !password.isEmpty else {
            error = "Ingresa tu usuario o correo y tu contraseña."
            return
        }
        busy = true; error = nil
        defer { busy = false }
        do { try await client.login(username: username, password: password, keepSignedIn: keepSignedIn); hasSavedSession = true; try await refresh() }
        catch { report(error) }
    }
    func refreshAutomatically() async throws {
        guard !automaticallyRefreshing else { return }
        automaticallyRefreshing = true; defer { automaticallyRefreshing = false }
        try await refresh()
    }
    func refresh() async throws {
        guard pending == nil else { throw APIError.message("Conserva o descarta tus cambios pendientes antes de actualizar.") }
        do {
            let result = try await client.workspace(forceNetwork: true)
            // A refresh already in flight can finish after a save or conflict.
            guard pending == nil else { return }
            if install(result) { error = nil; client.synchronizeOfflineContent(result) }
        }
        catch {
            if !AgendaOfflineCache.isUnavailable(error) { reportReadFailure(error) }
            throw error
        }
    }
    @discardableResult private func install(_ result: PayrollWorkspace) -> Bool {
        // A restricted control workspace deliberately uses revision zero and
        // contains no payroll. Revoking that module must replace older private
        // in-memory data immediately; ordinary payroll still obeys revision CAS.
        let payrollRevoked = workspace?.user.hasSection(.payroll) == true && !result.user.hasSection(.payroll)
        guard payrollRevoked || result.version >= (workspace?.version ?? 0) else { return false }
        if let savedAgenda, savedAgenda.user != result.user || !result.user.hasSection(.calendar) { forgetAgenda() }
        workspace = result; overview = result.overview; hasSavedSession = true; client.rememberWorkspace(result); return true
    }
    func signOut() async {
        JACNotifications.shared.stop()
        forgetAgenda()
        busy = true
        defer { busy = false }
        do { try await client.logout() }
        catch { report(error) }
        overview = nil
        workspace = nil; pending = nil; notice = nil; hasSavedSession = false
    }
    func report(_ failure: Error) {
        if failure is CancellationError { return }
        if let apiError = failure as? APIError, case .unauthorized = apiError { forgetAgenda(); overview = nil; workspace = nil; pending = nil; notice = nil; TemporaryDocuments.clear() }
        if let apiError = failure as? APIError, case .forbidden = apiError, isAgendaOnly { forgetAgenda(); overview = nil }
        error = failure.localizedDescription
    }

    @discardableResult func reportReadFailure(_ failure: Error) -> String? {
        // SwiftUI cancels view-bound reads when navigating away. URLSession
        // can report this as NSURLErrorCancelled instead of CancellationError.
        // Keep this policy separate from writes: a cancelled save may have
        // reached the server and must retain its draft and retry controls.
        let networkError = failure as NSError
        if failure is CancellationError ||
            (networkError.domain == NSURLErrorDomain && networkError.code == NSURLErrorCancelled) { return nil }
        report(failure)
        return failure.localizedDescription
    }

    var hasPending: Bool { pending != nil }
    var canWrite: Bool { workspace != nil && !isOffline && !busy && !hasPending }
    func submit(_ command: JSONValue, label: String, editorID: UUID? = nil) async -> Bool {
        guard !busy, !isOffline, let workspace else { return false }
        if let pending, pending.command != command && (editorID == nil || pending.editorID != editorID) {
            error = "Resuelve primero los cambios pendientes de \(pending.label)."; return false
        }
        busy = true; error = nil; notice = nil
        defer { busy = false }
        do {
            let result = try await client.payroll(command)
            let updated = try PayrollWorkspace(envelope: result, user: workspace.user)
            install(updated); pending = nil
            notice = result.mailNotice ?? "Cambios guardados."
            return true
        } catch is CancellationError {
            // Authentication changed while the request was pending. Never
            // revive the previous account's form or baseline in a new session.
            return false
        } catch {
            let keepsDraft = ["edit", "remove"].contains(command["action"].text)
            if keepsDraft { pending = PendingPayrollChange(command: command, baseline: workspace.data, label: label, editorID: editorID) }
            report(error)
            return false
        }
    }
    func action(_ action: String, periodID: String? = nil, employeeID: String? = nil, version: Int? = nil) async -> Bool {
        guard canWrite, let workspace else { return false }
        var body: [String: JSONValue] = ["action": .string(action), "version": .number(Double(version ?? workspace.version))]
        if let periodID { body["periodId"] = .string(periodID); if action == "deletePeriod" { body["confirmation"] = .string(periodID) } }
        if let employeeID { body["employeeId"] = .string(employeeID) }
        return await submit(.object(body), label: "la operación seleccionada")
    }
    func remove(kind: String, id: String, detail: PeriodDetail) async -> Bool {
        guard canWrite else { return false }
        return await submit(.object(["action": .string("remove"), "version": .number(Double(detail.version)), "edit": PayrollEdit(kind: kind, periodId: detail.period.id, id: id).value]), label: "eliminar el registro")
    }
    func retryPending() async { if let pending { _ = await submit(pending.command, label: pending.label, editorID: pending.editorID) } }
    func discardAndRefresh() async {
        guard !busy else { return }
        pending = nil
        do { try await refresh() } catch { reportReadFailure(error) }
    }
    func backupPending() throws -> ExportedDocument {
        guard let pending else { throw APIError.message("No hay cambios pendientes.") }
        let data = try JSONEncoder().encode(JSONValue.object(["version": pending.command["version"], "request": pending.command, "base": pending.baseline]))
        return try TemporaryDocuments.save(data, filename: "cambios-pendientes.json")
    }
    func activate(token: String, password: String) async -> Bool {
        guard !busy else { return false }; busy = true; error = nil
        defer { busy = false }
        do { try await client.activate(token: token, password: password); hasSavedSession = true; try await refresh(); return true }
        catch { report(error); return false }
    }
}

struct PendingPayrollChange {
    let command: JSONValue
    let baseline: JSONValue
    let label: String
    let editorID: UUID?
}
