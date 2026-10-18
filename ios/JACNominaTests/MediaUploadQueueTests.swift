#if os(iOS)
import XCTest
import CryptoKit
@testable import JACNomina

@MainActor
final class MediaUploadQueueTests: XCTestCase {
    private func waitFor(_ message: String, file: StaticString = #filePath, line: UInt = #line, _ condition: () -> Bool) async throws {
        for _ in 0..<250 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail(message, file: file, line: line)
        throw QueueTestFailure.timeout
    }
    private func root() -> URL { FileManager.default.temporaryDirectory.appendingPathComponent("upload-queue-test-" + UUID().uuidString, isDirectory: true) }
    private let folder = MediaFolder(id: "r2_fixture-folder", name: "Carpeta privada ficticia")

    private func client(character: Character = "q", canUpload: Bool = true) async throws -> (PayrollClient, QueueTestVault) {
        let fixture = UITestBackend.client()
        var workspace = try await fixture.workspace()
        if !canUpload {
            var value = try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(workspace))
            value["user"]["isOwner"] = .bool(false)
            value["user"]["sections"] = .array([.string("media")])
            workspace = try value.decoded(PayrollWorkspace.self)
        }
        let vault = QueueTestVault(String(repeating: String(character), count: 43))
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [QueueRejectNetwork.self]
        let client = PayrollClient(baseURL: URL(string: "https://upload-queue-test.invalid")!, vault: vault, configuration: config, automaticallyDownloadOffline: false)
        client.rememberWorkspace(workspace)
        return (client, vault)
    }

    private func file(_ name: String = "Foto reservada.png") throws -> MediaLocalFile {
        let source = try TemporaryDocuments.save(MediaFixture.photo, filename: name)
        defer { TemporaryDocuments.remove(source) }
        return try MediaLocalFile.stage(source.url, quality: .original)
    }

    func testAdoptionIsEncryptedDurableAndRestoresTheSameUUIDAfterTemporaryCleanup() async throws {
        let (client, primaryVault) = try await client()
        let location = root(), vault = QueueTestVault(), key = QueueTestVault()
        let item = try file(), expected = try Data(contentsOf: item.url)
        let first = MediaUploadQueue(root: location, vault: vault, encryptionKeyStore: key, transportFactory: { _, _ in XCTFail("Un fixture no debe abrir una sesión real"); return nil }, automaticallyStart: false)
        let restored = MediaUploadQueue(root: location, vault: vault, encryptionKeyStore: key, transportFactory: { _, _ in nil }, original: { _, file, destination, transferred, progress in
            XCTAssertEqual(file.id, item.id)
            XCTAssertEqual(destination, self.folder.id)
            XCTAssertEqual(try Data(contentsOf: file.url), expected)
            transferred(file.size); progress(file.size, file.size)
            return nil
        }, thumbnail: { _, _ in XCTFail("La ruta de prueba no usa miniatura") })
        defer { first.revoke(); restored.revoke(); item.remove(); try? FileManager.default.removeItem(at: location) }

        try await first.enqueue([item], destination: folder, client: client)
        XCTAssertFalse(FileManager.default.fileExists(atPath: item.url.path), "El propietario pasa de la hoja a la cola durable")
        XCTAssertEqual(first.jobs.map(\.id), [item.id])
        let sealed = try Data(contentsOf: location.appendingPathComponent("manifest.sealed"))
        XCTAssertNil(sealed.range(of: Data(item.name.utf8)))
        XCTAssertNil(sealed.range(of: Data(try XCTUnwrap(vault.load()).utf8)))
        XCTAssertThrowsError(try JSONSerialization.jsonObject(with: sealed))
        XCTAssertEqual(try location.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup, true)
        TemporaryDocuments.clear()

        restored.bind(client)
        await restored.restore()
        try await waitFor("La copia durable debe subirse aunque se hayan limpiado los temporales") { restored.jobs.count == 1 && restored.jobs.allSatisfy(\.completed) && !restored.uploading }
        XCTAssertEqual(restored.jobs.map(\.id), [item.id])
        XCTAssertNil(try vault.load(), "Se retira la copia AFU al terminar")
        XCTAssertNil(try key.load())
        XCTAssertEqual(try primaryVault.load(), String(repeating: "q", count: 43), "La sesión principal no se cambia")
        XCTAssertFalse(FileManager.default.fileExists(atPath: location.appendingPathComponent("manifest.sealed").path))
    }

    func testOriginalPipelineContinuesWhileThumbnailWaitsAndBoundsRetainedBacklog() async throws {
        let (client, _) = try await client()
        let location = root(), vault = QueueTestVault(), key = QueueTestVault(), gate = QueuePipelineGate()
        let items = try (1...6).map { try file("Foto \($0).png") }
        let queue = MediaUploadQueue(root: location, vault: vault, encryptionKeyStore: key, transportFactory: { _, _ in nil },
            original: { _, file, _, transferred, progress in try await gate.original(file, transferred: transferred, progress: progress) },
            thumbnail: { _, file in try await gate.thumbnail(file) })
        defer { queue.stop(); gate.close(); queue.revoke(); items.forEach { $0.remove() }; try? FileManager.default.removeItem(at: location) }
        try await queue.enqueue(items, destination: folder, client: client)
        try await waitFor("Solo deben comenzar dos originales") { gate.originalCalls.count == 2 }
        XCTAssertTrue(queue.uploading)
        XCTAssertGreaterThan(queue.meter.rate(), 0)
        try gate.finishOriginal(items[0].id)
        try await waitFor("El siguiente original no espera a la miniatura") { gate.originalCalls.count == 3 && gate.thumbnailCalls.count == 1 }
        XCTAssertFalse(queue.jobs[0].completed, "El100% espera a su miniatura")
        XCTAssertEqual(queue.jobs[0].progress, 0.99)
        try gate.finishOriginal(items[1].id)
        try await waitFor("Debe ocupar el segundo turno con otro original") { gate.originalCalls.count == 4 }
        try gate.finishOriginal(items[2].id)
        try gate.finishOriginal(items[3].id)
        try await waitFor("Cuatro originales quedan esperando miniatura") { queue.jobs.filter { $0.progress == 0.99 }.count == 4 }
        try await Task.sleep(for: .milliseconds(30))
        XCTAssertEqual(gate.originalCalls.count, 4, "El atraso de miniaturas queda acotado a cuatro")
        XCTAssertEqual(gate.thumbnailCalls.count, 1, "Solo se prepara una miniatura a la vez")
        try gate.finishThumbnail(items[0].id)
        try await waitFor("Liberar una miniatura debe continuar la cola") { gate.originalCalls.count == 5 && gate.thumbnailCalls.count == 2 }
        XCTAssertTrue(queue.jobs[0].completed)
        XCTAssertEqual(queue.jobs[0].progress, 1)
    }

    func testAFileErrorDoesNotStopOtherFilesAndRetryKeepsItsUUIDAndBytes() async throws {
        let (client, _) = try await client()
        let location = root(), vault = QueueTestVault(), key = QueueTestVault()
        let bad = try file("Revisar.png"), good = try file("Correcta.png")
        let expected = try Data(contentsOf: bad.url)
        var failBad = true, calls: [String] = []
        let queue = MediaUploadQueue(root: location, vault: vault, encryptionKeyStore: key, transportFactory: { _, _ in nil }, retryDelays: [], original: { _, file, _, _, _ in
            calls.append(file.id)
            if file.id == bad.id {
                XCTAssertEqual(try Data(contentsOf: file.url), expected)
                if failBad { throw APIError.invalid("Error ficticio de un archivo") }
            }
            return nil
        }, thumbnail: { _, _ in XCTFail("No usa miniatura") })
        defer { queue.revoke(); bad.remove(); good.remove(); try? FileManager.default.removeItem(at: location) }
        try await queue.enqueue([bad, good], destination: folder, client: client)
        try await waitFor("El archivo correcto debe terminar y el otro conservar su error") { queue.jobs.first { $0.id == good.id }?.completed == true && queue.jobs.first { $0.id == bad.id }?.error != nil && !queue.uploading }
        XCTAssertEqual(calls.filter { $0 == bad.id }.count, 1)
        XCTAssertEqual(calls.filter { $0 == good.id }.count, 1)
        XCTAssertNotNil(try vault.load(), "Un pendiente conserva la credencial de cola")
        failBad = false
        queue.retry()
        try await waitFor("Reintentar debe reutilizar la misma copia sin repetir el archivo correcto") { queue.jobs.allSatisfy(\.completed) && !queue.uploading }
        XCTAssertEqual(calls.filter { $0 == bad.id }.count, 2)
        XCTAssertEqual(calls.filter { $0 == good.id }.count, 1)
        XCTAssertNil(try vault.load())
    }

    func testExplicitPauseSurvivesRelaunchUntilRetry() async throws {
        let (client, _) = try await client()
        let location = root(), vault = QueueTestVault(), key = QueueTestVault(), gate = QueuePipelineGate()
        let item = try file()
        let first = MediaUploadQueue(root: location, vault: vault, encryptionKeyStore: key, transportFactory: { _, _ in nil },
            original: { _, file, _, transferred, progress in try await gate.original(file, transferred: transferred, progress: progress) }, thumbnail: { _, _ in })
        var resumed: [String] = []
        let second = MediaUploadQueue(root: location, vault: vault, encryptionKeyStore: key, transportFactory: { _, _ in nil }, original: { _, file, _, _, _ in resumed.append(file.id); return nil }, thumbnail: { _, _ in })
        defer { first.stop(); gate.close(); first.revoke(); second.revoke(); item.remove(); try? FileManager.default.removeItem(at: location) }
        try await first.enqueue([item], destination: folder, client: client)
        try await waitFor("Debe haber un original activo antes de pausar") { gate.originalCalls.count == 1 }
        first.stop()
        gate.close()
        XCTAssertFalse(first.uploading)
        second.bind(client)
        await second.restore(background: true)
        await Task.yield()
        XCTAssertTrue(resumed.isEmpty, "Una reapertura no invalida la pausa explícita")
        XCTAssertFalse(second.uploading)
        second.retry()
        try await waitFor("El reintento explícito retoma el mismoUUID") { second.jobs.allSatisfy(\.completed) && !second.uploading }
        XCTAssertEqual(resumed, [item.id])
    }

    func testChangedSessionOrRemovedUploadPermissionPurgesOnlyTheOutbox() async throws {
        for reason in ["session", "permission"] {
            let (main, primaryVault) = try await client()
            let location = root(), vault = QueueTestVault(), key = QueueTestVault(), item = try file()
            let queue = MediaUploadQueue(root: location, vault: vault, encryptionKeyStore: key, transportFactory: { _, _ in nil }, automaticallyStart: false)
            defer { queue.revoke(); item.remove(); try? FileManager.default.removeItem(at: location) }
            try await queue.enqueue([item], destination: folder, client: main)
            let (changed, _) = try await client(character: reason == "session" ? "r" : "q", canUpload: reason != "permission")
            queue.bind(changed)
            XCTAssertTrue(queue.jobs.isEmpty)
            XCTAssertFalse(queue.uploading)
            XCTAssertNil(try vault.load())
            XCTAssertNil(try key.load())
            XCTAssertFalse(FileManager.default.fileExists(atPath: location.path))
            XCTAssertEqual(try primaryVault.load(), String(repeating: "q", count: 43))
        }
    }

    func testLockedPrimaryKeychainIsNotLogoutAndBackgroundRestoreCanContinue() async throws {
        let (main, primaryVault) = try await client()
        let location = root(), vault = QueueTestVault(), key = QueueTestVault(), item = try file()
        let first = MediaUploadQueue(root: location, vault: vault, encryptionKeyStore: key, transportFactory: { _, _ in nil }, automaticallyStart: false)
        var restoredIDs: [String] = []
        let second = MediaUploadQueue(root: location, vault: vault, encryptionKeyStore: key, transportFactory: { _, _ in nil }, original: { _, file, _, _, _ in restoredIDs.append(file.id); return nil }, thumbnail: { _, _ in })
        defer { primaryVault.locked = false; first.revoke(); second.revoke(); item.remove(); try? FileManager.default.removeItem(at: location) }
        try await first.enqueue([item], destination: folder, client: main)
        primaryVault.locked = true
        first.bind(main)
        XCTAssertEqual(first.jobs.map(\.id), [item.id])
        XCTAssertNotNil(try vault.load(), "ElAFU de la cola sigue disponible")
        // A system relaunch has no in-process foreground client yet.
        await second.restore(background: true)
        try await waitFor("El arranquebackground puede continuar con su credencialAFU") { second.jobs.count == 1 && second.jobs.allSatisfy(\.completed) && !second.uploading }
        XCTAssertEqual(restoredIDs, [item.id])
        XCTAssertNil(try vault.load())
    }

    func testForbiddenUploadPurgesFilesCredentialsAndPendingJobsWithoutFallback() async throws {
        let (main, primaryVault) = try await client()
        let location = root(), vault = QueueTestVault(), key = QueueTestVault(), item = try file()
        let queue = MediaUploadQueue(root: location, vault: vault, encryptionKeyStore: key, transportFactory: { _, _ in nil }, original: { _, _, _, _, _ in throw APIError.forbidden("Acceso retirado ficticio") }, thumbnail: { _, _ in XCTFail("No debe hacer miniaturas tras403") })
        defer { queue.revoke(); item.remove(); try? FileManager.default.removeItem(at: location) }
        try await queue.enqueue([item], destination: folder, client: main)
        try await waitFor("403 debe retirar la cola y sus temporalesdurables") { queue.jobs.isEmpty && queue.notice == "Acceso retirado ficticio" }
        XCTAssertFalse(queue.uploading)
        XCTAssertFalse(FileManager.default.fileExists(atPath: location.path))
        XCTAssertNil(try vault.load())
        XCTAssertNil(try key.load())
        XCTAssertEqual(try primaryVault.load(), String(repeating: "q", count: 43), "403 de módulo no equivale a cerrar sesión principal")
    }

    func testUnauthorizedUploadAlsoInvalidatesThePrimarySessionImmediately() async throws {
        let (main, primaryVault) = try await client()
        let location = root(), vault = QueueTestVault(), key = QueueTestVault(), item = try file()
        var invalidations = 0
        main.onSessionInvalidated = { invalidations += 1 }
        let queue = MediaUploadQueue(root: location, vault: vault, encryptionKeyStore: key, transportFactory: { _, _ in nil }, original: { _, _, _, _, _ in throw APIError.unauthorized }, thumbnail: { _, _ in XCTFail("No debe continuar tras401") })
        defer { queue.revoke(); item.remove(); try? FileManager.default.removeItem(at: location) }
        try await queue.enqueue([item], destination: folder, client: main)
        try await waitFor("401 debe invalidar también la sesión principal") { queue.jobs.isEmpty && invalidations > 0 }
        XCTAssertNil(try primaryVault.load())
        XCTAssertFalse(try main.hasSession())
        XCTAssertFalse(queue.uploading)
        XCTAssertNil(try vault.load())
        XCTAssertNil(try key.load())
        XCTAssertFalse(FileManager.default.fileExists(atPath: location.path))
    }

    func testFailedBatchAdoptionRestoresEveryStagedFileAndDoesNotKeepCredentials() async throws {
        let (main, _) = try await client()
        let location = root(), vault = QueueTestVault(), key = QueueTestVault(), item = try file()
        let expected = try Data(contentsOf: item.url)
        let duplicate = MediaLocalFile(id: item.id, url: item.url, name: "Duplicada.png", mimeType: item.mimeType, size: item.size)
        let queue = MediaUploadQueue(root: location, vault: vault, encryptionKeyStore: key, transportFactory: { _, _ in nil }, automaticallyStart: false)
        defer { queue.revoke(); item.remove(); try? FileManager.default.removeItem(at: location) }
        do { try await queue.enqueue([item, duplicate], destination: folder, client: main); XCTFail("Un lote con identidadduplicada no debe confirmarse") }
        catch { XCTAssertTrue(error is APIError) }
        XCTAssertEqual(try Data(contentsOf: item.url), expected, "El rollback devuelve el archivo a su propietario inicial")
        XCTAssertTrue(queue.jobs.isEmpty)
        XCTAssertNil(try vault.load())
        XCTAssertNil(try key.load())
        XCTAssertFalse(FileManager.default.fileExists(atPath: location.appendingPathComponent("manifest.sealed").path))
    }

    func testMalformedAuthenticatedManifestCannotReadAPathOutsideItsJob() async throws {
        let (main, _) = try await client()
        let location = root(), vault = QueueTestVault(), key = QueueTestVault(), item = try file()
        let first = MediaUploadQueue(root: location, vault: vault, encryptionKeyStore: key, transportFactory: { _, _ in nil }, automaticallyStart: false)
        defer { first.revoke(); item.remove(); try? FileManager.default.removeItem(at: location) }
        try await first.enqueue([item], destination: folder, client: main)
        let manifest = location.appendingPathComponent("manifest.sealed")
        let encryptionKey = SymmetricKey(data: try XCTUnwrap(Data(base64Encoded: XCTUnwrap(key.load()))))
        let original = try AES.GCM.open(AES.GCM.SealedBox(combined: Data(contentsOf: manifest)), using: encryptionKey)
        for source in ["..", "../outside.png", "nested/other.png"] {
            var value = try JSONDecoder().decode(JSONValue.self, from: original)
            var entries = value["jobs"].elements
            entries[0]["sourceName"] = .string(source)
            value["jobs"] = .array(entries)
            let malformed = try XCTUnwrap(AES.GCM.seal(JSONEncoder().encode(value), using: encryptionKey).combined)
            try malformed.write(to: manifest, options: .atomic)
            let second = MediaUploadQueue(root: location, vault: vault, encryptionKeyStore: key, transportFactory: { _, _ in XCTFail("No debe preparar transporte para un manifiesto inválido"); return nil }, original: { _, _, _, _, _ in XCTFail("No debe abrir una ruta fuera del trabajo"); return nil }, thumbnail: { _, _ in XCTFail("No debe preparar miniaturas") })
            second.bind(main)
            await second.restore()
            XCTAssertTrue(second.jobs.isEmpty)
            XCTAssertFalse(second.uploading)
            XCTAssertNotNil(second.notice)
        }
    }

    func testRestoreOfCommittedDoneManifestCleansPayloadAndCredentialsWithoutUploadingAgain() async throws {
        let (main, primaryVault) = try await client()
        let location = root(), vault = QueueTestVault(), key = QueueTestVault(), item = try file()
        let first = MediaUploadQueue(root: location, vault: vault, encryptionKeyStore: key, transportFactory: { _, _ in nil }, automaticallyStart: false)
        let second = MediaUploadQueue(root: location, vault: vault, encryptionKeyStore: key, transportFactory: { _, _ in XCTFail("Un lote ya confirmado no debe abrir transporte"); return nil }, original: { _, _, _, _, _ in XCTFail("No debe volver a subir originales ya confirmados"); return nil }, thumbnail: { _, _ in XCTFail("No debe repetir miniaturas confirmadas") })
        defer { first.revoke(); second.revoke(); item.remove(); try? FileManager.default.removeItem(at: location) }
        try await first.enqueue([item], destination: folder, client: main)
        let manifest = location.appendingPathComponent("manifest.sealed")
        let encryptionKey = SymmetricKey(data: try XCTUnwrap(Data(base64Encoded: XCTUnwrap(key.load()))))
        var value = try JSONDecoder().decode(JSONValue.self, from: AES.GCM.open(AES.GCM.SealedBox(combined: Data(contentsOf: manifest)), using: encryptionKey))
        var entries = value["jobs"].elements
        entries[0]["phase"] = .string("done")
        entries[0]["completed"] = .bool(true)
        entries[0]["progress"] = .number(1)
        value["jobs"] = .array(entries)
        try XCTUnwrap(AES.GCM.seal(JSONEncoder().encode(value), using: encryptionKey).combined).write(to: manifest, options: .atomic)
        XCTAssertTrue(FileManager.default.fileExists(atPath: location.appendingPathComponent("files").path))
        second.bind(main)
        await second.restore(background: true)
        XCTAssertEqual(second.jobs.map(\.id), [item.id])
        XCTAssertTrue(second.jobs.allSatisfy(\.completed))
        XCTAssertFalse(second.uploading)
        XCTAssertFalse(FileManager.default.fileExists(atPath: location.appendingPathComponent("files").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: manifest.path))
        XCTAssertNil(try vault.load())
        XCTAssertNil(try key.load())
        XCTAssertEqual(try primaryVault.load(), String(repeating: "q", count: 43))
    }
}

