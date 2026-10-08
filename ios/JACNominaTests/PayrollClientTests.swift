import XCTest
import UserNotifications
@testable import JACNomina

@MainActor
private final class FakeNotificationPermission: NotificationPermissionProviding {
    var value: UNAuthorizationStatus = .notDetermined
    var granted = true
    var requests = 0
    func status() async -> UNAuthorizationStatus { value }
    func request() async throws -> Bool { requests += 1; value = granted ? .authorized : .denied; return granted }
}
private final class MemorySession: SessionStoring {
    var token: String?
    func load() throws -> String? { token }
    func save(_ token: String) throws { self.token = token }
    func clear() throws { token = nil }
}

private final class MockProtocol: URLProtocol {
    static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?
    static func requestBody(_ request: URLRequest) throws -> Data {
        if let data = request.httpBody { return data }
        guard let stream = request.httpBodyStream else { throw URLError(.badServerResponse) }
        stream.open(); defer { stream.close() }
        var data = Data(), buffer = [UInt8](repeating: 0, count: 4096)
        while true { let count = stream.read(&buffer, maxLength: buffer.count); if count < 0 { throw stream.streamError ?? URLError(.cannotDecodeRawData) }; if count == 0 { break }; data.append(contentsOf: buffer.prefix(count)) }
        return data
    }
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

