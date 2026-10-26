#if os(iOS)
import XCTest
import CryptoKit
import AVFoundation
import VideoToolbox
import UIKit
@testable import JACNomina

@MainActor
final class MediaVideoPreparationTests: XCTestCase {
    func testIncomingFolderLinksAcceptOnlyTheJACShareRouteWithoutGrantingAnAccount() throws {
        let token = String(repeating: "a", count: 43)
        for value in ["https://jhonalexcastano.com/compartir/" + token, "jacnomina://compartir/" + token] {
            let share = try XCTUnwrap(MediaIncomingShare.parse(try XCTUnwrap(URL(string: value))))
            XCTAssertEqual(share.id, token)
            XCTAssertEqual(share.url.absoluteString, "https://jhonalexcastano.com/compartir/" + token)
        }
        for value in ["https://evil.invalid/compartir/" + token, "http://jhonalexcastano.com/compartir/" + token,
                      "jacnomina://gmail/" + token, "https://jhonalexcastano.com/compartir/" + token + "?other=1",
                      "https://jhonalexcastano.com/compartir/" + token + "/child", "jacnomina://compartir/short"] {
            XCTAssertNil(MediaIncomingShare.parse(try XCTUnwrap(URL(string: value))))
        }
    }
    private func staged(_ bytes: Data = MediaFixture.video, name: String = "Video.mov") throws -> MediaLocalFile {
        let document = try TemporaryDocuments.save(bytes, filename: name)
        defer { TemporaryDocuments.remove(document) }
        return try MediaLocalFile.stage(document.url, quality: .original)
    }

    func testPhotosKeepIdenticalBytes() async throws {
        let file = try staged(MediaFixture.photo, name: "Foto.png"); defer { file.remove() }
        let result = try await MediaVideoPreparation.prepare(file)
        XCTAssertEqual(result.file.url, file.url)
        XCTAssertNil(result.detail)
        XCTAssertEqual(try Data(contentsOf: result.file.url), MediaFixture.photo)
    }

    func testOriginalVideoKeepsItsURLUUIDNameFormatAndEveryByte() async throws {
        let file = try staged(); defer { file.remove() }
        let before = try Data(contentsOf: file.url)
        let result = try await MediaVideoPreparation.prepare(file)
        XCTAssertEqual(result.file.url, file.url)
        XCTAssertEqual(result.file.id, file.id)
        XCTAssertEqual(result.file.name, "Video.mov")
        XCTAssertEqual(result.file.mimeType, "video/quicktime")
        XCTAssertEqual(result.file.size, Int64(before.count))
        XCTAssertFalse(result.file.videoPrepared)
        XCTAssertEqual(result.detail, "Video original · Sin compresión")
        XCTAssertEqual(try Data(contentsOf: result.file.url), before)
    }

    func testInvalidVideoIsRejectedWithoutChangingTheSource() async throws {
        let bytes = Data("Ficticio, sin contenido audiovisual".utf8)
        let file = try staged(bytes); defer { file.remove() }
        do { _ = try await MediaVideoPreparation.prepare(file); XCTFail("No debe aceptar texto como video") }
        catch { XCTAssertFalse(error is CancellationError) }
        XCTAssertEqual(try Data(contentsOf: file.url), bytes)
    }

