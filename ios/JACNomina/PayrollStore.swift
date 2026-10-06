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
    let client: PayrollClient

    init(client: PayrollClient? = nil) { self.client = client ?? PayrollClient() }
    func restore() async {
        defer { restoring = false }
        TemporaryDocuments.clear()
        do { if try client.hasSession() { try await refresh() } }
        catch { report(error) }
    }
    func signIn(username: String, password: String) async {
        guard !username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !password.isEmpty else {
            error = "Ingresa tu usuario o correo y tu contraseña."
            return
        }
        busy = true; error = nil
        defer { busy = false }
        do { try await client.login(username: username, password: password); try await refresh() }
        catch { report(error) }
    }
    func refresh() async throws {
        guard pending == nil else { throw APIError.message("Conserva o descarta tus cambios pendientes antes de actualizar.") }
        do { let result = try await client.workspace(); workspace = result; overview = result.overview; error = nil }
        catch { report(error); throw error }
    }
    func signOut() async {
        busy = true
        defer { busy = false }
        do { try await client.logout() }
        catch { report(error) }
        overview = nil
        workspace = nil; pending = nil; notice = nil
    }
    func report(_ failure: Error) {
        if failure is CancellationError { return }
        if let apiError = failure as? APIError, case .unauthorized = apiError { overview = nil; workspace = nil; pending = nil; notice = nil; TemporaryDocuments.clear() }
        error = failure.localizedDescription
    }

    var hasPending: Bool { pending != nil }
    var canWrite: Bool { !busy && !hasPending }
    func submit(_ command: JSONValue, label: String, editorID: UUID? = nil) async -> Bool {
        guard !busy, let workspace else { return false }
        if let pending, pending.command != command && (editorID == nil || pending.editorID != editorID) {
            error = "Resuelve primero los cambios pendientes de \(pending.label)."; return false
        }
        busy = true; error = nil; notice = nil
        defer { busy = false }
        do {
            let result = try await client.payroll(command)
            let updated = try PayrollWorkspace(envelope: result, user: workspace.user)
            self.workspace = updated; overview = updated.overview; pending = nil
            notice = result.mailNotice ?? "Cambios guardados."
            return true
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
        do { try await refresh() } catch { report(error) }
    }
    func backupPending() throws -> ExportedDocument {
        guard let pending else { throw APIError.message("No hay cambios pendientes.") }
        let data = try JSONEncoder().encode(JSONValue.object(["version": pending.command["version"], "request": pending.command, "base": pending.baseline]))
        return try TemporaryDocuments.save(data, filename: "cambios-pendientes.json")
    }
    func activate(token: String, password: String) async -> Bool {
        guard !busy else { return false }; busy = true; error = nil
        defer { busy = false }
        do { try await client.activate(token: token, password: password); try await refresh(); return true }
        catch { report(error); return false }
    }
}

struct PendingPayrollChange {
    let command: JSONValue
    let baseline: JSONValue
    let label: String
    let editorID: UUID?
}
