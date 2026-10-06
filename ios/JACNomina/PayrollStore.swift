import Foundation
import Combine

@MainActor
final class PayrollStore: ObservableObject {
    @Published private(set) var overview: PayrollOverview?
    @Published private(set) var restoring = true
    @Published private(set) var busy = false
    @Published var error: String?
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
        do { overview = try await client.overview(); error = nil }
        catch { report(error); throw error }
    }
    func signOut() async {
        busy = true
        defer { busy = false }
        do { try await client.logout() }
        catch { report(error) }
        overview = nil
    }
    func report(_ failure: Error) {
        if let apiError = failure as? APIError, case .unauthorized = apiError { overview = nil }
        error = failure.localizedDescription
    }
}