    func testCancelledPreparationLeavesSourceIntact() async throws {
        let file = try staged(); defer { file.remove() }
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await MediaVideoPreparation.prepare(file)
        }
        do { _ = try await task.value; XCTFail("La preparación cancelada no debe devolver un archivo para subir") }
        catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertEqual(try Data(contentsOf: file.url), MediaFixture.video)
    }

    func testLargeOriginalNeedsOnlyABoundedHeaderAndNoSecondVideoFile() async throws {
        let document = try TemporaryDocuments.save(Data([0,0,0,24]) + Data("ftypisom".utf8), filename: "Grande.mp4")
        defer { TemporaryDocuments.remove(document) }
        let handle = try FileHandle(forWritingTo: document.url)
        let count: Int64 = 4 * 1024 * 1024 * 1024
        try handle.truncate(atOffset: UInt64(count)); try handle.close()
        let file = MediaLocalFile(id: UUID().uuidString.lowercased(), url: document.url, name: "Grande.mp4", mimeType: "video/mp4", size: count)
        let before = try FileManager.default.contentsOfDirectory(atPath: document.url.deletingLastPathComponent().path)
        let result = try await MediaVideoPreparation.prepare(file)
        XCTAssertEqual(result.file.url, file.url); XCTAssertEqual(result.file.size, count)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: document.url.deletingLastPathComponent().path), before)
    }

    func testChangedSizeAndMismatchedFormatAreRejectedBeforeUpload() async throws {
        let file = try staged(); defer { file.remove() }
        for candidate in [MediaLocalFile(id: file.id, url: file.url, name: file.name, mimeType: file.mimeType, size: file.size + 1),
                          MediaLocalFile(id: file.id, url: file.url, name: file.name, mimeType: "video/webm", size: file.size)] {
            do { _ = try await MediaVideoPreparation.prepare(candidate); XCTFail("Debe rechazar datos cambiados") } catch { }
        }
    }

    func testMP4M4VAndWebMKeepTheirOriginalContainer() async throws {
        for (name, bytes) in [("Original.mp4", MediaFixture.video), ("Original.m4v", MediaFixture.video),
                              ("Original.webm", Data([0x1a,0x45,0xdf,0xa3,0,0,0,0]))] {
            let source = try staged(bytes, name: name); defer { source.remove() }
            let result = try await MediaVideoPreparation.prepare(source)
            XCTAssertEqual(result.file.url, source.url); XCTAssertEqual(result.file.mimeType, source.mimeType)
            XCTAssertEqual(result.file.name, name); XCTAssertEqual(try Data(contentsOf: result.file.url), bytes)
        }
    }

    func testHDRVideoKeepsItsOriginalCodecColorAndBytes() async throws {
        let fixture = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "SyntheticHDR", withExtension: "mp4"))
        let source = try MediaLocalFile.stage(fixture, quality: .original); defer { source.remove() }
        let original = try Data(contentsOf: source.url)
        let result = try await MediaVideoPreparation.prepare(source)
        XCTAssertEqual(result.file.url, source.url)
        XCTAssertEqual(try Data(contentsOf: result.file.url), original)
        let asset = AVURLAsset(url: result.file.url), tracks = try await asset.loadTracks(withMediaType: .video)
        let track = try XCTUnwrap(tracks.first)
        XCTAssertTrue(track.hasMediaCharacteristic(.containsHDRVideo))
        let formats = try await track.load(.formatDescriptions)
        XCTAssertEqual(formats.map { CMFormatDescriptionGetMediaSubType($0) }, [kCMVideoCodecType_HEVC])
    }

    func testVideoPlaybackUsesAnAudioCategoryThatIgnoresTheSilentSwitch() throws {
        let session = AVAudioSession.sharedInstance()
        let previousCategory = session.category, previousMode = session.mode, previousOptions = session.categoryOptions
        defer {
            MediaVideoAudioPlayback.deactivate()
            try? session.setCategory(previousCategory, mode: previousMode, options: previousOptions)
        }
        try MediaVideoAudioPlayback.activate()
        XCTAssertEqual(session.category, .playback)
        XCTAssertEqual(session.mode, .moviePlayback)
    }

}

