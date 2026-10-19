#if os(iOS)
import XCTest
import CryptoKit
import AVFoundation
import VideoToolbox
import UIKit
@testable import JACNomina

@MainActor
final class MediaVideoPreparationTests: XCTestCase {
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

    func testSmallVideosAlwaysProduceACompressedMP4InsteadOfTheOriginal() async throws {
        let file = try staged(); defer { file.remove() }
        let result = try await MediaVideoPreparation.prepare(file); defer { result.file.remove() }
        XCTAssertNotEqual(result.file.url, file.url)
        XCTAssertEqual(result.file.mimeType, "video/mp4")
        XCTAssertTrue(result.file.videoPrepared)
        XCTAssertTrue(result.detail?.contains("MP4 para web") == true)
        XCTAssertEqual(try Data(contentsOf: file.url), MediaFixture.video)
    }

    func testInvalidVideoIsRejectedWithoutOriginalFallback() async throws {
        let bytes = Data("Ficticio, sin contenido audiovisual".utf8)
        let file = try staged(bytes); defer { file.remove() }
        do { _ = try await MediaVideoPreparation.prepare(file); XCTFail("No debe devolverse el original sin comprimir") }
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

    func testMP4ConversionPreservesPortraitAudioTimingAndUploadIdentity() async throws {
        let input = try staged(); defer { input.remove() }
        let asset = AVURLAsset(url: input.url)
        let duration = try await asset.load(.duration)
        let composition = AVMutableComposition()
        let videoTracks = try await asset.loadTracks(withMediaType: .video)
        let video = try XCTUnwrap(videoTracks.first)
        let composedVideo = try XCTUnwrap(composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid))
        try composedVideo.insertTimeRange(CMTimeRange(start: .zero, duration: duration), of: video, at: .zero)
        composedVideo.preferredTransform = CGAffineTransform(rotationAngle: .pi / 2)
        // Local generated PCM silence verifies a real audio track becomes AAC.
        let samples = Int(ceil(duration.seconds * 44100))
        let payload = Data(repeating: 0, count: samples * 2)
        var wav = Data("RIFF".utf8)
        func word<T: FixedWidthInteger>(_ value: T) { var little = value.littleEndian; withUnsafeBytes(of: &little) { wav.append(contentsOf: $0) } }
        word(UInt32(36 + payload.count)); wav.append(Data("WAVEfmt ".utf8))
        word(UInt32(16)); word(UInt16(1)); word(UInt16(1)); word(UInt32(44100)); word(UInt32(88200)); word(UInt16(2)); word(UInt16(16))
        wav.append(Data("data".utf8)); word(UInt32(payload.count)); wav.append(payload)
        let sound = try TemporaryDocuments.save(wav, filename: "Silencio ficticio.wav")
        defer { TemporaryDocuments.remove(sound) }
        let soundAsset = AVURLAsset(url: sound.url)
        let audioTracks = try await soundAsset.loadTracks(withMediaType: .audio)
        let soundTrack = try XCTUnwrap(audioTracks.first)
        let composedAudio = try XCTUnwrap(composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid))
        try composedAudio.insertTimeRange(CMTimeRange(start: .zero, duration: duration), of: soundTrack, at: .zero)
        let sourceURL = input.url.deletingLastPathComponent().appendingPathComponent("Con audio.mov")
        let session = try XCTUnwrap(AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetPassthrough))
        session.outputURL = sourceURL; session.outputFileType = .mov
        await session.export()
        XCTAssertEqual(session.status, .completed, session.error?.localizedDescription ?? "")
        let source = try MediaLocalFile.stage(sourceURL, quality: .original); defer { source.remove() }
        let original = try Data(contentsOf: source.url)
        let result = try await MediaVideoPreparation.prepare(source)
        defer { if result.file.url != source.url { result.file.remove() } }
        XCTAssertNotEqual(result.file.url, source.url, result.detail ?? "")
        XCTAssertEqual(result.file.id, source.id)
        XCTAssertEqual(result.file.name, "Con audio.mp4")
        XCTAssertEqual(result.file.mimeType, "video/mp4")
        XCTAssertTrue(result.file.size < source.size)
        XCTAssertTrue(result.detail?.contains("% menos") == true)
        XCTAssertEqual(try Data(contentsOf: source.url), original)
        let output = AVURLAsset(url: result.file.url)
        let outputVideos = try await output.loadTracks(withMediaType: .video)
        let outputAudio = try await output.loadTracks(withMediaType: .audio)
        XCTAssertEqual(outputVideos.count, 1); XCTAssertEqual(outputAudio.count, 1)
        let outVideo = try XCTUnwrap(outputVideos.first)
        let outSize = try await outVideo.load(.naturalSize)
        let outTransform = try await outVideo.load(.preferredTransform)
        let inSize = try await video.load(.naturalSize)
        let rect = CGRect(origin: .zero, size: outSize).applying(outTransform)
        XCTAssertEqual(abs(rect.width / rect.height), inSize.height / inSize.width, accuracy: 0.02)
        XCTAssertLessThanOrEqual(max(abs(rect.width), abs(rect.height)), 1280)
        XCTAssertTrue(result.file.videoPrepared)
        let outputDuration = try await output.load(.duration)
        XCTAssertEqual(outputDuration.seconds, duration.seconds, accuracy: 0.1)
        let formats = try await outVideo.load(.formatDescriptions)
        XCTAssertEqual(formats.map { CMFormatDescriptionGetMediaSubType($0) }, [kCMVideoCodecType_H264])
        let soundFormats = try await outputAudio[0].load(.formatDescriptions)
        XCTAssertEqual(soundFormats.map { CMFormatDescriptionGetMediaSubType($0) }, [kAudioFormatMPEG4AAC])
    }

    func testHDRVideoIsConvertedToSDRInsteadOfKeepingTheOriginal() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("HDR ficticio.mov")
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let settings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.hevc, AVVideoWidthKey: 128, AVVideoHeightKey: 96,
            AVVideoCompressionPropertiesKey: [AVVideoProfileLevelKey: kVTProfileLevel_HEVC_Main10_AutoLevel],
            AVVideoColorPropertiesKey: [AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_2020,
                AVVideoTransferFunctionKey: AVVideoTransferFunction_ITU_R_2100_HLG, AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_2020]
        ]
        guard writer.canApply(outputSettings: settings, forMediaType: .video) else { throw XCTSkip("El simulador no dispone de codificador HEVC Main10 para generar el fixture HDR") }
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange,
            kCVPixelBufferWidthKey as String: 128, kCVPixelBufferHeightKey as String: 96
        ])
        writer.add(input)
        XCTAssertTrue(writer.startWriting(), writer.error?.localizedDescription ?? "")
        writer.startSession(atSourceTime: .zero)
        for frame in 0..<12 {
            var retries = 0
            while !input.isReadyForMoreMediaData && retries < 500 { try await Task.sleep(for: .milliseconds(10)); retries += 1 }
            XCTAssertTrue(input.isReadyForMoreMediaData)
            var buffer: CVPixelBuffer?
            XCTAssertEqual(CVPixelBufferPoolCreatePixelBuffer(nil, try XCTUnwrap(adaptor.pixelBufferPool), &buffer), kCVReturnSuccess)
            let pixel = try XCTUnwrap(buffer)
            CVPixelBufferLockBaseAddress(pixel, [])
            for plane in 0..<CVPixelBufferGetPlaneCount(pixel) {
                let address = try XCTUnwrap(CVPixelBufferGetBaseAddressOfPlane(pixel, plane)).assumingMemoryBound(to: UInt16.self)
                let count = CVPixelBufferGetBytesPerRowOfPlane(pixel, plane) * CVPixelBufferGetHeightOfPlane(pixel, plane) / 2
                for index in 0..<count { address[index] = UInt16(plane == 0 ? 256 + frame * 8 : 512) << 6 }
            }
            CVPixelBufferUnlockBaseAddress(pixel, [])
            XCTAssertTrue(adaptor.append(pixel, withPresentationTime: CMTime(value: Int64(frame), timescale: 12)))
        }
        input.markAsFinished()
        await writer.finishWriting()
        XCTAssertEqual(writer.status, .completed, writer.error?.localizedDescription ?? "")
        let source = try MediaLocalFile.stage(url, quality: .original); defer { source.remove() }
        let sourceAsset = AVURLAsset(url: source.url)
        let sourceTracks = try await sourceAsset.loadTracks(withMediaType: .video)
        XCTAssertTrue(try XCTUnwrap(sourceTracks.first).hasMediaCharacteristic(.containsHDRVideo))
        let result = try await MediaVideoPreparation.prepare(source); defer { result.file.remove() }
        XCTAssertNotEqual(result.file.url, source.url)
        XCTAssertTrue(result.file.videoPrepared)
        let output = AVURLAsset(url: result.file.url)
        let tracks = try await output.loadTracks(withMediaType: .video)
        let track = try XCTUnwrap(tracks.first)
        XCTAssertFalse(track.hasMediaCharacteristic(.containsHDRVideo))
        let formats = try await track.load(.formatDescriptions)
        XCTAssertEqual(formats.map { CMFormatDescriptionGetMediaSubType($0) }, [kCMVideoCodecType_H264])
    }
}

@MainActor
final class MediaGridThumbnailLoaderTests: XCTestCase {
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
    func testUncompressedVideoCannotEnterTheUploadQueue() async throws {
        let (main, _) = try await client()
        let location = root(), vault = QueueTestVault(), key = QueueTestVault()
        let queue = MediaUploadQueue(root: location, vault: vault, encryptionKeyStore: key, transportFactory: { _, _ in nil }, automaticallyStart: false)
        let document = try TemporaryDocuments.save(MediaFixture.video, filename: "Sin comprimir.mov")
        defer { TemporaryDocuments.remove(document) }
        let source = try MediaLocalFile.stage(document.url, quality: .original)
        defer { queue.revoke(); source.remove(); try? FileManager.default.removeItem(at: location) }
        do { try await queue.enqueue([source], destination: folder, client: main); XCTFail("No debe enviar el original") }
        catch { XCTAssertFalse(error is CancellationError) }
        XCTAssertTrue(queue.jobs.isEmpty)
        XCTAssertEqual(try Data(contentsOf: source.url), MediaFixture.video)
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
