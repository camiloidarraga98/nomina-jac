import XCTest
@testable import JACNomina

private final class MemorySession: SessionStoring {
    var token: String?
    func load() throws -> String? { token }
    func save(_ token: String) throws { self.token = token }
    func clear() throws { token = nil }
}

private final class MockProtocol: URLProtocol {
    static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            guard let handler = Self.handler else { throw URLError(.unsupportedURL) }
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}

final class PayrollClientTests: XCTestCase {
    private let base = URL(string: "https://payroll.example.invalid")!
    private let token = String(repeating: "a", count: 43)

    @MainActor private func makeClient(_ vault: MemorySession) -> PayrollClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockProtocol.self]
        return PayrollClient(baseURL: base, vault: vault, configuration: configuration)
    }
    override func tearDown() { MockProtocol.handler = nil; TemporaryDocuments.clear(); super.tearDown() }

    func testDeviceKeychainCanStoreReplaceAndRemoveSession() throws {
        let vault = KeychainSessionStore(account: "test-\(UUID().uuidString).invalid")
        defer { try? vault.clear() }
        XCTAssertNil(try vault.load())
        try vault.save(String(repeating: "a", count: 43))
        XCTAssertEqual(try vault.load(), String(repeating: "a", count: 43))
        try vault.save(String(repeating: "b", count: 43))
        XCTAssertEqual(try vault.load(), String(repeating: "b", count: 43))
        try vault.clear()
        XCTAssertNil(try vault.load())
    }

    @MainActor func testLoginUsesOriginAndStoresSessionWithoutSavingPassword() async throws {
        let vault = MemorySession()
        let client = makeClient(vault)
        MockProtocol.handler = { request in
            XCTAssertEqual(request.url?.path, "/api/auth")
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Origin"), self.base.absoluteString)
            XCTAssertNil(request.value(forHTTPHeaderField: "Cookie"))
            XCTAssertFalse(request.httpShouldHandleCookies)
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Set-Cookie": "__Host-jac_session=\(self.token); Path=/; HttpOnly; Secure; SameSite=Lax; Max-Age=43200"])!, Data("{\"ok\":true}".utf8))
        }
        try await client.login(username: "camilo", password: "1")
        XCTAssertEqual(vault.token, token)
    }

    @MainActor func testExpiredSessionIsRemoved() async throws {
        let vault = MemorySession(); vault.token = token
        let client = makeClient(vault)
        MockProtocol.handler = { request in
            XCTAssertEqual(request.value(forHTTPHeaderField: "Cookie"), "__Host-jac_session=\(self.token)")
            return (HTTPURLResponse(url: request.url!, statusCode: 401, httpVersion: nil, headerFields: nil)!, Data("{}".utf8))
        }
        do { _ = try await client.overview(); XCTFail("Debe rechazar la sesión vencida") }
        catch { guard let apiError = error as? APIError, case .unauthorized = apiError else { return XCTFail("Error de sesión esperado") } }
        XCTAssertNil(vault.token)
    }

    @MainActor func testPermissionDenialPreservesSessionAndDoesNotWriteDocument() async throws {
        let vault = MemorySession(); vault.token = token
        let client = makeClient(vault)
        MockProtocol.handler = { request in
            XCTAssertEqual(request.url?.path, "/api/payroll/export")
            return (HTTPURLResponse(url: request.url!, statusCode: 403, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!, Data("{\"error\":\"Sin permiso de exportación\"}".utf8))
        }
        do { _ = try await client.download(periodID: "private-period", format: .pdf); XCTFail("Debe rechazar la descarga") }
        catch { XCTAssertEqual(error.localizedDescription, "Sin permiso de exportación") }
        XCTAssertEqual(vault.token, token)
        XCTAssertFalse(FileManager.default.fileExists(atPath: TemporaryDocuments.root.path))
    }

    @MainActor func testRedirectIsRejectedWithoutFollowingDestination() async throws {
        let vault = MemorySession(); vault.token = token
        let client = makeClient(vault)
        var requests = 0
        MockProtocol.handler = { request in
            requests += 1
            XCTAssertEqual(request.url?.host, "payroll.example.invalid")
            return (HTTPURLResponse(url: request.url!, statusCode: 302, httpVersion: nil, headerFields: ["Location": "https://other.example.invalid"])!, Data())
        }
        do { _ = try await client.overview(); XCTFail("Debe rechazar la redirección") }
        catch { guard let apiError = error as? APIError, case .unauthorized = apiError else { return XCTFail("Error de sesión esperado") } }
        XCTAssertEqual(requests, 1)
        XCTAssertNil(vault.token)
    }

    func testServerAmountsAndEmptyPeriodsDecodeWithoutLocalCalculation() throws {
        let empty = Data(#"{"version":8,"company":"Empresa de prueba","user":{"id":"u","username":"demo","email":"demo@example.invalid","displayName":"Prueba","isOwner":false,"permissions":[]},"periods":[],"employees":[]}"#.utf8)
        let overview = try JSONDecoder().decode(PayrollOverview.self, from: empty)
        XCTAssertTrue(overview.periods.isEmpty)
        XCTAssertFalse(overview.user.can("export"))
        let row = Data(#"{"employeeId":"e","name":"Persona de prueba","document":"","role":"Prueba","category":"tecnica","gross":750000,"reimbursements":18000,"deductions":71250.25,"net":696749.75,"items":[]}"#.utf8)
        let payment = try JSONDecoder().decode(PayrollPayment.self, from: row)
        XCTAssertEqual(payment.net, 696749.75)
        XCTAssertEqual(payment.deductions, 71250.25)
    }

    func testLegacyAndSharedRoutesDecodeTogether() throws {
        let fixture = Data(#"[{"id":"legacy","date":"2026-10-01","name":"Prueba","km":10,"employeeId":"a","rate":1000},{"id":"shared","date":"2026-10-01","name":"Prueba","km":10,"showId":"show","drivers":[{"employeeId":"a","rate":1000},{"employeeId":"b","rate":1250}]}]"#.utf8)
        let routes = try JSONDecoder().decode([PayrollRoute].self, from: fixture)
        XCTAssertEqual(routes[0].participants.count, 1)
        XCTAssertEqual(routes[1].participants.count, 2)
    }
}