@MainActor
final class MediaGridThumbnailLoaderTests: XCTestCase {
    func testVisibleCellAndPrefetchShareOneDownloadWhenTheCellLeaves() async throws {
        let loader = MediaGridThumbnailLoader(limit: 1)
        var reply: CheckedContinuation<Data, Error>?, downloads = 0
        let background = Task {
            try await loader.load(key: "same", authorized: { true }, priority: .prefetch, bytes: {
                downloads += 1
                return try await withCheckedThrowingContinuation { reply = $0 }
            })
        }
        try await waitFor { reply != nil }
        let visible = Task {
            try await loader.load(key: "same", authorized: { true }, bytes: { XCTFail("No debe duplicar una descarga en curso"); return MediaFixture.photo })
        }
        for _ in 0..<10 { await Task.yield() }
        visible.cancel()
        do { _ = try await visible.value; XCTFail("La celda retirada debe cancelar su espera") }
        catch { XCTAssertTrue(error is CancellationError) }
        reply?.resume(returning: MediaFixture.photo)
        let image = try await background.value
        let saved = try await loader.load(key: "same", authorized: { true }, bytes: { XCTFail(); return MediaFixture.photo })
        XCTAssertTrue(image === saved); XCTAssertEqual(downloads, 1)
    }
    func testVisibleWorkOvertakesQueuedBackgroundThumbnails() async throws {
        let loader = MediaGridThumbnailLoader(limit: 1)
        var reply: CheckedContinuation<Data, Error>?, order: [String] = []
        let first = Task {
            try await loader.load(key: "running", authorized: { true }, priority: .prefetch, bytes: {
                try await withCheckedThrowingContinuation { reply = $0 }
            })
        }
        try await waitFor { reply != nil }
        let background = Task {
            try await loader.load(key: "later", authorized: { true }, priority: .prefetch, bytes: { order.append("background"); return MediaFixture.photo })
        }
        for _ in 0..<10 { await Task.yield() }
        let visible = Task {
            try await loader.load(key: "visible", authorized: { true }, bytes: { order.append("visible"); return MediaFixture.photo })
        }
        for _ in 0..<10 { await Task.yield() }
        reply?.resume(returning: MediaFixture.photo)
        _ = try await first.value; _ = try await visible.value; _ = try await background.value
        XCTAssertEqual(order, ["visible", "background"])
    }
    func testCachedPixelsAreInstalledBeforeStartingAnotherCellTask() {
        let cell = MediaTileThumbnail(), image = UIImage()
        cell.show(key: "saved", authorized: { true }, cached: image,
                  load: { XCTFail("La imagen ya está decodificada"); return nil }, denied: { _ in XCTFail() })
        XCTAssertTrue(cell.image === image)
        cell.hide(); XCTAssertNil(cell.image)
    }
    func testReturningCellRestartsAfterCancellationAndUsesTheSameCachedPixels() async throws {
        let loader = MediaGridThumbnailLoader(), cell = MediaTileThumbnail()
        var downloads = 0
        func show() {
            cell.show(key: "same-revision", authorized: { true }, load: {
                try await loader.load(key: "session|same-revision", authorized: { true }, bytes: {
                    downloads += 1; return MediaFixture.photo
                })
            }, denied: { _ in XCTFail("No hay revocación en este recorrido") })
        }
        show()
        try await waitFor { cell.image != nil }
        let original = cell.image
        cell.hide(); XCTAssertNil(cell.image)
        show()
        try await waitFor { cell.image != nil }
        XCTAssertTrue(original === cell.image); XCTAssertEqual(downloads, 1)
    }
    func testLateCellCompletionCannotReplaceANewerRevisionOrRestoreAHiddenCell() async throws {
        let cell = MediaTileThumbnail(), old = UIImage(), current = UIImage()
        var reply: CheckedContinuation<UIImage?, Never>?
        cell.show(key: "old", authorized: { true }, load: {
            await withCheckedContinuation { reply = $0 }
        }, denied: { _ in XCTFail() })
        try await waitFor { reply != nil }
        cell.show(key: "new", authorized: { true }, load: { current }, denied: { _ in XCTFail() })
        try await waitFor { cell.image === current }
        reply?.resume(returning: old)
        for _ in 0..<10 { await Task.yield() }
        XCTAssertTrue(cell.image === current)
        var hiddenReply: CheckedContinuation<UIImage?, Never>?
        cell.show(key: "hidden", authorized: { true }, load: {
            await withCheckedContinuation { hiddenReply = $0 }
        }, denied: { _ in XCTFail() })
        try await waitFor { hiddenReply != nil }
        cell.hide(); hiddenReply?.resume(returning: old)
        for _ in 0..<10 { await Task.yield() }
        XCTAssertNil(cell.image); XCTAssertFalse(cell.visible)
    }
    func testTransientThumbnailFailureRetriesWithoutAnotherFolderRefresh() async throws {
        let cell = MediaTileThumbnail(); var attempts = 0
        cell.show(key: "ready-soon", authorized: { true }, load: {
            attempts += 1
            if attempts == 1 { throw MediaThumbnailUnavailable() }
            return UIImage()
        }, denied: { _ in XCTFail() })
        try await waitFor { cell.image != nil }
        XCTAssertEqual(attempts, 2); cell.hide()
    }
    func testOfflineReusesOnlyAlreadyAuthorizedSessionPixelsAndDenialClearsThem() async throws {
        let loader = MediaGridThumbnailLoader(); var reads = 0
        let image = try await loader.load(key: "saved", authorized: { true }, bytes: { reads += 1; return MediaFixture.photo })
        let offline = try await loader.load(key: "saved", authorized: { true }, allowNetwork: false, bytes: { reads += 1; return MediaFixture.photo })
        let absent = try await loader.load(key: "not-saved", authorized: { true }, allowNetwork: false, bytes: { reads += 1; return MediaFixture.photo })
        XCTAssertTrue(image === offline); XCTAssertNil(absent); XCTAssertEqual(reads, 1)
        do {
            _ = try await loader.load(key: "saved", authorized: { false }, allowNetwork: false, bytes: { XCTFail(); return MediaFixture.photo })
            XCTFail("Offline no permite ignorar una revocación")
        } catch { XCTAssertTrue(error is CancellationError) }
    }
    private func waitFor(_ predicate: () -> Bool) async throws {
        for _ in 0..<500 {
            if predicate() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("La miniatura no alcanzó el estado esperado")
        throw URLError(.timedOut)
    }
    func testReturningToTheSameRevisionReusesDecodedImageButAnotherRevisionLoads() async throws {
        let loader = MediaGridThumbnailLoader(); var count = 0
        let first = try await loader.load(key: "session|revision1", authorized: { true }, bytes: { count += 1; return MediaFixture.photo })
        let again = try await loader.load(key: "session|revision1", authorized: { true }, bytes: { count += 1; return MediaFixture.photo })
        XCTAssertNotNil(first); XCTAssertTrue(first === again); XCTAssertEqual(count, 1)
        _ = try await loader.load(key: "session|revision2", authorized: { true }, bytes: { count += 1; return MediaFixture.photo })
        XCTAssertEqual(count, 2)
    }
    func testThumbnailWorkIsBoundedWhenManyCellsAppearTogether() async throws {
        let loader = MediaGridThumbnailLoader(limit: 3); var active = 0; var maximum = 0
        let tasks = (0..<15).map { index in Task { @MainActor in
            try await loader.load(key: String(index), authorized: { true }, bytes: {
                active += 1; maximum = max(maximum, active); defer { active -= 1 }
                try await Task.sleep(for: .milliseconds(20)); return MediaFixture.photo
            })
        } }
        for task in tasks { let image = try await task.value; XCTAssertNotNil(image) }
        XCTAssertEqual(maximum, 3); XCTAssertEqual(active, 0)
    }
    func testLeavingTheViewportCancelsQueuedWorkAndDoesNotLeakCapacity() async throws {
        let loader = MediaGridThumbnailLoader(limit: 1); var entered = false; var unwanted = 0
        let first = Task { try await loader.load(key: "visible", authorized: { true }, bytes: {
            entered = true; try await Task.sleep(for: .milliseconds(80)); return MediaFixture.photo
        }) }
        while !entered { await Task.yield() }
        let cancelled = Task { try await loader.load(key: "gone", authorized: { true }, bytes: { unwanted += 1; return MediaFixture.photo }) }
        await Task.yield(); cancelled.cancel()
        do { _ = try await cancelled.value; XCTFail("Una celda retirada no debe iniciar una descarga pendiente") }
        catch { XCTAssertTrue(error is CancellationError) }
        _ = try await first.value
        let image = try await loader.load(key: "next", authorized: { true }, bytes: { MediaFixture.photo })
        XCTAssertNotNil(image); XCTAssertEqual(unwanted, 0)
    }
    func testRevocationRejectsCachedAndLateImagesWithoutFallback() async throws {
        let loader = MediaGridThumbnailLoader(); var authorized = true; var count = 0
        _ = try await loader.load(key: "private", authorized: { authorized }, bytes: { count += 1; return MediaFixture.photo })
        authorized = false
        do { _ = try await loader.load(key: "private", authorized: { authorized }, bytes: { count += 1; return MediaFixture.photo }); XCTFail("No se permite una copia de sesión revocada") }
        catch { XCTAssertTrue(error is CancellationError) }
        authorized = true
        do { _ = try await loader.load(key: "late", authorized: { authorized }, bytes: { authorized = false; return MediaFixture.photo }); XCTFail("La imagen tardía debe descartarse") }
        catch { XCTAssertTrue(error is CancellationError) }
        authorized = true
        _ = try await loader.load(key: "private", authorized: { authorized }, bytes: { count += 1; return MediaFixture.photo })
        XCTAssertEqual(count, 2)
    }
}

@MainActor
final class MediaUploadQueueTests: XCTestCase {
    func testThumbnailRetryKeepsTheLocalFileAndNeverUploadsTheOriginalTwice() async throws {
        let (main, _) = try await client()
        let location = root(), vault = QueueTestVault(), key = QueueTestVault()
        let source = try file()
        var originals = 0, covers = 0
        let queue = MediaUploadQueue(root: location, vault: vault, encryptionKeyStore: key,
            transportFactory: { _, _ in nil }, retryDelays: [], original: { _, _, _, _, _ in originals += 1; return "r2" },
            thumbnail: { _, file in
                covers += 1
                XCTAssertEqual(try Data(contentsOf: file.url), MediaFixture.photo)
                if covers == 1 { throw APIError.message("Miniatura pendiente ficticia") }
            })
        defer { queue.revoke(); source.remove(); try? FileManager.default.removeItem(at: location) }
        try await queue.enqueue([source], destination: folder, client: main)
        try await waitFor("El error de miniatura debe dejar pendiente el trabajo") { queue.jobs.first?.error != nil && !queue.uploading }
        XCTAssertEqual(originals, 1); XCTAssertFalse(queue.jobs[0].completed)
        XCTAssertEqual(queue.jobs[0].progress, 0.99)
        queue.retry()
        try await waitFor("El reintento debe completar únicamente la miniatura") { queue.jobs.first?.completed == true && !queue.uploading }
        XCTAssertEqual(originals, 1); XCTAssertEqual(covers, 2)
    }