private enum QueueTestFailure: Error { case timeout }

private final class QueueTestVault: SessionStoring {
    private var token: String?
    var locked = false
    init(_ token: String? = nil) { self.token = token }
    func load() throws -> String? { if locked { throw APIError.message("Llavero bloqueado ficticio") }; return token }
    func save(_ token: String) throws { self.token = token }
    func clear() throws { token = nil }
}

private final class QueueRejectNetwork: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() { XCTFail("Las pruebas del motor no deben enviar peticiones de red"); client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL)) }
    override func stopLoading() {}
}

@MainActor private final class QueuePipelineGate {
    private var originals: [String: CheckedContinuation<String?, Error>] = [:]
    private var thumbnails: [String: CheckedContinuation<Void, Error>] = [:]
    private var closed = false
    private(set) var originalCalls: [String] = []
    private(set) var thumbnailCalls: [String] = []

    func original(_ file: MediaLocalFile, transferred: @escaping (Int64) -> Void, progress: @escaping (Int64, Int64) -> Void) async throws -> String? {
        guard !closed else { throw CancellationError() }
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.url.path))
        originalCalls.append(file.id)
        transferred(max(1, file.size / 2)); progress(file.size / 2, file.size)
        return try await withCheckedThrowingContinuation { continuation in originals[file.id] = continuation }
    }
    func thumbnail(_ file: MediaLocalFile) async throws {
        guard !closed else { throw CancellationError() }
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.url.path))
        thumbnailCalls.append(file.id)
        try await withCheckedThrowingContinuation { continuation in thumbnails[file.id] = continuation }
    }
    func finishOriginal(_ id: String) throws { try XCTUnwrap(originals.removeValue(forKey: id)).resume(returning: "r2") }
    func finishThumbnail(_ id: String) throws { try XCTUnwrap(thumbnails.removeValue(forKey: id)).resume(returning: ()) }
    func close() {
        closed = true
        let originals = self.originals, thumbnails = self.thumbnails
        self.originals = [:]; self.thumbnails = [:]
        originals.values.forEach { $0.resume(throwing: CancellationError()) }
        thumbnails.values.forEach { $0.resume(throwing: CancellationError()) }
    }
}
#endif
