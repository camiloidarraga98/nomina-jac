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

    func testActivationLinksAreRestrictedToOurDomainAndAValidOneUseToken() {
        let token = String(repeating: "n", count: 43)
        XCTAssertEqual(ActivationInput.token(token), token)
        XCTAssertEqual(ActivationInput.token("https://jhonalexcastano.com/acceso#activacion=" + token), token)
        XCTAssertNil(ActivationInput.token("https://other.example.invalid/acceso#activacion=" + token))
        XCTAssertNil(ActivationInput.token("https://jhonalexcastano.com/acceso?token=" + token))
        XCTAssertNil(ActivationInput.token("https://jhonalexcastano.com/acceso#activacion=incorrecto"))
    }

    @MainActor func testGmailCallbackRequiresMatchingNonceAndExpectedDestination() throws {
        let nonce = String(repeating: "n", count: 43)
        XCTAssertNoThrow(try GmailAuthorizer.validate(URL(string: "jacnomina://gmail?result=connected&nonce=" + nonce), nonce: nonce))
        XCTAssertThrowsError(try GmailAuthorizer.validate(URL(string: "jacnomina://gmail?result=connected&nonce=" + String(repeating: "x", count: 43)), nonce: nonce))
        XCTAssertThrowsError(try GmailAuthorizer.validate(URL(string: "other://gmail?result=connected&nonce=" + nonce), nonce: nonce))
        XCTAssertThrowsError(try GmailAuthorizer.validate(URL(string: "jacnomina://other?result=connected&nonce=" + nonce), nonce: nonce))
        XCTAssertThrowsError(try GmailAuthorizer.validate(URL(string: "jacnomina://gmail?result=connected&nonce=" + nonce + "&nonce=" + nonce), nonce: nonce))
        XCTAssertThrowsError(try GmailAuthorizer.validate(URL(string: "jacnomina://gmail?result=error&nonce=" + nonce), nonce: nonce))
    }

    func testJSONEditsPreserveFieldsAndNeverContainWholeHistoricalPeriods() throws {
        let raw = try JSONDecoder().decode(JSONValue.self, from: Data(#"{"id":"employee","withholding":0.095,"unknownFutureField":{"keep":true},"amount":696749.75}"#.utf8))
        var record = raw; record["amount"] = .number(1.25)
        let edit = PayrollEdit(kind: "employee", record: record).value
        let roundtrip = try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(edit))
        XCTAssertEqual(roundtrip["record"]["unknownFutureField"], raw["unknownFutureField"])
        XCTAssertEqual(roundtrip["record"]["withholding"].number, 0.095)
        XCTAssertEqual(roundtrip["record"]["amount"].number, 1.25)
        XCTAssertNil(roundtrip.fields["data"])
        XCTAssertNil(roundtrip.fields["periods"])
    }

    @MainActor func testConflictKeepsDraftAndRevisionUntilExplicitRetryOrDiscard() async throws {
        let store = PayrollStore(client: UITestBackend.client(conflict: true))
        await store.restore()
        let workspace = try XCTUnwrap(store.workspace)
        var employee = try XCTUnwrap(workspace.record("employees", id: "music")); employee["showRate"] = .number(700000)
        let session = PayrollEditorSession(kind: .employee, workspace: workspace, detail: nil, record: employee)
        let command = session.command(employee)
        let saved = await store.submit(command, label: "Personal", editorID: session.id)
        XCTAssertFalse(saved)
        XCTAssertEqual(store.pending?.command, command)
        XCTAssertEqual(store.pending?.baseline, workspace.data)
        XCTAssertEqual(store.workspace?.version, workspace.version)
        XCTAssertTrue(try store.client.hasSession(), "Un conflicto no borra la sesión")
        do { try await store.refresh(); XCTFail("No debe borrar el borrador al actualizar") } catch { }
        let backup = try store.backupPending(); defer { TemporaryDocuments.remove(backup) }
        let bytes = try JSONDecoder().decode(JSONValue.self, from: Data(contentsOf: backup.url))
        XCTAssertEqual(bytes["request"], command)
        await store.retryPending()
        XCTAssertNil(store.pending)
        XCTAssertEqual(store.workspace?.record("employees", id: "music")?["showRate"].number, 700000)
        XCTAssertEqual(store.workspace?.version, workspace.version + 1)
    }

    @MainActor func testNativeWorkspaceAndActionsUseTheSameVersionedServerContract() async throws {
        let client = UITestBackend.client()
        var workspace = try await client.workspace()
        let p = try XCTUnwrap(workspace.periods.first)
        let detail = try await client.detail(periodID: p.id)
        var movement = PayrollEditorSession.newRecord(.movement, workspace: workspace, detail: detail)
        movement["concept"] = .string("Novedad desde iPhone")
        let editor = PayrollEditorSession(kind: .movement, workspace: workspace, detail: detail, record: movement)
        let preview = try await client.preview(editor.command(movement))
        XCTAssertEqual(preview.version, workspace.version)
        let afterPreview = try await client.workspace(); XCTAssertEqual(afterPreview.version, workspace.version)
        let saved = try await client.payroll(editor.command(movement))
        workspace = try PayrollWorkspace(envelope: saved, user: workspace.user)
        XCTAssertEqual(workspace.version, detail.version + 1)
        let changed = try await client.detail(periodID: p.id)
        XCTAssertEqual(changed.period.movements.first?.concept, "Novedad desde iPhone")
        let closed = try await client.payroll(.object(["action": .string("close"), "version": .number(Double(workspace.version)), "periodId": .string(p.id)]))
        XCTAssertEqual(closed.data["periods"].elements.first?["status"].text, "cerrada")
        let reopened = try await client.payroll(.object(["action": .string("reopen"), "version": .number(Double(closed.version)), "periodId": .string(p.id)]))
        XCTAssertEqual(reopened.data["periods"].elements.first?["revisions"].elements.count, 1)
    }

    @MainActor func testOldResponseCannotClearANewerLogin() async throws {
        let vault = MemorySession(); vault.token = token
        let client = makeClient(vault)
        let replacement = String(repeating: "b", count: 43)
        MockProtocol.handler = { request in
            vault.token = replacement
            return (HTTPURLResponse(url: request.url!, statusCode: 401, httpVersion: nil, headerFields: nil)!, Data("{}".utf8))
        }
        do { _ = try await client.overview(); XCTFail("Debe descartar la respuesta antigua") }
        catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertEqual(vault.token, replacement)
    }

    @MainActor func testLateRefreshCannotReplaceTheNewerPayrollRevision() async throws {
        let vault = MemorySession(); vault.token = token
        let store = PayrollStore(client: makeClient(vault))
        var replies = 0
        MockProtocol.handler = { request in
            replies += 1
            let version = replies == 1 ? 8 : 7
            let company = replies == 1 ? "Vigente" : "Anterior"
            let payload = JSONValue.object([
                "version": .number(Double(version)),
                "company": .string(company), "periods": .array([]), "employees": .array([]),
                "user": .object(["id": .string("fixture"), "username": .string("prueba"), "email": .string("test@example.invalid"), "displayName": .string("Prueba"), "isOwner": .bool(true), "permissions": .array([])]),
                "data": .object(["employees": .array([]), "periods": .array([]), "concepts": .array([]), "settings": .object(["company": .string(company)])])
            ])
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, try JSONEncoder().encode(payload))
        }
        try await store.refresh(); try await store.refresh()
        XCTAssertEqual(store.workspace?.version, 8)
        XCTAssertEqual(store.overview?.company, "Vigente")
    }

    @MainActor func testSupersededSessionCannotRestoreAPendingPayrollChange() async throws {
        let vault = MemorySession(); vault.token = token
        let store = PayrollStore(client: makeClient(vault))
        let payload = Data(#"{"version":8,"company":"Prueba","periods":[],"employees":[],"user":{"id":"fixture","username":"prueba","email":"test@example.invalid","displayName":"Prueba","isOwner":true,"permissions":[]},"data":{"employees":[],"periods":[],"concepts":[],"settings":{"company":"Prueba"}}}"#.utf8)
        MockProtocol.handler = { request in
            if request.httpMethod == "POST" {
                vault.token = String(repeating: "b", count: 43)
                return (HTTPURLResponse(url: request.url!, statusCode: 401, httpVersion: nil, headerFields: nil)!, Data("{}".utf8))
            }
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, payload)
        }
        try await store.refresh()
        let saved = await store.submit(.object(["action": .string("edit"), "version": .number(8), "edit": .object(["kind": .string("settings"), "record": .object(["company": .string("No guardado")])])]), label: "Formulario anterior")
        XCTAssertFalse(saved)
        XCTAssertNil(store.pending, "Una respuesta de otra sesión no debe recuperar el formulario ni su base privada")
        XCTAssertEqual(vault.token, String(repeating: "b", count: 43))
    }
}