    func testOriginalVideoEntersTheDurableQueueWithoutConversion() async throws {
        let (main, _) = try await client()
        let location = root(), vault = QueueTestVault(), key = QueueTestVault()
        let queue = MediaUploadQueue(root: location, vault: vault, encryptionKeyStore: key, transportFactory: { _, _ in nil }, automaticallyStart: false)
        let document = try TemporaryDocuments.save(MediaFixture.video, filename: "Sin comprimir.mov")
        defer { TemporaryDocuments.remove(document) }
        let source = try MediaLocalFile.stage(document.url, quality: .original)
        defer { queue.revoke(); source.remove(); try? FileManager.default.removeItem(at: location) }
        try await queue.enqueue([source], destination: folder, client: main)
        let job = try XCTUnwrap(queue.jobs.first)
        XCTAssertEqual(job.id, source.id); XCTAssertEqual(job.name, source.name)
        XCTAssertEqual(job.mimeType, "video/quicktime"); XCTAssertEqual(job.size, source.size)
        let adopted = location.appendingPathComponent("files").appendingPathComponent(job.id).appendingPathComponent(job.sourceName)
        XCTAssertEqual(try Data(contentsOf: adopted), MediaFixture.video)
        XCTAssertFalse(FileManager.default.fileExists(atPath: source.url.path))
    }
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