    @MainActor private func makeClient(_ vault: MemorySession, cache: AgendaOfflineCache? = nil) -> PayrollClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockProtocol.self]
        return PayrollClient(baseURL: base, vault: vault, configuration: configuration, agendaCache: cache ?? AgendaOfflineCache(root: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)))
    }
    override func tearDown() { MockProtocol.handler = nil; TemporaryDocuments.clear(); super.tearDown() }

    @MainActor func testNotificationPermissionIsRequestedAfterSessionAndDenialIsRespected() async throws {
        let suite = "push-test-" + UUID().uuidString, defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let vault = MemorySession(), client = makeClient(vault), permission = FakeNotificationPermission()
        var remoteRequests = 0
        let hub = JACNotifications(defaults: defaults, permission: permission, allowsFixture: true, registerRemote: { remoteRequests += 1 }, unregisterRemote: {})
        await hub.bind(client); XCTAssertEqual(permission.requests, 0, "Sin sesión no se debe solicitar autorización.")
        vault.token = token; permission.granted = false
        await hub.bind(client); await hub.bind(client)
        XCTAssertEqual(permission.requests, 1); XCTAssertEqual(remoteRequests, 0); XCTAssertNotNil(hub.message)
        permission.value = .authorized
        await hub.bind(client); XCTAssertEqual(remoteRequests, 1); XCTAssertEqual(permission.requests, 1)
        hub.stop()
    }

    @MainActor func testNotificationsDisablePersistsAndLateTokenCannotRegisterUntilExplicitEnable() async throws {
        let suite = "push-test-" + UUID().uuidString, defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let vault = MemorySession(); vault.token = token
        let client = makeClient(vault), permission = FakeNotificationPermission()
        var commands: [String] = [], remoteRequests = 0
        MockProtocol.handler = { request in
            let body = try JSONDecoder().decode(JSONValue.self, from: MockProtocol.requestBody(request)); commands.append(body["action"].text)
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, Data("{\"ok\":true}".utf8))
        }
        let hub = JACNotifications(defaults: defaults, permission: permission, allowsFixture: true, registerRemote: { remoteRequests += 1 }, unregisterRemote: {})
        await hub.bind(client); XCTAssertEqual(permission.requests, 1); XCTAssertEqual(remoteRequests, 1)
        await hub.register(String(repeating: "ab", count: 32)); await hub.disable(client)
        await hub.register(String(repeating: "cd", count: 32)); await hub.bind(client)
        XCTAssertFalse(hub.enabled); XCTAssertEqual(commands, ["register", "unregister"]); XCTAssertEqual(remoteRequests, 1)
        let reopened = JACNotifications(defaults: defaults, permission: permission, allowsFixture: true, registerRemote: { remoteRequests += 1 }, unregisterRemote: {})
        await reopened.bind(client); XCTAssertEqual(remoteRequests, 1); XCTAssertFalse(reopened.enabled)
        await reopened.enable(client); XCTAssertTrue(reopened.enabled); XCTAssertEqual(remoteRequests, 2); XCTAssertEqual(permission.requests, 1)
        reopened.stop(); hub.stop()
    }

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

    @MainActor func testAgendaUsesAuthenticatedSharedAPIAndRestrictedOwnerListing() async throws {
        let client = UITestBackend.client()
        let data = try await client.agenda(month: CalendarClock.month(Date()))
        XCTAssertEqual(data.timeZone, "America/Bogota")
        XCTAssertEqual(data.days.count, 42)
        XCTAssertEqual(data.events.first?.title, "Concierto simulado")
        let calendars = try await client.agendaCalendars()
        XCTAssertEqual(calendars.first?.id, "fixture-calendar")
        let reader = UITestBackend.client(reader: true)
        let readable = try await reader.agenda(month: CalendarClock.month(Date()))
        XCTAssertEqual(readable.connection.selected?.id, "fixture-calendar")
        do { _ = try await reader.agendaCalendars(); XCTFail("El lector no debe configurar Agenda") } catch { XCTAssertEqual(error.localizedDescription, "Solo Camilo puede elegir el calendario.") }
    }

    @MainActor func testAgendaCreatesAndUpdatesWithRevisionETagAndAuthorizedSessions() async throws {
        let client = UITestBackend.client(), feed = try await client.agenda(month: CalendarClock.month(Date()))
        XCTAssertEqual(feed.canEditEvents, true)
        let draft = AgendaEventDraft(title: "Evento de prueba", start: "2026-10-20T00:00:00.000Z", end: "2026-10-20T02:00:00.000Z", allDay: false, location: "Lugar", description: "Solo simulado")
        let result = try await client.saveAgendaEvent(draft, revision: feed.connection.revision, event: nil, requestID: UUID())
        XCTAssertEqual(result.event.title, draft.title); XCTAssertEqual(result.event.start, draft.start); XCTAssertNotNil(result.event.etag)
        _ = try await client.saveAgendaEvent(draft, revision: feed.connection.revision, event: result.event, requestID: UUID())
        do { _ = try await client.saveAgendaEvent(draft, revision: feed.connection.revision, event: result.event, requestID: UUID()); XCTFail("No debe sobrescribir un ETag obsoleto") } catch { XCTAssertEqual(error.localizedDescription, "Otra persona modificó este evento.") }
        let reader = UITestBackend.client(reader: true)
        let readable = try await reader.agenda(month: CalendarClock.month(Date())); XCTAssertEqual(readable.canEditEvents, true)
        let colleagueEvent = try await reader.saveAgendaEvent(draft, revision: 1, event: nil, requestID: UUID()); XCTAssertEqual(colleagueEvent.event.title, draft.title)
    }

    func testCalendarDaysRespectColombiaMidnightAndExclusiveAllDayEnd() {
        let concert = AgendaEvent(id: "concert", title: "Prueba", start: "2026-10-07T04:30:00.000Z", end: "2026-10-07T05:00:00.000Z", allDay: false, location: "", description: "", url: "https://calendar.google.com/calendar/event?eid=simulado")
        let trip = AgendaEvent(id: "trip", title: "Viaje", start: "2026-10-06", end: "2026-10-08", allDay: true, location: "", description: "", url: "javascript:alert(1)")
        XCTAssertEqual(concert.firstDay, "2026-10-06")
        XCTAssertTrue(concert.occurs(on: "2026-10-06")); XCTAssertFalse(concert.occurs(on: "2026-10-07"))
        XCTAssertTrue(trip.occurs(on: "2026-10-07")); XCTAssertFalse(trip.occurs(on: "2026-10-08"))
        let buckets = CalendarClock.eventsByDay([concert, trip], days: ["2026-10-06", "2026-10-07", "2026-10-08"])
        XCTAssertEqual(buckets["2026-10-06"]?.count, 2); XCTAssertEqual(buckets["2026-10-07"]?.count, 1); XCTAssertNil(buckets["2026-10-08"])
        XCTAssertNotNil(concert.googleURL); XCTAssertNil(trip.googleURL)
        XCTAssertEqual(CalendarClock.shift("2026-12", by: 1), "2027-01")
    }

    @MainActor func testCalendarAuthorizationRejectsMismatchedOrGmailCallbacks() throws {
        let nonce = String(repeating: "n", count: 43)
        XCTAssertNoThrow(try CalendarAuthorizer.validate(URL(string: "jacnomina://calendar?result=connected&nonce=" + nonce), nonce: nonce))
        for value in ["jacnomina://gmail?result=connected&nonce=" + nonce, "other://calendar?result=connected&nonce=" + nonce, "jacnomina://calendar?result=connected&nonce=" + String(repeating: "x", count: 43), "jacnomina://calendar?result=connected&nonce=" + nonce + "&nonce=" + nonce, "jacnomina://calendar?result=error&nonce=" + nonce] {
            XCTAssertThrowsError(try CalendarAuthorizer.validate(URL(string: value), nonce: nonce))
        }
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

    @MainActor func testAgendaDiskCacheIsEncryptedSessionBoundAndRejectsCorruption() async throws {
        let client = UITestBackend.client(), feed = try await client.agenda(month: CalendarClock.month(Date())), user = try await client.workspace().user
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let cache = AgendaOfflineCache(root: root), scope = AgendaCacheScope(origin: base.absoluteString, token: token)
        let record = AgendaOfflineRecord(schema: 1, user: user, months: [SavedAgenda(data: feed, receivedAt: Date())])
        try cache.save(record, scope: scope)
        XCTAssertEqual(cache.load(scope)?.latest?.data.events.first?.title, "Concierto simulado")
        let bytes = try Data(contentsOf: cache.file(scope))
        XCTAssertNil(bytes.range(of: Data("Concierto simulado".utf8))); XCTAssertNil(bytes.range(of: Data(token.utf8)))
        XCTAssertEqual(try root.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup, true)
        let otherSession = AgendaCacheScope(origin: base.absoluteString, token: String(repeating: "b", count: 43))
        try bytes.write(to: cache.file(otherSession))
        XCTAssertNil(cache.load(otherSession), "Ni copiando el archivo puede abrirse con otra sesión")
        let otherSite = AgendaCacheScope(origin: "https://another.example.invalid", token: token)
        try bytes.write(to: cache.file(otherSite)); XCTAssertNil(cache.load(otherSite))
        var corrupt = bytes; corrupt[corrupt.count / 2] ^= 1; try corrupt.write(to: cache.file(scope))
        XCTAssertNil(cache.load(scope), "Un archivo alterado nunca debe restaurar eventos ni identidad")
    }

    @MainActor func testAgendaRestoresImmediatelyOfflineThenRevalidatesAndLogoutPurgesCache() async throws {
        let fixture = UITestBackend.client(), feed = try await fixture.agenda(month: CalendarClock.month(Date())), workspace = try await fixture.workspace()
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let cache = AgendaOfflineCache(root: root), vault = MemorySession(); vault.token = token
        let client = makeClient(vault, cache: cache), scope = try XCTUnwrap(client.agendaScope())
        try cache.save(AgendaOfflineRecord(schema: 1, user: workspace.user, months: [SavedAgenda(data: feed, receivedAt: Date())]), scope: scope)
        MockProtocol.handler = { _ in throw URLError(.notConnectedToInternet) }
        let store = PayrollStore(client: client)
        XCTAssertFalse(store.restoring, "La agenda ya debe estar disponible antes de cualquier petición")
        XCTAssertTrue(store.isAgendaOnly); XCTAssertFalse(store.canWrite)
        XCTAssertNotNil(store.cachedAgenda(month: feed.month, userID: workspace.user.id))
        XCTAssertNil(store.cachedAgenda(month: feed.month, userID: "otra-cuenta"))
        await store.restore()
        XCTAssertTrue(store.isAgendaOnly); XCTAssertNil(store.error); XCTAssertNotNil(store.overview)
        let payload = try JSONEncoder().encode(JSONValue.object(["version": .number(Double(workspace.version)), "company": .string("Prueba"), "periods": .array([]), "employees": .array([]), "user": try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(workspace.user)), "data": workspace.data]))
        MockProtocol.handler = { request in (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, request.httpMethod == "POST" ? Data("{}".utf8) : payload) }
        try await store.refresh()
        XCTAssertFalse(store.isAgendaOnly); XCTAssertTrue(store.canWrite)
        await store.signOut()
        XCTAssertNil(vault.token); XCTAssertNil(store.savedAgenda); XCTAssertNil(store.overview)
        XCTAssertFalse(FileManager.default.fileExists(atPath: cache.file(scope).path))
        vault.token = String(repeating: "b", count: 43)
        XCTAssertNil(PayrollStore(client: client).overview)
    }

    @MainActor func testRevokedAgendaSessionAndForbiddenCalendarPurgeOfflineCopy() async throws {
        let fixture = UITestBackend.client(), feed = try await fixture.agenda(month: CalendarClock.month(Date())), workspace = try await fixture.workspace()
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let cache = AgendaOfflineCache(root: root), vault = MemorySession(); vault.token = token
        let client = makeClient(vault, cache: cache), scope = try XCTUnwrap(client.agendaScope())
        let record = AgendaOfflineRecord(schema: 1, user: workspace.user, months: [SavedAgenda(data: feed, receivedAt: Date())])
        try cache.save(record, scope: scope)
        let store = PayrollStore(client: client)
        MockProtocol.handler = { request in (HTTPURLResponse(url: request.url!, statusCode: 401, httpVersion: nil, headerFields: nil)!, Data("{}".utf8)) }
        await store.restore()
        XCTAssertNil(store.savedAgenda); XCTAssertNil(store.overview); XCTAssertNil(vault.token); XCTAssertNil(cache.load(scope))
        vault.token = token; try cache.save(record, scope: scope)
        MockProtocol.handler = { request in (HTTPURLResponse(url: request.url!, statusCode: 403, httpVersion: nil, headerFields: nil)!, Data("{\"error\":\"Sin acceso a Agenda\"}".utf8)) }
        do { _ = try await client.agenda(month: feed.month); XCTFail("No debe servir una copia en respuesta a una denegación") } catch { XCTAssertEqual(error.localizedDescription, "Sin acceso a Agenda") }
        XCTAssertNil(client.cachedAgenda()); XCTAssertEqual(vault.token, token)
    }

    @MainActor func testAgendaCacheDropsOldCalendarAndCannotRollbackConnectionOrRetainDisconnectedEvents() async throws {
        let client = UITestBackend.client(), store = PayrollStore(client: client)
        defer { store.forgetAgenda() }
        await store.restore()
        let feed = try await client.agenda(month: CalendarClock.month(Date())), user = try XCTUnwrap(store.overview?.user), scope = try XCTUnwrap(client.agendaScope())
        func changed(_ month: String, revision: Int, connected: Bool = true) throws -> AgendaData {
            var value = try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(feed))
            value["month"] = .string(month); value["connection"]["revision"] = .number(Double(revision)); value["connection"]["connected"] = .bool(connected)
            return try JSONDecoder().decode(AgendaData.self, from: JSONEncoder().encode(value))
        }
        try store.rememberAgenda(feed, userID: user.id, scope: scope)
        for offset in 1...7 { try store.rememberAgenda(changed(CalendarClock.shift(feed.month, by: offset)!, revision: feed.connection.revision), userID: user.id, scope: scope) }
        XCTAssertEqual(store.savedAgenda?.months.count, 6)
        try store.rememberAgenda(changed(feed.month, revision: feed.connection.revision + 1), userID: user.id, scope: scope)
        XCTAssertEqual(store.savedAgenda?.months.count, 1, "Una nueva conexión descarta los meses de la conexión anterior")
        do { try store.rememberAgenda(feed, userID: user.id, scope: scope); XCTFail("No restaurar una revisión antigua") } catch { XCTAssertTrue(error is CancellationError) }
        do { try store.rememberAgenda(feed, userID: "otra-cuenta", scope: scope); XCTFail("No guardar para otra identidad") } catch { XCTAssertTrue(error is CancellationError) }
        var large = try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(changed(feed.month, revision: feed.connection.revision + 2)))
        large["events"] = .array([.object(["id": .string("large"), "title": .string("Prueba"), "start": .string("2026-10-07"), "end": .string("2026-10-08"), "allDay": .bool(true), "location": .string(""), "description": .string(String(repeating: "x", count: AgendaOfflineCache.maximumBytes)), "url": .string("")])])
        try store.rememberAgenda(JSONDecoder().decode(AgendaData.self, from: JSONEncoder().encode(large)), userID: user.id, scope: scope)
        XCTAssertNotNil(store.agendaStorageWarning)
        XCTAssertNil(client.cachedAgenda(), "Si falla la nueva copia no se conserva el calendario anterior en disco")
        try store.rememberAgenda(changed(feed.month, revision: feed.connection.revision + 3, connected: false), userID: user.id, scope: scope)
        XCTAssertNil(store.savedAgenda); XCTAssertNil(client.cachedAgenda())
    }

    @MainActor func testCancelledReadsDoNotPublishErrorsOrClearExistingData() async throws {
        let store = PayrollStore(client: UITestBackend.client())
        await store.restore()
        let revision = store.workspace?.version
        let period = PeriodWorkspace()
        await period.load("fixture-period", store: store)
        XCTAssertNotNil(period.detail)
        for cancellation: Error in [CancellationError(), URLError(.cancelled), NSError(domain: NSURLErrorDomain, code: NSURLErrorCancelled)] {
            XCTAssertNil(store.reportReadFailure(cancellation))
            XCTAssertNil(store.error)
        }
        // Exercise URLSession's actual error path, not just classification.
        let vault = MemorySession(); vault.token = token
        let interrupted = PayrollStore(client: makeClient(vault))
        MockProtocol.handler = { _ in throw URLError(.cancelled) }
        do { try await interrupted.refresh(); XCTFail("La consulta sigue cancelada para su llamador") } catch {}
        await period.load("fixture-period", store: interrupted)
        await interrupted.restore()
        XCTAssertNil(interrupted.error); XCTAssertNil(period.error); XCTAssertFalse(period.loading)
        XCTAssertFalse(interrupted.restoring)
        XCTAssertNotNil(period.detail, "Una cancelación no borra la consulta anterior")
        XCTAssertEqual(store.workspace?.version, revision)
        XCTAssertEqual(vault.token, token)
        let existingFailure = "Error real anterior"
        store.error = existingFailure
        XCTAssertNil(store.reportReadFailure(URLError(.cancelled)))
        XCTAssertEqual(store.error, existingFailure, "Una cancelación no oculta otro error pendiente")
    }

    @MainActor func testRealReadFailuresRemainVisibleAndExpiredAccessIsRevoked() async throws {
        let store = PayrollStore(client: UITestBackend.client())
        await store.restore()
        for failure: Error in [URLError(.timedOut), URLError(.notConnectedToInternet), APIError.message("Sin permiso"), NSError(domain: "OtherDomain", code: NSURLErrorCancelled)] {
            XCTAssertEqual(store.reportReadFailure(failure), failure.localizedDescription)
            XCTAssertEqual(store.error, failure.localizedDescription)
        }
        XCTAssertNotNil(store.workspace)
        XCTAssertEqual(store.reportReadFailure(APIError.unauthorized), APIError.unauthorized.localizedDescription)
        XCTAssertNil(store.workspace); XCTAssertNil(store.overview)
    }

    @MainActor func testCancelledSaveStillRetainsDraftAndUncertainFailure() async throws {
        let vault = MemorySession(); vault.token = token
        let store = PayrollStore(client: makeClient(vault))
        let fixture = UITestBackend.client()
        let workspace = try await fixture.workspace()
        let payload = try JSONEncoder().encode(JSONValue.object([
            "version": .number(Double(workspace.version)), "company": .string("Prueba"), "periods": .array([]), "employees": .array([]),
            "user": .object(["id": .string("fixture"), "username": .string("prueba"), "email": .string("test@example.invalid"), "displayName": .string("Prueba"), "isOwner": .bool(true), "permissions": .array([])]), "data": workspace.data
        ]))
        MockProtocol.handler = { request in
            if request.httpMethod == "POST" { throw URLError(.cancelled) }
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, payload)
        }
        try await store.refresh()
        let command: JSONValue = .object(["action": .string("edit"), "version": .number(Double(workspace.version)), "edit": .object(["kind": .string("settings"), "record": .object(["company": .string("Borrador")])])])
        let saved = await store.submit(command, label: "Formulario")
        XCTAssertFalse(saved); XCTAssertEqual(store.pending?.command, command)
        XCTAssertNotNil(store.error); XCTAssertFalse(store.busy)
        XCTAssertEqual(vault.token, token)
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
    @MainActor func testItinerariesUseAuthenticatedAPIAndProtectedTemporaryPDF() async throws {
        let client = UITestBackend.client()
        let feed = try await client.notices()
        let item = try XCTUnwrap(feed.notices.first)
        XCTAssertEqual(item.kind, "itinerary"); XCTAssertEqual(item.body, "")
        let direct = try await client.notice(id: item.id); XCTAssertEqual(direct.id, item.id)
        let document = try await client.itinerary(item)
        defer { TemporaryDocuments.remove(document) }
        XCTAssertEqual(String(data: try Data(contentsOf: document.url).prefix(5), encoding: .utf8), "%PDF-")
        XCTAssertEqual(document.url.lastPathComponent, "Itinerario_simulado.pdf")
        try await client.noticeCommand(.object(["action": .string("read"), "id": .string(item.id)]))
    }
    @MainActor func testAlertCreationAndReaderPermissionUseTheSharedServerContract() async throws {
        let client = UITestBackend.client(), id = UUID().uuidString.lowercased()
        let command: JSONValue = .object(["action": .string("alert"), "alert": .object(["id": .string(id), "title": .string("Aviso simulado"), "body": .string("Mensaje de prueba"), "recipients": .array([.string("22222222-2222-4222-8222-222222222222")])])])
        try await client.noticeCommand(command); try await client.noticeCommand(command)
        let feed = try await client.notices()
        XCTAssertEqual(feed.notices.filter { $0.id == id }.count, 1)
        let reader = UITestBackend.client(reader: true)
        let readerFeed = try await reader.notices(); XCTAssertTrue(readerFeed.users.isEmpty)
        do { try await reader.noticeCommand(command); XCTFail("La API debe rechazar al lector") } catch { XCTAssertTrue(error.localizedDescription.contains("Solo Camilo")) }
    }
    @MainActor func testPushRoutingValidatesIdentifiersAndLogoutNamesOnlyThisDevice() async throws {
        let hub = JACNotifications.shared; hub.noticeID = nil
        hub.received("https://untrusted.example.invalid"); XCTAssertNil(hub.noticeID)
        let id = UUID().uuidString; hub.received(id); XCTAssertEqual(hub.noticeID, id.lowercased()); hub.noticeID = nil
        let vault = MemorySession(); vault.token = token
        MockProtocol.handler = { request in
            let body = try JSONDecoder().decode(JSONValue.self, from: MockProtocol.requestBody(request))
            XCTAssertEqual(body["action"].text, "logout"); XCTAssertEqual(body["notificationDeviceId"].text, JACNotifications.deviceID)
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, Data("{}".utf8))
        }
        try await makeClient(vault).logout(); XCTAssertNil(vault.token)
    }

    func testNoticeTimestampsUseColombiaDayAndTimeIncludingFractionalSeconds() {
        for timestamp in ["2026-10-07T00:00:00Z", "2026-10-07T00:00:00.000Z"] {
            let item = JACNotice(id: UUID().uuidString, kind: "alert", title: "Prueba", body: "", filename: "", size: 0, createdAt: timestamp, read: false)
            XCTAssertNotNil(item.createdLabel.range(of: "^6\\D", options: .regularExpression), "Debe mostrar el 6 de octubre en Colombia, no el día 7 de UTC")
            XCTAssertTrue(item.createdLabel.contains("7:00") || item.createdLabel.contains("19:00"))
            XCTAssertFalse(item.createdLabel.contains(timestamp))
        }
    }

    @MainActor func testManualItineraryAttachmentsArePrivateAndDeletionIsIdempotent() async throws {
        let client = UITestBackend.client(), id = UUID().uuidString.lowercased(), data = Data("%PDF-1.4 simulated only".utf8)
        let file = NoticeUpload(filename:"Prueba.pdf",data:data)
        try await client.publishNotice(id:id,kind:"itinerary",title:"Itinerario manual",body:"Sin Slack",recipients:[],files:[file])
        try await client.publishNotice(id:id,kind:"itinerary",title:"Itinerario manual",body:"Sin Slack",recipients:[],files:[file])
        let feed = try await client.notices(); XCTAssertEqual(feed.notices.filter { $0.id == id }.count,1)
        let item = try await client.notice(id:id), attachment = try XCTUnwrap(item.files.first)
        let document = try await client.noticeFile(item,file:attachment); defer { TemporaryDocuments.remove(document) }
        XCTAssertEqual(try Data(contentsOf:document.url),data)
        try await client.deleteNotice(item); try await client.deleteNotice(item)
        do { _ = try await client.notice(id:id); XCTFail("El itinerario eliminado no debe estar disponible") } catch {}
        do { try await client.publishNotice(id:id,kind:"itinerary",title:"Itinerario manual",body:"Sin Slack",recipients:[],files:[file]); XCTFail("No restaurar un aviso eliminado") } catch {}
    }
    @MainActor func testManualUploadPreservesServerContractAndRejectsUnsafeFileData() async throws {
        let vault = MemorySession(); vault.token = token; let client = makeClient(vault), id = UUID().uuidString.lowercased()
        MockProtocol.handler = { request in
            XCTAssertEqual(request.url?.path,"/api/notices/publish"); XCTAssertEqual(request.value(forHTTPHeaderField:"Origin"),self.base.absoluteString); XCTAssertEqual(request.value(forHTTPHeaderField:"Cookie"),"__Host-jac_session=" + self.token)
            let body = try JSONDecoder().decode(JSONValue.self,from:MockProtocol.requestBody(request)); XCTAssertEqual(body["id"].text,id); XCTAssertEqual(body["kind"].text,"alert"); XCTAssertEqual(body["files"].elements.count,1)
            XCTAssertEqual(Data(base64Encoded:body["files"].elements[0]["data"].text),Data("%PDF-1.4 fixture".utf8))
            return (HTTPURLResponse(url:request.url!,statusCode:200,httpVersion:nil,headerFields:nil)!,Data("{}".utf8))
        }
        try await client.publishNotice(id:id,kind:"alert",title:"Alerta",body:"Descripción",recipients:["fixture"],files:[NoticeUpload(filename:"Prueba.pdf",data:Data("%PDF-1.4 fixture".utf8))])
        do { try await client.publishNotice(id:id,kind:"alert",title:"Alerta",body:"Descripción",recipients:[],files:[NoticeUpload(filename:"fake.pdf",data:Data("<html>unsafe</html>".utf8))]); XCTFail("Rechazar archivo inválido antes de enviarlo") } catch {}
    }

    @MainActor func testTemporaryDocumentProtectionOnPhysicaliPhone() throws {
        #if targetEnvironment(simulator)
        throw XCTSkip("CoreSimulator no expone NSFileProtectionKey ni reproduce el cifrado del iPhone. Esta comprobación se conserva para un dispositivo físico.")
        #else
        let document = try TemporaryDocuments.save(Data("%PDF-1.4 fixture".utf8), filename:"Proteccion.pdf")
        defer { TemporaryDocuments.remove(document) }
        let protected = try FileManager.default.attributesOfItem(atPath:document.url.path)
        XCTAssertEqual(protected[.protectionKey] as? FileProtectionType,.complete)
        #endif
    }

    @MainActor func testBoardingDateParsingAndColombiaMidnight() throws {
        XCTAssertEqual(BoardingClock.today(try XCTUnwrap(CalendarClock.instant("2026-10-08T04:59:59Z"))),"2026-10-07")
        XCTAssertEqual(BoardingClock.today(try XCTUnwrap(CalendarClock.instant("2026-10-08T05:00:00Z"))),"2026-10-08")
        let at=try XCTUnwrap(CalendarClock.instant("2026-12-31T15:00:00Z"))
        XCTAssertEqual(BoardingClock.today(try XCTUnwrap(BoardingClock.filenameDate("Camilo 2 de enero.pdf",at:at))),"2027-01-02")
        XCTAssertNil(BoardingClock.filenameDate("Camilo 31 de abril 2026.pdf")); XCTAssertNil(BoardingClock.filenameDate("1 de octubre y 2 de octubre.pdf"))
    }
    @MainActor func testPrivateBoardingFeedHistoryAndManualContract() async throws {
        let client=UITestBackend.client(); let feed=try await client.notices(boarding:"current")
        XCTAssertEqual(feed.notices.filter { $0.travelDate == BoardingClock.today() }.count,2)
        XCTAssertEqual(feed.notices.count,3); let history=try await client.notices(boarding:"history"); XCTAssertEqual(history.notices.count,1)
        let reader=UITestBackend.client(reader:true); let otherFeed=try await reader.notices(boarding:"current"); XCTAssertTrue(otherFeed.notices.isEmpty)
        do { _ = try await reader.notice(id:"boarding-fixture-0"); XCTFail("Otro usuario no puede abrir un pase") } catch {}
        let vault=MemorySession(); vault.token=token; let sending=makeClient(vault)
        MockProtocol.handler = { request in let body=try JSONDecoder().decode(JSONValue.self,from:MockProtocol.requestBody(request)); XCTAssertEqual(body["kind"].text,"boarding_pass"); XCTAssertEqual(body["travelDate"].text,"2026-10-10"); XCTAssertEqual(body["recipients"].elements,[.string("recipient-fixture")]); return (HTTPURLResponse(url:request.url!,statusCode:200,httpVersion:nil,headerFields:nil)!,Data("{}".utf8)) }
        try await sending.publishNotice(id:UUID().uuidString.lowercased(),kind:"boarding_pass",title:"Pase ficticio",body:"",recipients:["recipient-fixture"],files:[NoticeUpload(filename:"10 de octubre.pdf",data:Data("%PDF-1.4 ficticio".utf8))],travelDate:"2026-10-10")
    }

}
