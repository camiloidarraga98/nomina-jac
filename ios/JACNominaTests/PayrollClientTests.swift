import XCTest
import UserNotifications
import UIKit
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
    func testReceiptParserChoosesTotalAndIssueDateInsteadOfTaxesCashAndDueDate() {
        let value = ReceiptParser.parse(["Restaurante Ficticio", "FACTURA 882299", "FECHA EMISIÓN 08/10/2026", "VENCE 10/10/2026", "SUBTOTAL 40.000", "IVA 7.600", "TOTAL A PAGAR COP 47.600,00", "EFECTIVO 50.000", "CAMBIO 2.400"])
        XCTAssertEqual(value.amount, 47600); XCTAssertEqual(value.date, "2026-10-08")
        XCTAssertEqual(value.kind, .food); XCTAssertEqual(value.concept, "Restaurante Ficticio")
        XCTAssertTrue(value.warnings.isEmpty)
        XCTAssertEqual(ReceiptParser.parse(["HOTEL DE PRUEBA", "Fecha: 8 de octubre de 2026", "TOTAL", "$ 123,000.00"]).amount, 123000)
        XCTAssertEqual(ReceiptParser.parse(["HOTEL DE PRUEBA", "Fecha: 8 de octubre de 2026", "TOTAL", "$ 123,000.00"]).date, "2026-10-08")
    }
    func testReceiptOCRPairsSeparatedPriceColumnsWithoutMergingAdjacentLines() {
        let lines = ReceiptOCR.orderedLines([
            ("47.600", CGRect(x: 0.7, y: 0.50, width: 0.2, height: 0.04)),
            ("SUBTOTAL", CGRect(x: 0.1, y: 0.60, width: 0.3, height: 0.04)),
            ("TOTAL A PAGAR", CGRect(x: 0.1, y: 0.505, width: 0.4, height: 0.04)),
            ("40.000", CGRect(x: 0.7, y: 0.60, width: 0.2, height: 0.04)),
            ("CAMBIO 2.400", CGRect(x: 0.1, y: 0.40, width: 0.8, height: 0.04))])
        XCTAssertEqual(lines, ["SUBTOTAL 40.000", "TOTAL A PAGAR 47.600", "CAMBIO 2.400"])
        XCTAssertEqual(ReceiptParser.parse(lines).amount, 47600)
    }
    func testReceiptAmbiguityForeignCurrencyInvalidDatesAndDecimalPesosNeedReview() {
        for rows in [["SUBTOTAL 10.000", "IVA 1.900", "EFECTIVO 20.000"], ["TOTAL 10.000", "TOTAL 20.000"], ["TOTAL USD 15.00"], ["TOTAL US$ 15.00"], ["TOTAL EUR 15"], ["TOTAL COP 10.000,50"], ["TOTAL -10.000"], ["TOTAL 1.000.000.001"], ["FACTURA 20261008"]] {
            let value = ReceiptParser.parse(rows); XCTAssertNil(value.amount, rows.description); XCTAssertFalse(value.warnings.isEmpty)
        }
        XCTAssertNil(ReceiptParser.parse(["FECHA: 31/02/2026"]).date)
        for rows in [["FECHA: 08/10/2026", "FECHA: 09/10/2026"], ["RESOLUCION 2026-10-08"], ["VENCIMIENTO 08/10/2026"]] { XCTAssertEqual(ReceiptParser.parse(rows).date,"2026-10-08", "La regla solicitada toma la primera fecha válida, sin filtrar etiquetas: " + rows.description) }
        XCTAssertNil(ReceiptParser.parse(["HOTEL Y RESTAURANTE"]).kind)
        XCTAssertEqual(ReceiptParser.parse(["TOTAL 10.000", "VALOR TOTAL 11.900"]).amount, 11900)
        XCTAssertEqual(ReceiptParser.parse(["TAXI FICTICIO", "FECHA 2026-10-08", "TOTAL 25000"]).kind, .transport)
        XCTAssertEqual(ReceiptParser.parse(["TERPEL", "TOTAL 80 000"]).amount, 80000)
        XCTAssertEqual(ReceiptParser.parse(["TERPEL", "TOTAL 80 000"]).kind, .fuel)
        XCTAssertNil(ReceiptParser.money("1,000,00")); XCTAssertNil(ReceiptParser.money("1.000.00"))
    }
    @MainActor func testNativeVisionReadsPhotographedFictitiousReceiptWithoutAnyServer() async throws {
        MockProtocol.handler = { _ in XCTFail("El OCR no debe usar el servidor"); throw URLError(.unsupportedURL) }
        let bytes = try ReceiptOCR.photograph(ReceiptOCR.fixture())
        let lines = try await ReceiptOCR.recognize(bytes)
        let value = ReceiptParser.parse(lines)
        XCTAssertEqual(value.amount, 47600, lines.description); XCTAssertEqual(value.date, "2026-10-08", lines.description)
        XCTAssertEqual(value.kind, .food); XCTAssertEqual(value.concept, "RESTAURANTE FICTICIO JAC"); XCTAssertEqual(value.time,"13:45:20")
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        let blank = UIGraphicsImageRenderer(size: CGSize(width: 1000, height: 1000), format: format).image { context in UIColor.white.setFill(); context.fill(CGRect(x: 0, y: 0, width: 1000, height: 1000)) }
        let emptyLines = try await ReceiptOCR.recognize(ReceiptOCR.photograph(blank))
        XCTAssertTrue(emptyLines.isEmpty)
    }
    @MainActor func testExpenseDraftIsEncryptedSessionScopedAndKeepsIdempotentSubmissionOnRelaunch() async throws {
        let cache = OfflineResponseCache(root: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        let vault = MemorySession(); vault.token = token
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [MockProtocol.self]
        let client = PayrollClient(baseURL: base, vault: vault, configuration: config, offlineCache: cache)
        let scope = try XCTUnwrap(client.offlineScope())
        var draft = ExpenseDraft(); draft.concept = "Factura privada ficticia"; draft.kind = ExpenseKind.food.rawValue
        draft.amount = "47600"; draft.note = "Solo prueba"; draft.receiptTime = "13:45:20"; draft.attempted = true
        draft.files = [.init(filename: "Ficticio.jpg", data: try ReceiptOCR.photograph(ReceiptOCR.fixture()))]
        client.beginOfflineRestore(); try client.saveExpenseDraft(draft, scope: scope)
        let sealed = try Data(contentsOf: cache.file(scope, key: "local-expense-draft-v1"))
        XCTAssertNil(sealed.range(of: Data(draft.concept.utf8))); XCTAssertNil(sealed.range(of: draft.files[0].data))
        let relaunched = PayrollClient(baseURL: base, vault: vault, configuration: config, offlineCache: cache)
        XCTAssertEqual(relaunched.expenseDraft(), draft)
        XCTAssertEqual(draft.submissionNote, "Tipo de gasto: Alimentación\nHora de factura: 13:45:20\nSolo prueba")
        let other = MemorySession(); other.token = String(repeating: "z", count: 43)
        let otherClient = PayrollClient(baseURL: URL(string: "https://other.invalid")!, vault: other, configuration: config, offlineCache: OfflineResponseCache(root: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)))
        XCTAssertNil(otherClient.expenseDraft())
        vault.token = String(repeating: "b", count: 43)
        XCTAssertNil(client.expenseDraft()); XCTAssertThrowsError(try client.saveExpenseDraft(draft, scope: scope))
        vault.token = token; try client.clearSession(); XCTAssertNil(client.expenseDraft()); XCTAssertNil(cache.load(scope, key: "local-expense-draft-v1"))
    }
    @MainActor func testDraftStorageRejectsInvalidAttachmentsAndDeletionRemovesLocalReceipt() throws {
        let vault = MemorySession(); vault.token = token; let client = makeClient(vault)
        let scope = try XCTUnwrap(client.offlineScope()); var draft = ExpenseDraft()
        draft.files = [.init(filename: "fake.jpg", data: Data("invalid".utf8))]
        XCTAssertThrowsError(try client.saveExpenseDraft(draft, scope: scope)); XCTAssertNil(client.expenseDraft())
        draft.files = []; draft.concept = "Borrador ficticio"; try client.saveExpenseDraft(draft, scope: scope)
        XCTAssertNotNil(client.expenseDraft()); try client.removeExpenseDraft(scope: scope); XCTAssertNil(client.expenseDraft())
    }
    func testReceiptFirstDateWinsInVerticalThenHorizontalOrderWithItsOwnTime() {
        let rows=ReceiptOCR.orderedLines([
            ("FECHA 09/10/2026 08:10",CGRect(x:0.1,y:0.4,width:0.8,height:0.04)),
            ("FECHA 08/10/2026 13:45:20",CGRect(x:0.1,y:0.8,width:0.8,height:0.04))])
        let first=ReceiptParser.parse(rows)
        XCTAssertEqual(first.date,"2026-10-08");XCTAssertEqual(first.time,"13:45:20")
        let horizontal=ReceiptParser.parse(["08/10/2026 09:10   07/10/2026 18:30"])
        XCTAssertEqual(horizontal.date,"2026-10-08");XCTAssertEqual(horizontal.time,"09:10")
        XCTAssertEqual(ReceiptParser.parse(["08/10/2026  07/10/2026 18:30"]).time,nil,"No tomar la hora de la segunda fecha")
        XCTAssertEqual(ReceiptParser.parse(["31/02/2026", "8 OCT. 2026", "Hora: 1:05:09 p. m."]).time,"13:05:09")
        XCTAssertEqual(ReceiptParser.parse(["08/10/26", "FECHA 09/10/2026 18:30"]).date,"2026-10-08")
        XCTAssertNil(ReceiptParser.parse(["08/10/2026", "FECHA 09/10/2026 18:30"]).time)
        XCTAssertNil(ReceiptParser.parse(["08/10/2026 25:75:00"]).time)
        XCTAssertEqual(ReceiptParser.parse(["2026/10/08 00:15", "08/10/2026 16:00"]).time,"00:15")
        XCTAssertEqual(ReceiptParser.parse(["8 de octubre de 2026 12:00 a. m."]).time,"00:00")
        XCTAssertEqual(ReceiptParser.parse(["8-SEP-26 12:00 PM"]).date,"2026-09-08")
        XCTAssertEqual(ReceiptParser.parse(["8-SEP-26 12:00 PM"]).time,"12:00")
        XCTAssertFalse(first.warnings.contains { $0.contains("fecha") })
    }
    func testReceiptCategoryUsesPurchasedItemsAndServiceInsteadOfOnlyMerchantName() {
        XCTAssertEqual(ReceiptParser.parse(["COMERCIO FICTICIO", "1 ALMUERZO", "1 POLLO CON ARROZ", "1 JUGO"]).kind,.food)
        XCTAssertEqual(ReceiptParser.parse(["HOTEL FICTICIO", "ALMUERZO", "POLLO", "ARROZ"]).kind,.food)
        XCTAssertEqual(ReceiptParser.parse(["HOTEL RESTAURANTE FICTICIO", "HABITACION", "2 NOCHES"]).kind,.lodging)
        XCTAssertEqual(ReceiptParser.parse(["ESTACION DE SERVICIO FICTICIA", "GASOLINA", "CAFE"]).kind,.fuel)
        XCTAssertEqual(ReceiptParser.parse(["COMERCIO FICTICIO", "TRANSPORTE", "PASAJE", "NIT 1234567"]).kind,.transport)
        XCTAssertNil(ReceiptParser.parse(["COMERCIO FICTICIO", "CIIU RESTAURANTE", "NIT 1234567"]).kind)
        XCTAssertNil(ReceiptParser.parse(["ARTICULO SIN DESCRIPCION"]).kind)
    }
    func testReceiptTimeIsOptionalForOldDraftsAndIncludedInReviewedNote() throws {
        let bytes=try JSONEncoder().encode(ExpenseDraft())
        let old=try JSONDecoder().decode(ExpenseDraft.self,from:bytes)
        XCTAssertNil(old.receiptTime);XCTAssertEqual(old.submissionNote,"")
        var draft=old;draft.kind=ExpenseKind.food.rawValue;draft.receiptTime="13:45:20";draft.note="Revisado"
        XCTAssertEqual(draft.submissionNote,"Tipo de gasto: Alimentación\nHora de factura: 13:45:20\nRevisado")
        XCTAssertNoThrow(try draft.validateStorage())
        draft.receiptTime="25:75";XCTAssertThrowsError(try draft.validateStorage())
    }
    private let base = URL(string: "https://payroll.example.invalid")!
    private let token = String(repeating: "a", count: 43)

    @MainActor private func makeClient(_ vault: MemorySession, cache: AgendaOfflineCache? = nil) -> PayrollClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockProtocol.self]
        return PayrollClient(baseURL: base, vault: vault, configuration: configuration, agendaCache: cache ?? AgendaOfflineCache(root: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)))
    }
    override func tearDown() { MockProtocol.handler = nil; TemporaryDocuments.clear(); super.tearDown() }

    @MainActor private func waitForOfflineCopy(_ client: PayrollClient) async throws {
        for _ in 0..<200 {
            if client.offlineSyncMessage == "La última información y sus adjuntos están guardados en este iPhone." { return }
            try await Task.sleep(for: .milliseconds(50))
        }
        XCTFail(client.offlineSyncMessage ?? "No terminó la descarga ficticia")
    }
    @MainActor private func cachedFixture(_ cache: OfflineResponseCache) async throws -> PayrollClient {
        let client = UITestBackend.client(contentCache: cache, downloadOffline: true)
        let workspace = try await client.workspace()
        client.synchronizeOfflineContent(workspace)
        try await waitForOfflineCopy(client)
        return client
    }
    @MainActor private func relaunchFixture(_ cache: OfflineResponseCache, token: String = String(repeating: "f", count: 43)) -> (PayrollClient, MemorySession) {
        let vault = MemorySession(); vault.token = token
        let configuration = URLSessionConfiguration.ephemeral; configuration.protocolClasses = [MockProtocol.self]
        return (PayrollClient(baseURL: UITestBackend.base, vault: vault, configuration: configuration, agendaCache: AgendaOfflineCache(root: cache.root.appendingPathComponent("agenda-test")), offlineCache: cache, automaticallyDownloadOffline: false), vault)
    }

    @MainActor func testFullCopyRestoresBeforeNetworkAndOpensPayrollAgendaItineraryAndPrivatePassOffline() async throws {
        let cache = OfflineResponseCache(root: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        defer { try? FileManager.default.removeItem(at: cache.root) }
        let initial = try await cachedFixture(cache), workspace = try XCTUnwrap(initial.cachedWorkspace())
        let itinerary = try XCTUnwrap(initial.cachedNotices()?.notices.first { $0.kind == "itinerary" })
        let pass = try XCTUnwrap(initial.cachedNotices(boarding: "current")?.notices.first)
        let (client, vault) = relaunchFixture(cache); var requests = 0
        MockProtocol.handler = { _ in requests += 1; throw URLError(.notConnectedToInternet) }
        let store = PayrollStore(client: client)
        XCTAssertEqual(store.workspace?.version, workspace.version); XCTAssertFalse(store.restoring)
        XCTAssertTrue(store.hasSavedSession); XCTAssertTrue(store.isOffline); XCTAssertFalse(store.canWrite)
        XCTAssertEqual(requests, 0, "La pantalla no debe esperar ninguna petición para mostrar lo descargado")
        await store.restore()
        XCTAssertNil(store.error); XCTAssertEqual(store.overview?.user.id, workspace.user.id)
        let detail = try await client.detail(periodID: workspace.periods[0].id)
        XCTAssertEqual(detail.version, workspace.version)
        let agenda = try await client.agenda(month: CalendarClock.month(Date()))
        XCTAssertFalse(agenda.events.isEmpty)
        let pdf = try await client.itinerary(itinerary), privatePDF = try await client.noticeFile(pass, file: pass.files[0])
        XCTAssertTrue(try Data(contentsOf: pdf.url).starts(with: Data("%PDF-".utf8)))
        XCTAssertTrue(try Data(contentsOf: privatePDF.url).starts(with: Data("%PDF-".utf8)))
        _ = try await client.users(); _ = try await client.mail(periodID: nil); _ = try await client.expenses()
        do { try await client.confirmNotice(itinerary); XCTFail("No deben enviarse cambios desde la copia") } catch APIError.invalid { }
        XCTAssertEqual(requests, 1, "Solo se intentó revalidar la sesión; el contenido se abrió desde disco")
        XCTAssertEqual(vault.token, String(repeating: "f", count: 43))
        await store.signOut()
        XCTAssertNil(vault.token); XCTAssertNil(store.workspace); XCTAssertFalse(store.hasSavedSession)
        XCTAssertNil(client.cachedWorkspace()); XCTAssertFalse(FileManager.default.fileExists(atPath: privatePDF.url.path))
    }

    @MainActor func testAlertImageAndExpenseReceiptDownloadAutomaticallyAndRemainReadableOffline() async throws {
        let cache = OfflineResponseCache(root: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        defer { try? FileManager.default.removeItem(at: cache.root) }
        let client = UITestBackend.client(contentCache: cache, downloadOffline: true)
        let image = try XCTUnwrap(Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jRZkAAAAASUVORK5CYII="))
        let id = UUID().uuidString.lowercased()
        try await client.publishNotice(id: id, kind: "alert", title: "Imagen ficticia", body: "Solo prueba local", recipients: ["11111111-1111-4111-8111-111111111111"], files: [NoticeUpload(filename: "Imagen.png", data: image)])
        try await client.submitExpense(id: UUID().uuidString.lowercased(), concept: "Comprobante simulado", amount: 1000, date: BoardingClock.today(), note: "Sin datos reales", files: [NoticeUpload(filename: "Comprobante.png", data: image)])
        client.synchronizeOfflineContent(try await client.workspace()); try await waitForOfflineCopy(client)
        let (offline, _) = relaunchFixture(cache); let store = PayrollStore(client: offline)
        MockProtocol.handler = { _ in XCTFail("Los adjuntos descargados no deben esperar internet"); throw URLError(.notConnectedToInternet) }
        let alert = try await offline.notice(id: id), expense = try XCTUnwrap(offline.cachedExpenses()?.expenses.first)
        let alertFile = try await offline.noticeFile(alert, file: alert.files[0]), receipt = try await offline.expenseFile(expense, file: expense.attachments[0])
        XCTAssertEqual(try Data(contentsOf: alertFile.url), image); XCTAssertEqual(try Data(contentsOf: receipt.url), image)
        XCTAssertTrue(store.isOffline); XCTAssertTrue(store.hasSavedSession)
    }

    @MainActor func testFullCopyRevalidatesAndRestoresAuthorizedActionsAfterInternetReturns() async throws {
        let cache = OfflineResponseCache(root: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        defer { try? FileManager.default.removeItem(at: cache.root) }
        let initial = try await cachedFixture(cache), workspace = try XCTUnwrap(initial.cachedWorkspace())
        let (client, vault) = relaunchFixture(cache)
        let store = PayrollStore(client: client)
        MockProtocol.handler = { _ in throw URLError(.timedOut) }
        await store.restore(); XCTAssertTrue(store.isOffline); XCTAssertFalse(store.canWrite)
        let bytes = try JSONEncoder().encode(workspace)
        MockProtocol.handler = { request in (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!, bytes) }
        try await store.refreshAutomatically()
        XCTAssertFalse(store.isOffline); XCTAssertFalse(store.offlineMode); XCTAssertTrue(store.canWrite)
        XCTAssertTrue(store.hasSavedSession); XCTAssertEqual(vault.token, String(repeating: "f", count: 43)); XCTAssertNotNil(client.cachedWorkspace())
    }

    @MainActor func testSavedSessionWithoutDownloadedDataDoesNotBecomeLogoutWhenOffline() async throws {
        let vault = MemorySession(); vault.token = token
        let store = PayrollStore(client: makeClient(vault))
        MockProtocol.handler = { _ in throw URLError(.notConnectedToInternet) }
        await store.restore()
        XCTAssertTrue(store.hasSavedSession); XCTAssertNil(store.overview); XCTAssertFalse(store.restoring)
        XCTAssertEqual(vault.token, token); XCTAssertNil(store.error)
    }

    @MainActor func testFullOfflineCopyIsEncryptedSessionBoundAndRejectsTampering() async throws {
        let cache = OfflineResponseCache(root: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        defer { try? FileManager.default.removeItem(at: cache.root) }
        let client = try await cachedFixture(cache), scope = try XCTUnwrap(client.offlineScope())
        let entry = try XCTUnwrap(cache.entries(scope).first { $0.url.contains("workspace=1") })
        let disk = try Data(contentsOf: cache.file(scope, key: entry.key))
        XCTAssertNil(disk.range(of: Data("Prueba".utf8))); XCTAssertNil(disk.range(of: Data(String(repeating: "f", count: 43).utf8)))
        XCTAssertNil(cache.load(OfflineResponseCache.scope(origin: UITestBackend.base.absoluteString, token: token), key: entry.key))
        XCTAssertNil(cache.load(OfflineResponseCache.scope(origin: "https://other.example.invalid", token: String(repeating: "f", count: 43)), key: entry.key))
        XCTAssertEqual(try cache.root.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup, true)
        var corrupt = disk; corrupt[0] ^= 1; try corrupt.write(to: cache.file(scope, key: entry.key))
        XCTAssertNil(cache.load(scope, key: entry.key))
        XCTAssertThrowsError(try cache.save(OfflineResponse(key: "huge", url: UITestBackend.base.absoluteString, headers: [:], data: Data(count: OfflineResponseCache.maximumEntryBytes + 1), receivedAt: Date(), revision: 1), scope: scope))
    }

    @MainActor func testRevalidationRevocationPurgesFullCacheRatherThanUsingFallback() async throws {
        let cache = OfflineResponseCache(root: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        defer { try? FileManager.default.removeItem(at: cache.root) }
        _ = try await cachedFixture(cache)
        let (client, vault) = relaunchFixture(cache)
        let scope = try XCTUnwrap(client.offlineScope()), store = PayrollStore(client: client)
        XCTAssertNotNil(store.workspace)
        MockProtocol.handler = { request in (HTTPURLResponse(url: request.url!, statusCode: 401, httpVersion: nil, headerFields: nil)!, Data("{}".utf8)) }
        await store.restore()
        XCTAssertNil(store.workspace); XCTAssertNil(store.overview); XCTAssertFalse(store.hasSavedSession)
        XCTAssertNil(client.cachedWorkspace()); XCTAssertTrue(cache.entries(scope).isEmpty)
        XCTAssertNil(vault.token)
    }

    @MainActor func testForbiddenPrivateAttachmentPurgesNoticeAndNeverReturnsCachedPDFOnline() async throws {
        let cache = OfflineResponseCache(root: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        defer { try? FileManager.default.removeItem(at: cache.root) }
        let initial = try await cachedFixture(cache), pass = try XCTUnwrap(initial.cachedNotices(boarding: "current")?.notices.first)
        let (client, _) = relaunchFixture(cache)
        MockProtocol.handler = { request in (HTTPURLResponse(url: request.url!, statusCode: 403, httpVersion: nil, headerFields: nil)!, Data("{\"error\":\"Sin permiso\"}".utf8)) }
        do { _ = try await client.noticeFile(pass, file: pass.files[0]); XCTFail("No debe abrir una copia denegada por el servidor") } catch APIError.forbidden { }
        XCTAssertNil(client.cachedNotice(pass.id)); XCTAssertFalse(client.usingOfflineCopy)
        client.beginOfflineRestore()
        XCTAssertFalse(client.cachedNotices(boarding: "current")?.notices.contains { $0.id == pass.id } ?? true)
        XCTAssertFalse(cache.entries(try XCTUnwrap(client.offlineScope())).contains { $0.url.contains("id=" + pass.id) })
    }

    @MainActor func testNotificationPermissionIsRequestedAfterSessionAndDenialIsRespected() async throws {
        let suite = "push-test-" + UUID().uuidString, defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let vault = MemorySession(), client = makeClient(vault), permission = FakeNotificationPermission()
        var remoteRequests = 0
        let hub = JACNotifications(defaults: defaults, permission: permission, allowsFixture: true, pushAvailable: true, registerRemote: { remoteRequests += 1 }, unregisterRemote: {})
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
        let hub = JACNotifications(defaults: defaults, permission: permission, allowsFixture: true, pushAvailable: true, registerRemote: { remoteRequests += 1 }, unregisterRemote: {})
        await hub.bind(client); XCTAssertEqual(permission.requests, 1); XCTAssertEqual(remoteRequests, 1)
        await hub.register(String(repeating: "ab", count: 32)); await hub.disable(client)
        await hub.register(String(repeating: "cd", count: 32)); await hub.bind(client)
        XCTAssertFalse(hub.enabled); XCTAssertEqual(commands, ["register", "unregister"]); XCTAssertEqual(remoteRequests, 1)
        let reopened = JACNotifications(defaults: defaults, permission: permission, allowsFixture: true, pushAvailable: true, registerRemote: { remoteRequests += 1 }, unregisterRemote: {})
        await reopened.bind(client); XCTAssertEqual(remoteRequests, 1); XCTAssertFalse(reopened.enabled)
        await reopened.enable(client); XCTAssertTrue(reopened.enabled); XCTAssertEqual(remoteRequests, 2); XCTAssertEqual(permission.requests, 1)
        reopened.stop(); hub.stop()
    }

    @MainActor func testSuspendedPushCannotRequestPermissionRegisterOrChangeUserPreference() async throws {
        XCTAssertFalse(JACNotifications.buildSupportsPush, "La configuración temporal del binario debe suspender push.")
        let suite = "push-suspended-" + UUID().uuidString, defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(true, forKey: "jac.push.enabled")
        let vault = MemorySession(); vault.token = token
        let client = makeClient(vault), permission = FakeNotificationPermission()
        var remoteCalls = 0, networkCalls = 0
        MockProtocol.handler = { _ in networkCalls += 1; throw URLError(.unsupportedURL) }
        let hub = JACNotifications(defaults: defaults, permission: permission, allowsFixture: true, pushAvailable: false, registerRemote: { remoteCalls += 1 }, unregisterRemote: { remoteCalls += 1 })
        await hub.bind(client); await hub.enable(client)
        await hub.register(String(repeating: "ab", count: 32)); await hub.disable(client)
        hub.received(UUID().uuidString); hub.stop()
        XCTAssertFalse(hub.enabled); XCTAssertFalse(hub.busy); XCTAssertNil(hub.noticeID)
        XCTAssertEqual(permission.requests, 0); XCTAssertEqual(remoteCalls, 0); XCTAssertEqual(networkCalls, 0)
        XCTAssertEqual(defaults.object(forKey: "jac.push.enabled") as? Bool, true, "La suspensión del build no debe borrar la elección del usuario.")
        let restored = JACNotifications(defaults: defaults, permission: permission, pushAvailable: true, registerRemote: {}, unregisterRemote: {})
        XCTAssertTrue(restored.enabled)
        defaults.set(false, forKey: "jac.push.enabled")
        let optedOut = JACNotifications(defaults: defaults, permission: permission, pushAvailable: true, registerRemote: {}, unregisterRemote: {})
        XCTAssertFalse(optedOut.enabled, "Al reactivar la capacidad se conserva una desactivación previa.")
    }

    func testDeviceKeychainCanStoreReplaceAndRemoveSession() throws {
        let account = "test-\(UUID().uuidString).invalid"
        let vault = KeychainSessionStore(account: account)
        defer { try? vault.clear() }
        XCTAssertNil(try vault.load())
        try vault.save(String(repeating: "a", count: 43))
        XCTAssertEqual(try vault.load(), String(repeating: "a", count: 43))
        XCTAssertEqual(try KeychainSessionStore(account: account).load(), String(repeating: "a", count: 43), "Una nueva instancia recupera la sesión del Llavero.")
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
            let input = try JSONSerialization.jsonObject(with: MockProtocol.requestBody(request)) as! [String: Any]
            XCTAssertEqual(input["keepSignedIn"] as? Bool, false)
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Set-Cookie": "__Host-jac_session=\(self.token); Path=/; HttpOnly; Secure; SameSite=Lax; Max-Age=43200"])!, Data("{\"ok\":true}".utf8))
        }
        try await client.login(username: "camilo", password: "1")
        XCTAssertEqual(vault.token, token)
    }

    @MainActor func testPersistentLoginRestoresInNewClientAndManualLogoutClearsIt() async throws {
        let vault = MemorySession(), client = makeClient(vault)
        MockProtocol.handler = { request in
            let body = try JSONSerialization.jsonObject(with: MockProtocol.requestBody(request)) as! [String: Any]
            XCTAssertEqual(body["keepSignedIn"] as? Bool, true)
            XCTAssertEqual(body["username"] as? String, "fixture")
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Set-Cookie": "__Host-jac_session=\(self.token); Path=/; HttpOnly; Secure; SameSite=Lax"])!, Data("{\"ok\":true}".utf8))
        }
        try await client.login(username: " fixture ", password: "local-only", keepSignedIn: true)
        XCTAssertEqual(vault.token, token)
        let reopened = makeClient(vault)
        XCTAssertTrue(try reopened.hasSession())
        MockProtocol.handler = { request in
            XCTAssertEqual(request.value(forHTTPHeaderField: "Cookie"), "__Host-jac_session=\(self.token)")
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, Data("{\"ok\":true}".utf8))
        }
        try await reopened.noticeCommand(.object(["action": .string("read"), "id": .string("fixture")]))
        try await reopened.logout()
        XCTAssertFalse(try client.hasSession()); XCTAssertFalse(try reopened.hasSession())
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
        let hub = JACNotifications(pushAvailable: true, registerRemote: {}, unregisterRemote: {})
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
        let cache = OfflineResponseCache(root: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        defer { try? FileManager.default.removeItem(at: cache.root) }
        let scope = OfflineResponseCache.scope(origin: base.absoluteString, token: token)
        try cache.save(OfflineResponse(key: "test", url: base.absoluteString, headers: [:], data: Data("fixture".utf8), receivedAt: Date(), revision: 1), scope: scope)
        XCTAssertEqual(try FileManager.default.attributesOfItem(atPath: cache.file(scope, key: "test").path)[.protectionKey] as? FileProtectionType, .complete)
        #endif
    }

    @MainActor func testBoardingDateParsingAndColombiaMidnight() throws {
        XCTAssertEqual(BoardingClock.today(try XCTUnwrap(CalendarClock.instant("2026-10-08T04:59:59Z"))),"2026-10-07")
        XCTAssertEqual(BoardingClock.today(try XCTUnwrap(CalendarClock.instant("2026-10-08T05:00:00Z"))),"2026-10-08")
        let at=try XCTUnwrap(CalendarClock.instant("2026-12-31T15:00:00Z"))
        XCTAssertEqual(BoardingClock.today(try XCTUnwrap(BoardingClock.filenameDate("Camilo 2 de enero.pdf",at:at))),"2027-01-02")
        XCTAssertEqual(BoardingClock.nextDay("2026-12-31"),"2027-01-01")
        XCTAssertEqual(BoardingClock.priorityDays("2026-10-07",hasToday:false),["2026-10-08","2026-10-07"])
        XCTAssertEqual(BoardingClock.priorityDays("2026-10-07",hasToday:true),["2026-10-07","2026-10-08"])
        XCTAssertEqual(BoardingClock.filenameDetails("Jhon Alex 16 de octubre 2026 Pereira-Bogotá.pdf"),BoardingFilenameDetails(passenger:"Jhon Alex",origin:"Pereira",destination:"Bogotá"))
        XCTAssertEqual(BoardingClock.filenameDetails("Camilo 16 de octubre Pereira-Bogota.PDF")?.passenger,"Camilo")
        XCTAssertNil(BoardingClock.filenameDetails("Camilo 16 de octubre Pereira-Bogota-Medellin.pdf"))
        XCTAssertNil(BoardingClock.filenameDate("Camilo 31 de abril 2026.pdf")); XCTAssertNil(BoardingClock.filenameDate("1 de octubre y 2 de octubre.pdf"))
    }
    @MainActor func testPrivateBoardingFeedHistoryAndManualContract() async throws {
        let client=UITestBackend.client(); let feed=try await client.notices(boarding:"current")
        XCTAssertEqual(feed.notices.filter { $0.travelDate == BoardingClock.today() }.count,2)
        XCTAssertEqual(feed.notices.count,4); let history=try await client.notices(boarding:"history"); XCTAssertEqual(history.notices.count,1)
        let reader=UITestBackend.client(reader:true); let otherFeed=try await reader.notices(boarding:"current"); XCTAssertTrue(otherFeed.notices.isEmpty)
        do { _ = try await reader.notice(id:"boarding-fixture-0"); XCTFail("Otro usuario no puede abrir un pase") } catch {}
        let vault=MemorySession(); vault.token=token; let sending=makeClient(vault)
        MockProtocol.handler = { request in let body=try JSONDecoder().decode(JSONValue.self,from:MockProtocol.requestBody(request)); XCTAssertEqual(body["kind"].text,"boarding_pass"); XCTAssertEqual(body["travelDate"].text,"2026-10-10"); XCTAssertEqual(body["recipients"].elements,[.string("recipient-fixture")]); return (HTTPURLResponse(url:request.url!,statusCode:200,httpVersion:nil,headerFields:nil)!,Data("{}".utf8)) }
        try await sending.publishNotice(id:UUID().uuidString.lowercased(),kind:"boarding_pass",title:"Pase ficticio",body:"",recipients:["recipient-fixture"],files:[NoticeUpload(filename:"10 de octubre.pdf",data:Data("%PDF-1.4 ficticio".utf8))],travelDate:"2026-10-10")
    }

    @MainActor func testBoardingDeletionUsesSeparateConfirmedCommandAndRevokesPrivateFile() async throws {
        let client=UITestBackend.client(); let feed=try await client.notices(boarding:"current"); let item=try XCTUnwrap(feed.notices.first)
        let file=try XCTUnwrap(item.files.first); try await client.deleteNotice(item); try await client.deleteNotice(item)
        let refreshed=try await client.notices(boarding:"current"); XCTAssertFalse(refreshed.notices.contains {$0.id == item.id})
        do { _ = try await client.noticeFile(item,file:file); XCTFail("Un pase eliminado no debe descargarse") } catch {}
    }

    @MainActor func testTravelContractsPreserveRevisionAndExpenseReviewIdentity() async throws {
        let vault=MemorySession();vault.token=token;let client=makeClient(vault)
        let item=try JSONDecoder().decode(JACNotice.self,from:Data("{\"id\":\"33333333-3333-4333-8333-333333333333\",\"kind\":\"itinerary\",\"title\":\"Ficticio\",\"body\":\"\",\"filename\":\"\",\"size\":0,\"createdAt\":\"2026-10-08T12:00:00Z\",\"read\":true,\"revision\":3,\"confirmed\":false}".utf8))
        var commands:[JSONValue]=[]
        MockProtocol.handler={ request in
            XCTAssertEqual(request.url?.host,"payroll.example.invalid");XCTAssertEqual(request.value(forHTTPHeaderField:"Origin"),self.base.absoluteString)
            let body=try JSONDecoder().decode(JSONValue.self,from:MockProtocol.requestBody(request));commands.append(body)
            return (HTTPURLResponse(url:request.url!,statusCode:200,httpVersion:nil,headerFields:nil)!,Data("{}".utf8))
        }
        try await client.confirmNotice(item);XCTAssertEqual(commands.last?["revision"].number,3);XCTAssertEqual(commands.last?["action"].text,"confirm")
        let requestID=UUID().uuidString.lowercased(),files=[NoticeUpload(filename:"Ficticio.pdf",data:Data("%PDF-1.4 fixture".utf8))]
        try await client.updateItinerary(item,requestID:requestID,title:item.title,body:"",summary:"Cambio de hora",files:files)
        XCTAssertEqual(commands.last?["requestId"].text,requestID);XCTAssertEqual(commands.last?["revision"].number,3)
        let expenseID=UUID().uuidString.lowercased();try await client.submitExpense(id:expenseID,concept:"Taxi ficticio",amount:25000,date:"2026-10-08",note:"",files:files)
        XCTAssertEqual(commands.last?["id"].text,expenseID);XCTAssertEqual(commands.last?["amount"].number,25000);XCTAssertEqual(commands.last?["files"].elements.count,1)
        let expense=try JSONDecoder().decode(TravelExpense.self,from:Data("{\"id\":\"\(expenseID)\",\"userId\":\"fixture\",\"name\":\"Ficticio\",\"concept\":\"Taxi\",\"amount\":25000,\"expenseDate\":\"2026-10-08\",\"note\":\"\",\"status\":\"pending\",\"version\":1,\"reviewNote\":\"\",\"periodId\":\"\",\"employeeId\":\"\",\"attachments\":[]}".utf8))
        try await client.reviewExpense(expense,approve:true,reason:"Validado",employeeID:"employee-fixture",periodID:"period-fixture")
        XCTAssertEqual(commands.last?["decision"].text,"approve");XCTAssertEqual(commands.last?["employeeId"].text,"employee-fixture");XCTAssertEqual(commands.last?["version"].number,1)
        let count=commands.count
        do { try await client.submitExpense(id:expenseID,concept:"Taxi",amount:1,date:"2026-10-08",note:"",files:[NoticeUpload(filename:"No.pdf",data:Data("invalid".utf8))]);XCTFail("Archivo inválido") } catch {}
        XCTAssertEqual(commands.count,count,"Un archivo inválido no se envía")
    }

}
