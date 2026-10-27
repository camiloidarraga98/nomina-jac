import XCTest
import UserNotifications
import AVFoundation
import ImageIO
import CryptoKit
import Security
import PDFKit
import CoreText
import CoreImage
import Vision
#if os(iOS)
import UIKit
@testable import JACNomina
#else
import AppKit
@testable import JACMac
#endif

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
    var locked = false
    func load() throws -> String? { if locked { throw APIError.message("Llavero bloqueado de prueba.") }; return token }
    func save(_ token: String) throws { self.token = token }
    func clear() throws { token = nil }
}
@MainActor private final class ScriptedUploadTransport: MediaUploadTransporting {
    var handler: ((URLRequest, Data, String) throws -> (Data, URLResponse))?
    var calls = 0
    func send(_ request: URLRequest, body: Data, key: String, progress: @escaping @MainActor (Int64) -> Void) async throws -> (Data, URLResponse) {
        calls += 1; progress(Int64(body.count)); return try handler!(request, body, key)
    }
    func cancelAll() {}
}
private struct DeniedMediaPhotosWriter:MediaPhotosWriting {
    @MainActor func authorize() async throws {throw APIError.invalid("Permiso de Fotos rechazado en prueba.")}
    @MainActor func save(_ document:ExportedDocument,item:MediaItem) async throws {XCTFail("No debe guardar sin autorización")}
}
@MainActor private final class SelectionMediaPhotosWriter: MediaPhotosWriting {
    var authorizeAction: (() throws -> Void)?
    var saved: [String: Data] = [:]
    var lastURL: URL?
    func authorize() async throws { try authorizeAction?() }
    func save(_ document: ExportedDocument, item: MediaItem) async throws { lastURL=document.url; saved[item.id] = try Data(contentsOf: document.url) }
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

private final class OfflinePersistenceGate: @unchecked Sendable {
    private let lock = NSLock(), releaseSignal = DispatchSemaphore(value: 0)
    private var enabled = false
    private var began = false
    private var remaining: Int
    init(maximumWaits: Int = .max) { remaining = maximumWaits }
    func enable() { lock.lock(); enabled = true; lock.unlock() }
    var entered: Bool { lock.lock(); defer { lock.unlock() }; return began }
    func waitBeforeWrite() {
        lock.lock(); let shouldWait = enabled && remaining > 0; if shouldWait { began = true; remaining -= 1 }; lock.unlock()
        if shouldWait { _ = releaseSignal.wait(timeout: .now() + 5) }
    }
    func release() { releaseSignal.signal() }
}

private final class BoardingCardTestReader: @unchecked Sendable {
    private let lock = NSLock()
    private let barrier = DispatchSemaphore(value: 0)
    private var released = false
    private var started = 0
    private var downloads = 0
    var extractionCount: Int { lock.lock(); defer { lock.unlock() }; return started }
    var downloadCount: Int { lock.lock(); defer { lock.unlock() }; return downloads }
    func downloaded() { lock.lock(); downloads += 1; lock.unlock() }
    func release() {
        lock.lock(); released = true; let waiting = started; lock.unlock()
        for _ in 0..<waiting { barrier.signal() }
    }
    func extract(_ bytes: Data, _ mime: String) throws -> BoardingCardDetails {
        lock.lock(); started += 1; let shouldWait = !released; lock.unlock()
        if shouldWait, barrier.wait(timeout: .now() + 5) != .success { throw URLError(.timedOut) }
        guard mime == "application/pdf" else { throw URLError(.cannotDecodeContentData) }
        let value = String(decoding: bytes, as: UTF8.self)
        if value.contains("BROKEN") { throw URLError(.cannotDecodeContentData) }
        if value.contains("SECOND") { return BoardingCardDetails(seat: "22B", departureTime: "00:30") }
        if value.contains("THIRD") { return BoardingCardDetails(seat: "33C", departureTime: "09:15") }
        return BoardingCardDetails(seat: "12A", departureTime: "18:45")
    }
}

#if os(iOS)
private final class RestartUploadProtocol: URLProtocol {
    static let lock=NSLock()
    static var count=0
    static func reset(){lock.lock();count=0;lock.unlock()}
    static func started()->Int{lock.lock();defer{lock.unlock()};return count}
    override class func canInit(with request:URLRequest)->Bool{true}
    override class func canonicalRequest(for request:URLRequest)->URLRequest{request}
    override func startLoading(){
        Self.lock.lock();Self.count += 1;let n=Self.count;Self.lock.unlock()
        if n == 1 {return}
        client?.urlProtocol(self,didReceive:HTTPURLResponse(url:request.url!,statusCode:200,httpVersion:nil,headerFields:nil)!,cacheStoragePolicy:.notAllowed)
        client?.urlProtocol(self,didLoad:Data("second-transfer".utf8));client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading(){}
}
#endif
private final class CRMDelayedProtocol:URLProtocol {
    static let lock=NSLock()
    static var held:CRMDelayedProtocol?
    override class func canInit(with request:URLRequest)->Bool{true}
    override class func canonicalRequest(for request:URLRequest)->URLRequest{request}
    override func startLoading(){
        guard request.url?.host?.hasSuffix(".invalid")==true else{client?.urlProtocol(self,didFailWithError:URLError(.unsupportedURL));return}
        if request.httpMethod == "POST" {respond(Data("{}".utf8))}
        else{Self.lock.lock();Self.held=self;Self.lock.unlock()}
    }
    func respond(_ data:Data){let response=HTTPURLResponse(url:request.url!,statusCode:200,httpVersion:nil,headerFields:["Content-Type":"application/json"])!;client?.urlProtocol(self,didReceive:response,cacheStoragePolicy:.notAllowed);client?.urlProtocol(self,didLoad:data);client?.urlProtocolDidFinishLoading(self)}
    static func pending()->CRMDelayedProtocol?{lock.lock();defer{lock.unlock()};return held}
    static func resetPending(){lock.lock();defer{lock.unlock()};held=nil}
    override func stopLoading(){}
}

private final class MediaDelayedProtocol: URLProtocol {
    private static let lock = NSLock()
    private static var reads: [MediaDelayedProtocol] = []
    static func reset() { lock.lock(); defer { lock.unlock() }; reads = [] }
    static func pending() -> [MediaDelayedProtocol] { lock.lock(); defer { lock.unlock() }; return reads }
    override class func canInit(with request: URLRequest) -> Bool { request.url?.host?.hasSuffix(".invalid") == true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() { Self.lock.lock(); Self.reads.append(self); Self.lock.unlock() }
    func respond(_ data: Data) {
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data); client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

private final class MediaDownloadChunkProtocol: URLProtocol, @unchecked Sendable {
    static let bytes = Data(repeating: 42, count: 1024 * 1024)
    private let lock = NSLock()
    private var stopped = false
    override class func canInit(with request: URLRequest) -> Bool { request.url?.host?.hasSuffix(".invalid") == true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let data = Self.bytes, midpoint = Self.bytes.count / 2
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "image/png", "Content-Length": String(data.count)])!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data.prefix(midpoint))
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.8) { [self] in
            lock.lock(); let cancelled = stopped; lock.unlock()
            guard !cancelled else { return }
            client?.urlProtocol(self, didLoad: data.suffix(data.count - midpoint))
            client?.urlProtocolDidFinishLoading(self)
        }
    }
    override func stopLoading() { lock.lock(); stopped = true; lock.unlock() }
}

private final class MediaDataGateProtocol:URLProtocol,@unchecked Sendable {
    static let bytes=Data(repeating:42,count:256*1024)
    private static let lock=NSLock()
    private static var held:MediaDataGateProtocol?
    private let stateLock=NSLock()
    private var stopped=false
    static func reset() {lock.lock();held=nil;lock.unlock()}
    static func complete() {lock.lock();let value=held;held=nil;lock.unlock();value?.finish()}
    override class func canInit(with request:URLRequest)->Bool {request.url?.host?.hasSuffix(".invalid")==true}
    override class func canonicalRequest(for request:URLRequest)->URLRequest {request}
    override func startLoading() {
        Self.lock.lock();Self.held=self;Self.lock.unlock()
        client?.urlProtocol(self,didReceive:HTTPURLResponse(url:request.url!,statusCode:200,httpVersion:nil,headerFields:["Content-Length":String(Self.bytes.count)])!,cacheStoragePolicy:.notAllowed)
        client?.urlProtocol(self,didLoad:Self.bytes.prefix(Self.bytes.count/2))
    }
    private func finish() {
        stateLock.lock();let cancelled=stopped;stateLock.unlock()
        guard !cancelled else {return}
        client?.urlProtocol(self,didLoad:Self.bytes.suffix(Self.bytes.count/2))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {stateLock.lock();stopped=true;stateLock.unlock()}
}

@MainActor private final class FakeMediaPhotosWriter: MediaPhotosWriting {
    var authorizations = 0
    var saved: [String] = []
    func authorize() async throws { authorizations += 1 }
    func save(_ document: ExportedDocument, item: MediaItem) async throws {
        XCTAssertTrue(FileManager.default.fileExists(atPath: document.url.path))
        if item.kind == "video" { throw APIError.invalid("Formato ficticio no admitido para probar fallo individual") }
        saved.append(item.id)
    }
}

final class PayrollClientTests: XCTestCase {
    func testWideWorkspaceNeedsUsableColumnsAndRespectsAccessibilityText() {
        XCTAssertFalse(JACWorkspaceLayout.phone(size: CGSize(width: 393, height: 759), accessibility: false).isWide)
        XCTAssertFalse(JACWorkspaceLayout.phone(size: CGSize(width: 667, height: 325), accessibility: false).isWide)
        let landscape = JACWorkspaceLayout.phone(size: CGSize(width: 900, height: 600), accessibility: false)
        XCTAssertTrue(landscape.isWide)
        XCTAssertGreaterThanOrEqual(landscape.contentWidth, 660, "El menú no puede dejar sin espacio a las dos columnas")
        XCTAssertFalse(JACWorkspaceLayout.phone(size: CGSize(width: 900, height: 600), accessibility: true).isWide)
        XCTAssertFalse(JACWorkspaceLayout.phone(size: CGSize(width: 900, height: 280), accessibility: false).isWide)
    }
    @MainActor func testOpenNoticeDocumentStampRejectsOtherAttachmentsNewRevisionAndLogout() async throws {
        let client = UITestBackend.client()
        _ = try await client.workspace()
        let feed = try await client.notices()
        let item = try XCTUnwrap(feed.notices.first(where: { $0.kind == "itinerary" }))
        let file = try XCTUnwrap(item.files.first)
        let stamp = try client.noticeDocumentAccessStamp(item, file: file)
        let document = try await client.itinerary(item)
        defer { TemporaryDocuments.remove(document); try? client.clearSession() }
        XCTAssertEqual(try client.noticeDocumentAccessStamp(item, file: file), stamp)
        XCTAssertTrue(try Data(contentsOf: document.url).starts(with: Data("%PDF-".utf8)))
        let baseline = JACPerformanceDiagnostics.snapshot()
        for _ in 0..<250 { XCTAssertEqual(client.noticeDocumentPresentationStamp(item, file: file), stamp) }
        let sample = JACPerformanceDiagnostics.snapshot().delta(from: baseline)
        for operation in [JACPerformanceDiagnostics.Operation.diskRead, .diskWrite, .keyDerivation, .jsonDecode, .jsonEncode, .sessionRead] {
            XCTAssertEqual(sample.count(operation, mainThread: true), 0, "Revalidar el panel visible no debe bloquear el desplazamiento con \(operation)")
        }
        let wrong = NoticeAttachment(id: "another-recipient-file", filename: file.filename, mimeType: file.mimeType, size: file.size)
        XCTAssertThrowsError(try client.noticeDocumentAccessStamp(item, file: wrong))
        try await client.updateItinerary(item, requestID: UUID().uuidString.lowercased(), title: item.title, body: "Actualización ficticia", summary: "Cambió la salida", files: [NoticeUpload(filename: "Nuevo.pdf", data: Data("%PDF-1.4 fixture actualizado".utf8))])
        let updated = try await client.notice(id: item.id), updatedFile = try XCTUnwrap(updated.files.first)
        XCTAssertGreaterThan(updated.revision ?? 1, item.revision ?? 1)
        XCTAssertThrowsError(try client.noticeDocumentAccessStamp(item, file: file))
        XCTAssertNotEqual(try client.noticeDocumentAccessStamp(updated, file: updatedFile), stamp)
        try client.clearSession()
        XCTAssertNil(client.noticeDocumentPresentationStamp(updated, file: updatedFile))
        XCTAssertThrowsError(try client.noticeDocumentAccessStamp(updated, file: updatedFile))
    }
    // Synthetic BCBP with fixed-width fields and deliberate trailing spaces.
    // It is not a real airline reservation or valid travel document.
    // Real JPEG bytes: CFNetwork sniffs the PNG fixture even when a mocked
    // response labels it image/jpeg. Match the production preview contract.
    private func photoPreviewJPEGFixture() throws -> Data {
        let source=try XCTUnwrap(CGImageSourceCreateWithData(MediaFixture.photo as CFData,nil))
        let image=try XCTUnwrap(CGImageSourceCreateImageAtIndex(source,0,nil))
        let data=NSMutableData()
        let destination=try XCTUnwrap(CGImageDestinationCreateWithData(data,"public.jpeg" as CFString,1,nil))
        CGImageDestinationAddImage(destination,image,[kCGImageDestinationLossyCompressionQuality:0.78] as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return data as Data
    }
    private var walletIATAFixture: String {
        "M1" + "DOE/TEST".padding(toLength:20,withPad:" ",startingAt:0) + "E" + "ABC123 " + "BOG" + "MDE" + "XX " + "00001" + "297" + "Y" + "001A" + "00001" + "1" + "00" + "   "
    }
    private var walletNoticeFixture: JSONValue {
        .object(["id":.string("wallet-private-fixture"),"kind":.string("boarding_pass"),"title":.string("Pase ficticio"),"body":.string(""),"filename":.string("Ficticio.pdf"),"size":.number(42),"createdAt":.string("2026-10-23T10:00:00Z"),"read":.bool(false),"revision":.number(2),"attachments":.array([.object(["id":.string("wallet-file"),"filename":.string("Ficticio.pdf"),"mimeType":.string("application/pdf"),"size":.number(42)])])])
    }
    private func boardingCardNoticeFixture(revision: Int = 2, files: [String] = ["FIRST"], boardingDetails: JSONValue? = nil) -> JSONValue {
        var fields: [String: JSONValue] = [
            "id": .string("card-private-fixture"), "kind": .string("boarding_pass"), "title": .string("Pases ficticios"), "body": .string(""),
            "filename": .string("Ficticio.pdf"), "size": .number(42), "createdAt": .string("2026-10-25T10:00:00Z"), "read": .bool(false), "revision": .number(Double(revision)),
            "attachments": .array(files.map { .object(["id": .string("card-" + $0), "filename": .string($0 + ".pdf"), "mimeType": .string("application/pdf"), "size": .number(42)]) })
        ]
        if let boardingDetails { fields["boardingDetails"] = boardingDetails }
        return .object(fields)
    }
    @MainActor private func waitForBoardingCard(_ condition: @MainActor () -> Bool) async -> Bool {
        let end = Date().addingTimeInterval(3)
        while Date() < end {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return condition()
    }
    private func fortyBoardingCardsFixture() throws -> Data {
        let items = (0..<40).map { index -> JSONValue in
            var value = boardingCardNoticeFixture(boardingDetails: .object(["seat": .string("14C"), "departureTime": .string("18:45"), "boardingTime": .string("17:45"), "airline": .string("Aerolínea ficticia")]))
            value["id"] = .string("scroll-card-\(index)"); return value
        }
        let encoder = JSONEncoder(); encoder.outputFormatting = .sortedKeys
        return try encoder.encode(JSONValue.object(["notices": .array(items), "nextCursor": .string(""), "users": .array([]), "settings": .object(["version": .number(1), "slackConnected": .bool(false), "appleConfigured": .bool(false), "webPublicKey": .string("")])]))
    }
    func testSessionProtectionFailureClassificationDoesNotHideRevocation() {
        XCTAssertTrue(SessionStoreFailure.isProtectedDataUnavailable(NSError(domain: NSOSStatusErrorDomain, code: Int(errSecInteractionNotAllowed))))
        XCTAssertFalse(SessionStoreFailure.isProtectedDataUnavailable(NSError(domain: NSOSStatusErrorDomain, code: Int(errSecItemNotFound))))
        XCTAssertFalse(SessionStoreFailure.isProtectedDataUnavailable(NSError(domain: NSOSStatusErrorDomain, code: Int(errSecAuthFailed))))
        XCTAssertFalse(SessionStoreFailure.isProtectedDataUnavailable(NSError(domain: "fixture.invalid", code: Int(errSecInteractionNotAllowed))))
        XCTAssertFalse(SessionStoreFailure.isProtectedDataUnavailable(APIError.unauthorized))
        XCTAssertFalse(SessionStoreFailure.isProtectedDataUnavailable(APIError.forbidden("Acceso retirado")))
        XCTAssertFalse(SessionStoreFailure.isProtectedDataUnavailable(APIError.message("Llavero bloqueado de prueba.")), "Never infer a protected-data exception from localized error text.")
    }
    @MainActor func testWarmFortyBoardingCardsPerformNoMainThreadIOCryptoOrJSON() async throws {
        let cache = OfflineResponseCache(root: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        let (client, _) = relaunchFixture(cache), cards = BoardingCardDetailsStore()
        defer { cards.cancelPending(); MockProtocol.handler = nil; try? client.clearSession(); try? FileManager.default.removeItem(at: cache.root) }
        client.rememberWorkspace(try await UITestBackend.client(downloadOffline: false).workspace())
        let bytes = try fortyBoardingCardsFixture()
        MockProtocol.handler = { request in
            XCTAssertEqual(request.url?.host, "ui-fixture.example.invalid"); XCTAssertEqual(request.url?.path, "/api/notices")
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!, bytes)
        }
        let feed = try await client.notices(boarding: "current")
        XCTAssertEqual(feed.notices.count, 40)
        for item in feed.notices { cards.load(item, file: try XCTUnwrap(item.files.first), client: client) }
        let baseline = JACPerformanceDiagnostics.snapshot()
        var ready = 0
        // Exercise the actual presentation path used by each visible card,
        // including its task key, canonical revision check and ready details.
        for _ in 0..<500 {
            for item in feed.notices {
                let file = item.files[0]
                if cards.presentationKey(item, file: file, client: client) != nil,
                   case .ready = cards.entry(item, file: file, client: client) { ready += 1 }
            }
        }
        let sample = JACPerformanceDiagnostics.snapshot().delta(from: baseline)
        XCTAssertEqual(ready, 20_000)
        for operation in [JACPerformanceDiagnostics.Operation.diskRead, .diskWrite, .keyDerivation, .jsonDecode, .jsonEncode, .sessionRead] {
            XCTAssertEqual(sample.count(operation, mainThread: true), 0, "Warm card render performed \(operation)")
        }
        JACPerformanceDiagnostics.reportHotPath(since: baseline)
    }
    @MainActor func testGalleryPinPresentationChecksEightyItemsWithoutMainThreadIOAndRejectsRevocation() async throws {
        let workspace = try await UITestBackend.client(downloadOffline: false).workspace()
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString), cache = MediaOfflineCache(root: root)
        let vault = MemorySession(); vault.token = token
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [MockProtocol.self]
        let client = PayrollClient(baseURL: base, vault: vault, configuration: config, mediaOffline: cache, automaticallyDownloadOffline: false)
        client.rememberWorkspace(workspace)
        let scope = try XCTUnwrap(client.mediaScope())
        let items = (0..<80).map { MediaItem(id: "pin-presentation-\($0)", name: "Fixture-\($0).png", mimeType: "image/png", kind: "image", size: Int64(MediaFixture.photo.count), modifiedAt: "fixture", thumbnailAvailable: true) }
        let source = try TemporaryDocuments.save(MediaFixture.photo, filename: "Fixture.png")
        defer { TemporaryDocuments.remove(source); try? client.clearSession(); try? FileManager.default.removeItem(at: root) }
        try cache.saveFile(source.url, item: items[0], scope: scope, preview: true)
        try cache.pinFile(items[0], scope: scope)
        try cache.saveFile(source.url, item: items[1], scope: scope, preview: true) // Available locally, but deliberately not pinned.
        let reopened = PayrollClient(baseURL: base, vault: vault, configuration: config, agendaCache: client.agendaCache, offlineCache: client.offlineCache, mediaOffline: cache, automaticallyDownloadOffline: false)
        let before = JACPerformanceDiagnostics.snapshot()
        var pinned: [String] = []
        for item in items { if await reopened.mediaPinnedForPresentation(item) { pinned.append(item.id) } }
        let sample = JACPerformanceDiagnostics.snapshot().delta(from: before)
        XCTAssertEqual(pinned, [items[0].id], "A cold offline client must read real pin status, including local-but-unpinned and unavailable items.")
        XCTAssertGreaterThanOrEqual(sample.count(.diskRead), 80, "The budget must observe the actual pin-cache probes, not merely an empty counter.")
        XCTAssertEqual(sample.count(.sessionRead), 0)
        XCTAssertEqual(sample.mainThreadExpensiveOperations, 0)
        var revoked = try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(workspace))
        revoked["user"]["isOwner"] = .bool(false); revoked["user"]["sections"] = .array([.string("calendar")])
        reopened.rememberWorkspace(try revoked.decoded(PayrollWorkspace.self))
        let denied = await reopened.mediaPinnedForPresentation(items[0]); XCTAssertFalse(denied)
        try client.clearSession()
        let loggedOut = await client.mediaPinnedForPresentation(items[0]); XCTAssertFalse(loggedOut)
    }
    #if os(iOS)
    @MainActor func testDecodedGalleryThumbnailsReuseEightyWarmImagesWithoutSessionReadsAndRejectRevocation() async throws {
        let workspace = try await UITestBackend.client(downloadOffline: false).workspace()
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let vault = MemorySession(); vault.token = token
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [MockProtocol.self]
        let client = PayrollClient(baseURL: base, vault: vault, configuration: config, mediaOffline: MediaOfflineCache(root: root), automaticallyDownloadOffline: false)
        client.rememberWorkspace(workspace)
        let loader = MediaGridThumbnailLoader()
        let items = (0..<80).map { MediaItem(id: "decoded-presentation-\($0)", name: "Fixture-\($0).png", mimeType: "image/png", kind: "image", size: Int64(MediaFixture.photo.count), modifiedAt: "fixture", thumbnailAvailable: true) }
        var requests = 0
        MockProtocol.handler = { request in
            XCTAssertEqual(request.url?.path, "/api/media/file")
            let parts = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)
            XCTAssertEqual(parts?.queryItems?.first { $0.name == "thumbnail" }?.value, "1")
            requests += 1
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "image/png"])!, MediaFixture.photo)
        }
        defer { MockProtocol.handler = nil; loader.clear(); try? client.clearSession(); try? FileManager.default.removeItem(at: root) }
        // Populate decoded memory through the real authenticated loader rather
        // than writing a fabricated cache key or supplying prebuilt pixels.
        for item in items { let image = try await loader.image(item, client: client); XCTAssertNotNil(image) }
        XCTAssertEqual(requests, 80)
        let baseline = JACPerformanceDiagnostics.snapshot()
        for item in items { let image = try await loader.image(item, client: client, priority: .prefetch); XCTAssertNotNil(image) }
        let sample = JACPerformanceDiagnostics.snapshot().delta(from: baseline)
        XCTAssertEqual(requests, 80, "Warm prefetch must reuse decoded pixels without another HTTP request.")
        XCTAssertEqual(sample.count(.sessionRead), 0)
        XCTAssertEqual(sample.mainThreadExpensiveOperations, 0)
        var revoked = try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(workspace))
        revoked["user"]["isOwner"] = .bool(false); revoked["user"]["sections"] = .array([.string("calendar")])
        client.rememberWorkspace(try revoked.decoded(PayrollWorkspace.self))
        do { _ = try await loader.image(items[0], client: client); XCTFail("Revoked photo access must reject decoded pixels.") } catch is CancellationError {}
        try client.clearSession()
        do { _ = try await loader.image(items[0], client: client); XCTFail("Logging out must reject decoded pixels.") } catch is CancellationError {}
        XCTAssertEqual(requests, 80)
    }
    #endif
    @MainActor func testUnrelatedCacheWritesKeepFortyWarmCardsOffMainThreadIO() async throws {
        let workspace = try await UITestBackend.client(downloadOffline: false).workspace()
        var workspaceValue = try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(workspace))
        workspaceValue["version"] = .number(Double(workspace.version + 1))
        let workspaceBytes = try JSONEncoder().encode(workspaceValue), noticeBytes = try fortyBoardingCardsFixture()
        let mediaBytes = try JSONEncoder().encode(MediaFeed(connected: true, canRead: true, canUpload: false, canConnect: false, root: nil, folder: nil, breadcrumbs: [], items: [], nextPageToken: nil))
        let cache = OfflineResponseCache(root: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        let (client, _) = relaunchFixture(cache), cards = BoardingCardDetailsStore()
        defer { cards.cancelPending(); MockProtocol.handler = nil; try? client.clearSession(); try? FileManager.default.removeItem(at: cache.root) }
        client.rememberWorkspace(workspace)
        MockProtocol.handler = { request in
            let bytes: Data
            switch request.url?.path {
            case "/api/notices": bytes = noticeBytes
            case "/api/mobile/payroll": bytes = workspaceBytes
            case "/api/media": bytes = mediaBytes
            default: throw URLError(.unsupportedURL)
            }
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!, bytes)
        }
        let feed = try await client.notices(boarding: "current")
        XCTAssertEqual(client.cachedNotices(boarding: "current")?.notices.map(\.id), feed.notices.map(\.id), "Equal-date cards preserve the server array order when restoring the cached feed.")
        for item in feed.notices { cards.load(item, file: item.files[0], client: client) }
        _ = try await client.workspace(forceNetwork: true) // New payroll revision, exactly the same permissions.
        _ = try await client.media(forceNetwork: true) // Another module also commits an encrypted response.
        let baseline = JACPerformanceDiagnostics.snapshot()
        var ready = 0
        for _ in 0..<500 {
            for item in feed.notices {
                if cards.presentationKey(item, file: item.files[0], client: client) != nil,
                   case .ready = cards.entry(item, file: item.files[0], client: client) { ready += 1 }
            }
        }
        XCTAssertEqual(ready, 20_000)
        XCTAssertEqual(JACPerformanceDiagnostics.snapshot().delta(from: baseline).mainThreadExpensiveOperations, 0, "Unrelated writes must not evict canonical cards and move decryption/JSON back into their render path.")
        XCTAssertEqual(client.cachedNotices(boarding: "current")?.notices.map(\.id), feed.notices.map(\.id))
        let original = try XCTUnwrap(feed.notices.first)
        var changed = boardingCardNoticeFixture(revision: 3, boardingDetails: .object(["seat": .string("22D"), "departureTime": .string("19:15"), "boardingTime": .string("18:15")]))
        changed["id"] = .string(original.id)
        let changedBytes = try JSONEncoder().encode(JSONValue.object(["item": changed]))
        MockProtocol.handler = { request in (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!, changedBytes) }
        let updated = try await client.notice(id: original.id)
        XCTAssertNil(cards.presentationKey(original, file: original.files[0], client: client))
        cards.load(updated, file: updated.files[0], client: client)
        XCTAssertEqual(cards.entry(updated, file: updated.files[0], client: client), .ready(BoardingCardDetails(seat: "22D", departureTime: "19:15", explicitBoardingTime: "18:15")))
        let afterChange = JACPerformanceDiagnostics.snapshot()
        for item in feed.notices.dropFirst() { XCTAssertNotNil(cards.presentationKey(item, file: item.files[0], client: client)) }
        XCTAssertEqual(JACPerformanceDiagnostics.snapshot().delta(from: afterChange).mainThreadExpensiveOperations, 0, "Updating one card must retain the other 39 canonical records.")
        MockProtocol.handler = { request in (HTTPURLResponse(url: request.url!, statusCode: 403, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!, Data("{\"error\":\"Acceso retirado\"}".utf8)) }
        do { _ = try await client.notices(boarding: "current"); XCTFail("Revocation still must invalidate all private cards.") } catch APIError.forbidden { }
        for item in feed.notices { XCTAssertNil(client.cachedNotice(item.id)); XCTAssertNil(cards.presentationKey(item, file: item.files[0], client: client)) }
    }
    @MainActor func testNoticeBatchPersistsOneIndexAndUnchangedPollDoesNotWriteOrPublish() async throws {
        let cache = OfflineResponseCache(root: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        let (client, _) = relaunchFixture(cache)
        defer { MockProtocol.handler = nil; try? client.clearSession(); try? FileManager.default.removeItem(at: cache.root) }
        client.rememberWorkspace(try await UITestBackend.client(downloadOffline: false).workspace())
        let bytes = try fortyBoardingCardsFixture()
        MockProtocol.handler = { request in (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!, bytes) }
        let baseline = JACPerformanceDiagnostics.snapshot()
        _ = try await client.notices(boarding: "current")
        let first = JACPerformanceDiagnostics.snapshot().delta(from: baseline)
        XCTAssertEqual(first.count(.indexWrite), 1, "A 40-card feed must commit its index once, rather than once per item.")
        XCTAssertEqual(first.count(.diskWrite), 42) // feed + 40 canonical notices + index
        XCTAssertEqual(first.count(.diskWrite, mainThread: true), 0)
        XCTAssertEqual(first.count(.diskRead, mainThread: true), 0)
        let revision = client.cacheRevision, beforeRepeat = JACPerformanceDiagnostics.snapshot()
        _ = try await client.notices(boarding: "current")
        let repeated = JACPerformanceDiagnostics.snapshot().delta(from: beforeRepeat)
        XCTAssertEqual(repeated.count(.diskWrite), 0, "An unchanged poll must retain the authenticated bytes/nonce already on disk.")
        XCTAssertEqual(repeated.count(.indexWrite), 0)
        XCTAssertEqual(client.cacheRevision, revision, "An unchanged response must not invalidate every visited workspace.")
        let reopened = OfflineResponseCache(root: cache.root), scope = try XCTUnwrap(client.offlineScope())
        XCTAssertEqual(reopened.entries(scope).filter { $0.url.contains("item=scroll-card-") }.count, 40)
    }
    func testOfflineBatchRejectsLateWritesAfterRevocationAndRemainsReadableOnRelaunch() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString), cache = OfflineResponseCache(root: root)
        defer { try? FileManager.default.removeItem(at: root) }
        let scope = OfflineResponseCache.scope(origin: "https://cache-budget.invalid", token: String(repeating: "x", count: 43))
        let records = (0..<40).map { OfflineResponse(key: "entry-\($0)", url: "https://cache-budget.invalid/api/notices?item=\($0)", headers: ["Content-Type": "application/json"], data: Data("{\"version\":2}".utf8), receivedAt: Date(), revision: 2) }
        let before = JACPerformanceDiagnostics.snapshot()
        XCTAssertTrue(try cache.saveBatch(records, scope: scope))
        XCTAssertEqual(JACPerformanceDiagnostics.snapshot().delta(from: before).count(.indexWrite), 1)
        let reopened = OfflineResponseCache(root: root)
        XCTAssertEqual(reopened.entries(scope).count, 40)
        XCTAssertEqual(reopened.load(scope, key: records[0].key)?.data, records[0].data)
        // A disconnected-calendar cleanup can match the very response that is
        // being saved. An identical replacement still must retain its file.
        try cache.saveBatch([records[0]], scope: scope, removing: { $0.key == records[0].key })
        XCTAssertEqual(reopened.load(scope, key: records[0].key)?.data, records[0].data)
        XCTAssertTrue(cache.entries(scope).contains { $0.key == records[0].key })
        let epoch = cache.epoch(scope)
        cache.clear(scope)
        XCTAssertThrowsError(try cache.saveBatch(records, scope: scope, expectedEpoch: epoch)) { XCTAssertTrue($0 is CancellationError) }
        XCTAssertTrue(cache.entries(scope).isEmpty)
        XCTAssertNil(reopened.load(scope, key: records[0].key), "A previously opened cache cannot keep serving a deleted private response.")
        XCTAssertTrue(try cache.saveBatch(records, scope: scope, expectedEpoch: cache.epoch(scope)), "A newly authorized operation can create a fresh copy.")
        let protectedEpoch = cache.epoch(scope)
        cache.remove(scope) { $0.key == records[0].key }
        XCTAssertThrowsError(try cache.saveBatch(records, scope: scope, expectedEpoch: protectedEpoch))
        XCTAssertNil(cache.load(scope, key: records[0].key))
        let beforeOverflow = cache.memoryChanges(scope, since: nil).revision
        for revision in 1...129 {
            let record = OfflineResponse(key: "journal-key", url: "https://cache-budget.invalid/api/notices?item=journal", headers: [:], data: Data("{\"version\":\(revision)}".utf8), receivedAt: Date(), revision: revision)
            try cache.save(record, scope: scope)
        }
        let overflow = cache.memoryChanges(scope, since: beforeOverflow)
        XCTAssertTrue(overflow.invalidatesAll, "A client older than the bounded change history must discard its typed values instead of treating missing history as unchanged.")
        let latest = cache.memoryChanges(scope, since: overflow.revision - 1)
        XCTAssertFalse(latest.invalidatesAll); XCTAssertEqual(latest.keys, Set(["journal-key"]))
        XCTAssertTrue(cache.memoryChanges(scope, since: overflow.revision).keys.isEmpty)
    }
    @MainActor func testOlderWorkspaceResponseCannotReplaceWarmNewerWorkspace() async throws {
        let fixture = try await UITestBackend.client(downloadOffline: false).workspace()
        var current = try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(fixture)); current["version"] = .number(14)
        let cache = OfflineResponseCache(root: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)), (client, _) = relaunchFixture(cache)
        defer { MockProtocol.handler = nil; try? client.clearSession(); try? FileManager.default.removeItem(at: cache.root) }
        MockProtocol.handler = { request in (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!, try JSONEncoder().encode(current)) }
        _ = try await client.workspace(forceNetwork: true)
        XCTAssertEqual(client.cachedWorkspace()?.version, 14)
        current["version"] = .number(13)
        do { _ = try await client.workspace(forceNetwork: true); XCTFail("A delayed older response must not replace a newer authorized workspace in RAM.") }
        catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertEqual(client.cachedWorkspace()?.version, 14)
        let scope = try XCTUnwrap(client.offlineScope()), entry = try XCTUnwrap(cache.entries(scope).first { $0.url.contains("workspace=1") })
        XCTAssertEqual(cache.load(scope, key: entry.key)?.revision, 14)
    }
    @MainActor func testNoticeFeedDenialInvalidatesWarmCanonicalCards() async throws {
        let cache = OfflineResponseCache(root: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        let (client, _) = relaunchFixture(cache), cards = BoardingCardDetailsStore()
        defer { cards.cancelPending(); MockProtocol.handler = nil; try? client.clearSession(); try? FileManager.default.removeItem(at: cache.root) }
        client.rememberWorkspace(try await UITestBackend.client(downloadOffline: false).workspace())
        let bytes = try fortyBoardingCardsFixture()
        MockProtocol.handler = { request in (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!, bytes) }
        let feed = try await client.notices(boarding: "current")
        for item in feed.notices { XCTAssertNotNil(client.cachedNotice(item.id)) }
        MockProtocol.handler = { request in (HTTPURLResponse(url: request.url!, statusCode: 403, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!, Data("{\"error\":\"Acceso retirado\"}".utf8)) }
        do { _ = try await client.notices(boarding: "current"); XCTFail("A denied feed must not use the warmed copy.") } catch APIError.forbidden { }
        for item in feed.notices {
            XCTAssertNil(client.cachedNotice(item.id))
            XCTAssertNil(cards.presentationKey(item, file: item.files[0], client: client))
        }
        let scope = try XCTUnwrap(client.offlineScope())
        XCTAssertFalse(cache.entries(scope).contains { $0.url.contains("/api/notices") })
    }
    @MainActor func testPendingNoticePersistenceCannotReturnAfterLogout() async throws {
        let gate = OfflinePersistenceGate(), root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let cache = OfflineResponseCache(root: root, beforeBatch: { gate.waitBeforeWrite() }), (client, _) = relaunchFixture(cache)
        defer { gate.release(); MockProtocol.handler = nil; try? client.clearSession(); try? FileManager.default.removeItem(at: root) }
        client.rememberWorkspace(try await UITestBackend.client(downloadOffline: false).workspace())
        let bytes = try fortyBoardingCardsFixture(), scope = try XCTUnwrap(client.offlineScope())
        MockProtocol.handler = { request in (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!, bytes) }
        gate.enable()
        let pending = Task { try await client.notices(boarding: "current") }
        let entered = await waitForBoardingCard { gate.entered }
        XCTAssertTrue(entered, "Hold the real request after its network response and before durable cache commit.")
        try client.clearSession(); gate.release()
        do { _ = try await pending.value; XCTFail("A completed response must not escape after logout while persistence was suspended.") }
        catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertTrue(cache.entries(scope).isEmpty)
        XCTAssertNil(client.cachedNotice("scroll-card-0")); XCTAssertNil(client.cachedWorkspace())
    }
    @MainActor func testConcurrentAgendaPersistenceMergesMonthsAndRejectsOlderPendingUpdate() async throws {
        let fixture = UITestBackend.client(downloadOffline: false), workspace = try await fixture.workspace(), feed = try await fixture.agenda(month: CalendarClock.month(Date()))
        let gate = OfflinePersistenceGate(maximumWaits: 1), root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let cache = AgendaOfflineCache(root: root, beforeSave: { gate.waitBeforeWrite() }), vault = MemorySession(); vault.token = token
        let client = makeClient(vault, cache: cache)
        client.rememberWorkspace(workspace)
        let store = PayrollStore(client: client), scope = try XCTUnwrap(client.agendaScope())
        defer { gate.release(); try? client.clearSession(); try? FileManager.default.removeItem(at: root) }
        func data(_ month: String, updatedAt: String) throws -> AgendaData {
            var value = try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(feed))
            value["month"] = .string(month); value["updatedAt"] = .string(updatedAt)
            return try value.decoded(AgendaData.self)
        }
        let nextMonth = try XCTUnwrap(CalendarClock.shift(feed.month, by: 1))
        let first = try data(feed.month, updatedAt: "2099-01-02T12:00:00.000Z")
        let second = try data(nextMonth, updatedAt: "2099-01-03T12:00:00.000Z")
        let older = try data(feed.month, updatedAt: "2099-01-01T12:00:00.000Z")
        gate.enable()
        let pendingFirst = Task { try await store.rememberAgendaInBackground(first, userID: workspace.user.id, scope: scope) }
        let entered = await waitForBoardingCard { gate.entered }
        XCTAssertTrue(entered, "Hold the first real encrypted write while another month arrives.")
        let pendingSecond = Task { try await store.rememberAgendaInBackground(second, userID: workspace.user.id, scope: scope) }
        let merged = await waitForBoardingCard { store.savedAgenda?.months.count == 2 }
        XCTAssertTrue(merged, "A pending month must participate in the next reservation before either write completes.")
        do { try await store.rememberAgendaInBackground(older, userID: workspace.user.id, scope: scope); XCTFail("An older same-month update must be rejected even while the newer update is awaiting persistence.") }
        catch { XCTAssertTrue(error is CancellationError) }
        gate.release()
        try await pendingFirst.value; try await pendingSecond.value
        XCTAssertEqual(Set(store.savedAgenda?.months.map { $0.data.month } ?? []), Set([feed.month, nextMonth]))
        XCTAssertEqual(store.cachedAgenda(month: feed.month, userID: workspace.user.id)?.data.updatedAt, first.updatedAt)
        XCTAssertEqual(store.cachedAgenda(month: nextMonth, userID: workspace.user.id)?.data.updatedAt, second.updatedAt)
        let durable = try XCTUnwrap(cache.load(scope)), memory = try XCTUnwrap(client.cachedAgenda())
        XCTAssertEqual(Set(durable.months.map { $0.data.month }), Set([feed.month, nextMonth]))
        XCTAssertEqual(Set(memory.months.map { $0.data.month }), Set([feed.month, nextMonth]))
        XCTAssertEqual(durable.month(feed.month)?.data.updatedAt, first.updatedAt)
        XCTAssertEqual(memory.month(feed.month)?.data.updatedAt, first.updatedAt)
        let reopened = PayrollStore(client: makeClient(vault, cache: cache))
        XCTAssertNotNil(reopened.cachedAgenda(month: feed.month, userID: workspace.user.id))
        XCTAssertNotNil(reopened.cachedAgenda(month: nextMonth, userID: workspace.user.id))
    }
    @MainActor func testWarmCalendarAndWorkspaceRenderDoNotReadSessionOrDecode() async throws {
        let fixture = UITestBackend.client(downloadOffline: false), workspace = try await fixture.workspace(), data = try await fixture.agenda(month: CalendarClock.month(Date()))
        let cache = OfflineResponseCache(root: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        let (client, _) = relaunchFixture(cache)
        defer { try? client.clearSession(); try? FileManager.default.removeItem(at: cache.root) }
        client.rememberWorkspace(workspace)
        let store = PayrollStore(client: client), scope = try XCTUnwrap(client.agendaScope())
        try await store.rememberAgendaInBackground(data, userID: workspace.user.id, scope: scope)
        XCTAssertNotNil(client.cachedWorkspace()); XCTAssertNotNil(client.cachedAgenda())
        let before = JACPerformanceDiagnostics.snapshot()
        var visible = 0
        for _ in 0..<500 {
            if client.cachedWorkspace() != nil, client.cachedAgenda() != nil, store.cachedAgenda(month: data.month, userID: workspace.user.id) != nil { visible += 1 }
        }
        let sample = JACPerformanceDiagnostics.snapshot().delta(from: before)
        XCTAssertEqual(visible, 500)
        XCTAssertEqual(sample.mainThreadExpensiveOperations, 0)
        try client.clearSession()
        XCTAssertNil(client.cachedWorkspace()); XCTAssertNil(client.cachedAgenda()); XCTAssertNil(store.cachedAgenda(month: data.month, userID: workspace.user.id))
    }
    @MainActor func testBoardingCardMessageMetadataDoesNotDownloadOriginalAndRevalidatesChanges() async throws {
        let cache = OfflineResponseCache(root: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        let (client, _) = relaunchFixture(cache), reader = BoardingCardTestReader(); reader.release()
        let store = BoardingCardDetailsStore(extract: { try reader.extract($0, $1) })
        defer { store.cancelPending(); try? client.clearSession(); try? FileManager.default.removeItem(at: cache.root) }
        client.rememberWorkspace(try await UITestBackend.client(downloadOffline: false).workspace())
        var current = boardingCardNoticeFixture(boardingDetails: .object(["seat": .string("14C"), "departureTime": .string("18:45"), "boardingTime": .string("18:05"), "airline": .string("Aerolínea de prueba")]))
        MockProtocol.handler = { request in
            XCTAssertEqual(request.url?.host, "ui-fixture.example.invalid")
            if request.url?.path == "/api/notices/file" {
                reader.downloaded()
                return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/pdf"])!, Data("%PDF-1.4\nFIRST\n%%EOF".utf8))
            }
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!, try JSONEncoder().encode(JSONValue.object(["item": current])))
        }
        let original = try await client.notice(id: "card-private-fixture"), file = try XCTUnwrap(original.files.first)
        let originalKey = try XCTUnwrap(store.key(original, file: file, client: client))
        store.load(original, file: file, client: client)
        XCTAssertEqual(store.entry(original, file: file, client: client), .ready(BoardingCardDetails(seat: "14C", departureTime: "18:45", explicitBoardingTime: "18:05", airline: "Aerolínea de prueba")))
        XCTAssertEqual(reader.downloadCount, 0); XCTAssertEqual(reader.extractionCount, 0, "Known message fields must be usable without reading the PDF.")
        current = boardingCardNoticeFixture(boardingDetails: .object(["seat": .string(""), "departureTime": .string("01:15"), "boardingTime": .string("00:10")]))
        let updated = try await client.notice(id: original.id), updatedFile = try XCTUnwrap(updated.files.first)
        store.revalidate()
        XCTAssertNil(store.key(original, file: file, client: client)); XCTAssertThrowsError(try client.boardingCodeAccessStamp(original, file: file))
        XCTAssertNotEqual(store.key(updated, file: updatedFile, client: client), originalKey, "Metadata changes must not reuse an old card, even if the document revision is unchanged.")
        store.load(updated, file: updatedFile, client: client)
        XCTAssertEqual(store.entry(updated, file: updatedFile, client: client), .ready(BoardingCardDetails(seat: "", departureTime: "01:15", explicitBoardingTime: "00:10")))
        XCTAssertEqual(reader.downloadCount, 0); XCTAssertEqual(reader.extractionCount, 0)
        try client.clearSession(); store.revalidate()
        XCTAssertNil(store.key(updated, file: updatedFile, client: client))
        XCTAssertEqual(store.entry(updated, file: updatedFile, client: client), .unavailable, "Structured data shares the original private notice's session and revocation boundary.")
    }
    @MainActor func testBoardingCardMessageMetadataKeepsPartialFieldsWhenExtractionFails() async throws {
        let cache = OfflineResponseCache(root: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        let (client, _) = relaunchFixture(cache), reader = BoardingCardTestReader(); reader.release()
        let store = BoardingCardDetailsStore(extract: { try reader.extract($0, $1) })
        defer { store.cancelPending(); try? client.clearSession(); try? FileManager.default.removeItem(at: cache.root) }
        client.rememberWorkspace(try await UITestBackend.client(downloadOffline: false).workspace())
        let partial: JSONValue = .object(["seat": .string("14C"), "boardingTime": .string("18:05"), "airline": .string("Aerolínea de prueba")])
        var current = boardingCardNoticeFixture(boardingDetails: partial), broken = true
        MockProtocol.handler = { request in
            XCTAssertEqual(request.url?.host, "ui-fixture.example.invalid")
            if request.url?.path == "/api/notices/file" {
                reader.downloaded()
                let file = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "file" }?.value ?? ""
                return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/pdf"])!, Data(("%PDF-1.4\n" + (broken ? "BROKEN" : file) + "\n%%EOF").utf8))
            }
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!, try JSONEncoder().encode(JSONValue.object(["item": current])))
        }
        let initial = try await client.notice(id: "card-private-fixture"), file = try XCTUnwrap(initial.files.first)
        store.load(initial, file: file, client: client)
        let partialReady = await waitForBoardingCard { store.entry(initial, file: file, client: client) == .ready(BoardingCardDetails(seat: "14C", explicitBoardingTime: "18:05", airline: "Aerolínea de prueba")) }
        XCTAssertTrue(partialReady, "A local PDF/OCR error must not hide validated message fields.")
        XCTAssertEqual(reader.extractionCount, 1); XCTAssertEqual(reader.downloadCount, 1)
        broken = false
        current = boardingCardNoticeFixture(revision: 3, boardingDetails: .object(["seat": .string(""), "boardingTime": .string("18:05")]))
        let updated = try await client.notice(id: initial.id), updatedFile = try XCTUnwrap(updated.files.first)
        store.load(updated, file: updatedFile, client: client)
        let merged = await waitForBoardingCard { store.entry(updated, file: updatedFile, client: client) == .ready(BoardingCardDetails(seat: "", departureTime: "18:45", explicitBoardingTime: "18:05")) }
        XCTAssertTrue(merged, "The PDF supplies only absent values and cannot replace an explicit unassigned seat or room time.")
        current = boardingCardNoticeFixture(revision: 4, files: ["FIRST", "SECOND"], boardingDetails: .object(["seat": .string("14C"), "departureTime": .string("18:45"), "boardingTime": .string("18:05")]))
        let multiple = try await client.notice(id: initial.id)
        XCTAssertNil(multiple.singleFileBoardingDetails, "One shared description cannot identify which of multiple attachments it describes.")
        for attachment in multiple.files { store.load(multiple, file: attachment, client: client) }
        let independentlyRead = await waitForBoardingCard {
            multiple.files.allSatisfy { attachment in
                let expected = attachment.id.hasSuffix("SECOND") ? BoardingCardDetails(seat: "22B", departureTime: "00:30") : BoardingCardDetails(seat: "12A", departureTime: "18:45")
                return store.entry(multiple, file: attachment, client: client) == .ready(expected)
            }
        }
        XCTAssertTrue(independentlyRead, "Per-file originals keep their own seat/time when a description cannot be assigned safely.")
        XCTAssertEqual(reader.extractionCount, 4); XCTAssertEqual(reader.downloadCount, 4)
    }
    @MainActor func testBoardingCardMetadataCachesEachFileAndBoundsConcurrentReads() async throws {
        let cache = OfflineResponseCache(root: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        let (client, _) = relaunchFixture(cache), reader = BoardingCardTestReader()
        let store = BoardingCardDetailsStore(extract: { try reader.extract($0, $1) })
        defer { reader.release(); store.cancelPending(); try? client.clearSession(); try? FileManager.default.removeItem(at: cache.root) }
        client.rememberWorkspace(try await UITestBackend.client(downloadOffline: false).workspace())
        let json = boardingCardNoticeFixture(files: ["FIRST", "SECOND", "THIRD"])
        MockProtocol.handler = { request in
            XCTAssertEqual(request.url?.host, "ui-fixture.example.invalid")
            if request.url?.path == "/api/notices/file" {
                reader.downloaded()
                let file = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "file" }?.value ?? ""
                return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/pdf"])!, Data(("%PDF-1.4\n" + file + "\n%%EOF").utf8))
            }
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!, try JSONEncoder().encode(JSONValue.object(["item": json])))
        }
        let item = try await client.notice(id: "card-private-fixture")
        XCTAssertEqual(item.files.count, 3)
        for file in item.files { store.load(item, file: file, client: client); store.load(item, file: file, client: client) }
        let twoStarted = await waitForBoardingCard { reader.extractionCount == 2 }
        XCTAssertTrue(twoStarted); XCTAssertEqual(reader.downloadCount, 2, "The third visible card must wait for one of the two active reads.")
        reader.release()
        let ready = await waitForBoardingCard { item.files.allSatisfy { if case .ready = store.entry(item, file: $0, client: client) { return true }; return false } }
        XCTAssertTrue(ready); XCTAssertEqual(reader.downloadCount, 3)
        for (file, details) in zip(item.files, [BoardingCardDetails(seat: "12A", departureTime: "18:45"), BoardingCardDetails(seat: "22B", departureTime: "00:30"), BoardingCardDetails(seat: "33C", departureTime: "09:15")]) {
            XCTAssertEqual(store.entry(item, file: file, client: client), .ready(details), "Attachments sharing a revision must not share their extracted values.")
        }
        _ = try await client.notice(id: item.id) // The unchanged 30-second feed refresh does not create another extraction scope.
        store.revalidate()
        for file in item.files { store.load(item, file: file, client: client) }
        await Task.yield()
        XCTAssertEqual(reader.downloadCount, 3); XCTAssertEqual(reader.extractionCount, 3, "Scrolling or reopening a known card must reuse its result.")
    }
    @MainActor func testBoardingCardMetadataRevocationAndNewRevisionNeverRestoreOldValues() async throws {
        let cache = OfflineResponseCache(root: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        let (client, _) = relaunchFixture(cache), reader = BoardingCardTestReader(); reader.release()
        let store = BoardingCardDetailsStore(extract: { try reader.extract($0, $1) })
        defer { store.cancelPending(); try? client.clearSession(); try? FileManager.default.removeItem(at: cache.root) }
        client.rememberWorkspace(try await UITestBackend.client(downloadOffline: false).workspace())
        var current = boardingCardNoticeFixture(), rejectFile = false, marker = "FIRST"
        MockProtocol.handler = { request in
            if request.url?.path == "/api/notices/file" {
                reader.downloaded()
                if rejectFile { return (HTTPURLResponse(url: request.url!, statusCode: 403, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!, Data("{\"error\":\"Pase retirado\"}".utf8)) }
                return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/pdf"])!, Data(("%PDF-1.4\n" + marker + "\n%%EOF").utf8))
            }
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!, try JSONEncoder().encode(JSONValue.object(["item": current])))
        }
        let original = try await client.notice(id: "card-private-fixture"), file = try XCTUnwrap(original.files.first)
        store.load(original, file: file, client: client)
        let firstReady = await waitForBoardingCard { store.entry(original, file: file, client: client) == .ready(BoardingCardDetails(seat: "12A", departureTime: "18:45")) }
        XCTAssertTrue(firstReady)
        rejectFile = true
        store.load(original, file: file, client: client, retry: true)
        let denied = await waitForBoardingCard { reader.downloadCount == 2 && client.cachedNotice(original.id) == nil }
        XCTAssertTrue(denied); store.revalidate()
        XCTAssertNil(store.key(original, file: file, client: client)); XCTAssertEqual(store.entry(original, file: file, client: client), .unavailable)
        for _ in 0..<3 { store.load(original, file: file, client: client) }
        await Task.yield(); XCTAssertEqual(reader.downloadCount, 2, "403 must not loop through invalidation and automatic retries or expose the saved document.")
        rejectFile = false; marker = "SECOND"; current = boardingCardNoticeFixture(revision: 3)
        let updated = try await client.notice(id: original.id), updatedFile = try XCTUnwrap(updated.files.first)
        store.load(updated, file: updatedFile, client: client)
        let newReady = await waitForBoardingCard { store.entry(updated, file: updatedFile, client: client) == .ready(BoardingCardDetails(seat: "22B", departureTime: "00:30")) }
        XCTAssertTrue(newReady); XCTAssertEqual(reader.downloadCount, 3)
        XCTAssertNil(store.key(original, file: file, client: client)); XCTAssertEqual(store.entry(original, file: file, client: client), .unavailable)
    }
    @MainActor func testBoardingCardMetadataDiscardsLateExtractionAfterLogout() async throws {
        let cache = OfflineResponseCache(root: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        let (client, vault) = relaunchFixture(cache), reader = BoardingCardTestReader()
        let store = BoardingCardDetailsStore(extract: { try reader.extract($0, $1) })
        defer { reader.release(); store.cancelPending(); try? client.clearSession(); try? FileManager.default.removeItem(at: cache.root) }
        let workspace = try await UITestBackend.client(downloadOffline: false).workspace()
        client.rememberWorkspace(workspace)
        let json = boardingCardNoticeFixture()
        MockProtocol.handler = { request in
            let document = request.url?.path == "/api/notices/file"
            if document { reader.downloaded() }
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": document ? "application/pdf" : "application/json"])!, document ? Data("%PDF-1.4\nFIRST\n%%EOF".utf8) : try JSONEncoder().encode(JSONValue.object(["item": json])))
        }
        let item = try await client.notice(id: "card-private-fixture"), file = try XCTUnwrap(item.files.first)
        let oldKey = try XCTUnwrap(store.key(item, file: file, client: client))
        store.load(item, file: file, client: client)
        let entered = await waitForBoardingCard { reader.extractionCount == 1 }
        XCTAssertTrue(entered)
        try client.clearSession(); store.revalidate(); reader.release()
        XCTAssertNil(store.key(item, file: file, client: client)); XCTAssertEqual(store.entry(item, file: file, client: client), .unavailable)
        vault.token = String(repeating: "f", count: 43); client.rememberWorkspace(workspace)
        let restored = try await client.notice(id: item.id), restoredFile = try XCTUnwrap(restored.files.first)
        XCTAssertNotEqual(store.key(restored, file: restoredFile, client: client), oldKey)
        XCTAssertEqual(store.entry(restored, file: restoredFile, client: client), .loading, "Even the same token and revision after logout cannot reuse a previous session's late result.")
        store.load(restored, file: restoredFile, client: client)
        let ready = await waitForBoardingCard { store.entry(restored, file: restoredFile, client: client) == .ready(BoardingCardDetails(seat: "12A", departureTime: "18:45")) }
        XCTAssertTrue(ready); XCTAssertEqual(reader.downloadCount, 2); XCTAssertEqual(reader.extractionCount, 2)
    }
    func testBoardingWalletPreservesExactIATAPayloadAndOriginalCrop() throws {
        let payload=walletIATAFixture,filter=try XCTUnwrap(CIFilter(name:"CIQRCodeGenerator"))
        filter.setValue(Data(payload.utf8),forKey:"inputMessage");filter.setValue("M",forKey:"inputCorrectionLevel")
        let output=try XCTUnwrap(filter.outputImage).transformed(by:CGAffineTransform(scaleX:10,y:10))
        let qr=try XCTUnwrap(CIContext(options:[.useSoftwareRenderer:true]).createCGImage(output,from:output.extent))
        let context=try XCTUnwrap(CGContext(data:nil,width:qr.width+80,height:qr.height+80,bitsPerComponent:8,bytesPerRow:0,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(gray:1,alpha:1));context.fill(CGRect(x:0,y:0,width:qr.width+80,height:qr.height+80));context.interpolationQuality = .none
        context.draw(qr,in:CGRect(x:40,y:40,width:qr.width,height:qr.height))
        let image=try XCTUnwrap(context.makeImage())
        let bytes=NSMutableData(),destination=try XCTUnwrap(CGImageDestinationCreateWithData(bytes,"public.png" as CFString,1,nil))
        CGImageDestinationAddImage(destination,image,nil);XCTAssertTrue(CGImageDestinationFinalize(destination))
        let codes=try BoardingCodeExtractor.extract(bytes as Data,mime:"image/png"),code=try XCTUnwrap(codes.first)
        XCTAssertEqual(codes.count,1);XCTAssertEqual(code.walletBarcode?.format,"PKBarcodeFormatQR")
        XCTAssertEqual(code.walletBarcode?.message,payload,"Do not trim or regenerate the airline's payload.")
        let request=VNDetectBarcodesRequest();try BoardingCodeExtractor.configure(request)
        try VNImageRequestHandler(cgImage:code.image,options:[:]).perform([request])
        XCTAssertEqual(request.results?.first?.payloadStringValue,payload,"The displayed original crop must still scan exactly.")
    }
    func testBoardingWalletRejectsUnsupportedOrLossyBarcodes() throws {
        let payload=walletIATAFixture
        for (symbology,format) in [(VNBarcodeSymbology.qr,"PKBarcodeFormatQR"),(.pdf417,"PKBarcodeFormatPDF417"),(.aztec,"PKBarcodeFormatAztec")] {
            XCTAssertEqual(BoardingWalletBarcode.extracted(symbology,message:payload),BoardingWalletBarcode(format:format,message:payload))
        }
        for count in 1...4 { XCTAssertNotNil(BoardingWalletBarcode(format:"PKBarcodeFormatQR",message:"M\(count)"+String(payload.dropFirst(2)))) }
        XCTAssertNil(BoardingWalletBarcode.extracted(.dataMatrix,message:payload));XCTAssertNil(BoardingWalletBarcode.extracted(.qr,message:nil))
        for message in ["https://boarding.example.invalid/flight",String(payload.prefix(59)),"M5"+String(payload.dropFirst(2))," "+payload,payload+"\n",payload+"é",payload+"\u{0000}","M1"+String(repeating:"A",count:4095)] {
            XCTAssertNil(BoardingWalletBarcode(format:"PKBarcodeFormatQR",message:message))
        }
        XCTAssertNotNil(BoardingWalletBarcode(format:"PKBarcodeFormatAztec",message:"M1"+String(repeating:"A",count:4094)))
        XCTAssertNil(BoardingWalletBarcode(format:"PKBarcodeFormatDataMatrix",message:payload))
    }
    @MainActor func testBoardingWalletUsesPrivateNetworkContractAndRejectsWrongPackages() async throws {
        let cache=OfflineResponseCache(root:FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        defer {try? FileManager.default.removeItem(at:cache.root)}
        let (client,_)=relaunchFixture(cache),workspace=try await UITestBackend.client(downloadOffline:false).workspace()
        client.rememberWorkspace(workspace)
        let item=try walletNoticeFixture.decoded(JACNotice.self),file=try XCTUnwrap(item.files.first)
        let source=Data("%PDF-fixture-only".utf8),hash=SHA256.hash(data:source).map {String(format:"%02x",$0)}.joined()
        let barcode=try XCTUnwrap(BoardingWalletBarcode(format:"PKBarcodeFormatQR",message:walletIATAFixture))
        let package=Data([0x50,0x4b,0x03,0x04])+Data("transport fixture; deliberately unsigned".utf8)
        var mime="application/vnd.apple.pkpass",responseBytes=package,requests=0
        MockProtocol.handler={request in
            requests += 1;XCTAssertEqual(request.url?.host,"ui-fixture.example.invalid");XCTAssertEqual(request.url?.path,"/api/notices/wallet")
            XCTAssertEqual(request.value(forHTTPHeaderField:"Cookie"),"__Host-jac_session="+String(repeating:"f",count:43))
            let headers:[String:String],data:Data
            if request.httpMethod == "POST" {
                XCTAssertEqual(request.value(forHTTPHeaderField:"Origin"),"https://ui-fixture.example.invalid")
                let sent=try JSONDecoder().decode(JSONValue.self,from:MockProtocol.requestBody(request))
                XCTAssertEqual(sent["action"].text,"create");XCTAssertEqual(sent["id"].text,item.id);XCTAssertEqual(sent["file"].text,file.id)
                XCTAssertEqual(sent["revision"].number,2);XCTAssertEqual(sent["sourceSha256"].text,hash)
                XCTAssertEqual(sent["barcode"]["format"].text,barcode.format);XCTAssertEqual(sent["barcode"]["message"].text,barcode.message)
                headers=["Content-Type":mime];data=responseBytes
            } else {headers=["Content-Type":"application/json"];data=Data("{\"configured\":true,\"version\":1,\"passTypeId\":\"pass.example.invalid.fixture\"}".utf8)}
            return (HTTPURLResponse(url:request.url!,statusCode:200,httpVersion:nil,headerFields:headers)!,data)
        }
        let status=try await client.boardingWalletStatus(item,file:file)
        let received=try await client.boardingWalletPass(item,file:file,sourceSha256:hash,barcode:barcode)
        XCTAssertTrue(status.configured);XCTAssertEqual(received,package)
        let scope=OfflineResponseCache.scope(origin:UITestBackend.base.absoluteString,token:String(repeating:"f",count:43))
        XCTAssertFalse(cache.entries(scope).contains {$0.url.contains("/api/notices/wallet")},"Do not persist Wallet status or signed packages in the offline cache.")
        let beforeInvalid=requests
        let wrongKind=try JSONValue.object(walletNoticeFixture.fields.merging(["kind":.string("itinerary")]) {_,new in new}).decoded(JACNotice.self)
        do {_ = try await client.boardingWalletPass(wrongKind,file:file,sourceSha256:hash,barcode:barcode);XCTFail("Only boarding passes may produce Wallet packages.")} catch {}
        let foreignFile=NoticeAttachment(id:"different-user-file",filename:"Other.pdf",mimeType:"application/pdf",size:42)
        do {_ = try await client.boardingWalletPass(item,file:foreignFile,sourceSha256:hash,barcode:barcode);XCTFail("An attachment outside this private notice must be rejected locally.")} catch {}
        do {_ = try await client.boardingWalletPass(item,file:file,sourceSha256:"not-a-source-hash",barcode:barcode);XCTFail("The hash must identify the exact analyzed original.")} catch {}
        XCTAssertEqual(requests,beforeInvalid)
        mime="application/pdf"
        do {_ = try await client.boardingWalletPass(item,file:file,sourceSha256:hash,barcode:barcode);XCTFail("PDFs are not signed Wallet packages.")} catch APIError.invalid {}
        mime="application/vnd.apple.pkpass";responseBytes=Data(repeating:0x50,count:1024*1024+1)
        do {_ = try await client.boardingWalletPass(item,file:file,sourceSha256:hash,barcode:barcode);XCTFail("Oversized packages must not reach PassKit.")} catch APIError.invalid {}
        responseBytes=Data("wrong zip format".utf8)
        do {_ = try await client.boardingWalletPass(item,file:file,sourceSha256:hash,barcode:barcode);XCTFail("Wrong package headers must not reach PassKit.")} catch APIError.invalid {}
        let beforeOffline=requests;client.beginOfflineRestore()
        do {_ = try await client.boardingWalletPass(item,file:file,sourceSha256:hash,barcode:barcode);XCTFail("Do not create passes from an offline copy.")} catch APIError.invalid {}
        XCTAssertEqual(requests,beforeOffline)
    }
    @MainActor func testBoardingWalletDenialAndChangedSessionRejectPrivatePass() async throws {
        let cache=OfflineResponseCache(root:FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        defer {try? FileManager.default.removeItem(at:cache.root)}
        let (client,vault)=relaunchFixture(cache),workspace=try await UITestBackend.client(downloadOffline:false).workspace()
        client.rememberWorkspace(workspace)
        let itemJSON=walletNoticeFixture,hash=String(repeating:"a",count:64)
        let barcode=try XCTUnwrap(BoardingWalletBarcode(format:"PKBarcodeFormatQR",message:walletIATAFixture))
        MockProtocol.handler={request in
            let wallet=request.url?.path == "/api/notices/wallet"
            return (HTTPURLResponse(url:request.url!,statusCode:wallet ? 403:200,httpVersion:nil,headerFields:["Content-Type":"application/json"])!,wallet ? Data("{\"error\":\"Revocado\"}".utf8):try JSONEncoder().encode(JSONValue.object(["item":itemJSON])))
        }
        let item=try await client.notice(id:"wallet-private-fixture"),file=try XCTUnwrap(item.files.first)
        let stamp=try client.boardingCodeAccessStamp(item,file:file)
        do {_ = try await client.boardingWalletPass(item,file:file,sourceSha256:hash,barcode:barcode);XCTFail("A denial must never use a downloaded copy.")} catch APIError.forbidden {}
        XCTAssertNil(client.cachedNotice(item.id));XCTAssertNotEqual(stamp,try client.boardingCodeAccessStamp(item,file:file))
        let package=Data([0x50,0x4b,0x03,0x04])+Data("late private fixture".utf8)
        MockProtocol.handler={request in
            vault.token=String(repeating:"r",count:43)
            return (HTTPURLResponse(url:request.url!,statusCode:200,httpVersion:nil,headerFields:["Content-Type":"application/vnd.apple.pkpass"])!,package)
        }
        do {_ = try await client.boardingWalletPass(item,file:file,sourceSha256:hash,barcode:barcode);XCTFail("A response from a previous login must not become a Wallet pass.")} catch is CancellationError {}
        XCTAssertFalse(cache.entries(OfflineResponseCache.scope(origin:UITestBackend.base.absoluteString,token:String(repeating:"f",count:43))).contains {$0.url.contains("/api/notices/wallet")})
    }
    @MainActor func testBoardingWalletConfirmedDetailsKeepExplicitBlanksAndSelectedLeg() async throws {
        let cache=OfflineResponseCache(root:FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        defer {try? FileManager.default.removeItem(at:cache.root)}
        let (client,_)=relaunchFixture(cache),workspace=try await UITestBackend.client(downloadOffline:false).workspace()
        client.rememberWorkspace(workspace)
        let item=try walletNoticeFixture.decoded(JACNotice.self),file=try XCTUnwrap(item.files.first)
        let firstLeg=String(walletIATAFixture.dropFirst(23).prefix(37))
        let secondLeg="DEF456 "+"MDE"+"BOG"+"XX "+"00002"+"297"+"Y"+"014B"+"00002"+"1"+"00"
        let message="M2"+String(walletIATAFixture.dropFirst(2).prefix(21))+firstLeg+secondLeg
        let barcode=try XCTUnwrap(BoardingWalletBarcode(format:"PKBarcodeFormatPDF417",message:message))
        let hash=String(repeating:"b",count:64),package=Data([0x50,0x4b,0x03,0x04])+Data("synthetic transport only".utf8)
        let confirmed=BoardingWalletDetails(passenger:" Paula Fixture ",origin:"Bogotá (BOG)",destination:"Medellín (MDE)",departureTime:"18:35",boardingTime:"17:55",seat:"")
        var sent:[JSONValue]=[]
        MockProtocol.handler={request in
            XCTAssertEqual(request.url?.path,"/api/notices/wallet");XCTAssertEqual(request.httpMethod,"POST")
            XCTAssertEqual(request.value(forHTTPHeaderField:"Origin"),"https://ui-fixture.example.invalid")
            sent.append(try JSONDecoder().decode(JSONValue.self,from:MockProtocol.requestBody(request)))
            return (HTTPURLResponse(url:request.url!,statusCode:200,httpVersion:nil,headerFields:["Content-Type":"application/vnd.apple.pkpass"])!,package)
        }
        let received=try await client.boardingWalletPass(item,file:file,sourceSha256:hash,barcode:barcode,legIndex:1,details:confirmed)
        XCTAssertEqual(received,package)
        XCTAssertEqual(sent[0]["legIndex"].number,1);XCTAssertEqual(sent[0]["barcode"]["message"].text,message)
        XCTAssertEqual(sent[0]["sourceSha256"].text,hash);XCTAssertEqual(sent[0]["revision"].number,2)
        XCTAssertEqual(Set(sent[0]["details"].fields.keys),Set(["passenger","origin","destination","departureTime","boardingTime","seat"]))
        XCTAssertEqual(sent[0]["details"]["passenger"].text,"Paula Fixture")
        XCTAssertEqual(sent[0]["details"]["departureTime"].text,"18:35");XCTAssertEqual(sent[0]["details"]["boardingTime"].text,"17:55")
        XCTAssertEqual(sent[0]["details"]["seat"].text,"","Removing a suggestion must stay an explicit blank.")
        _ = try await client.boardingWalletPass(item,file:file,sourceSha256:hash,barcode:barcode)
        XCTAssertNil(sent[1].fields["details"]);XCTAssertNil(sent[1].fields["legIndex"],"Existing callers retain their private transport contract.")
        let scope=OfflineResponseCache.scope(origin:UITestBackend.base.absoluteString,token:String(repeating:"f",count:43))
        XCTAssertFalse(cache.entries(scope).contains {$0.url.contains("/api/notices/wallet")})
    }
    @MainActor func testBoardingWalletFlightFieldsValidateBeforeAnyNetworkRequest() async throws {
        let blank=BoardingWalletDetails()
        XCTAssertNil(blank.validationMessage)
        let fields=try blank.walletRequestFields();XCTAssertEqual(fields.count,6)
        XCTAssertTrue(fields.values.allSatisfy {$0.text.isEmpty},"Missing source data must never be guessed from a JAC profile.")
        let seat=BoardingWalletDetails(seat:" 12a ");XCTAssertEqual(try seat.walletRequestFields()["seat"]?.text,"12A")
        let invalid=[BoardingWalletDetails(passenger:"Fixture\nOther"),BoardingWalletDetails(origin:String(repeating:"A",count:101)),BoardingWalletDetails(destination:"MDE\u{0000}"),BoardingWalletDetails(departureTime:"25:00"),BoardingWalletDetails(boardingTime:"8:30"),BoardingWalletDetails(departureTime:"18:99"),BoardingWalletDetails(seat:"12 A"),BoardingWalletDetails(seat:"1234567"),BoardingWalletDetails(seat:"0000")]
        let cache=OfflineResponseCache(root:FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        defer {try? FileManager.default.removeItem(at:cache.root)}
        let (client,_)=relaunchFixture(cache),workspace=try await UITestBackend.client(downloadOffline:false).workspace()
        client.rememberWorkspace(workspace)
        let item=try walletNoticeFixture.decoded(JACNotice.self),file=try XCTUnwrap(item.files.first)
        let barcode=try XCTUnwrap(BoardingWalletBarcode(format:"PKBarcodeFormatQR",message:walletIATAFixture))
        var requests=0
        MockProtocol.handler={request in requests += 1;throw APIError.invalid("Unexpected synthetic request")}
        for details in invalid {
            XCTAssertNotNil(details.validationMessage)
            do {_ = try await client.boardingWalletPass(item,file:file,sourceSha256:String(repeating:"a",count:64),barcode:barcode,legIndex:0,details:details);XCTFail("Invalid details must be rejected before transport.")} catch APIError.invalid {}
        }
        for leg in [-1,4] {
            do {_ = try await client.boardingWalletPass(item,file:file,sourceSha256:String(repeating:"a",count:64),barcode:barcode,legIndex:leg,details:blank);XCTFail("A leg outside the supported range must be rejected locally.")} catch APIError.invalid {}
        }
        XCTAssertEqual(requests,0)
    }
    @MainActor func testNativeNoticeRecipientsRefreshKeepsExplicitSelections() async throws {
        let camilo=NoticeUser(id:"fixture-owner",name:"Persona uno"),luisa=NoticeUser(id:"fixture-reader",name:"Persona dos"),andres=NoticeUser(id:"fixture-new",name:"Andrés ficticio",ready:false)
        let first=NoticeRecipientSelection.reconcile([],users:[camilo,luisa],initialized:false)
        XCTAssertEqual(first.selected,Set([camilo.id,luisa.id]));XCTAssertFalse(first.removed)
        var chosen=first.selected;chosen.remove(luisa.id)
        let added=NoticeRecipientSelection.reconcile(chosen,users:[camilo,luisa,andres],initialized:true)
        XCTAssertEqual(added.selected,Set([camilo.id]),"Refreshing must not reselect a previously unchecked person or select a new user.")
        XCTAssertFalse(added.removed)
        chosen=added.selected;chosen.insert(andres.id)
        let revoked=NoticeRecipientSelection.reconcile(chosen,users:[luisa,andres],initialized:true)
        XCTAssertEqual(revoked.selected,Set([andres.id]));XCTAssertTrue(revoked.removed,"The composer must ask the user to review a removed selected recipient before publishing.")
        let automatic=NoticeRecipientSelection.reconcile(revoked.selected,users:[luisa,andres],initialized:true,reviewRequired:revoked.reviewRequired)
        XCTAssertFalse(automatic.removed);XCTAssertTrue(automatic.reviewRequired,"A later automatic refresh must not dismiss the pending review.")
        let reviewed=NoticeRecipientSelection.reconcile(automatic.selected,users:[luisa,andres],initialized:true,reviewRequired:automatic.reviewRequired,reviewed:true)
        XCTAssertFalse(reviewed.reviewRequired);XCTAssertEqual(reviewed.selected,Set([andres.id]),"Acknowledging the refreshed list must not select other people.")
        let cache=OfflineResponseCache(root:FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        defer {try? FileManager.default.removeItem(at:cache.root)}
        let (client,vault)=relaunchFixture(cache),workspace=try await UITestBackend.client(downloadOffline:false).workspace()
        client.rememberWorkspace(workspace)
        var requests=0,late=false
        MockProtocol.handler={request in
            requests += 1;XCTAssertEqual(request.url?.path,"/api/notices/recipients");XCTAssertEqual(request.httpMethod,"GET")
            XCTAssertEqual(request.value(forHTTPHeaderField:"Cookie"),"__Host-jac_session="+String(repeating:"f",count:43))
            if late {vault.token=String(repeating:"r",count:43)}
            let json=JSONValue.object(["users":.array([.object(["id":.string(camilo.id),"name":.string(camilo.name),"ready":.bool(true)]),.object(["id":.string(andres.id),"name":.string(andres.name),"ready":.bool(false)])]),"boardingUsers":.array([.object(["id":.string(luisa.id),"name":.string(luisa.name)])])])
            return (HTTPURLResponse(url:request.url!,statusCode:200,httpVersion:nil,headerFields:["Content-Type":"application/json"])!,try JSONEncoder().encode(json))
        }
        let roster=try await client.noticeRecipients()
        XCTAssertEqual(roster.users.map(\.id),[camilo.id,andres.id]);XCTAssertEqual(roster.users.last?.ready,false)
        XCTAssertEqual(roster.boardingUsers.map(\.id),[luisa.id]);XCTAssertEqual(requests,1)
        let scope=OfflineResponseCache.scope(origin:UITestBackend.base.absoluteString,token:String(repeating:"f",count:43))
        XCTAssertFalse(cache.entries(scope).contains {$0.url.contains("/api/notices/recipients")},"Recipient lists are fresh reads, never an offline cache or a notice publication.")
        late=true
        do {_ = try await client.noticeRecipients();XCTFail("A roster from a previous login must not become a recipient selection.")} catch is CancellationError {}
        XCTAssertEqual(requests,2)
        client.beginOfflineRestore()
        do {_ = try await client.noticeRecipients();XCTFail("Do not use offline recipient lists to publish.")} catch APIError.invalid {}
        XCTAssertEqual(requests,2)
    }
    func testBoardingCodeCropsKeepOriginalQRAndPDF417PayloadAcrossPagesAndRotation() throws {
        let pdf=try XCTUnwrap(PDFDocument(data:UITestBackend.boardingCodePDF()))
        // Nonzero crop origin and rotation catch both PDF drawing and Vision's
        // bottom-left -> top-left conversion, not just centered QR detection.
        pdf.page(at:0)!.setBounds(CGRect(x:20,y:25,width:560,height:750),for:.cropBox)
        pdf.page(at:0)!.rotation=90
        let data=try XCTUnwrap(pdf.dataRepresentation())
        let codes=try BoardingCodeExtractor.extract(data,mime:"application/pdf")
        XCTAssertEqual(codes.count,2);XCTAssertEqual(codes.map(\.page),[1,2]);XCTAssertEqual(codes.map(\.format),["QR","PDF417"])
        for (index,code) in codes.enumerated() {
            let request=VNDetectBarcodesRequest()
            try BoardingCodeExtractor.configure(request)
            try VNImageRequestHandler(cgImage:code.image,options:[:]).perform([request])
            XCTAssertEqual(request.results?.first?.payloadStringValue,"JAC FICTICIO SIN VALIDEZ - CODIGO \(index+1)","The displayed crop must still scan as the original, including PDF417.")
        }
    }
    func testBoardingCodeAlsoReadsAnImageAndReportsNoCodeWithoutInventingOne() throws {
        let code=try XCTUnwrap(BoardingCodeExtractor.extract(UITestBackend.boardingCodePDF(),mime:"application/pdf").first)
        let bytes=NSMutableData(),destination=try XCTUnwrap(CGImageDestinationCreateWithData(bytes,"public.png" as CFString,1,nil))
        CGImageDestinationAddImage(destination,code.image,nil);XCTAssertTrue(CGImageDestinationFinalize(destination))
        XCTAssertEqual(try BoardingCodeExtractor.extract(bytes as Data,mime:"image/png").first?.format,"QR")
        let pdf=PDFDocument();pdf.insert(PDFPage(),at:0)
        XCTAssertTrue(try BoardingCodeExtractor.extract(XCTUnwrap(pdf.dataRepresentation()),mime:"application/pdf").isEmpty)
        XCTAssertThrowsError(try BoardingCodeExtractor.extract(Data("invalid".utf8),mime:"application/pdf"))
        XCTAssertThrowsError(try BoardingCodeExtractor.extract(Data(repeating:0,count:10*1024*1024+1),mime:"image/png"))
    }
    func testBoardingCodeExtractionHonorsCancellation() async {
        let task=Task.detached { () throws -> [BoardingCodeImage] in
            try? await Task.sleep(for:.milliseconds(100))
            return try BoardingCodeExtractor.extract(UITestBackend.boardingCodePDF(),mime:"application/pdf")
        }
        task.cancel()
        do {_ = try await task.value;XCTFail("Cancelled work must not install private pixels.")} catch is CancellationError {} catch {XCTFail("Unexpected error: \(error)")}
    }
    @MainActor func testBoardingBrightnessRestoresOnCloseBackgroundAndDisplayChange() {
        final class Screen:BoardingScreenBrightness {var brightness:CGFloat;init(_ value:CGFloat){brightness=value}}
        let screen=Screen(0.37),other=Screen(0.62),lease=BoardingBrightnessLease()
        lease.begin(screen);XCTAssertEqual(screen.brightness,1)
        lease.begin(screen);lease.end();XCTAssertEqual(screen.brightness,0.37)
        lease.end();XCTAssertEqual(screen.brightness,0.37)
        screen.brightness=0.21;lease.begin(screen);lease.end();XCTAssertEqual(screen.brightness,0.21)
        lease.begin(screen);lease.begin(other);XCTAssertEqual(screen.brightness,0.21);XCTAssertEqual(other.brightness,1)
        lease.end();XCTAssertEqual(other.brightness,0.62)
    }
    @MainActor func testBoardingDerivedCodeAccessIsInvalidatedByDeletionLogoutAndNewSession() async throws {
        let client=UITestBackend.client(),feed=try await client.notices(boarding:"current")
        let item=try XCTUnwrap(feed.notices.first),file=try XCTUnwrap(item.files.first)
        let stamp=try client.boardingCodeAccessStamp(item,file:file)
        let doc=try await client.noticeFile(item,file:file);defer {TemporaryDocuments.remove(doc)}
        XCTAssertEqual(stamp,try client.boardingCodeAccessStamp(item,file:file))
        try await client.deleteNotice(item)
        XCTAssertNotEqual(stamp,try client.boardingCodeAccessStamp(item,file:file))
        try client.clearSession();XCTAssertThrowsError(try client.boardingCodeAccessStamp(item,file:file))
        let other=UITestBackend.client(reader:true)
        XCTAssertNotEqual(stamp,try other.boardingCodeAccessStamp(item,file:file))
        do {_ = try await other.noticeFile(item,file:file);XCTFail("Another recipient must never receive the PDF or derived code.")} catch {}
    }
    @MainActor func testBoardingCodeUsesPrivateDownloadedPDFOfflineAndDenialRevokesItsStamp() async throws {
        let cache=OfflineResponseCache(root:FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        defer {try? FileManager.default.removeItem(at:cache.root)}
        let (client,_)=relaunchFixture(cache),pdf=try UITestBackend.boardingCodePDF()
        let itemJSON:JSONValue = .object(["id":.string("private-code-fixture"),"kind":.string("boarding_pass"),"title":.string("Ficticio"),"body":.string(""),"filename":.string("Ficticio.pdf"),"size":.number(Double(pdf.count)),"createdAt":.string("2026-10-17T10:00:00Z"),"read":.bool(false),"revision":.number(1),"attachments":.array([.object(["id":.string("fake-file"),"filename":.string("Ficticio.pdf"),"mimeType":.string("application/pdf"),"size":.number(Double(pdf.count))])])])
        var requests=0
        MockProtocol.handler = {request in
            requests+=1;XCTAssertEqual(request.url?.host,"ui-fixture.example.invalid")
            let document=request.url?.path == "/api/notices/file"
            return (HTTPURLResponse(url:request.url!,statusCode:200,httpVersion:nil,headerFields:["Content-Type":document ? "application/pdf":"application/json"])!,document ? pdf:try JSONEncoder().encode(JSONValue.object(["item":itemJSON])))
        }
        let item=try await client.notice(id:"private-code-fixture"),file=try XCTUnwrap(item.files.first)
        let stamp=try client.boardingCodeAccessStamp(item,file:file)
        let downloaded=try await client.noticeFile(item,file:file);defer {TemporaryDocuments.remove(downloaded)}
        XCTAssertEqual(try BoardingCodeExtractor.extract(Data(contentsOf:downloaded.url),mime:file.mimeType).count,2)
        let beforeOffline=requests;client.beginOfflineRestore()
        MockProtocol.handler = {_ in XCTFail("Downloaded passes must open without a network request.");throw URLError(.notConnectedToInternet)}
        let offline=try await client.noticeFile(item,file:file);defer {TemporaryDocuments.remove(offline)}
        XCTAssertEqual(try BoardingCodeExtractor.extract(Data(contentsOf:offline.url),mime:file.mimeType).count,2)
        XCTAssertEqual(requests,beforeOffline);XCTAssertEqual(stamp,try client.boardingCodeAccessStamp(item,file:file))
        let (online,_)=relaunchFixture(cache),onlineStamp=try online.boardingCodeAccessStamp(item,file:file)
        MockProtocol.handler = {request in (HTTPURLResponse(url:request.url!,statusCode:403,httpVersion:nil,headerFields:["Content-Type":"application/json"])!,Data("{\"error\":\"Revocado\"}".utf8))}
        do {_ = try await online.noticeFile(item,file:file);XCTFail("403 must never use the saved private PDF.")} catch APIError.forbidden {}
        XCTAssertNotEqual(onlineStamp,try online.boardingCodeAccessStamp(item,file:file));XCTAssertNil(online.cachedNotice(item.id))
    }
    @MainActor func testMediaRevalidatesImmediatelyWhileWorkspaceStillUsesItsRestoredCopy() async throws {
        let vault=MemorySession();vault.token=token
        let configuration=URLSessionConfiguration.ephemeral;configuration.protocolClasses=[MockProtocol.self]
        let client=PayrollClient(baseURL:URL(string:"https://media-startup.invalid")!,vault:vault,configuration:configuration,automaticallyDownloadOffline:false)
        let root=MediaFolder(id:"root",name:"JAC ficticia")
        func feed(_ id:String)->MediaFeed {MediaFeed(connected:true,canRead:true,canUpload:true,canConnect:false,root:root,folder:root,breadcrumbs:[root],items:[MediaItem(id:id,name:id,mimeType:"application/vnd.google-apps.folder",kind:"folder",size:0,modifiedAt:"",thumbnailAvailable:false)],nextPageToken:nil)}
        var requests=0
        MockProtocol.handler={request in
            XCTAssertEqual(request.url?.path,"/api/media");requests += 1
            if requests == 2 {XCTAssertEqual(request.timeoutInterval,30,"La consulta explícita no debe agotarse a los cinco segundos mientras la copia ya está visible")}
            return (HTTPURLResponse(url:request.url!,statusCode:200,httpVersion:nil,headerFields:["Content-Type":"application/json"])!,try JSONEncoder().encode(feed(requests == 1 ? "saved":"fresh")))
        }
        defer {MockProtocol.handler=nil;try? client.clearSession()}
        _ = try await client.media();client.beginOfflineRestore()
        XCTAssertEqual(client.cachedMedia()?.items.map(\.id),["saved"]);XCTAssertEqual(requests,1)
        let saved=try await client.media();XCTAssertEqual(saved.items.map(\.id),["saved"])
        let fresh=try await client.media(forceNetwork:true)
        XCTAssertEqual(fresh.items.map(\.id),["fresh"]);XCTAssertTrue(fresh.canUpload);XCTAssertEqual(requests,2)
        XCTAssertTrue(client.usingOfflineCopy,"Leer Drive no debe habilitar escrituras financieras antes de revalidar la sesión")
        MockProtocol.handler={_ in throw URLError(.notConnectedToInternet)}
        do {_ = try await client.media(forceNetwork:true);XCTFail("Una lectura forzada no debe presentar la copia como una respuesta de internet") }catch {XCTAssertTrue(AgendaOfflineCache.isUnavailable(error))}
        XCTAssertEqual(client.cachedMedia()?.items.map(\.id),["fresh"])
        MockProtocol.handler={request in (HTTPURLResponse(url:request.url!,statusCode:403,httpVersion:nil,headerFields:["Content-Type":"application/json"])!,Data("{\"error\":\"Acceso retirado\"}".utf8))}
        do {_ = try await client.media(forceNetwork:true);XCTFail("Una revocación nunca debe usar la copia") }catch {guard case APIError.forbidden = error else{return XCTFail(error.localizedDescription)}}
        XCTAssertNil(client.cachedMedia());XCTAssertNotNil(vault.token)
    }
    @MainActor func testMediaRootPrefetchSharesItsReadAndCannotRestoreDataAfterLogout() async throws {
        MediaDelayedProtocol.reset();defer{MediaDelayedProtocol.reset()}
        let vault=MemorySession();vault.token=token
        let configuration=URLSessionConfiguration.ephemeral;configuration.protocolClasses=[MediaDelayedProtocol.self]
        let client=PayrollClient(baseURL:URL(string:"https://media-prefetch.invalid")!,vault:vault,configuration:configuration,automaticallyDownloadOffline:false)
        let root=MediaFolder(id:"root",name:"Solo prueba"),feed=MediaFeed(connected:true,canRead:true,canUpload:true,canConnect:false,root:root,folder:root,breadcrumbs:[root],items:[],nextPageToken:nil)
        let first=Task{try await client.media(forceNetwork:true)},second=Task{try await client.media(forceNetwork:true)},cancelled=Task{try await client.media(forceNetwork:true)}
        for _ in 0..<100 {if !MediaDelayedProtocol.pending().isEmpty {break};try await Task.sleep(for:.milliseconds(10))}
        try await Task.sleep(for:.milliseconds(30))
        XCTAssertEqual(MediaDelayedProtocol.pending().count,1,"Precarga y entrada simultánea comparten el GET de raíz")
        cancelled.cancel()
        try XCTUnwrap(MediaDelayedProtocol.pending().first).respond(JSONEncoder().encode(feed))
        let a=try await first.value,b=try await second.value;XCTAssertEqual(a.folder?.id,b.folder?.id);XCTAssertNotNil(client.cachedMedia())
        do {_ = try await cancelled.value;XCTFail("Una vista cancelada no debe recibir el resultado compartido") }catch {XCTAssertTrue(error is CancellationError)}
        let late=Task{try await client.media(forceNetwork:true)}
        for _ in 0..<100 {if MediaDelayedProtocol.pending().count == 2 {break};try await Task.sleep(for:.milliseconds(10))}
        XCTAssertEqual(MediaDelayedProtocol.pending().count,2);try client.clearSession()
        do {_ = try await late.value;XCTFail("No debe terminar una lectura de la sesión cerrada") }catch {}
        XCTAssertNil(client.cachedMedia());XCTAssertNil(vault.token)
    }
    @MainActor func testAuthorizedStartupPrefetchesOnlyRootMetadataOnceAndRefreshCallersJoin() async throws {
        let fixture=UITestBackend.client(),workspace=try await fixture.workspace()
        let vault=MemorySession();vault.token=token
        let configuration=URLSessionConfiguration.ephemeral;configuration.protocolClasses=[MockProtocol.self]
        let client=PayrollClient(baseURL:URL(string:"https://media-preload.invalid")!,vault:vault,configuration:configuration,automaticallyDownloadOffline:false)
        client.rememberWorkspace(workspace)
        var workspaces=0,roots=0
        MockProtocol.handler={request in
            let bytes:Data
            if request.url?.path == "/api/mobile/payroll" {workspaces += 1;bytes=try JSONEncoder().encode(workspace)}
            else {XCTAssertEqual(request.url?.path,"/api/media");XCTAssertNil(request.url?.query);roots += 1;let root=MediaFolder(id:"root",name:"Solo metadatos");bytes=try JSONEncoder().encode(MediaFeed(connected:true,canRead:true,canUpload:true,canConnect:false,root:root,folder:root,breadcrumbs:[root],items:[],nextPageToken:nil))}
            return (HTTPURLResponse(url:request.url!,statusCode:200,httpVersion:nil,headerFields:["Content-Type":"application/json"])!,bytes)
        }
        defer {MockProtocol.handler=nil;try? client.clearSession()}
        let store=PayrollStore(client:client)
        store.prefetchMediaRoot();await Task.yield();XCTAssertEqual(roots,0,"No precargar antes de validar la sesión")
        async let first:Void=store.refreshAutomatically();async let second:Void=store.refreshAutomatically();_ = try await(first,second)
        XCTAssertEqual(workspaces,1);XCTAssertFalse(store.isOffline)
        store.prefetchMediaRoot();store.prefetchMediaRoot()
        for _ in 0..<100 {if client.cachedMedia() != nil {break};try await Task.sleep(for:.milliseconds(10))}
        XCTAssertEqual(roots,1);XCTAssertNotNil(client.cachedMedia());XCTAssertTrue(store.canWrite)
    }
    @MainActor func testAutomaticSessionRefreshCannotReinstallWorkspaceAfterManualLogout() async throws {
        MediaDelayedProtocol.reset();defer{MediaDelayedProtocol.reset()}
        let fixture=UITestBackend.client(),workspace=try await fixture.workspace()
        let vault=MemorySession();vault.token=token
        let configuration=URLSessionConfiguration.ephemeral;configuration.protocolClasses=[MediaDelayedProtocol.self]
        let client=PayrollClient(baseURL:URL(string:"https://session-revalidation.invalid")!,vault:vault,configuration:configuration,automaticallyDownloadOffline:false)
        client.rememberWorkspace(workspace)
        let store=PayrollStore(client:client),pending=Task{try await store.refreshAutomatically()}
        for _ in 0..<100 {if !MediaDelayedProtocol.pending().isEmpty {break};try await Task.sleep(for:.milliseconds(10))}
        XCTAssertEqual(MediaDelayedProtocol.pending().count,1);XCTAssertNotNil(store.workspace)
        await store.signOut()
        do {try await pending.value;XCTFail("La validación cancelada no debe restaurar una sesión cerrada") }catch {}
        XCTAssertNil(vault.token);XCTAssertNil(store.workspace);XCTAssertNil(store.overview);XCTAssertFalse(store.hasSavedSession)
    }
    func testMediaGalleryUsesCreationDateAndKeepsLegacyFoldersAtTheEnd() {
        func item(_ id:String,_ name:String,_ date:String?,_ kind:String="folder",modified:String="2099-12-31T12:00:00Z")->MediaItem {MediaItem(id:id,name:name,mimeType:kind == "folder" ? "application/vnd.google-apps.folder":"image/png",kind:kind,size:0,modifiedAt:modified,thumbnailAvailable:false,createdAt:date)}
        let old=item("old","A antiguo","2026-10-01T12:00:00Z"),new=item("new","Z nuevo","2026-10-16T12:00:00Z",modified:"2020-01-01T00:00:00Z"),legacy=item("legacy","A sin fecha",nil),file=item("file","Foto","2027-01-01T00:00:00Z","image")
        XCTAssertEqual(MediaGalleryOrder.sorted([legacy,old,file,new]).map(\.id),["new","old","legacy","file"])
        XCTAssertEqual(MediaGalleryOrder.sorted([item("b","Igual",nil),item("a","Igual",nil)]).map(\.id),["a","b"])
    }
    func testLargeJPEGIsReducedBeforeUploadWithoutChangingTheSourceAndKeepsThumbnail() async throws {
        let width=4000,height=3000
        var pixels=[UInt8](repeating:255,count:width*height*4),random:UInt32=12345
        for index in stride(from:0,to:pixels.count,by:4) {for channel in 0..<3 {random=1664525 &* random &+ 1013904223;pixels[index+channel]=UInt8(truncatingIfNeeded:random>>24)}}
        let data=Data(pixels),provider=try XCTUnwrap(CGDataProvider(data:data as CFData)),image=try XCTUnwrap(CGImage(width:width,height:height,bitsPerComponent:8,bitsPerPixel:32,bytesPerRow:width*4,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGBitmapInfo(rawValue:CGImageAlphaInfo.noneSkipLast.rawValue),provider:provider,decode:nil,shouldInterpolate:false,intent:.defaultIntent))
        let original=NSMutableData(),encoder=try XCTUnwrap(CGImageDestinationCreateWithData(original,"public.jpeg" as CFString,1,nil));CGImageDestinationAddImage(encoder,image,[kCGImageDestinationLossyCompressionQuality:1.0,kCGImagePropertyOrientation:6] as [CFString:Any] as CFDictionary);XCTAssertTrue(CGImageDestinationFinalize(encoder));XCTAssertGreaterThan(original.length,8_000_000)
        let source=try TemporaryDocuments.save(original as Data,filename:"Cámara original.JPG");defer{TemporaryDocuments.remove(source)}
        let sourceImage=try XCTUnwrap(CGImageSourceCreateWithURL(source.url as CFURL,nil)),sourceProperties=try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(sourceImage,0,nil) as? [CFString:Any]);XCTAssertEqual(sourceProperties[kCGImagePropertyOrientation] as? Int,6)
        let staged=try await Task.detached {try MediaLocalFile.stage(source.url,quality:.compact)}.value;defer{staged.remove()}
        XCTAssertEqual(staged.name,"Cámara original.JPG");XCTAssertEqual(staged.mimeType,"image/jpeg");XCTAssertLessThanOrEqual(staged.size,2_000_000);XCTAssertGreaterThan(staged.size,0)
        XCTAssertEqual(try Data(contentsOf:source.url),original as Data,"No sobrescribir el original de la cámara")
        let optimized=try XCTUnwrap(CGImageSourceCreateWithURL(staged.url as CFURL,nil)),properties=try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(optimized,0,nil) as? [CFString:Any])
        XCTAssertLessThan((properties[kCGImagePropertyPixelWidth] as? Int) ?? 0,(properties[kCGImagePropertyPixelHeight] as? Int) ?? 0,"La orientación EXIF debe quedar aplicada")
        let generated=await MediaThumbnail.jpeg(for:staged),thumbnail=try XCTUnwrap(generated);XCTAssertLessThanOrEqual(thumbnail.count,512*1024);XCTAssertNotNil(MediaThumbnail.image(thumbnail))
        for quality in [MediaImageQuality.balanced,.detailed,.original] {
            let next=try await Task.detached {try MediaLocalFile.stage(source.url,quality:quality)}.value;defer{next.remove()}
            XCTAssertEqual(next.imageLimit,Int64(quality.rawValue))
            if quality == .original {XCTAssertEqual(try Data(contentsOf:next.url),original as Data)} else {XCTAssertLessThanOrEqual(next.size,Int64(quality.rawValue));XCTAssertGreaterThan(next.size,staged.size)}
        }
        let movie=try TemporaryDocuments.save(MediaFixture.video,filename:"Video.mov");defer{TemporaryDocuments.remove(movie)}
        let stagedMovie=try MediaLocalFile.stage(movie.url,quality:.compact);defer{stagedMovie.remove()};XCTAssertEqual(stagedMovie.imageLimit,0);XCTAssertEqual(try Data(contentsOf:stagedMovie.url),MediaFixture.video)

    }
    @MainActor func testPhotoViewerPagesMetadataSkipsVideosAndCleansTemporaryOriginals() async throws {
        func photo(_ id:String)->MediaItem {MediaItem(id:id,name:id+".jpg",mimeType:"image/jpeg",kind:"image",size:17,modifiedAt:"fixture",thumbnailAvailable:true)}
        let first=photo("one"),second=photo("two"),third=photo("three"),folder=MediaFolder(id:"folder",name:"Exact name"),initial=try TemporaryDocuments.save(MediaFixture.photo,filename:"one.png")
        defer{TemporaryDocuments.remove(initial)}
        var requests=[String](),loaded=[String](),denials=0
        let viewer=MediaPhotoViewer(selected:first,document:initial,items:[first,second],token:"next",folderID:folder.id,collectionID:"r2-test",load:{item in loaded.append(item.id);return try TemporaryDocuments.save(MediaFixture.photo,filename:item.name)},page:{token in requests.append(token);return MediaFeed(connected:true,canRead:true,canUpload:false,canConnect:false,root:folder,folder:folder,breadcrumbs:[folder],items:[second,MediaItem(id:"movie",name:"m.mov",mimeType:"video/quicktime",kind:"video",size:20,modifiedAt:"f",thumbnailAvailable:true),third],nextPageToken:nil,provider:"r2",collectionID:"r2-test")},denied:{_ in denials+=1})
        XCTAssertFalse(viewer.canPrevious);await viewer.move(1);XCTAssertEqual(viewer.selected.id,"two");let previous=try XCTUnwrap(viewer.document)
        await viewer.move(1);XCTAssertEqual(viewer.selected.id,"three");XCTAssertEqual(requests,["next"]);XCTAssertEqual(viewer.items.map(\.id),["one","two","three"]);XCTAssertFalse(FileManager.default.fileExists(atPath:previous.url.path));XCTAssertFalse(viewer.canNext)
        await viewer.move(-1);XCTAssertEqual(viewer.selected.id,"two");XCTAssertEqual(loaded,["two","three","two"]);let current=try XCTUnwrap(viewer.document);viewer.stop();XCTAssertFalse(FileManager.default.fileExists(atPath:current.url.path));XCTAssertEqual(denials,0)
    }
    @MainActor func testPhotoViewerCannotShowLateOriginalAfterDismissalAndWithdrawsOnDenial() async throws {
        let first=MediaItem(id:"one",name:"one.jpg",mimeType:"image/jpeg",kind:"image",size:17,modifiedAt:"f",thumbnailAvailable:true),second=MediaItem(id:"two",name:"two.jpg",mimeType:"image/jpeg",kind:"image",size:17,modifiedAt:"f",thumbnailAvailable:true)
        var viewer:MediaPhotoViewer!,late:ExportedDocument?,denied=0
        viewer=MediaPhotoViewer(selected:first,document:nil,items:[first,second],token:"",folderID:"f",collectionID:nil,load:{_ in late=try TemporaryDocuments.save(MediaFixture.photo,filename:"late.png");viewer.stop();return late!},page:{_ in throw URLError(.notConnectedToInternet)},denied:{_ in denied+=1})
        await viewer.move(1);XCTAssertNil(viewer.document);XCTAssertEqual(viewer.selected.id,"one");XCTAssertFalse(FileManager.default.fileExists(atPath:try XCTUnwrap(late).url.path));XCTAssertEqual(denied,0)
        let revoked=MediaPhotoViewer(selected:first,document:nil,items:[first,second],token:"",folderID:"f",collectionID:nil,load:{_ in throw APIError.forbidden("Acceso retirado")},page:{_ in throw URLError(.notConnectedToInternet)},denied:{_ in denied+=1})
        await revoked.move(1);XCTAssertEqual(denied,1);XCTAssertNil(revoked.document);XCTAssertEqual(revoked.selected.id,"one")
    }
    #if os(iOS)
    @MainActor func testFolderShareClientCreatesListsAndRevokesWithTheSameRequestIdentity() async throws {
        let vault = MemorySession(); vault.token = String(repeating: "f", count: 43)
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [MockProtocol.self]
        let client = PayrollClient(baseURL: URL(string: "https://shares.invalid")!, vault: vault, configuration: config, automaticallyDownloadOffline: false)
        let id = UUID().uuidString.lowercased(), folder = "r2_" + UUID().uuidString.lowercased()
        let link: JSONValue = .object(["id": .string(id), "url": .string("/compartir/" + String(repeating: "a", count: 43)), "createdAt": .string("2026-10-19T12:00:00Z"), "expiresAt": .string("2026-11-18T12:00:00Z")])
        var calls: [String] = []
        MockProtocol.handler = { request in
            XCTAssertEqual(request.url?.path, "/api/media/shares")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Cookie"), "__Host-jac_session=" + String(repeating: "f", count: 43))
            let result: JSONValue
            if request.httpMethod == "GET" {
                XCTAssertTrue(request.url?.query?.contains(folder) == true); calls.append("list"); result = .object(["links": .array([link])])
            } else {
                let body = try JSONDecoder().decode(JSONValue.self, from: MockProtocol.requestBody(request))
                XCTAssertEqual(body["folderId"].text, folder); XCTAssertEqual(body["id"].text, id)
                calls.append(body["action"].text)
                result = body["action"].text == "create" ? .object(["link": link]) : .object(["revoked": .bool(true)])
            }
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type":"application/json"])!, try JSONEncoder().encode(result))
        }; defer { MockProtocol.handler = nil }
        let created = try await client.createMediaFolderShare(folder, id: id, days: 30)
        XCTAssertEqual(created.id, id)
        XCTAssertEqual(created.absoluteURL(origin: client.baseURL)?.host, "shares.invalid")
        let listed = try await client.mediaFolderShares(folder)
        XCTAssertEqual(listed.map(\.id), [id])
        try await client.revokeMediaFolderShare(folder, id: id)
        XCTAssertEqual(calls, ["create", "list", "revoke"])
    }
    #endif

    @MainActor func testThumbnailFailureRemainsAnErrorUntilTheIndexedJPEGIsConfirmed() async throws {
        let vault = MemorySession(); vault.token = String(repeating: "f", count: 43)
        let transport = ScriptedUploadTransport()
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [MockProtocol.self]
        let client = PayrollClient(baseURL: URL(string: "https://thumbnail-upload.invalid")!, vault: vault,
            configuration: config, automaticallyDownloadOffline: false, mediaUploadTransport: transport)
        let document = try TemporaryDocuments.save(MediaFixture.photo, filename: "Foto ficticia.png")
        defer { TemporaryDocuments.remove(document) }
        let source = try MediaLocalFile.stage(document.url, quality: .original); defer { source.remove() }
        var status = 503
        transport.handler = { request, bytes, _ in
            XCTAssertEqual(request.httpMethod, "PUT")
            XCTAssertEqual(request.url?.path, "/api/media/upload")
            XCTAssertTrue(request.url?.query?.contains("thumbnail=1") == true || request.url?.query?.contains("preview=1") == true)
            XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "image/jpeg")
            let image = try XCTUnwrap(CGImageSourceCreateWithData(bytes as CFData, nil))
            let properties = try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(image, 0, nil) as? [CFString: Any])
            XCTAssertLessThanOrEqual(try XCTUnwrap(properties[kCGImagePropertyPixelWidth] as? Int), request.url?.query?.contains("preview=1") == true ? 1600 : 360)
            XCTAssertLessThanOrEqual(try XCTUnwrap(properties[kCGImagePropertyPixelHeight] as? Int), request.url?.query?.contains("preview=1") == true ? 1600 : 360)
            return (Data((status == 200 ? "{\"saved\":true}" : "{\"error\":\"Miniatura pendiente ficticia\"}").utf8),
                HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: ["Content-Type":"application/json"])!)
        }
        do { try await client.uploadMediaThumbnail(source); XCTFail("No debe aparentar que la miniatura ya quedó guardada") }
        catch { XCTAssertFalse(error is CancellationError) }
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.url.path))
        status = 200
        try await client.uploadMediaThumbnail(source)
        XCTAssertEqual(transport.calls, 3)
        XCTAssertEqual(try Data(contentsOf: source.url), MediaFixture.photo)
    }

    @MainActor func testPhotoOnlyFolderPlanTraversesPagesAndSubfoldersWithoutIncludingVideos() async throws {
        let vault = MemorySession(); vault.token = String(repeating: "f", count: 43)
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [MockProtocol.self]
        let client = PayrollClient(baseURL: URL(string: "https://filtered-folder.invalid")!, vault: vault, configuration: config, automaticallyDownloadOffline: false)
        let root = MediaFolder(id: "root", name: "Carpeta ficticia"), child = MediaFolder(id: "child", name: "Subcarpeta")
        func item(_ id: String, _ kind: String) -> MediaItem { MediaItem(id: id, name: id, mimeType: kind == "image" ? "image/png" : kind == "video" ? "video/mp4" : "application/vnd.google-apps.folder", kind: kind, size: kind == "folder" ? 0 : 10, modifiedAt: "fixture", thumbnailAvailable: true) }
        var reads: [String] = []
        MockProtocol.handler = { request in
            XCTAssertEqual(request.url?.path, "/api/media")
            let query = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems ?? []
            let folder = query.first { $0.name == "folder" }?.value ?? "root"
            let page = query.first { $0.name == "pageToken" }?.value ?? ""
            reads.append(folder + ":" + page)
            let items = folder == "child" ? [item("child-photo", "image"), item("child-video", "video")] :
                page.isEmpty ? [item("photo", "image"), item("video", "video"), item("child", "folder")] : [item("page-photo", "image"), item("page-video", "video")]
            let feed = MediaFeed(connected: true, canRead: true, canUpload: false, canConnect: false, root: root,
                folder: folder == "child" ? child : root, breadcrumbs: [root], items: items,
                nextPageToken: folder == "root" && page.isEmpty ? "next" : nil, provider: "r2", collectionID: "fixture")
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type":"application/json"])!, try JSONEncoder().encode(feed))
        }; defer { MockProtocol.handler = nil }
        let filtered = try await client.mediaDownloadPlan(folder: "root", imagesOnly: true)
        XCTAssertEqual(filtered.files.map(\.id), ["photo", "page-photo", "child-photo"])
        XCTAssertEqual(filtered.totalBytes, 30)
        XCTAssertEqual(reads, ["root:", "root:next", "child:"])
        let complete = try await client.mediaDownloadPlan(folder: "root")
        XCTAssertEqual(complete.files.map(\.id), ["photo", "video", "page-photo", "page-video", "child-photo", "child-video"])
    }

    #if os(iOS)
    @MainActor func testOpeningFolderPrefetchesOffscreenPhotosVideosAndLaterPagesWithoutOriginals() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { MockProtocol.handler = nil; try? FileManager.default.removeItem(at: root) }
        let vault = MemorySession(); vault.token = String(repeating: "p", count: 43)
        let configuration = URLSessionConfiguration.ephemeral; configuration.protocolClasses = [MockProtocol.self]
        let cache = MediaOfflineCache(root: root)
        let client = PayrollClient(baseURL: URL(string: "https://prefetch.example.invalid")!, vault: vault, configuration: configuration, mediaOffline: cache, automaticallyDownloadOffline: false)
        // This scope exercises grid covers. Low Data Mode suppresses the new
        // full-screen bulk prefetch, which is verified separately on Wi-Fi.
        client.photoPreviews.updateConnection(MediaPhotoConnection(constrained: true))
        let folder = MediaFolder(id: "opened", name: "Carpeta sintética")
        func item(_ id: String, kind: String = "image", available: Bool = true) -> MediaItem {
            MediaItem(id: id, name: id, mimeType: kind == "video" ? "video/mp4" : "image/png", kind: kind, size: 100, modifiedAt: "revision-1", thumbnailAvailable: available)
        }
        let photo = item("visible"), video = item("offscreen-video", kind: "video"), later = item("next-page")
        let first = MediaFeed(connected: true, canRead: true, canUpload: false, canConnect: false, root: folder, folder: folder, breadcrumbs: [folder],
                              items: [photo, video, item("unopened", kind: "folder"), item("pending", available: false)], nextPageToken: "next", provider: "r2", collectionID: "jac-r2-synthetic")
        let second = MediaFeed(connected: true, canRead: true, canUpload: false, canConnect: false, root: folder, folder: folder, breadcrumbs: [folder],
                               items: [later], nextPageToken: nil, provider: "r2", collectionID: first.collectionID)
        let page = try JSONEncoder().encode(second), lock = NSLock()
        var requests: [String: Int] = [:], pages = 0
        MockProtocol.handler = { request in
            lock.lock(); defer { lock.unlock() }
            let url = try XCTUnwrap(request.url), query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
            if url.path == "/api/media" {
                XCTAssertEqual(query.first { $0.name == "pageToken" }?.value, "next")
                XCTAssertEqual(query.first { $0.name == "folder" }?.value, folder.id)
                pages += 1
                return (HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!, page)
            }
            XCTAssertEqual(url.path, "/api/media/file")
            XCTAssertEqual(query.first { $0.name == "thumbnail" }?.value, "1", "La precarga jamás debe descargar originales")
            let id = try XCTUnwrap(query.first { $0.name == "id" }?.value); requests[id, default: 0] += 1
            return (HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "image/png"])!, MediaFixture.photo)
        }
        let loader = MediaGridThumbnailLoader(), prefetch = MediaFolderThumbnailPrefetch(loader: loader)
        let scope = try XCTUnwrap(client.mediaScope())
        try cache.saveFeed(first, key: folder.id, append: false, scope: scope)
        prefetch.start(first, client: client, networkAllowed: true, denied: { _ in XCTFail("No se revocó este fixture") })
        await prefetch.task?.value
        XCTAssertEqual(requests, [photo.id: 1, video.id: 1, later.id: 1]); XCTAssertEqual(pages, 1)
        for file in [photo, video, later] { XCTAssertEqual(cache.loadThumbnail(file, scope: scope), MediaFixture.photo) }
        // Reopening after memory eviction restores the encrypted thumbnails;
        // only pagination metadata is revalidated, never the original files.
        prefetch.stop(); loader.clear()
        prefetch.start(first, client: client, networkAllowed: true, denied: { _ in XCTFail() })
        await prefetch.task?.value
        XCTAssertEqual(requests, [photo.id: 1, video.id: 1, later.id: 1]); XCTAssertEqual(pages, 2)
        prefetch.start(first, client: client, networkAllowed: false, denied: { _ in XCTFail() })
        XCTAssertNil(prefetch.task)
        // A denial during prefetch stops pagination and withdraws earlier cache.
        let changed = MediaItem(id: photo.id, name: photo.name, mimeType: photo.mimeType, kind: photo.kind, size: photo.size, modifiedAt: "denied-revision", thumbnailAvailable: true)
        var denied = false
        MockProtocol.handler = { request in
            XCTAssertEqual(request.url?.path, "/api/media/file")
            return (HTTPURLResponse(url: request.url!, statusCode: 403, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!, Data("{}".utf8))
        }
        prefetch.start(first.replacingItems([changed]), client: client, networkAllowed: true, denied: { _ in denied = true })
        await prefetch.task?.value
        XCTAssertTrue(denied); XCTAssertEqual(pages, 2)
        XCTAssertNil(cache.loadThumbnail(photo, scope: scope))
    }
    #endif

    @MainActor func testDerivedThumbnailScopeStillRequiresUnlockedCurrentSession() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let vault = MemorySession(); vault.token = String(repeating: "p", count: 43)
        let client = PayrollClient(baseURL: URL(string: "https://scope.example.invalid")!, vault: vault, mediaOffline: MediaOfflineCache(root: root), automaticallyDownloadOffline: false)
        let first = try XCTUnwrap(client.mediaScope())
        XCTAssertEqual(try client.mediaScope()?.id, first.id)
        vault.locked = true; XCTAssertThrowsError(try client.mediaScope())
        vault.locked = false; vault.token = String(repeating: "q", count: 43)
        XCTAssertNotEqual(try client.mediaScope()?.id, first.id)
        try client.clearSession(); XCTAssertNil(try client.mediaScope())
    }

    func testGalleryIndexMemoryTracksExternalWritesRemovalAndCorruption() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let scope = AgendaCacheScope(origin: "https://index.example.invalid", token: String(repeating: "i", count: 43))
        let first = MediaOfflineCache(root: root), second = MediaOfflineCache(root: root)
        let folder = MediaFolder(id: "folder", name: "Prueba")
        let item = MediaItem(id: "photo", name: "Foto.png", mimeType: "image/png", kind: "image", size: 100, modifiedAt: "one", thumbnailAvailable: true)
        let feed = MediaFeed(connected: true, canRead: true, canUpload: false, canConnect: false, root: folder, folder: folder, breadcrumbs: [folder], items: [item], nextPageToken: nil)
        try first.saveFeed(feed, key: folder.id, append: false, scope: scope)
        XCTAssertEqual(first.loadFeed(folder.id, scope: scope)?.items.map(\.id), [item.id])
        try second.removeFile(item, scope: scope)
        XCTAssertEqual(first.loadFeed(folder.id, scope: scope)?.items.count, 0)
        XCTAssertTrue(first.isDeleted(item.id, scope: scope))
        let index = root.appendingPathComponent(scope.id).appendingPathComponent("index.sealed")
        try Data("corrupto".utf8).write(to: index)
        XCTAssertNil(first.loadFeed(folder.id, scope: scope), "No debe rescatar una copia en memoria si el índice fue alterado")
        first.clear(scope); XCTAssertNil(first.loadFeed(folder.id, scope: scope))
    }

    @MainActor func testThumbnailCacheSurvivesClosingFolderMemoryEvictionAndReopeningSession() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let vault = MemorySession(); vault.token = String(repeating: "f", count: 43)
        let configuration = URLSessionConfiguration.ephemeral; configuration.protocolClasses = [MockProtocol.self]
        let item = MediaItem(id: "r2_cached", name: "Privada.png", mimeType: "image/png", kind: "image", size: 100, modifiedAt: "revision", thumbnailAvailable: true)
        var count = 0
        MockProtocol.handler = { request in count += 1; XCTAssertTrue(request.url?.query?.contains("thumbnail=1") == true); return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type":"image/png"])!, MediaFixture.photo) }
        defer { MockProtocol.handler = nil; try? FileManager.default.removeItem(at: root) }
        let client = PayrollClient(baseURL: URL(string: "https://cache.example.invalid")!, vault: vault, configuration: configuration, mediaOffline: MediaOfflineCache(root: root), automaticallyDownloadOffline: false)
        let first = try await client.mediaThumbnail(item); XCTAssertEqual(first, MediaFixture.photo)
        let reopened = PayrollClient(baseURL: client.baseURL, vault: vault, configuration: configuration, mediaOffline: MediaOfflineCache(root: root), automaticallyDownloadOffline: false)
        let second = try await reopened.mediaThumbnail(item, networkAllowed: false); XCTAssertEqual(second, MediaFixture.photo)
        XCTAssertEqual(count, 1)
        let scope = try XCTUnwrap(reopened.mediaScope()); try reopened.clearSession()
        XCTAssertNil(MediaOfflineCache(root: root).loadThumbnail(item, scope: scope))
    }
    func testThumbnailDiskCacheIsEncryptedBoundedByRevisionSessionAndExpiry() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString), cache = MediaOfflineCache(root: root)
        defer { try? FileManager.default.removeItem(at: root) }
        let scope = AgendaCacheScope(origin: "https://cache.example.invalid/media", token: String(repeating: "a", count: 43)), other = AgendaCacheScope(origin: "https://cache.example.invalid/media", token: String(repeating: "b", count: 43))
        let item = MediaItem(id: "photo", name: "Privada.png", mimeType: "image/png", kind: "image", size: 100, modifiedAt: "one", thumbnailAvailable: true), now = Date()
        try cache.saveThumbnail(MediaFixture.photo, item: item, scope: scope, now: now)
        XCTAssertEqual(cache.loadThumbnail(item, scope: scope, now: now), MediaFixture.photo)
        XCTAssertNil(cache.loadThumbnail(item, scope: other, now: now))
        let revision = MediaItem(id: item.id, name: item.name, mimeType: item.mimeType, kind: item.kind, size: item.size, modifiedAt: "two", thumbnailAvailable: true)
        XCTAssertNil(cache.loadThumbnail(revision, scope: scope, now: now))
        let urls = try XCTUnwrap(FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)?.allObjects as? [URL]), encrypted = try XCTUnwrap(urls.first { $0.path.contains("thumbnails/") && $0.pathExtension == "sealed" })
        XCTAssertNil(try Data(contentsOf: encrypted).range(of: MediaFixture.photo))
        try Data("alterada".utf8).write(to: encrypted)
        XCTAssertNil(cache.loadThumbnail(item, scope: scope, now: now))
        try cache.saveThumbnail(MediaFixture.photo, item: item, scope: scope, now: now)
        XCTAssertNil(cache.loadThumbnail(item, scope: scope, now: now.addingTimeInterval(49 * 3600)))
        try cache.saveThumbnail(MediaFixture.photo, item: item, scope: scope, now: now)
        try cache.removeFile(item, scope: scope)
        XCTAssertNil(cache.loadThumbnail(item, scope: scope))
        XCTAssertThrowsError(try cache.saveThumbnail(MediaFixture.photo, item: item, scope: scope))
        cache.clear(scope); XCTAssertThrowsError(try cache.saveThumbnail(MediaFixture.photo, item: item, scope: scope))
    }
    @MainActor func testLightPhotoPreviewAndAdaptiveVideoNeverRequestOriginalBytes() async throws {
        let vault = MemorySession(); vault.token = String(repeating: "f", count: 43)
        let configuration = URLSessionConfiguration.ephemeral; configuration.protocolClasses = [MockProtocol.self]
        let client = PayrollClient(baseURL: URL(string: "https://playback.example.invalid")!, vault: vault, configuration: configuration, automaticallyDownloadOffline: false)
        let source = try TemporaryDocuments.save(MediaFixture.photo, filename: "Foto.png"), local = try MediaLocalFile.stage(source.url, quality: .original)
        defer { MockProtocol.handler = nil; local.remove(); TemporaryDocuments.remove(source) }
        let generated = await MediaThumbnail.jpeg(for: local); let jpeg = try XCTUnwrap(generated)
        var requests = 0
        MockProtocol.handler = { request in
            requests += 1
            if request.url?.path == "/api/media/playback" { return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type":"application/json"])!, Data("{\"ready\":true,\"url\":\"https://playback.example.invalid/api/media/playback?lease=fixture&asset=manifest/video.m3u8\"}".utf8)) }
            XCTAssertTrue(request.url?.query?.contains("preview=1") == true)
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type":"image/jpeg"])!, jpeg)
        }
        let image = MediaItem(id: "photo", name: "Original.png", mimeType: "image/png", kind: "image", size: 1000000, modifiedAt: "one", thumbnailAvailable: true)
        let document = try await client.mediaPhotoPreview(image); defer { TemporaryDocuments.remove(document) }
        XCTAssertEqual(try Data(contentsOf: document.url), jpeg)
        let video = MediaItem(id: "video", name: "Original.mov", mimeType: "video/quicktime", kind: "video", size: 10000000, modifiedAt: "one", thumbnailAvailable: true)
        let url = try await client.mediaPlayback(video), stream = try MediaVideoStream(client: client, item: video, playbackURL: url)
        XCTAssertEqual(stream.asset.url, url); stream.cancel(); XCTAssertEqual(requests, 2)
    }
    @MainActor func testDownloadedFolderPhotosOpenLocallyWhileOnlineAndOfflineWithoutAnyRequest() async throws {
        let vault=MemorySession();vault.token=String(repeating:"a",count:43)
        let config=URLSessionConfiguration.ephemeral;config.protocolClasses=[MockProtocol.self]
        let cache=MediaOfflineCache(root:FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        let client=PayrollClient(baseURL:URL(string:"https://pinned-preview.invalid")!,vault:vault,configuration:config,mediaOffline:cache,automaticallyDownloadOffline:false)
        let scope=try XCTUnwrap(client.mediaScope()), folder=MediaFolder(id:"folder",name:"Carpeta descargada")
        let items=(0..<3).map { MediaItem(id:"r2_pinned-\($0)",name:"Foto\($0).png",mimeType:"image/png",kind:"image",size:Int64(MediaFixture.photo.count),modifiedAt:"one",thumbnailAvailable:true) }
        let feed=MediaFeed(connected:true,canRead:true,canUpload:false,canConnect:false,root:folder,folder:folder,breadcrumbs:[folder],items:items,nextPageToken:nil,provider:"r2",collectionID:"jac-r2-pinned")
        try cache.saveFeed(feed,key:folder.id,append:false,scope:scope);try cache.pinFeed(feed,key:folder.id,scope:scope)
        let source=try TemporaryDocuments.save(MediaFixture.photo,filename:"original.png")
        defer {TemporaryDocuments.remove(source);MockProtocol.handler=nil;cache.clear(scope)}
        for item in items {try cache.saveFile(source.url,item:item,scope:scope)}
        var calls=0
        MockProtocol.handler={_ in calls+=1;throw URLError(.notConnectedToInternet)}
        for offline in [false,true] {
            if offline {client.beginOfflineRestore()}
            for item in items {
                let document=try await client.mediaPhotoPreview(item,quality:.balanced)
                XCTAssertEqual(try Data(contentsOf:document.url),MediaFixture.photo)
                TemporaryDocuments.remove(document)
            }
        }
        XCTAssertEqual(calls,0,"Ni el original ni una vista remota deben volver a descargarse para mostrar una carpeta guardada")
    }

    @MainActor func testPhotoPreviewCacheReopensAcrossClientsImprovesOnceAndNeverFallsBackAfterDenial() async throws {
        let previewJPEG=try photoPreviewJPEGFixture()
        let vault=MemorySession();vault.token=String(repeating:"b",count:43)
        let config=URLSessionConfiguration.ephemeral;config.protocolClasses=[MockProtocol.self]
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString),cache=MediaOfflineCache(root:root)
        let base=URL(string:"https://preview-persistent.invalid")!
        let client=PayrollClient(baseURL:base,vault:vault,configuration:config,mediaOffline:cache,automaticallyDownloadOffline:false)
        let item=MediaItem(id:"photo",name:"Photo.heic",mimeType:"image/heic",kind:"image",size:8000000,modifiedAt:"one",thumbnailAvailable:true)
        var calls:[String]=[],denied=false
        MockProtocol.handler={ request in
            let q=URLComponents(url:request.url!,resolvingAgainstBaseURL:false)!.queryItems!
            XCTAssertEqual(q.first{$0.name=="preview"}?.value,"1")
            calls.append(q.first{$0.name=="quality"}?.value ?? "detail")
            return (HTTPURLResponse(url:request.url!,statusCode:denied ? 403:200,httpVersion:nil,headerFields:["Content-Type":denied ? "application/json":"image/jpeg"])!,denied ? Data("{}".utf8):previewJPEG)
        }
        defer {MockProtocol.handler=nil;try? FileManager.default.removeItem(at:root)}
        JACPerformanceDiagnostics.reset()
        let first=try await client.mediaPhotoPreview(item,quality:.balanced);TemporaryDocuments.remove(first)
        XCTAssertGreaterThanOrEqual(JACPerformanceDiagnostics.snapshot().count(.diskWrite),1)
        XCTAssertEqual(JACPerformanceDiagnostics.snapshot().count(.diskWrite,mainThread:true),0,"Preparar el JPEG temporal no debe bloquear el hilo de interfaz")
        let restored=PayrollClient(baseURL:base,vault:vault,configuration:config,mediaOffline:MediaOfflineCache(root:root),automaticallyDownloadOffline:false)
        let second=try await restored.mediaPhotoPreview(item,quality:.balanced);defer{TemporaryDocuments.remove(second)}
        XCTAssertEqual(try Data(contentsOf:second.url),previewJPEG);XCTAssertEqual(calls,["balanced"])
        restored.photoPreviews.updateConnection(MediaPhotoConnection(wifi:true))
        let improvement=try await restored.improveMediaPhotoPreview(item,current:second)
        let improved=try XCTUnwrap(improvement);TemporaryDocuments.remove(improved)
        XCTAssertEqual(calls,["balanced","detail"])
        let best=try await restored.mediaPhotoPreview(item,quality:.balanced)
        XCTAssertEqual(best.url.lastPathComponent,MediaPhotoPreviewQuality.detail.filename);TemporaryDocuments.remove(best)
        XCTAssertEqual(calls.count,2)
        denied=true
        let changed=MediaItem(id:item.id,name:item.name,mimeType:item.mimeType,kind:item.kind,size:item.size,modifiedAt:"two",thumbnailAvailable:true)
        do {_ = try await restored.mediaPhotoPreview(changed,quality:.balanced);XCTFail("403 no admite fallback")}
        catch APIError.forbidden {}
        let scope=AgendaCacheScope(origin:base.absoluteString+"/media-offline-v1",token:String(repeating:"b",count:43))
        XCTAssertNil(cache.loadPhotoPreview(item,quality:.balanced,scope:scope))
    }

    func testPhotoPreviewDiskCacheRejectsOtherRevisionQualitySessionExpiryDeletionAndLateCollectionWrites() throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString),cache=MediaOfflineCache(root:root)
        defer{try? FileManager.default.removeItem(at:root)}
        let scope=AgendaCacheScope(origin:"https://preview-cache.invalid/media-offline-v1",token:String(repeating:"c",count:43))
        let item=MediaItem(id:"photo",name:"Photo.jpg",mimeType:"image/jpeg",kind:"image",size:10000000,modifiedAt:"one",thumbnailAvailable:true)
        let now=Date(timeIntervalSince1970:1_800_000_000),data=Data(repeating:73,count:2000)
        try cache.savePhotoPreview(data,item:item,quality:.balanced,scope:scope,collectionID:nil,now:now)
        XCTAssertEqual(cache.loadPhotoPreview(item,quality:.balanced,scope:scope,now:now),data)
        XCTAssertNil(cache.loadPhotoPreview(item,quality:.detail,scope:scope,now:now))
        let encrypted=try FileManager.default.contentsOfDirectory(at:root.appendingPathComponent(scope.id).appendingPathComponent("photo-previews"),includingPropertiesForKeys:nil)
        XCTAssertEqual(encrypted.count,1);XCTAssertNil(try Data(contentsOf:encrypted[0]).range(of:data))
        let changed=MediaItem(id:item.id,name:item.name,mimeType:item.mimeType,kind:item.kind,size:item.size,modifiedAt:"two",thumbnailAvailable:true)
        XCTAssertNil(cache.loadPhotoPreview(changed,quality:.balanced,scope:scope,now:now))
        let other=AgendaCacheScope(origin:"https://preview-cache.invalid/media-offline-v1",token:String(repeating:"d",count:43))
        XCTAssertNil(cache.loadPhotoPreview(item,quality:.balanced,scope:other,now:now))
        XCTAssertNil(cache.loadPhotoPreview(item,quality:.balanced,scope:scope,now:now.addingTimeInterval(49*3600)))
        try cache.savePhotoPreview(data,item:item,quality:.balanced,scope:scope,collectionID:nil,now:now)
        try cache.removeFile(item,scope:scope)
        XCTAssertNil(cache.loadPhotoPreview(item,quality:.balanced,scope:scope,now:now))
        XCTAssertThrowsError(try cache.savePhotoPreview(data,item:item,quality:.balanced,scope:scope,collectionID:nil,now:now))
        let folder=MediaFolder(id:"folder",name:"Nueva colección")
        let feed=MediaFeed(connected:true,canRead:true,canUpload:false,canConnect:false,root:folder,folder:folder,breadcrumbs:[folder],items:[],nextPageToken:nil,provider:"r2",collectionID:"jac-r2-new")
        try cache.saveFeed(feed,key:folder.id,append:false,scope:scope)
        XCTAssertThrowsError(try cache.savePhotoPreview(data,item:changed,quality:.balanced,scope:scope,collectionID:nil,now:now))
        cache.clear(scope)
        XCTAssertThrowsError(try cache.savePhotoPreview(data,item:changed,quality:.balanced,scope:scope,collectionID:nil,now:now))
    }

    #if os(iOS)
    @MainActor func testWholeFolderPreviewPrefetchTraversesPagesWarmsThirdPhotoAndSkipsDownloadedOriginals() async throws {
        let previewJPEG=try photoPreviewJPEGFixture()
        let vault=MemorySession();vault.token=String(repeating:"e",count:43)
        let config=URLSessionConfiguration.ephemeral;config.protocolClasses=[MockProtocol.self]
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString),cache=MediaOfflineCache(root:root)
        let client=PayrollClient(baseURL:URL(string:"https://whole-folder-preview.invalid")!,vault:vault,configuration:config,mediaOffline:cache,automaticallyDownloadOffline:false)
        client.photoPreviews.updateConnection(MediaPhotoConnection(expensive:true))
        let folder=MediaFolder(id:"folder",name:"Carpeta de prueba")
        let items=(0..<8).map {MediaItem(id:"r2_photo-\($0)",name:"Foto\($0).png",mimeType:"image/png",kind:"image",size:Int64(MediaFixture.photo.count),modifiedAt:"one",thumbnailAvailable:true)}
        func feed(_ photos:[MediaItem],next:String?)->MediaFeed {MediaFeed(connected:true,canRead:true,canUpload:false,canConnect:false,root:folder,folder:folder,breadcrumbs:[folder],items:photos,nextPageToken:next,provider:"r2",collectionID:"jac-r2-prefetch")}
        let first=feed(Array(items.prefix(4)),next:"next"),second=feed(Array(items.suffix(4)),next:nil)
        let scope=try XCTUnwrap(client.mediaScope());try cache.saveFeed(first,key:folder.id,append:false,scope:scope)
        let original=try TemporaryDocuments.save(MediaFixture.photo,filename:"saved.png")
        try cache.saveFile(original.url,item:items[0],scope:scope);try cache.pinFile(items[0],scope:scope)
        let lock=NSLock();var previews=Set<String>(),pageCalls=0
        let pageData=try JSONEncoder().encode(second)
        MockProtocol.handler={request in
            lock.lock();defer{lock.unlock()}
            let q=URLComponents(url:request.url!,resolvingAgainstBaseURL:false)!.queryItems!
            if request.url?.path=="/api/media" {pageCalls+=1;return(HTTPURLResponse(url:request.url!,statusCode:200,httpVersion:nil,headerFields:["Content-Type":"application/json"])!,pageData)}
            XCTAssertEqual(q.first{$0.name=="preview"}?.value,"1");XCTAssertEqual(q.first{$0.name=="quality"}?.value,"balanced")
            previews.insert(try XCTUnwrap(q.first{$0.name=="id"}?.value))
            return(HTTPURLResponse(url:request.url!,statusCode:200,httpVersion:nil,headerFields:["Content-Type":"image/jpeg"])!,previewJPEG)
        }
        let prefetch=MediaFolderPhotoPrefetch()
        defer{prefetch.stop();TemporaryDocuments.remove(original);MockProtocol.handler=nil;cache.clear(scope)}
        prefetch.start(first,client:client,denied:{_ in XCTFail("No se retiró acceso")})
        for _ in 0..<500 {
            if cache.loadPhotoPreview(items[5],quality:.balanced,scope:scope) != nil {break}
            try await Task.sleep(for:.milliseconds(10))
        }
        XCTAssertNotNil(cache.loadPhotoPreview(items[2],quality:.balanced,scope:scope))
        XCTAssertNil(cache.loadPhotoPreview(items[6],quality:.balanced,scope:scope),"En datos móviles se anticipa una ventana, sin descargar toda la carpeta")
        client.photoPreviews.updateConnection(MediaPhotoConnection(wifi:true))
        prefetch.start(first,client:client,denied:{_ in XCTFail("No se retiró acceso")})
        for _ in 0..<500 {
            if cache.loadPhotoPreview(items[7],quality:.balanced,scope:scope) != nil {break}
            try await Task.sleep(for:.milliseconds(10))
        }
        XCTAssertEqual(previews,Set(items.dropFirst().map(\.id)));XCTAssertEqual(pageCalls,2)
        let before=previews
        let third=try await client.mediaPhotoPreview(items[2],quality:.balanced);TemporaryDocuments.remove(third)
        XCTAssertEqual(previews,before,"La tercera ya fue preparada sin tocarla")
        XCTAssertTrue(cache.isPinned(items[0],scope:scope))
    }
    #endif

    @MainActor func testPhotoPreviewQueueSharesReadersReservesCapacityAndPrioritizesVisibleRequests() async throws {
        let pipeline=MediaPhotoPreviewPipeline(limit:1,monitorNetwork:false)
        var pending:[String:CheckedContinuation<Data,Never>]=[:],calls:[String]=[]
        func load(_ id:String) async -> Data {
            calls.append(id);return await withCheckedContinuation {pending[id]=$0}
        }
        let first=Task {try await pipeline.data(key:"first",priority:.prefetch,authorized:{true}) {_ in await load("first")}}
        let shared=Task {try await pipeline.data(key:"first",priority:.visible,authorized:{true}) {_ in XCTFail("Debe compartir la petición");return Data()}}
        for _ in 0..<100 {if pending["first"] != nil {break};try await Task.sleep(for:.milliseconds(5))}
        let background=Task {try await pipeline.data(key:"background",priority:.prefetch,authorized:{true}) {_ in await load("background")}}
        await Task.yield()
        let visible=Task {try await pipeline.data(key:"visible",priority:.visible,authorized:{true}) {_ in await load("visible")}}
        defer {first.cancel();shared.cancel();background.cancel();visible.cancel();for reply in pending.values {reply.resume(returning:Data())}}
        for _ in 0..<20 {await Task.yield()}
        XCTAssertEqual(calls,["first"])
        first.cancel()
        for _ in 0..<20 {await Task.yield()}
        pending.removeValue(forKey:"first")?.resume(returning:Data([1]))
        let sharedValue=try await shared.value;XCTAssertEqual(sharedValue,Data([1]))
        for _ in 0..<100 {if pending["visible"] != nil {break};try await Task.sleep(for:.milliseconds(5))}
        XCTAssertEqual(calls,["first","visible"],"Una foto visible pasa antes que la cola de fondo")
        pending.removeValue(forKey:"visible")?.resume(returning:Data([2]))
        _ = try await visible.value
        for _ in 0..<100 {if pending["background"] != nil {break};try await Task.sleep(for:.milliseconds(5))}
        pending.removeValue(forKey:"background")?.resume(returning:Data([3]))
        _ = try await background.value
        XCTAssertEqual(calls,["first","visible","background"])
    }

    @MainActor func testPhotoPreviewQueueSharesMeasuredProgressAndWithdrawsCancelledAndRevokedReaders() async throws {
        let pipeline=MediaPhotoPreviewPipeline(monitorNetwork:false)
        var report:MediaPhotoPreviewPipeline.Progress?,reply:CheckedContinuation<Data,Never>?
        var firstValues:[Int64]=[],secondValues:[Int64]=[],permitted=true
        let first=Task {try await pipeline.data(key:"shared-progress",priority:.prefetch,authorized:{true},progress:{received,_ in firstValues.append(received)}) {send in
            report=send;return await withCheckedContinuation {reply=$0}
        }}
        defer {first.cancel();reply?.resume(returning:Data())}
        for _ in 0..<100 {if report != nil {break};try await Task.sleep(for:.milliseconds(5))}
        let send=try XCTUnwrap(report)
        send(50,100)
        let second=Task {try await pipeline.data(key:"shared-progress",priority:.visible,authorized:{permitted},progress:{received,_ in secondValues.append(received)}) {_ in
            XCTFail("El lector visible debe compartir la transferencia precargada");return Data()
        }}
        defer {second.cancel()}
        for _ in 0..<100 {if !secondValues.isEmpty {break};try await Task.sleep(for:.milliseconds(5))}
        XCTAssertEqual(firstValues,[50]);XCTAssertEqual(secondValues,[50],"El lector tardío recibe la medida actual")
        first.cancel()
        do {_ = try await first.value;XCTFail("Cancelar retira sólo ese consumidor")} catch is CancellationError {}
        send(60,100)
        XCTAssertEqual(firstValues,[50]);XCTAssertEqual(secondValues,[50,60])
        permitted=false;send(80,100)
        XCTAssertEqual(secondValues,[50,60],"Revocar retira también los callbacks intermedios")
        reply?.resume(returning:Data([1]));reply=nil
        do {_ = try await second.value;XCTFail("No se entrega el JPEG al lector revocado")} catch is CancellationError {}
        send(90,100)
        XCTAssertEqual(firstValues,[50]);XCTAssertEqual(secondValues,[50,60],"Un reporter antiguo no revive lectores finalizados")
    }

    @MainActor func testPhotoPreviewQueueRejectsRevokedLateResultsAndConnectionPolicyAvoidsBulkOnLowData() async throws {
        let pipeline=MediaPhotoPreviewPipeline(monitorNetwork:false)
        var permitted=true,reply:CheckedContinuation<Data,Never>?
        let read=Task {try await pipeline.data(key:"late",priority:.visible,authorized:{permitted}) {_ in
            await withCheckedContinuation {reply=$0}
        }}
        for _ in 0..<100 {if reply != nil {break};try await Task.sleep(for:.milliseconds(5))}
        permitted=false;reply?.resume(returning:Data([1]));reply=nil
        do {_ = try await read.value;XCTFail("Una respuesta tardía no restaura el acceso")}
        catch is CancellationError {}
        pipeline.updateConnection(MediaPhotoConnection(wifi:true))
        XCTAssertTrue(pipeline.connection.improvesQuality);XCTAssertEqual(pipeline.connection.prefetchCount,Int.max)
        pipeline.measured(bytes:32_000,seconds:2)
        XCTAssertFalse(pipeline.connection.improvesQuality);XCTAssertEqual(pipeline.connection.prefetchCount,6)
        pipeline.updateConnection(MediaPhotoConnection(expensive:true,wifi:false))
        XCTAssertFalse(pipeline.connection.improvesQuality);XCTAssertEqual(pipeline.connection.prefetchCount,6)
        pipeline.updateConnection(MediaPhotoConnection(constrained:true,wifi:true))
        XCTAssertFalse(pipeline.connection.improvesQuality);XCTAssertEqual(pipeline.connection.prefetchCount,0)
        pipeline.updateConnection(MediaPhotoConnection(available:false))
        XCTAssertEqual(pipeline.connection.prefetchCount,0)
    }

    @MainActor func testPendingPhotoPreviewRetriesOnlyTheLightVersionAndKeepsItsSession() async throws {
        let previewJPEG=try photoPreviewJPEGFixture()
        let vault = MemorySession(); vault.token = String(repeating: "f", count: 43)
        let configuration = URLSessionConfiguration.ephemeral; configuration.protocolClasses = [MockProtocol.self]
        let client = PayrollClient(baseURL: URL(string: "https://preview-pending.invalid")!, vault: vault, configuration: configuration, automaticallyDownloadOffline: false)
        let stamp = try client.mediaAccessStamp(), revision = client.cacheRevision
        let item = MediaItem(id: "photo", name: "Original.jpg", mimeType: "image/jpeg", kind: "image", size: 3000000, modifiedAt: "fixture", thumbnailAvailable: true)
        var reads = 0
        MockProtocol.handler = { request in
            reads += 1; XCTAssertTrue(request.url?.query?.contains("preview=1") == true); XCTAssertFalse(request.url?.query?.contains("thumbnail=1") == true)
            if reads == 1 { return (HTTPURLResponse(url: request.url!, statusCode: 503, httpVersion: nil, headerFields: ["Content-Type":"application/json","Retry-After":"0"])!, Data("{\"code\":\"preview_preparing\",\"error\":\"Preparando vista previa\"}".utf8)) }
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type":"image/jpeg"])!, previewJPEG)
        }
        defer { MockProtocol.handler = nil; try? client.clearSession() }
        let document = try await client.mediaPhotoPreview(item); defer { TemporaryDocuments.remove(document) }
        XCTAssertEqual(reads, 2); XCTAssertEqual(try Data(contentsOf: document.url), previewJPEG)
        XCTAssertEqual(try client.mediaAccessStamp(), stamp); XCTAssertEqual(client.cacheRevision, revision); XCTAssertFalse(client.usingOfflineCopy)
    }
    @MainActor func testPhotoPreviewFailureIsReadableBoundedAndDoesNotBecomeAMissingThumbnail() async throws {
        let vault = MemorySession(); vault.token = String(repeating: "f", count: 43)
        let configuration = URLSessionConfiguration.ephemeral; configuration.protocolClasses = [MockProtocol.self]
        let client = PayrollClient(baseURL: URL(string: "https://preview-failure.invalid")!, vault: vault, configuration: configuration, automaticallyDownloadOffline: false)
        let stamp = try client.mediaAccessStamp(), revision = client.cacheRevision
        let item = MediaItem(id: "photo", name: "Original.jpg", mimeType: "image/jpeg", kind: "image", size: 3000000, modifiedAt: "fixture", thumbnailAvailable: true)
        var reads = 0, preparing = true
        MockProtocol.handler = { request in
            reads += 1; XCTAssertTrue(request.url?.query?.contains("preview=1") == true)
            let code = preparing ? "preview_preparing" : "preview_unavailable"
            return (HTTPURLResponse(url: request.url!, statusCode: 503, httpVersion: nil, headerFields: ["Content-Type":"application/json","Retry-After":"0"])!, Data("{\"code\":\"\(code)\",\"error\":\"La vista previa está pendiente. Puedes reintentar.\"}".utf8))
        }
        defer { MockProtocol.handler = nil; try? client.clearSession() }
        do { _ = try await client.mediaPhotoPreview(item); XCTFail("The retry budget must stop") }
        catch let failure as MediaPreviewUnavailable { XCTAssertTrue(failure.preparing); XCTAssertTrue(failure.localizedDescription.contains("vista previa")); XCTAssertFalse(failure.localizedDescription.contains("JACNomina")) }
        XCTAssertEqual(reads, 3)
        preparing = false; reads = 0
        do { _ = try await client.mediaPhotoPreview(item); XCTFail("A definitive failure requires explicit retry") }
        catch let failure as MediaPreviewUnavailable { XCTAssertFalse(failure.preparing) }
        XCTAssertEqual(reads, 1); XCTAssertEqual(try client.mediaAccessStamp(), stamp); XCTAssertEqual(client.cacheRevision, revision); XCTAssertFalse(client.usingOfflineCopy)
    }
    @MainActor func testForbiddenPhotoPreviewNeverRetriesOrFallsBackToAnOriginal() async throws {
        let vault = MemorySession(); vault.token = String(repeating: "f", count: 43)
        let configuration = URLSessionConfiguration.ephemeral; configuration.protocolClasses = [MockProtocol.self]
        let client = PayrollClient(baseURL: URL(string: "https://preview-denial.invalid")!, vault: vault, configuration: configuration, automaticallyDownloadOffline: false)
        let item = MediaItem(id: "photo", name: "Original.jpg", mimeType: "image/jpeg", kind: "image", size: 3000000, modifiedAt: "fixture", thumbnailAvailable: true)
        var reads = 0
        MockProtocol.handler = { request in reads += 1; XCTAssertTrue(request.url?.query?.contains("preview=1") == true);return (HTTPURLResponse(url: request.url!, statusCode: 403, httpVersion: nil, headerFields: ["Content-Type":"application/json"])!, Data("{\"error\":\"Sin acceso\"}".utf8)) }
        defer { MockProtocol.handler = nil; try? client.clearSession() }
        do { _ = try await client.mediaPhotoPreview(item); XCTFail("A denied preview cannot fall back") } catch APIError.forbidden { }
        XCTAssertEqual(reads, 1)
    }
    @MainActor func testGalleryThumbnailUsesOnlyAuthenticatedThumbnailEndpointAndBoundsItsPixels() async throws {
        let vault=MemorySession();vault.token=String(repeating:"f",count:43)
        let configuration=URLSessionConfiguration.ephemeral;configuration.protocolClasses=[MockProtocol.self]
        let client=PayrollClient(baseURL:URL(string:"https://thumbnails.example.invalid")!,vault:vault,configuration:configuration,automaticallyDownloadOffline:false)
        var count=0
        MockProtocol.handler={request in
            count += 1;let parts=try XCTUnwrap(URLComponents(url:try XCTUnwrap(request.url),resolvingAgainstBaseURL:false));XCTAssertEqual(parts.path,"/api/media/file");XCTAssertEqual(parts.queryItems?.first{$0.name == "id"}?.value,"photo_exact-ID");XCTAssertEqual(parts.queryItems?.first{$0.name == "thumbnail"}?.value,"1");XCTAssertEqual(request.value(forHTTPHeaderField:"Cookie"),"__Host-jac_session="+String(repeating:"f",count:43))
            return (HTTPURLResponse(url:request.url!,statusCode:200,httpVersion:nil,headerFields:["Content-Type":"image/png"])!,MediaFixture.photo)
        };defer{MockProtocol.handler=nil}
        let item=MediaItem(id:"photo_exact-ID",name:"No descargar original.png",mimeType:"image/png",kind:"image",size:20*1024*1024*1024,modifiedAt:"fixture",thumbnailAvailable:false)
        let bytes=try await client.mediaThumbnail(item);XCTAssertNotNil(MediaThumbnail.image(bytes));XCTAssertEqual(count,1)
        let context=try XCTUnwrap(CGContext(data:nil,width:1600,height:1000,bitsPerComponent:8,bytesPerRow:0,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)),image=try XCTUnwrap(context.makeImage()),output=NSMutableData()
        let destination=try XCTUnwrap(CGImageDestinationCreateWithData(output,"public.png" as CFString,1,nil));CGImageDestinationAddImage(destination,image,nil);XCTAssertTrue(CGImageDestinationFinalize(destination))
        let bounded=try XCTUnwrap(MediaThumbnail.image(output as Data));XCTAssertLessThanOrEqual(bounded.size.width,360);XCTAssertLessThanOrEqual(bounded.size.height,360)
        XCTAssertNil(MediaThumbnail.image(Data(repeating:0,count:512*1024+1)))
    }
    @MainActor func testMissingThumbnailDoesNotInvalidateOtherImagesOrFolderSession() async throws {
        let vault = MemorySession(); vault.token = String(repeating: "f", count: 43)
        let configuration = URLSessionConfiguration.ephemeral; configuration.protocolClasses = [MockProtocol.self]
        let client = PayrollClient(baseURL: URL(string: "https://missing-cover.invalid")!, vault: vault, configuration: configuration, automaticallyDownloadOffline: false)
        let stamp = try client.mediaAccessStamp(), revision = client.cacheRevision
        let item = MediaItem(id: "no-cover-yet", name: "Pendiente.jpg", mimeType: "image/jpeg", kind: "image", size: 100, modifiedAt: "same", thumbnailAvailable: true)
        var reads = 0
        MockProtocol.handler = { request in
            reads += 1
            return (HTTPURLResponse(url: request.url!, statusCode: 404, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!, Data("{\"error\":\"Miniatura pendiente\"}".utf8))
        }
        defer { MockProtocol.handler = nil; try? client.clearSession() }
        do { _ = try await client.mediaThumbnail(item); XCTFail("La ausencia debe informarse") }
        catch { XCTAssertTrue(error is MediaThumbnailUnavailable) }
        XCTAssertEqual(try client.mediaAccessStamp(), stamp); XCTAssertEqual(client.cacheRevision, revision)
        XCTAssertFalse(client.usingOfflineCopy); XCTAssertEqual(reads, 1)
        #if os(iOS)
        let missing = MediaItem(id: item.id, name: item.name, mimeType: item.mimeType, kind: item.kind, size: item.size, modifiedAt: item.modifiedAt, thumbnailAvailable: false)
        let image = try await MediaGridThumbnailLoader().image(missing, client: client)
        XCTAssertNil(image); XCTAssertEqual(reads, 1, "Una portada aún no indexada no debe generar otro 404")
        #endif
        MockProtocol.handler = { _ in throw URLError(.timedOut) }
        do { _ = try await client.mediaThumbnail(item); XCTFail() } catch {}
        XCTAssertFalse(client.usingOfflineCopy, "Un fallo aislado no desconecta toda la aplicación")
        XCTAssertEqual(try client.mediaAccessStamp(), stamp)
    }
    func testCacheNotificationsPreserveLoadedPagesAndOrderWhileApplyingExplicitDeletions() {
        let items = (0..<120).map { index in
            MediaItem(id: "photo-\(index)", name: String(format: "%03d.jpg", index), mimeType: "image/jpeg", kind: "image", size: 100,
                      modifiedAt: "unchanged", thumbnailAvailable: true, createdAt: "2026-10-19T12:00:00Z")
        }
        let partial = MediaFeed(connected: true, canRead: true, canUpload: false, canConnect: false,
                               root: nil, folder: nil, breadcrumbs: [], items: Array(items.prefix(100)), nextPageToken: "100")
        XCTAssertEqual(MediaGalleryOrder.applyingDeletions(to: items, from: partial), items)
        var deleted = partial; deleted.deletedFiles = ["photo-2", "photo-112"]
        let remaining = MediaGalleryOrder.applyingDeletions(to: items, from: deleted)
        XCTAssertEqual(remaining.map(\.id), items.filter { !["photo-2", "photo-112"].contains($0.id) }.map(\.id))
        XCTAssertEqual(MediaGalleryOrder.sorted(Array(items.reversed())), items)
        XCTAssertEqual(partial.replacingItems(items).items.count, 120)
        XCTAssertEqual(partial.replacingItems(items).nextPageToken, "100")
    }
    func testCachedGalleryIncludesDeletionMarkersForVisibleAndPinnedFolders() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let cache = MediaOfflineCache(root: root), scope = AgendaCacheScope(origin: "https://deletions.invalid", token: String(repeating: "f", count: 43))
        defer { cache.clear(scope); try? FileManager.default.removeItem(at: root) }
        let item = MediaItem(id: "removed", name: "Retirada.jpg", mimeType: "image/jpeg", kind: "image", size: 100, modifiedAt: "old", thumbnailAvailable: true)
        let feed = MediaFeed(connected: true, canRead: true, canUpload: false, canConnect: false, root: nil, folder: MediaFolder(id: "day", name: "Evento"), breadcrumbs: [], items: [item], nextPageToken: nil, collectionID: "jac-r2-test")
        _ = try cache.saveFeed(feed, key: "day", append: false, scope: scope)
        try cache.pinFeed(feed, key: "day", scope: scope)
        var removed = feed.replacingItems([]); removed.deletedFiles = [item.id]
        _ = try cache.saveFeed(removed, key: "day", append: false, scope: scope)
        let saved = try XCTUnwrap(cache.loadFeed("day", scope: scope))
        XCTAssertTrue(saved.items.isEmpty); XCTAssertEqual(saved.deletedFiles, [item.id])
        XCTAssertTrue(MediaGalleryOrder.applyingDeletions(to: [item], from: saved).isEmpty)
    }
    @MainActor func testGalleryRefreshRestoresAllVisiblePagesBeforeReturningTheReplacement() async throws {
        let items = (0..<120).map { index in MediaItem(id: "photo-\(index)", name: String(format: "%03d.jpg", index), mimeType: "image/jpeg", kind: "image", size: 100, modifiedAt: "same", thumbnailAvailable: true) }
        var calls: [String] = []
        let read = try await MediaGalleryListing.read(minimumPages: 1, minimumItems: 120) { cursor in
            calls.append(cursor)
            return MediaFeed(connected: true, canRead: true, canUpload: false, canConnect: false, root: nil, folder: nil, breadcrumbs: [],
                             items: cursor.isEmpty ? Array(items.prefix(100).reversed()) : [items[99]] + Array(items.suffix(20).reversed()), nextPageToken: cursor.isEmpty ? "next" : nil)
        }
        XCTAssertEqual(calls, ["", "next"]); XCTAssertEqual(read.pages, 2)
        XCTAssertEqual(read.feed.items, items); XCTAssertNil(read.feed.nextPageToken)
    }
    @MainActor func testGalleryRefreshDoesNotPublishAPartialReplacementWhenALaterPageFails() async throws {
        let first = MediaFeed(connected: true, canRead: true, canUpload: false, canConnect: false, root: nil, folder: nil, breadcrumbs: [], items: [], nextPageToken: "second")
        var calls: [String] = []
        do {
            _ = try await MediaGalleryListing.read(minimumPages: 2, minimumItems: 0) { cursor in
                calls.append(cursor)
                if !cursor.isEmpty { throw URLError(.timedOut) }
                return first
            }
            XCTFail("Un reemplazo incompleto no debe devolverse a la interfaz")
        } catch { XCTAssertEqual((error as? URLError)?.code, .timedOut) }
        XCTAssertEqual(calls, ["", "second"])
    }
    @MainActor func testGalleryNameTiesMatchServerOrderSoLoadingAnotherPageDoesNotMoveExistingFiles() async throws {
        let names = ["IMG_1.jpg", "IMG_10.jpg", "IMG_2.jpg"]
        let items = names.enumerated().map { index, name in
            MediaItem(id: "photo-\(index)", name: name, mimeType: "image/jpeg", kind: "image", size: 100, modifiedAt: "same", thumbnailAvailable: true, createdAt: "2026-10-19T12:00:00.000Z")
        }
        let read = try await MediaGalleryListing.read(minimumPages: 2, minimumItems: 0) { cursor in
            MediaFeed(connected: true, canRead: true, canUpload: false, canConnect: false, root: nil, folder: nil, breadcrumbs: [],
                      items: cursor.isEmpty ? Array(items.prefix(2)) : [items[2]], nextPageToken: cursor.isEmpty ? "next" : nil)
        }
        XCTAssertEqual(read.feed.items.map(\.name), names)
        XCTAssertEqual(Array(read.feed.items.prefix(2)), Array(items.prefix(2)), "Cargar más conserva las posiciones de las páginas anteriores")
    }
    @MainActor func testGalleryRefreshRejectsRepeatedCursorsAndMixedCollections() async throws {
        let first = MediaFeed(connected: true, canRead: true, canUpload: false, canConnect: false, root: nil, folder: nil, breadcrumbs: [], items: [], nextPageToken: "repeated", collectionID: "original")
        var calls = 0
        do {
            _ = try await MediaGalleryListing.read(minimumPages: 3, minimumItems: 0) { _ in calls += 1; return first }
            XCTFail("Un cursor circular no puede continuar")
        } catch { guard case APIError.invalid = error else { return XCTFail("Error incorrecto: \(error)") } }
        XCTAssertEqual(calls, 2)
        do {
            _ = try await MediaGalleryListing.read(minimumPages: 2, minimumItems: 0) { cursor in
                var value = first; if !cursor.isEmpty { value.collectionID = "another-collection" }; return value
            }
            XCTFail("No se mezclan archivos de colecciones distintas")
        } catch { guard case APIError.forbidden = error else { return XCTFail("Error incorrecto: \(error)") } }
    }
    @MainActor func testControlWorkspaceRevocationReplacesHigherPayrollRevisionWithoutLosingSession() async throws {
        let original=try await UITestBackend.client().workspace()
        var payload=try JSONDecoder().decode(JSONValue.self,from:JSONEncoder().encode(original));payload["version"] = .number(14)
        let configuration=URLSessionConfiguration.ephemeral;configuration.protocolClasses=[MockProtocol.self]
        let vault=MemorySession();vault.token=String(repeating:"f",count:43)
        let client=PayrollClient(baseURL:URL(string:"https://sections.example.invalid")!,vault:vault,configuration:configuration,automaticallyDownloadOffline:false)
        MockProtocol.handler={request in XCTAssertEqual(request.url?.path,"/api/mobile/payroll");return (HTTPURLResponse(url:request.url!,statusCode:200,httpVersion:nil,headerFields:["Content-Type":"application/json"])!,try JSONEncoder().encode(payload))};defer{MockProtocol.handler=nil}
        let store=PayrollStore(client:client);await store.restore();XCTAssertEqual(store.workspace?.version,14);XCTAssertFalse(store.overview?.periods.isEmpty ?? true)
        payload["version"] = .number(0);payload["user"]["isOwner"] = .bool(false);payload["user"]["mediaOnly"] = .bool(true);payload["user"]["itinerariesOnly"] = .bool(true);payload["user"]["sections"] = .array([.string("media")])
        try await store.refresh();XCTAssertEqual(store.workspace?.version,0);XCTAssertFalse(store.overview?.user.hasSection(.payroll) ?? true);XCTAssertTrue(store.overview?.periods.isEmpty == true);XCTAssertTrue(store.overview?.employees.isEmpty == true);XCTAssertTrue(store.hasSavedSession)
        XCTAssertEqual(client.cachedWorkspace()?.version,0);XCTAssertFalse(client.cachedWorkspace()?.user.hasSection(.payroll) ?? true)
    }
    @MainActor func testRejectedWorkspaceSaveCannotRestoreRevokedRoleOrOldAgendaIdentity() async throws {
        let client=UITestBackend.client(),original=try await client.workspace(),agenda=try await client.agenda(month:CalendarClock.month(Date())),scope=try XCTUnwrap(client.agendaScope())
        try client.saveAgenda(AgendaOfflineRecord(schema:1,user:original.user,months:[SavedAgenda(data:agenda,receivedAt:Date())]),scope:scope);XCTAssertNotNil(client.cachedAgenda())
        var json=try JSONDecoder().decode(JSONValue.self,from:JSONEncoder().encode(original));json["version"] = .number(0);json["user"]["isOwner"] = .bool(false);json["user"]["sections"] = .array([.string("calendar")]);json["user"]["displayName"] = .string(String(repeating:"x",count:OfflineResponseCache.maximumEntryBytes+1))
        client.rememberWorkspace(try json.decoded(PayrollWorkspace.self))
        XCTAssertNil(client.cachedWorkspace());XCTAssertNil(client.cachedAgenda());XCTAssertNotNil(client.offlineSyncMessage)
        let vault=MemorySession();vault.token=String(repeating:"f",count:43)
        let reopened=PayrollClient(baseURL:client.baseURL,vault:vault,agendaCache:client.agendaCache,offlineCache:client.offlineCache,automaticallyDownloadOffline:false),store=PayrollStore(client:reopened)
        XCTAssertNil(store.overview);XCTAssertTrue(store.hasSavedSession,"A failed cache write must keep login while withholding stale permissions")
    }
    func testAndersonCanDeleteOnlyWhilePhotographyIsGranted() {
        let anderson = PayrollUser(id: "photo", email: "anderson@example.invalid", username: "anderson", displayName: "Anderson ficticio", isOwner: false, permissions: [], mediaOnly: true)
        XCTAssertTrue(anderson.canDeleteMedia)
        XCTAssertFalse(anderson.hasSection(.crm)); XCTAssertFalse(anderson.can("payroll"))
        var readOnly = anderson; readOnly.sections = ["media"]
        XCTAssertTrue(readOnly.canDeleteMedia); XCTAssertFalse(readOnly.canUploadMedia)
        var revoked = anderson; revoked.sections = []
        XCTAssertFalse(revoked.canDeleteMedia)
        let other = PayrollUser(id: "other", email: anderson.email, username: "other", displayName: anderson.displayName, isOwner: false, permissions: [], mediaOnly: true)
        XCTAssertTrue(other.canUploadMedia); XCTAssertFalse(other.canDeleteMedia)
        let admin = PayrollUser(id: "admin", email: "admin@example.invalid", username: "jac", displayName: "Admin ficticio", isOwner: true, permissions: [])
        XCTAssertTrue(admin.canDeleteMedia)
    }
    func testModernSectionsAreExactAndLegacyRestrictionsRemainDefensive() throws {
        var user=PayrollUser(id:"sections",email:"sections@example.invalid",username:"sections",displayName:"Cuenta ficticia",isOwner:false,permissions:["payroll","export"],itinerariesOnly:true,mediaOnly:true,sections:["media","itineraries"])
        XCTAssertTrue(user.canReadMedia);XCTAssertTrue(user.hasSection(.itineraries));XCTAssertFalse(user.canUploadMedia)
        XCTAssertFalse(user.hasSection(.calendar));XCTAssertFalse(user.hasSection(.boarding));XCTAssertFalse(user.can("payroll"));XCTAssertFalse(user.hasSection(.crm))
        user.sections=["calendar"];XCTAssertEqual(JACSection.allCases.filter{user.hasSection($0)},[.calendar]);XCTAssertEqual(user.firstDestination,"agenda")
        user.sections=["alerts"];XCTAssertEqual(JACSection.allCases.filter{user.hasSection($0)},[.alerts]);XCTAssertTrue(user.hasNotices);XCTAssertEqual(user.firstDestination,"alerts")
        user.sections=["mediaUpload"];XCTAssertFalse(user.canUploadMedia)
        user.sections=["media","crm"];XCTAssertFalse(user.hasSection(.crm))
        user.sections=["media","unknown"];XCTAssertTrue(JACSection.allCases.allSatisfy{!user.hasSection($0)})
        user.sections=[];XCTAssertEqual(user.firstDestination,"management")
        for (sections,destination) in [(["payroll","calendar"],"agenda"),(["calendar"],"agenda"),(["payroll"],"payroll"),(["media"],"media"),(["music"],"music"),(["alerts"],"alerts"),([],"management"),(["calendar","unknown"],"management")] {
            user.sections=sections
            XCTAssertEqual(user.initialMobileDestination,destination)
        }
        let administrator=PayrollUser(id:"admin",email:"admin@example.invalid",username:"admin",displayName:"Administrador ficticio",isOwner:true,permissions:[],sections:[])
        XCTAssertTrue(JACSection.allCases.allSatisfy{administrator.hasSection($0)});XCTAssertTrue(administrator.canUploadMedia)
        XCTAssertEqual(administrator.initialMobileDestination,"agenda")
        let legacy=PayrollUser(id:"legacy",email:"legacy@example.invalid",username:"legacy",displayName:"Legado",isOwner:false,permissions:[],itinerariesOnly:true)
        XCTAssertTrue(legacy.hasSection(.calendar));XCTAssertTrue(legacy.hasSection(.boarding));XCTAssertFalse(legacy.hasSection(.payroll));XCTAssertFalse(legacy.canReadMedia)
    }
    @MainActor func testModernHybridReadsOnlyGrantedModulesOfflineAndRestoresEmptyFinancialWorkspace() async throws {
        let client=UITestBackend.client(),original=try await client.workspace()
        var json=try JSONDecoder().decode(JSONValue.self,from:JSONEncoder().encode(original))
        json["user"]["isOwner"] = .bool(false);json["user"]["mediaOnly"] = .bool(true);json["user"]["itinerariesOnly"] = .bool(true);json["user"]["sections"] = .array([.string("media"),.string("itineraries")])
        let hybrid=try json.decoded(PayrollWorkspace.self);client.rememberWorkspace(hybrid)
        XCTAssertTrue(client.cachedWorkspace()?.periods.isEmpty == true);XCTAssertTrue(client.cachedWorkspace()?.employees.isEmpty == true);XCTAssertTrue(client.cachedWorkspace()?.data["periods"].elements.isEmpty == true)
        let notices=try await client.notices();XCTAssertFalse(notices.notices.isEmpty);XCTAssertTrue(notices.notices.allSatisfy{$0.kind == "itinerary"})
        let media=try await client.media(folder:"media-day"),photo=try XCTUnwrap(media.items.first{$0.kind == "image"});try await client.saveMediaOffline(photo)
        client.beginOfflineRestore();let offlineNotices=try await client.notices();XCTAssertFalse(offlineNotices.notices.isEmpty)
        let document=try await client.mediaDocument(photo);TemporaryDocuments.remove(document)
        do {_ = try await client.detail(periodID:"fixture-period");XCTFail("No payroll details offline")}catch{guard case APIError.forbidden = error else{return XCTFail(String(describing:error))}}
        do {_ = try await client.agenda(month:CalendarClock.month(Date()));XCTFail("No calendar offline")}catch{guard case APIError.forbidden = error else{return XCTFail(String(describing:error))}}
        do {_ = try await client.notices(boarding:"current");XCTFail("No private boarding section offline")}catch{guard case APIError.forbidden = error else{return XCTFail(String(describing:error))}}
        let vault=MemorySession();vault.token=String(repeating:"f",count:43)
        let reopened=PayrollClient(baseURL:client.baseURL,vault:vault,offlineCache:client.offlineCache,mediaOffline:client.mediaOffline,automaticallyDownloadOffline:false),store=PayrollStore(client:reopened)
        XCTAssertTrue(store.hasSavedSession);XCTAssertTrue(store.isOffline);XCTAssertEqual(store.overview?.user.sections,["media","itineraries"]);XCTAssertTrue(store.overview?.periods.isEmpty == true)
        let reopenedMedia=try await reopened.media(folder:"media-day");XCTAssertTrue(reopenedMedia.items.contains{$0.id == photo.id})
    }
    @MainActor func testRevokingNoticeSectionsPurgesOldPDFAndStopsRetainedNoticeReads() async throws {
        let client=UITestBackend.client(),original=try await client.workspace(),feed=try await client.notices(),item=try XCTUnwrap(feed.notices.first{$0.kind == "itinerary"})
        let document=try await client.itinerary(item);TemporaryDocuments.remove(document)
        var json=try JSONDecoder().decode(JSONValue.self,from:JSONEncoder().encode(original));json["user"]["isOwner"] = .bool(false);json["user"]["sections"] = .array([.string("alerts")])
        client.rememberWorkspace(try json.decoded(PayrollWorkspace.self));client.beginOfflineRestore()
        XCTAssertNil(client.cachedNotices());XCTAssertNil(client.cachedNotice(item.id))
        do {_ = try await client.itinerary(item);XCTFail("Retained itinerary must not reopen a revoked PDF")}catch{guard case APIError.forbidden = error else{return XCTFail(String(describing:error))}}
        let scope=try XCTUnwrap(client.offlineScope());XCTAssertFalse(client.offlineCache.entries(scope).contains{URL(string:$0.url)?.path.hasPrefix("/api/notices") == true})
        XCTAssertTrue(try client.hasSession(),"Section revocation preserves the other authorized modules and login")
    }
    @MainActor func testMediaMovieIsPlayableAndBulkPhotosReportsIndividualFailuresWithoutRealLibrary() async throws {
        let client = UITestBackend.client(), root = MediaFolder(id: "media-day", name: "Día ficticio")
        let feed = try await client.media(folder: root.id), video = try XCTUnwrap(feed.items.first { $0.kind == "video" })
        let document = try await client.mediaDocument(video); defer { TemporaryDocuments.remove(document) }
        let tracks = try await AVURLAsset(url: document.url).loadTracks(withMediaType: .video)
        XCTAssertFalse(tracks.isEmpty, "Fixture MOV must be genuinely playable by the native AVFoundation player")
        XCTAssertThrowsError(try DeviceMediaPhotosWriter.validateCreatedAsset(false)); XCTAssertNoThrow(try DeviceMediaPhotosWriter.validateCreatedAsset(true))
        let writer = FakeMediaPhotosWriter(), transfer = MediaFolderTransfer()
        transfer.start(client: client, plan: MediaDownloadPlan(folder: root, files: feed.items), photos: true, writer: writer)
        for _ in 0..<400 { if !transfer.running { break }; try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertFalse(transfer.running); XCTAssertEqual(writer.authorizations, 1); XCTAssertEqual(writer.saved, ["media-photo"])
        XCTAssertEqual(transfer.completed, 1); XCTAssertEqual(transfer.total, 2); XCTAssertEqual(transfer.failures.count, 1)
        XCTAssertTrue(transfer.failures[0].contains("Video ficticio.mov")); XCTAssertEqual(transfer.message, "1 de 2 archivos guardados en Fotos.")
    }
    func testLargeFolderStorageReviewCountsTemporarySpaceWithoutReadingVideoBytes() {
        let files = (0..<5).map { MediaItem(id: String($0), name: "Video ficticio.mov", mimeType: "video/quicktime", kind: "video", size: 10 * 1024 * 1024 * 1024, modifiedAt: "fixture", thumbnailAvailable: false) }
        let plan = MediaDownloadPlan(folder: MediaFolder(id: "root", name: "Ficticia"), files: files)
        XCTAssertEqual(plan.totalBytes, 50 * 1024 * 1024 * 1024)
        XCTAssertGreaterThan(MediaStorageReview.required(files), 60 * 1024 * 1024 * 1024)
        XCTAssertEqual(MediaStorageReview.required([]), 0)
    }
    @MainActor func testMediaManualLogoutErasesCiphertextAndLateDownloadCannotRestoreIt() async throws {
        let client = UITestBackend.client(), feed = try await client.media(folder: "media-day")
        let item = try XCTUnwrap(feed.items.first)
        try await client.saveMediaOffline(item); let scope = try XCTUnwrap(client.mediaScope())
        XCTAssertTrue(client.mediaOffline.hasFile(item, scope: scope)); try client.clearSession()
        XCTAssertFalse(client.mediaOffline.hasFile(item, scope: scope)); XCTAssertNil(client.mediaOffline.loadFeed("media-day", scope: scope)); XCTAssertNil(try client.mediaScope())
        let vault = MemorySession(); vault.token = String(repeating: "f", count: 43)
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [CRMDelayedProtocol.self]
        let delayed = PayrollClient(baseURL: UITestBackend.base, vault: vault, configuration: config)
        CRMDelayedProtocol.resetPending()
        let request = Task { try await delayed.mediaDocument(item) }
        for _ in 0..<100 { if CRMDelayedProtocol.pending() != nil { break }; try await Task.sleep(for: .milliseconds(10)) }
        let held = try XCTUnwrap(CRMDelayedProtocol.pending()); XCTAssertEqual(held.request.url?.path, "/api/media/file"); try delayed.clearSession(); held.respond(MediaFixture.photo)
        do { _ = try await request.value; XCTFail("Late media download must not return a document after logout") } catch { XCTAssertTrue(error is CancellationError, String(describing: error)) }
    }
    func testPhotographerRoleDoesNotInheritPayrollOrGeneralAccess() throws {
        let user = try JSONDecoder().decode(PayrollUser.self, from: Data("{\"id\":\"photo\",\"email\":\"anderson@example.invalid\",\"username\":\"anderson\",\"displayName\":\"Anderson ficticio\",\"isOwner\":false,\"permissions\":[],\"itinerariesOnly\":true,\"mediaOnly\":true}".utf8))
        XCTAssertTrue(user.canReadMedia); XCTAssertTrue(user.canUploadMedia); XCTAssertFalse(user.can("payroll")); XCTAssertFalse(user.can("users"))
        var malicious = user; malicious = PayrollUser(id: user.id, email: user.email, username: user.username, displayName: user.displayName, isOwner: true, permissions: ["payroll"], mediaOnly: true)
        XCTAssertFalse(malicious.can("payroll"), "The media restriction overrides an owner flag")
        let historical = try JSONDecoder().decode(PayrollUser.self, from: Data("{\"id\":\"reader\",\"email\":\"reader@example.invalid\",\"username\":\"reader\",\"displayName\":\"Reader\",\"isOwner\":false,\"permissions\":[]}".utf8))
        XCTAssertFalse(historical.canReadMedia); XCTAssertFalse(historical.canUploadMedia)
    }
    func testDeletedFolderPrunesOnlyItsOfflineSubtreeAndLateCopiesCannotRestoreIt() throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString);defer{try? FileManager.default.removeItem(at:root)}
        let cache=MediaOfflineCache(root:root),scope=AgendaCacheScope(origin:"https://delete.example.invalid/media-offline-v1",token:String(repeating:"f",count:43)),base=MediaFolder(id:"jac_r2_root",name:"Fotografía"),target=MediaFolder(id:"r2_"+UUID().uuidString.lowercased(),name:"Borrar"),child=MediaFolder(id:"r2_"+UUID().uuidString.lowercased(),name:"Dentro"),other=MediaFolder(id:"r2_"+UUID().uuidString.lowercased(),name:"Conservar")
        func file(_ name:String)->MediaItem {MediaItem(id:"r2_"+UUID().uuidString.lowercased(),name:name+".png",mimeType:"image/png",kind:"image",size:Int64(MediaFixture.photo.count),modifiedAt:"fixture",thumbnailAvailable:true)}
        func folderItem(_ folder:MediaFolder)->MediaItem {MediaItem(id:folder.id,name:folder.name,mimeType:"application/vnd.google-apps.folder",kind:"folder",size:0,modifiedAt:"fixture",thumbnailAvailable:false)}
        func feed(_ folder:MediaFolder,_ breadcrumbs:[MediaFolder],_ items:[MediaItem])->MediaFeed {MediaFeed(connected:true,canRead:true,canUpload:true,canConnect:false,root:base,folder:folder,breadcrumbs:breadcrumbs,items:items,nextPageToken:nil,provider:"r2",collectionID:"jac-r2-test")}
        let one=file("Uno"),two=file("Dos"),kept=file("Conservar"),feeds=[feed(base,[base],[folderItem(target),folderItem(other)]),feed(target,[base,target],[one,folderItem(child)]),feed(child,[base,target,child],[two]),feed(other,[base,other],[kept])]
        for item in feeds {try cache.saveFeed(item,key:item.folder!.id,append:false,scope:scope);try cache.pinFeed(item,key:item.folder!.id,scope:scope)}
        let source=try TemporaryDocuments.save(MediaFixture.photo,filename:"Fixture.png");defer{TemporaryDocuments.remove(source)}
        for item in [one,two,kept] {try cache.saveFile(source.url,item:item,scope:scope)}
        try cache.removeFolders([target.id],scope:scope)
        let reopened=MediaOfflineCache(root:root)
        XCTAssertNil(reopened.loadFeed(target.id,scope:scope));XCTAssertNil(reopened.loadFeed(child.id,scope:scope));XCTAssertEqual(reopened.loadFeed(base.id,scope:scope)?.items.map(\.id),[other.id]);XCTAssertTrue(reopened.hasFile(kept,scope:scope));XCTAssertFalse(reopened.hasFile(one,scope:scope));XCTAssertFalse(reopened.hasFile(two,scope:scope))
        XCTAssertThrowsError(try reopened.saveFile(source.url,item:one,scope:scope));XCTAssertThrowsError(try reopened.saveFeed(feeds[1],key:target.id,append:false,scope:scope));XCTAssertThrowsError(try reopened.pinFeed(feeds[1],key:target.id,scope:scope))
        try reopened.saveFeed(feeds[0],key:base.id,append:false,scope:scope);XCTAssertEqual(reopened.loadFeed(base.id,scope:scope)?.items.map(\.id),[other.id]);let document=try XCTUnwrap(reopened.document(kept,scope:scope));defer{TemporaryDocuments.remove(document)};XCTAssertEqual(try Data(contentsOf:document.url),MediaFixture.photo)
    }
    func testIndividuallyPinnedPhotoSurvivesReopenAndRemoteDeletionRetiresOnlyThatPhoto() throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer {try? FileManager.default.removeItem(at:root)}
        let cache=MediaOfflineCache(root:root),scope=AgendaCacheScope(origin:"https://photo-actions.invalid/media-offline-v1",token:String(repeating:"f",count:43)),folder=MediaFolder(id:"jac_r2_root",name:"Fotografía")
        func photo(_ id:String)->MediaItem {MediaItem(id:id,name:id+".png",mimeType:"image/png",kind:"image",size:Int64(MediaFixture.photo.count),modifiedAt:"fixture",thumbnailAvailable:true)}
        let one=photo("r2_one-photo"),two=photo("r2_two-photo"),feed=MediaFeed(connected:true,canRead:true,canUpload:true,canConnect:false,root:folder,folder:folder,breadcrumbs:[folder],items:[one,two],nextPageToken:nil,provider:"r2",collectionID:"jac-r2-test")
        try cache.saveFeed(feed,key:"",append:false,scope:scope)
        let source=try TemporaryDocuments.save(MediaFixture.photo,filename:"Fixture.png");defer{TemporaryDocuments.remove(source)}
        for item in [one,two] {try cache.saveFile(source.url,item:item,scope:scope,preview:true)}
        XCTAssertFalse(cache.isPinned(one,scope:scope));try cache.pinFile(one,scope:scope)
        let reopened=MediaOfflineCache(root:root);XCTAssertTrue(reopened.isPinned(one,scope:scope));XCTAssertFalse(reopened.isPinned(two,scope:scope))
        var removed=feed;removed.deletedFiles=[one.id]
        let safe=try reopened.saveFeed(removed,key:"",append:false,scope:scope)
        XCTAssertEqual(safe.items.map(\.id),[two.id]);XCTAssertFalse(reopened.hasFile(one,scope:scope));XCTAssertTrue(reopened.hasFile(two,scope:scope))
        XCTAssertNil(try reopened.document(one,scope:scope));XCTAssertThrowsError(try reopened.pinFile(one,scope:scope));XCTAssertThrowsError(try reopened.saveFile(source.url,item:one,scope:scope))
        let stale=try reopened.saveFeed(feed,key:"",append:false,scope:scope);XCTAssertEqual(stale.items.map(\.id),[two.id])
        let document=try XCTUnwrap(reopened.document(two,scope:scope));defer{TemporaryDocuments.remove(document)};XCTAssertEqual(try Data(contentsOf:document.url),MediaFixture.photo)
    }
    @MainActor func testIndividualPhotoDeletionUsesCurrentRevisionAndPreservesOtherPhotosAndSession() async throws {
        let client=UITestBackend.client();_=try await client.workspace();let root=try await client.media(),folder=try XCTUnwrap(root.items.first{$0.kind=="folder"})
        let feed=try await client.media(folder:folder.id),photo=try XCTUnwrap(feed.items.first{$0.kind=="image"})
        try await client.saveMediaOffline(photo);let scope=try XCTUnwrap(client.mediaScope());XCTAssertTrue(client.mediaOffline.isPinned(photo,scope:scope))
        let result=try await client.deleteMediaFileStep(photo);XCTAssertEqual(result.id,photo.id);XCTAssertEqual(result.complete,true)
        XCTAssertFalse(client.mediaOffline.hasFile(photo,scope:scope));XCTAssertFalse(client.cachedMedia(folder:folder.id)?.items.contains{$0.id==photo.id} ?? true)
        XCTAssertNotNil(client.cachedWorkspace());let workspace=try await client.workspace();XCTAssertTrue(workspace.user.canReadMedia)
    }
    #if os(iOS)
    @MainActor func testMediaSelectionIncludesPhotosAndVideosAcrossFoldersWithoutSelectingFolders() async throws {
        let client = UITestBackend.client(); _ = try await client.workspace()
        let feed = try await client.media(folder: "media-day"), model = MediaBatchSelection()
        let photo = try XCTUnwrap(feed.items.first { $0.kind == "image" }), video = try XCTUnwrap(feed.items.first { $0.kind == "video" })
        model.select(photo, in: feed, client: client); model.select(photo, in: feed, client: client)
        model.toggle(video, in: feed, client: client)
        XCTAssertTrue(model.active); XCTAssertEqual(model.items.map(\.id), [photo.id, video.id]); XCTAssertTrue(model.canDelete)
        let folder = MediaItem(id: "folder", name: "No seleccionar", mimeType: "application/vnd.google-apps.folder", kind: "folder", size: 0, modifiedAt: "fixture", thumbnailAvailable: false)
        model.select(folder, in: feed, client: client); XCTAssertEqual(model.count, 2)
        model.toggle(photo, in: feed, client: client); XCTAssertEqual(model.items, [video])
        let other = MediaItem(id: "other", name: "Otra.png", mimeType: photo.mimeType, kind: "image", size: photo.size, modifiedAt: "other-revision", thumbnailAvailable: true)
        let otherFeed = MediaFeed(connected: true, canRead: true, canUpload: false, canConnect: false, root: feed.root, folder: MediaFolder(id: "other-day", name: "Otro día"), breadcrumbs: feed.breadcrumbs, items: [other], nextPageToken: nil, collectionID: feed.collectionID, canDelete: false)
        model.toggle(other, in: otherFeed, client: client); XCTAssertEqual(model.items.map(\.id), [video.id, other.id]); XCTAssertFalse(model.canDelete)
        model.toggle(other, in: otherFeed, client: client); model.toggle(video, in: feed, client: client)
        XCTAssertTrue(model.active); XCTAssertEqual(model.count, 0)
        model.reset(); XCTAssertFalse(model.active)
    }
    @MainActor func testMediaSelectionPreservesUnlistedPagesAndPrunesOnlyConfirmedChanges() async throws {
        let client = UITestBackend.client(); _ = try await client.workspace()
        let feed = try await client.media(folder: "media-day"), model = MediaBatchSelection()
        for item in feed.items { model.select(item, in: feed, client: client) }
        var page = MediaFeed(connected: true, canRead: true, canUpload: false, canConnect: false, root: feed.root, folder: feed.folder, breadcrumbs: feed.breadcrumbs, items: [], nextPageToken: "next", collectionID: feed.collectionID, canDelete: feed.canDelete)
        model.reconcile(page); XCTAssertEqual(model.count, feed.items.count, "A missing page is not a deletion")
        page.deletedFiles = [feed.items[0].id]; model.reconcile(page); XCTAssertEqual(model.items, Array(feed.items.dropFirst()))
        page.deletedFolders = [try XCTUnwrap(feed.folder?.id)]; model.reconcile(page); XCTAssertEqual(model.count, 0)
        model.select(feed.items[0], in: feed, client: client)
        var replacement = page; replacement.collectionID = "another-collection"; model.reconcile(replacement)
        XCTAssertFalse(model.active); XCTAssertEqual(model.count, 0)
        model.select(feed.items[0], in: feed, client: client)
        let old = feed.items[0], revised = MediaItem(id: old.id, name: old.name, mimeType: old.mimeType, kind: old.kind, size: old.size, modifiedAt: "new-revision", thumbnailAvailable: old.thumbnailAvailable, createdAt: old.createdAt)
        var refreshed = MediaFeed(connected: true, canRead: true, canUpload: false, canConnect: false, root: feed.root, folder: feed.folder, breadcrumbs: feed.breadcrumbs, items: [revised], nextPageToken: nil, collectionID: feed.collectionID, canDelete: true)
        model.reconcile(refreshed); XCTAssertEqual(model.count, 0, "A changed revision must be selected again before deletion")
        model.select(revised, in: refreshed, client: client); XCTAssertTrue(model.canDelete)
        var cached = refreshed; cached.canDelete = nil
        model.reconcile(cached); XCTAssertTrue(model.canDelete, "A cache refresh omits write permissions and must not revoke a confirmed permission")
        refreshed.canDelete = false; model.reconcile(refreshed); XCTAssertFalse(model.canDelete)
    }
    @MainActor func testMediaSelectionIsRemovedOnSessionChangeAndPermissionRevocation() async throws {
        let client = UITestBackend.client(), workspace = try await client.workspace(), feed = try await client.media(folder: "media-day"), model = MediaBatchSelection()
        model.select(feed.items[0], in: feed, client: client)
        var changed = try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(workspace))
        changed["user"]["isOwner"] = .bool(false); changed["user"]["administrator"] = .bool(false); changed["user"]["sections"] = .array([.string("calendar")])
        client.rememberWorkspace(try changed.decoded(PayrollWorkspace.self)); model.synchronize(client: client)
        XCTAssertFalse(model.active); XCTAssertEqual(model.count, 0)
        client.rememberWorkspace(workspace); model.select(feed.items[0], in: feed, client: client)
        try client.clearSession(); model.synchronize(client: client); XCTAssertFalse(model.active); XCTAssertEqual(model.count, 0)
    }
    @MainActor private func selectionDeletionFixture() async throws -> (PayrollClient, MediaFeed) {
        let workspace = try await UITestBackend.client().workspace(), vault = MemorySession(); vault.token = String(repeating: "f", count: 43)
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [MockProtocol.self]
        let cache = MediaOfflineCache(root: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        let client = PayrollClient(baseURL: URL(string: "https://selection.example.invalid")!, vault: vault, configuration: config, mediaOffline: cache, automaticallyDownloadOffline: false)
        client.rememberWorkspace(workspace)
        let folder = MediaFolder(id: "r2_day", name: "Selección ficticia")
        let items = ["image", "video", "image"].enumerated().map { index, kind in MediaItem(id: "r2_file_\(index)", name: "Archivo \(index)", mimeType: kind == "image" ? "image/png" : "video/quicktime", kind: kind, size: 100, modifiedAt: "revision-\(index)", thumbnailAvailable: true) }
        let feed = MediaFeed(connected: true, canRead: true, canUpload: false, canConnect: false, root: folder, folder: folder, breadcrumbs: [folder], items: items, nextPageToken: nil, provider: "r2", collectionID: "jac-r2-selection", canDelete: true)
        try cache.saveFeed(feed, key: folder.id, append: false, scope: XCTUnwrap(client.mediaScope()))
        return (client, feed)
    }
    @MainActor func testAndersonCanDeleteExistingPhotoVideoBatchAndFolder() async throws {
        let (client, feed) = try await selectionDeletionFixture(), model = MediaBatchSelection()
        defer { MockProtocol.handler = nil; try? client.clearSession() }
        var payload = try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(try await UITestBackend.client().workspace()))
        payload["user"]["username"] = .string("anderson"); payload["user"]["isOwner"] = .bool(false)
        payload["user"]["permissions"] = .array([]); payload["user"]["sections"] = .array([.string("media")])
        client.rememberWorkspace(try payload.decoded(PayrollWorkspace.self))
        let targets = Array(feed.items.prefix(2))
        for item in targets { model.select(item, in: feed, client: client) }
        var commands: [String] = []
        MockProtocol.handler = { request in
            let body = try JSONDecoder().decode(JSONValue.self, from: MockProtocol.requestBody(request))
            commands.append(body["action"].text)
            let result = MediaFolderDeletion(id: body["id"].text, parentId: "r2_parent", name: body["id"].text, removed: 1, complete: true)
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!, try JSONEncoder().encode(result))
        }
        model.delete(targets, client: client) { XCTFail("Unexpected denial: \($0)") }
        for _ in 0..<400 where model.deleting { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertFalse(model.deleting); XCTAssertEqual(model.completed, 2); XCTAssertTrue(model.failures.isEmpty)
        _ = try await client.deleteMediaFolderStep(try XCTUnwrap(feed.folder))
        XCTAssertEqual(commands, ["deleteFile", "deleteFile", "deleteFolder"])
    }
    @MainActor func testMediaBatchDeletionRetriesTheSameRevisionAndKeepsUnselectedFiles() async throws {
        let (client, feed) = try await selectionDeletionFixture(), model = MediaBatchSelection()
        defer { MockProtocol.handler = nil; try? client.clearSession() }
        let targets = Array(feed.items.prefix(2)); for item in targets { model.select(item, in: feed, client: client) }
        var calls: [String] = []
        MockProtocol.handler = { request in
            XCTAssertEqual(request.url?.host, "selection.example.invalid"); XCTAssertEqual(request.url?.path, "/api/media"); XCTAssertEqual(request.httpMethod, "POST")
            let body = try JSONDecoder().decode(JSONValue.self, from: MockProtocol.requestBody(request)), id = body["id"].text
            XCTAssertEqual(body["action"].text, "deleteFile"); XCTAssertEqual(body["revision"].text, targets.first { $0.id == id }?.modifiedAt)
            calls.append(id)
            let result = MediaFolderDeletion(id: id, parentId: feed.folder!.id, name: id, removed: 1, complete: calls.count != 1, waiting: false)
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!, try JSONEncoder().encode(result))
        }
        model.delete(targets, client: client) { XCTFail("Unexpected denial: \($0)") }
        for _ in 0..<400 where model.deleting { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertFalse(model.deleting); XCTAssertEqual(model.completed, 2); XCTAssertTrue(model.failures.isEmpty)
        XCTAssertEqual(calls, [targets[0].id, targets[0].id, targets[1].id]); XCTAssertEqual(model.count, 0)
        XCTAssertEqual(client.cachedMedia(folder: feed.folder!.id)?.items, [feed.items[2]])
        model.synchronize(client: client); XCTAssertTrue(model.active, "Own deletions may advance the cache stamp without invalidating the batch")
    }
    @MainActor func testMediaBatchDeletionReportsConflictAndKeepsThatFileSelected() async throws {
        let (client, feed) = try await selectionDeletionFixture(), model = MediaBatchSelection()
        defer { MockProtocol.handler = nil; try? client.clearSession() }
        let targets = Array(feed.items.prefix(2)); for item in targets { model.select(item, in: feed, client: client) }
        MockProtocol.handler = { request in
            let body = try JSONDecoder().decode(JSONValue.self, from: MockProtocol.requestBody(request)), id = body["id"].text
            let conflict = id == targets[0].id
            let data = conflict ? Data("{\"error\":\"El archivo cambió\"}".utf8) : try JSONEncoder().encode(MediaFolderDeletion(id: id, parentId: feed.folder!.id, name: id, removed: 1, complete: true))
            return (HTTPURLResponse(url: request.url!, statusCode: conflict ? 409 : 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!, data)
        }
        model.delete(targets, client: client) { XCTFail("Unexpected denial: \($0)") }
        for _ in 0..<400 where model.deleting { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertFalse(model.deleting); XCTAssertEqual(model.completed, 1); XCTAssertEqual(model.failures.count, 1)
        XCTAssertEqual(model.items, [targets[0]]); XCTAssertEqual(model.message, "1 de 2 archivos eliminados.")
    }
    @MainActor func testMediaBatchDeletionStopsImmediatelyWhenAuthorizationIsRevoked() async throws {
        let (client, feed) = try await selectionDeletionFixture(), model = MediaBatchSelection()
        defer { MockProtocol.handler = nil; try? client.clearSession() }
        for item in feed.items { model.select(item, in: feed, client: client) }
        var calls = 0, denials = 0
        MockProtocol.handler = { request in calls += 1; return (HTTPURLResponse(url: request.url!, statusCode: 403, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!, Data("{\"error\":\"Acceso retirado\"}".utf8)) }
        model.delete(model.items, client: client) { _ in denials += 1 }
        for _ in 0..<400 where model.deleting { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertEqual(calls, 1); XCTAssertEqual(denials, 1); XCTAssertFalse(model.active); XCTAssertEqual(model.count, 0)
    }
    @MainActor func testMediaBatchCancellationStopsPendingRetriesAndProtectsANewSelection() async throws {
        let (client, feed) = try await selectionDeletionFixture(), model = MediaBatchSelection()
        defer { MockProtocol.handler = nil; try? client.clearSession() }
        for item in feed.items.prefix(2) { model.select(item, in: feed, client: client) }
        var calls = 0
        MockProtocol.handler = { request in
            calls += 1
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!, try JSONEncoder().encode(MediaFolderDeletion(id: feed.items[0].id, parentId: feed.folder!.id, name: "Pendiente", removed: 0, complete: false, waiting: true)))
        }
        model.delete(model.items, client: client) { XCTFail("Unexpected denial: \($0)") }
        for _ in 0..<200 where calls == 0 { try await Task.sleep(for: .milliseconds(10)) }
        model.reset(); model.select(feed.items[2], in: feed, client: client)
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(calls, 1); XCTAssertFalse(model.deleting); XCTAssertEqual(model.items, [feed.items[2]]); XCTAssertNil(model.message)
    }
    @MainActor func testSelectedPhotoAndVideoDownloadsKeepTheirOriginalBytesAndExcludeOtherItems() async throws {
        let client = UITestBackend.client(); _ = try await client.workspace()
        let feed = try await client.media(folder: "media-day"), model = MediaBatchSelection(), writer = SelectionMediaPhotosWriter(), transfer = MediaFolderTransfer()
        for item in feed.items { model.select(item, in: feed, client: client) }
        let plan = MediaDownloadPlan(folder: feed.folder!, files: model.items)
        transfer.start(client: client, plan: plan, photos: true, writer: writer)
        for _ in 0..<400 where transfer.running { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertFalse(transfer.running); XCTAssertTrue(transfer.failures.isEmpty); XCTAssertEqual(transfer.completed, 2)
        XCTAssertEqual(writer.saved["media-photo"], MediaFixture.photo); XCTAssertEqual(writer.saved["media-video"], MediaFixture.video)
        model.toggle(feed.items.first { $0.kind == "image" }!, in: feed, client: client)
        transfer.start(client: client, plan: MediaDownloadPlan(folder: feed.folder!, files: model.items), photos: false)
        for _ in 0..<400 where transfer.running { try await Task.sleep(for: .milliseconds(10)) }
        let scope = try XCTUnwrap(client.mediaScope())
        XCTAssertEqual(transfer.completed, 1); XCTAssertTrue(client.mediaOffline.isPinned(feed.items.first { $0.kind == "video" }!, scope: scope))
        XCTAssertFalse(client.mediaOffline.isPinned(feed.items.first { $0.kind == "image" }!, scope: scope))
    }
    #endif
    @MainActor func testLocalFolderRemovalKeepsServerGalleryAndAllowsDownloadingAgain() async throws {
        let client = UITestBackend.client(); _ = try await client.workspace()
        _ = try await client.media()
        let plan = try await client.mediaDownloadPlan(folder: "media-day")
        for item in plan.files { try await client.saveMediaOffline(item) }
        let scope = try XCTUnwrap(client.mediaScope()), item = try XCTUnwrap(plan.files.first)
        let folders = await client.localMediaFoldersForPresentation()
        XCTAssertTrue(folders.contains("media-day"))
        let bytes = try await client.removeLocalMediaFolder("media-day")
        XCTAssertGreaterThan(bytes, 0)
        XCTAssertFalse(client.mediaOffline.hasFile(item, scope: scope))
        XCTAssertFalse(client.mediaOffline.isDeleted(item.id, scope: scope))
        XCTAssertTrue(client.cachedMedia(folder: "media-day")?.items.contains(where: { $0.id == item.id }) == true)
        let after = try await client.media(folder: "media-day")
        XCTAssertTrue(after.items.contains(where: { $0.id == item.id }))
        let removedFolders = await client.localMediaFoldersForPresentation()
        XCTAssertFalse(removedFolders.contains("media-day"))
        try await client.saveMediaOffline(item)
        XCTAssertTrue(client.mediaOffline.hasFile(item, scope: scope))
    }

    func testLocalFolderRemovalIsRecursiveAndPreservesOtherFoldersAndSessions() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let cache = MediaOfflineCache(root: root), scope = AgendaCacheScope(origin: "https://fixture.invalid", token: String(repeating:"p", count:43))
        let other = AgendaCacheScope(origin:"https://fixture.invalid", token:String(repeating:"q",count:43))
        let parent = MediaFolder(id:"parent",name:"Padre"), child=MediaFolder(id:"child",name:"Hija"), sibling=MediaFolder(id:"sibling",name:"Otra")
        let source = try TemporaryDocuments.save(MediaFixture.photo, filename:"Local.png"); defer { TemporaryDocuments.remove(source) }
        func item(_ id:String)->MediaItem { MediaItem(id:id,name:id+".png",mimeType:"image/png",kind:"image",size:Int64(MediaFixture.photo.count),modifiedAt:"one",thumbnailAvailable:false) }
        let first=item("first"), second=item("second")
        func feed(_ folder:MediaFolder,_ path:[MediaFolder],_ files:[MediaItem])->MediaFeed { MediaFeed(connected:true,canRead:true,canUpload:false,canConnect:false,root:parent,folder:folder,breadcrumbs:path,items:files,nextPageToken:nil,provider:"r2",collectionID:"fixture") }
        let childFeed=feed(child,[parent,child],[first]), siblingFeed=feed(sibling,[sibling],[second])
        for current in [scope,other] {
            _ = try cache.saveFeed(childFeed,key:child.id,append:false,scope:current);try cache.pinFeed(childFeed,key:child.id,scope:current)
            _ = try cache.saveFeed(siblingFeed,key:sibling.id,append:false,scope:current);try cache.pinFeed(siblingFeed,key:sibling.id,scope:current)
            try cache.saveFile(source.url,item:first,scope:current);try cache.saveFile(source.url,item:second,scope:current)
        }
        let epoch=cache.localDownloadEpoch
        XCTAssertEqual(try cache.forgetLocalFolder(parent.id,scope:scope),first.size)
        XCTAssertFalse(cache.hasFile(first,scope:scope));XCTAssertTrue(cache.hasFile(second,scope:scope));XCTAssertTrue(cache.hasFile(first,scope:other))
        XCTAssertFalse(cache.isDeleted(first.id,scope:scope));XCTAssertNotNil(cache.loadFeed(child.id,scope:scope))
        XCTAssertThrowsError(try cache.saveFile(source.url,item:first,scope:scope,expectedLocalEpoch:epoch))
        XCTAssertFalse(cache.hasFile(first,scope:scope),"A download started before removal cannot restore the deleted copy")
        try cache.saveFile(source.url,item:first,scope:scope,expectedLocalEpoch:cache.localDownloadEpoch)
        XCTAssertTrue(cache.hasFile(first,scope:scope))
    }

    @MainActor func testDirectPhotoSaveWritesTheOriginalAndCleansItsTemporaryFile() async throws {
        let client=UITestBackend.client();_ = try await client.workspace()
        let feed=try await client.media(folder:"media-day"), item=try XCTUnwrap(feed.items.first(where:{$0.kind=="image"}))
        let writer=SelectionMediaPhotosWriter()
        try await MediaPhotosExport.save(item,client:client,writer:writer)
        XCTAssertEqual(writer.saved[item.id],MediaFixture.photo)
        XCTAssertFalse(FileManager.default.fileExists(atPath: try XCTUnwrap(writer.lastURL).path))
    }

    @MainActor func testDirectPhotoSaveStopsAfterDeniedPermissionOrSessionChange() async throws {
        let client=UITestBackend.client();_ = try await client.workspace()
        let feed=try await client.media(folder:"media-day"), item=try XCTUnwrap(feed.items.first(where:{$0.kind=="image"}))
        do { try await MediaPhotosExport.save(item,client:client,writer:DeniedMediaPhotosWriter());XCTFail("Debe respetar Fotos") } catch { }
        let writer=SelectionMediaPhotosWriter();writer.authorizeAction={try client.clearSession()}
        do { try await MediaPhotosExport.save(item,client:client,writer:writer);XCTFail("Debe respetar la sesión") } catch { }
        XCTAssertTrue(writer.saved.isEmpty)
    }

    @MainActor func testBulkPhotoExportStopsIfSessionChangesWhilePhotosPermissionIsPending() async throws {
        let client = UITestBackend.client(); _ = try await client.workspace()
        let feed = try await client.media(folder: "media-day"), writer = SelectionMediaPhotosWriter(), transfer = MediaFolderTransfer()
        writer.authorizeAction = { try client.clearSession() }
        transfer.start(client: client, plan: MediaDownloadPlan(folder: feed.folder!, files: feed.items), photos: true, writer: writer)
        for _ in 0..<400 where transfer.running { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertFalse(transfer.running); XCTAssertEqual(transfer.completed, 0); XCTAssertTrue(writer.saved.isEmpty)
        XCTAssertEqual(transfer.message, "Operación detenida. Los archivos completados se conservan.")
    }
    @MainActor func testNativeFolderDeletionUsesJACAndKeepsSessionAndOtherModules() async throws {
        let client=UITestBackend.client();_ = try await client.workspace();let root=try await client.media(),folder=try XCTUnwrap(root.items.first{$0.kind=="folder"});_ = try await client.media(folder:folder.id)
        let result=try await client.deleteMediaFolderStep(MediaFolder(id:folder.id,name:folder.name));XCTAssertEqual(result.id,folder.id);XCTAssertEqual(result.complete,true);XCTAssertNil(client.cachedMedia(folder:folder.id));XCTAssertFalse(client.cachedMedia()?.items.contains{$0.id==folder.id} ?? true)
        let after=try await client.workspace();XCTAssertTrue(after.user.canReadMedia);XCTAssertTrue(after.user.hasSection(.payroll));XCTAssertNotNil(client.cachedWorkspace())
    }
    func testMediaCacheStreamsAuthenticatedBlocksAndRejectsCorruptionOtherSessionAndOldRevision() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString), source = root.appendingPathComponent("source.mov")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true); defer { try? FileManager.default.removeItem(at: root) }
        let bytes = Data(repeating: 71, count: 2 * 1024 * 1024 + 333); try bytes.write(to: source)
        let cache = MediaOfflineCache(root: root.appendingPathComponent("cache")), scope = AgendaCacheScope(origin: "https://fixture.invalid/media-offline-v1", token: String(repeating: "f", count: 43))
        let item = MediaItem(id: "movie", name: "Ficticio.mov", mimeType: "video/quicktime", kind: "video", size: Int64(bytes.count), modifiedAt: "2026-10-16T12:00:00Z", thumbnailAvailable: false)
        try cache.saveFile(source, item: item, scope: scope)
        XCTAssertTrue(cache.hasFile(item, scope: scope)); XCTAssertFalse(try Data(contentsOf: cache.encryptedFile(item, scope: scope)).contains(Data(repeating: 71, count: 100)))
        let opened = try XCTUnwrap(cache.document(item, scope: scope)); defer { TemporaryDocuments.remove(opened) }
        XCTAssertEqual(try Data(contentsOf: opened.url), bytes)
        let other = AgendaCacheScope(origin: "https://fixture.invalid/media-offline-v1", token: String(repeating: "x", count: 43))
        XCTAssertNil(try cache.document(item, scope: other))
        let updated = MediaItem(id: item.id, name: item.name, mimeType: item.mimeType, kind: item.kind, size: item.size, modifiedAt: "2026-10-17T12:00:00Z", thumbnailAvailable: false)
        XCTAssertFalse(cache.hasFile(updated, scope: scope)); XCTAssertNil(try cache.document(updated, scope: scope))
        #if os(macOS)
        let attrs = try FileManager.default.attributesOfItem(atPath: cache.encryptedFile(item, scope: scope).path)
        XCTAssertEqual((attrs[.posixPermissions] as? NSNumber)?.intValue, 0o600)
        #endif
        XCTAssertEqual(try cache.root.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup, true)
        var broken = try Data(contentsOf: cache.encryptedFile(item, scope: scope)); broken[64] ^= 1; try broken.write(to: cache.encryptedFile(item, scope: scope))
        XCTAssertThrowsError(try cache.document(item, scope: scope)); cache.clear(scope)
        XCTAssertFalse(cache.hasFile(item, scope: scope)); XCTAssertFalse(FileManager.default.fileExists(atPath: cache.encryptedFile(item, scope: scope).path))
    }
    func testUploadSpeedCountsBytesFromConcurrentTransfersAndExpiresWhenIdle() {
        var meter=MediaUploadRate();meter.record(1000,at:0);meter.record(1000,at:0);XCTAssertEqual(meter.rate(at:0.5),2000)
        meter.record(1000,at:0.5);meter.record(0,at:0.5);XCTAssertEqual(meter.rate(at:0.5),3000);XCTAssertEqual(meter.rate(at:5),0)
    }
    @MainActor func testDeniedPhotosPermissionReportsAnActionableResultWithoutDownloading() async throws {
        let client=UITestBackend.client(),plan=MediaDownloadPlan(folder:MediaFolder(id:"ficticia",name:"Prueba"),files:[]),transfer=MediaFolderTransfer()
        transfer.start(client:client,plan:plan,photos:true,writer:DeniedMediaPhotosWriter())
        for _ in 0..<100 where transfer.running {try await Task.sleep(for:.milliseconds(20))}
        XCTAssertFalse(transfer.running);XCTAssertEqual(transfer.completed,0);XCTAssertEqual(transfer.failures,["Permiso de Fotos rechazado en prueba."]);XCTAssertTrue(transfer.message?.contains("No se pudo iniciar el guardado en Fotos") == true)
    }
    @MainActor func testR2FolderDownloadPlanPreservesCollectionForOfflineAndPhotos() async throws {
        let vault=MemorySession();vault.token=String(repeating:"f",count:43)
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString);defer{try? FileManager.default.removeItem(at:root);MockProtocol.handler=nil}
        let config=URLSessionConfiguration.ephemeral;config.protocolClasses=[MockProtocol.self]
        let cache=MediaOfflineCache(root:root),client=PayrollClient(baseURL:URL(string:"https://r2-download.invalid")!,vault:vault,configuration:config,mediaOffline:cache,automaticallyDownloadOffline:false)
        let folder=MediaFolder(id:"jac_r2_root",name:"Fotografía"),day=MediaFolder(id:"r2_"+UUID().uuidString.lowercased(),name:"Show ficticio")
        let item=MediaItem(id:"r2_"+UUID().uuidString.lowercased(),name:"Foto ficticia.png",mimeType:"image/png",kind:"image",size:Int64(MediaFixture.photo.count),modifiedAt:"2026-10-16T12:00:00Z",thumbnailAvailable:true)
        MockProtocol.handler={req in
            XCTAssertEqual(req.url?.host,"r2-download.invalid")
            if req.url?.path=="/api/media/file",req.url?.query?.contains("metadata=1")==true {return(HTTPURLResponse(url:req.url!,statusCode:200,httpVersion:nil,headerFields:["Content-Type":"application/json"])!,try JSONEncoder().encode(JSONValue.object(["item":try JSONDecoder().decode(JSONValue.self,from:JSONEncoder().encode(item))])))}
            if req.url?.path=="/api/media/file" {return(HTTPURLResponse(url:req.url!,statusCode:200,httpVersion:nil,headerFields:["Content-Type":"image/png"])!,MediaFixture.photo)}
            let feed=MediaFeed(connected:true,canRead:true,canUpload:false,canConnect:false,root:folder,folder:day,breadcrumbs:[folder,day],items:[item],nextPageToken:nil,provider:"r2",collectionID:"jac-r2-new-20261016",canDelete:false)
            return(HTTPURLResponse(url:req.url!,statusCode:200,httpVersion:nil,headerFields:["Content-Type":"application/json"])!,try JSONEncoder().encode(feed))
        }
        let plan=try await client.mediaDownloadPlan(folder:day.id)
        XCTAssertEqual(plan.files.map(\.id),[item.id]);let scope=try XCTUnwrap(client.mediaScope())
        XCTAssertEqual(cache.loadFeed(day.id,scope:scope)?.collectionID,"jac-r2-new-20261016")
        let transfer=MediaFolderTransfer();transfer.start(client:client,plan:plan,photos:false)
        for _ in 0..<100 where transfer.running {try await Task.sleep(for:.milliseconds(20))}
        XCTAssertFalse(transfer.running);XCTAssertEqual(transfer.completed,1);XCTAssertTrue(transfer.failures.isEmpty);XCTAssertTrue(cache.hasFile(item,scope:scope))
        transfer.start(client:client,plan:plan,photos:true,writer:FixtureMediaPhotosWriter())
        for _ in 0..<100 where transfer.running {try await Task.sleep(for:.milliseconds(20))}
        XCTAssertEqual(transfer.completed,1,transfer.failures.joined(separator:"; "));XCTAssertEqual(transfer.message,"1 de 1 archivos guardados en Fotos.");XCTAssertTrue(transfer.failures.isEmpty)
    }
    @MainActor func testMediaFolderPaginationRecursionOfflineReopenAndRevocation() async throws {
        let vault = MemorySession(); vault.token = String(repeating: "f", count: 43)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString); defer { try? FileManager.default.removeItem(at: root) }
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [MockProtocol.self]
        let mediaCache = MediaOfflineCache(root: root.appendingPathComponent("media")), content = OfflineResponseCache(root: root.appendingPathComponent("content"))
        let client = PayrollClient(baseURL: URL(string: "https://mock.example.invalid")!, vault: vault, configuration: config, offlineCache: content, mediaOffline: mediaCache, automaticallyDownloadOffline: false)
        let item = MediaItem(id: "photo", name: "Foto ficticia.png", mimeType: "image/png", kind: "image", size: Int64(MediaFixture.photo.count), modifiedAt: "2026-10-16T12:00:00Z", thumbnailAvailable: true)
        let folder = MediaFolder(id: "root", name: "Ficticia"), day = MediaFolder(id: "day", name: "Día ficticio")
        var reads: [String] = []
        MockProtocol.handler = { req in
            XCTAssertEqual(req.url?.host, "mock.example.invalid"); XCTAssertEqual(req.value(forHTTPHeaderField: "Cookie"), "__Host-jac_session=" + vault.token!)
            let parts = URLComponents(url: req.url!, resolvingAgainstBaseURL: false)!, query = parts.queryItems ?? []
            if parts.path == "/api/media/file" { return (HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "image/png"])!, MediaFixture.photo) }
            let selected = query.first { $0.name == "folder" }?.value ?? "", page = query.first { $0.name == "pageToken" }?.value ?? ""; reads.append(selected + ":" + page)
            let entries = selected == "day" ? [item] : page.isEmpty ? [MediaItem(id: "day", name: day.name, mimeType: "application/vnd.google-apps.folder", kind: "folder", size: 0, modifiedAt: "", thumbnailAvailable: false)] : []
            let feed = MediaFeed(connected: true, canRead: true, canUpload: false, canConnect: true, root: folder, folder: selected == "day" ? day : folder, breadcrumbs: selected == "day" ? [folder, day] : [folder], items: entries, nextPageToken: selected.isEmpty && page.isEmpty ? "page2" : nil)
            return (HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!, try JSONEncoder().encode(feed))
        }
        let plan = try await client.mediaDownloadPlan(); XCTAssertEqual(plan.files.map(\.id), ["photo"]); XCTAssertEqual(Set(reads), Set([":", ":page2", "day:"]))
        try await client.saveMediaOffline(item)
        let workspace: PayrollWorkspace = try JSONDecoder().decode(PayrollWorkspace.self, from: Data("{\"data\":{\"employees\":[],\"periods\":[]},\"version\":1,\"user\":{\"id\":\"photographer\",\"email\":\"photo@example.invalid\",\"username\":\"anderson\",\"displayName\":\"Anderson ficticio\",\"isOwner\":false,\"permissions\":[],\"itinerariesOnly\":true,\"mediaOnly\":true},\"company\":\"JAC\",\"periods\":[],\"employees\":[]}".utf8))
        client.rememberWorkspace(workspace)
        let reopened = PayrollClient(baseURL: client.baseURL, vault: vault, configuration: config, offlineCache: content, mediaOffline: mediaCache, automaticallyDownloadOffline: false)
        let store = PayrollStore(client: reopened); XCTAssertEqual(store.overview?.user.mediaOnly, true); XCTAssertTrue(store.isOffline)
        MockProtocol.handler = { _ in throw URLError(.notConnectedToInternet) }
        let offlinePlan = try await reopened.mediaDownloadPlan(); XCTAssertEqual(offlinePlan.files.map(\.id), ["photo"])
        let local = try await reopened.mediaDocument(item); XCTAssertEqual(try Data(contentsOf: local.url), MediaFixture.photo); TemporaryDocuments.remove(local)
        let scope = try XCTUnwrap(reopened.mediaScope())
        let unavailable = PayrollClient(baseURL: client.baseURL, vault: vault, configuration: config, offlineCache: content, mediaOffline: mediaCache, automaticallyDownloadOffline: false)
        MockProtocol.handler = { req in (HTTPURLResponse(url: req.url!, statusCode: 503, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!, Data("{\"error\":\"Interrupción ficticia\"}".utf8)) }
        let temporaryOutage = try await unavailable.media(folder: "day"); XCTAssertEqual(temporaryOutage.items.map(\.id), ["photo"]); XCTAssertTrue(unavailable.usingOfflineCopy)
        let online = PayrollClient(baseURL: client.baseURL, vault: vault, configuration: config, offlineCache: content, mediaOffline: mediaCache, automaticallyDownloadOffline: false)
        MockProtocol.handler = { req in (HTTPURLResponse(url: req.url!, statusCode: 403, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!, Data("{\"error\":\"Acceso retirado\"}".utf8)) }
        do { _ = try await online.media(); XCTFail("Debe respetar revocación") } catch { guard case APIError.forbidden = error else { return XCTFail("Error incorrecto: \(error)") } }
        XCTAssertNil(mediaCache.loadFeed("", scope: scope)); XCTAssertFalse(mediaCache.hasFile(item, scope: scope)); XCTAssertNotNil(vault.token)
        MockProtocol.handler = nil
    }
    @MainActor func testMediaUploadUsesPrivateChunksAndReconcilesAlreadyCommittedTimeout() async throws {
        let vault = MemorySession(); vault.token = String(repeating: "f", count: 43)
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [MockProtocol.self]
        let client = PayrollClient(baseURL: URL(string: "https://mock.example.invalid")!, vault: vault, configuration: config)
        let source = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".mp4")
        let bytes = Data(repeating: 71, count: 2 * 1024 * 1024 + 99); try bytes.write(to: source); defer { try? FileManager.default.removeItem(at: source) }
        let file = try MediaLocalFile.stage(source); defer { file.remove() }
        var offset = 0, starts = 0, status = 0, chunks: [Int] = [], received = Data(), failed = false
        MockProtocol.handler = { req in
            XCTAssertEqual(req.value(forHTTPHeaderField: "Cookie"), "__Host-jac_session=" + vault.token!); XCTAssertEqual(req.value(forHTTPHeaderField: "Origin"), client.baseURL.absoluteString)
            if req.httpMethod == "PUT" {
                let q = URLComponents(url: req.url!, resolvingAgainstBaseURL: false)!.queryItems!
                XCTAssertEqual(q.first { $0.name == "id" }?.value, file.id); XCTAssertEqual(Int(q.first { $0.name == "offset" }!.value!), offset)
                let chunk = try MockProtocol.requestBody(req); XCTAssertLessThanOrEqual(chunk.count, 1024 * 1024); chunks.append(chunk.count); received.append(chunk); offset += chunk.count
                if !failed { failed = true; throw URLError(.timedOut) }
            } else {
                let command = try JSONDecoder().decode(JSONValue.self, from: MockProtocol.requestBody(req))
                XCTAssertEqual(command["id"].text, file.id)
                if command["action"].text == "start" { starts += 1 } else { XCTAssertEqual(command["action"].text, "status"); status += 1 }
            }
            let data = try JSONEncoder().encode(JSONValue.object(["id": .string(file.id), "offset": .number(Double(offset)), "chunkSize": .number(1024 * 1024), "complete": .bool(offset == bytes.count)]))
            return (HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!, data)
        }
        var progress: Int64 = 0
        try await client.uploadMedia(file, parentID: "day") { sent, total in XCTAssertEqual(total, file.size); progress = sent }
        XCTAssertEqual(progress, file.size); XCTAssertEqual(starts, 1); XCTAssertEqual(status, 1); XCTAssertEqual(chunks, [1024 * 1024, 1024 * 1024, 99]); XCTAssertEqual(received, bytes)
        MockProtocol.handler = nil
    }
    @MainActor func testDirectMediaUploadSkipsJACForBytesAndRecoversCommittedTimeout() async throws {
        let vault = MemorySession(); vault.token = String(repeating: "f", count: 43)
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [MockProtocol.self]
        let client = PayrollClient(baseURL: URL(string: "https://mock.example.invalid")!, vault: vault, configuration: config)
        let source = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".mp4")
        let bytes = Data(repeating: 71, count: 8 * 1024 * 1024 + 19); try bytes.write(to: source); defer { try? FileManager.default.removeItem(at: source) }
        let file = try MediaLocalFile.stage(source); defer { file.remove(); MockProtocol.handler = nil }
        var offset = 0, starts = 0, statuses = 0, chunks: [Int] = [], received = Data(), failed = false
        MockProtocol.handler = { req in
            if req.url?.host == "www.googleapis.com" {
                XCTAssertEqual(req.httpMethod, "PUT"); XCTAssertNil(req.value(forHTTPHeaderField: "Cookie")); XCTAssertNil(req.value(forHTTPHeaderField: "Authorization")); XCTAssertNil(req.value(forHTTPHeaderField: "Origin"))
                let chunk = try MockProtocol.requestBody(req)
                XCTAssertEqual(req.value(forHTTPHeaderField: "Content-Range"), "bytes \(offset)-\(offset + chunk.count - 1)/\(bytes.count)")
                offset += chunk.count; chunks.append(chunk.count); received.append(chunk)
                if !failed { failed = true; throw URLError(.timedOut) }
                return (HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, Data())
            }
            XCTAssertEqual(req.url?.path, "/api/media/upload"); XCTAssertEqual(req.httpMethod, "POST"); XCTAssertEqual(req.value(forHTTPHeaderField: "Cookie"), "__Host-jac_session=" + vault.token!)
            let command = try JSONDecoder().decode(JSONValue.self, from: MockProtocol.requestBody(req)); XCTAssertEqual(command["transport"].text, "direct"); XCTAssertEqual(command["id"].text, file.id)
            if command["action"].text == "start" { starts += 1 } else { XCTAssertEqual(command["action"].text, "status"); statuses += 1 }
            var state: JSONValue = .object(["id": .string(file.id), "offset": .number(Double(offset)), "chunkSize": .number(8 * 1024 * 1024), "complete": .bool(offset == bytes.count)])
            if offset < bytes.count { state["uploadURL"] = .string("https://www.googleapis.com/upload/drive/v3/files?upload_id=fixture-one-file") }
            return (HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!, try JSONEncoder().encode(state))
        }
        var progress: Int64 = 0; try await client.uploadMedia(file, parentID: "fixture-day") { sent, _ in progress = sent }
        XCTAssertEqual(progress, file.size); XCTAssertEqual(starts, 1); XCTAssertEqual(statuses, 2); XCTAssertEqual(chunks, [8 * 1024 * 1024, 19]); XCTAssertEqual(received, bytes)
        for value in ["http://www.googleapis.com/upload/drive/v3/files?upload_id=x", "https://attacker.invalid/upload/drive/v3/files?upload_id=x", "https://www.googleapis.com:443/upload/drive/v3/files?upload_id=x", "https://user@www.googleapis.com/upload/drive/v3/files?upload_id=x", "https://www.googleapis.com/drive/v3/files/other?upload_id=x", "https://www.googleapis.com/upload/drive/v3/files"] {
            XCTAssertThrowsError(try PayrollClient.directMediaRequest(URL(string: value)!, mime: "video/mp4", offset: 0, count: 19, total: 19))
        }
    }
    @MainActor func testR2UploadUsesSignedPartsWithoutJACCredentialsAndRecoversCommittedTimeout() async throws {
        let vault = MemorySession(); vault.token = String(repeating: "f", count: 43)
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [MockProtocol.self]
        let client = PayrollClient(baseURL: URL(string: "https://mock.example.invalid")!, vault: vault, configuration: config)
        let source = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".mp4"), bytes = Data(repeating: 71, count: 8 * 1024 * 1024 + 19)
        try bytes.write(to: source); defer { try? FileManager.default.removeItem(at: source); MockProtocol.handler = nil }
        let file = try MediaLocalFile.stage(source); defer { file.remove() }
        var offset = 0, starts = 0, statuses = 0, chunks: [Int] = [], failed = false
        func signed(_ part: Int) -> String {
            var url = URLComponents(string: "https://" + String(repeating: "1", count: 32) + ".r2.cloudflarestorage.com/jac-fotografia/originals/" + file.id.lowercased())!
            url.queryItems = [URLQueryItem(name: "uploadId", value: "fixture-one-file"), URLQueryItem(name: "partNumber", value: String(part)), URLQueryItem(name: "X-Amz-Algorithm", value: "AWS4-HMAC-SHA256"), URLQueryItem(name: "X-Amz-Credential", value: String(repeating: "2", count: 32) + "/20261016/auto/s3/aws4_request"), URLQueryItem(name: "X-Amz-Date", value: "20261016T120000Z"), URLQueryItem(name: "X-Amz-Expires", value: "300"), URLQueryItem(name: "X-Amz-SignedHeaders", value: "content-length;content-type;host"), URLQueryItem(name: "X-Amz-Signature", value: String(repeating: "a", count: 64))]
            return url.url!.absoluteString
        }
        MockProtocol.handler = { req in
            if req.url?.host?.hasSuffix(".r2.cloudflarestorage.com") == true {
                XCTAssertEqual(req.httpMethod, "PUT"); for header in ["Cookie", "Authorization", "Origin", "Content-Range"] { XCTAssertNil(req.value(forHTTPHeaderField: header)) }
                let chunk = try MockProtocol.requestBody(req); XCTAssertEqual(req.value(forHTTPHeaderField: "Content-Length"), String(chunk.count))
                chunks.append(chunk.count); offset += chunk.count
                if !failed { failed = true; throw URLError(.timedOut) }
                return (HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, Data())
            }
            XCTAssertEqual(req.httpMethod, "POST", "R2 must never fall back to relay bytes through JAC")
            let body = try JSONDecoder().decode(JSONValue.self, from: MockProtocol.requestBody(req))
            if body["action"].text == "start" { starts += 1 } else { statuses += 1 }
            var state: JSONValue = .object(["id": .string(file.id), "provider": .string("r2"), "offset": .number(Double(offset)), "chunkSize": .number(8 * 1024 * 1024), "complete": .bool(offset == bytes.count)])
            if offset < bytes.count { state["uploadURL"] = .string(signed(offset / (8 * 1024 * 1024) + 1)) }
            return (HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, try JSONEncoder().encode(state))
        }
        try await client.uploadMedia(file, parentID: "jac_r2_root") { _, _ in }
        XCTAssertEqual(offset, bytes.count); XCTAssertEqual(starts, 1); XCTAssertEqual(statuses, 2); XCTAssertEqual(chunks, [8 * 1024 * 1024, 19])
        let valid = URL(string: signed(1))!
        for invalid in [valid.absoluteString.replacingOccurrences(of: "jac-fotografia", with: "another-bucket"), valid.absoluteString.replacingOccurrences(of: "originals", with: "thumbnails"), valid.absoluteString + "&partNumber=2", valid.absoluteString.replacingOccurrences(of: "X-Amz-Expires=300", with: "X-Amz-Expires=86400")] {
            XCTAssertThrowsError(try PayrollClient.directMediaRequest(URL(string: invalid)!, mime: "video/mp4", offset: 0, count: 8 * 1024 * 1024, total: Int64(bytes.count)))
        }
        XCTAssertThrowsError(try PayrollClient.directMediaRequest(valid, mime: "video/mp4", offset: 0, count: 19, total: Int64(bytes.count)))
    }
    func testNewR2CollectionDiscardsOnlyLegacyGalleryCacheAndRejectsLateOldWrites() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString), source = root.appendingPathComponent("photo.jpg")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true); defer { try? FileManager.default.removeItem(at: root) }
        let cache = MediaOfflineCache(root: root.appendingPathComponent("gallery")), scope = AgendaCacheScope(origin: "https://fixture.invalid", token: String(repeating: "f", count: 43)), bytes = Data([1, 2, 3]); try bytes.write(to: source)
        let old = MediaItem(id: "legacy-drive-photo", name: "Anterior.jpg", mimeType: "image/jpeg", kind: "image", size: 3, modifiedAt: "old", thumbnailAvailable: false)
        let oldFeed = MediaFeed(connected: true, canRead: true, canUpload: true, canConnect: false, root: MediaFolder(id: "drive-root", name: "Anterior"), folder: MediaFolder(id: "drive-root", name: "Anterior"), breadcrumbs: [], items: [old], nextPageToken: nil)
        try cache.saveFeed(oldFeed, key: "", append: false, scope: scope); try cache.saveFile(source, item: old, scope: scope); try cache.pinFeed(oldFeed, key: "", scope: scope)
        let fresh = MediaFeed(connected: true, canRead: true, canUpload: true, canConnect: false, root: MediaFolder(id: "jac_r2_root", name: "Fotografía"), folder: MediaFolder(id: "jac_r2_root", name: "Fotografía"), breadcrumbs: [], items: [], nextPageToken: nil, provider: "r2", collectionID: "jac-r2-new-20261016")
        try cache.saveFeed(fresh, key: "", append: true, scope: scope)
        XCTAssertEqual(cache.loadFeed("", scope: scope)?.items.count, 0); XCTAssertEqual(cache.loadFeed("", scope: scope)?.provider, "r2")
        XCTAssertFalse(cache.hasFile(old, scope: scope)); XCTAssertFalse(FileManager.default.fileExists(atPath: cache.encryptedFile(old, scope: scope).path))
        XCTAssertThrowsError(try cache.saveFeed(oldFeed, key: "", append: false, scope: scope)); XCTAssertThrowsError(try cache.pinFeed(oldFeed, key: "", scope: scope)); XCTAssertThrowsError(try cache.saveFile(source, item: old, scope: scope))
        XCTAssertEqual(try Data(contentsOf: source), bytes, "The original source outside JAC's gallery cache is untouched")
    }
    func testNativeThumbnailIsSmallJPEGWhileOriginalRemainsUnchanged() async throws {
        let source = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".png"); try MediaFixture.photo.write(to: source); defer { try? FileManager.default.removeItem(at: source) }
        let file = try MediaLocalFile.stage(source); defer { file.remove() }
        let generated = await MediaThumbnail.jpeg(for: file)
        let thumbnail = try XCTUnwrap(generated); XCTAssertLessThanOrEqual(thumbnail.count, 512 * 1024)
        let image = try XCTUnwrap(CGImageSourceCreateWithData(thumbnail as CFData, nil)); XCTAssertEqual(CGImageSourceGetType(image) as String?, "public.jpeg")
        let properties = try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(image, 0, nil) as? [CFString: Any]); XCTAssertLessThanOrEqual(properties[kCGImagePropertyPixelWidth] as? Int ?? 1000, 640)
        XCTAssertEqual(try Data(contentsOf: source), MediaFixture.photo)
    }
    @MainActor func testDirectMediaUploadFallsBackToSameSessionIfNetworkRefusesDirectBytes() async throws {
        let vault = MemorySession(); vault.token = String(repeating: "f", count: 43)
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [MockProtocol.self]
        let client = PayrollClient(baseURL: URL(string: "https://mock.example.invalid")!, vault: vault, configuration: config)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".png"), bytes = Data(repeating: 71, count: 1024 * 1024 + 13)
        try bytes.write(to: url); defer { try? FileManager.default.removeItem(at: url); MockProtocol.handler = nil }
        let file = try MediaLocalFile.stage(url); defer { file.remove() }; var offset = 0, direct = 0, starts = 0, chunks: [Int] = []
        MockProtocol.handler = { req in
            if req.url?.host == "www.googleapis.com" { direct += 1; throw URLError(.cannotConnectToHost) }
            if req.httpMethod == "PUT" {
                let q = URLComponents(url: req.url!, resolvingAgainstBaseURL: false)!.queryItems!
                XCTAssertEqual(q.first { $0.name == "id" }?.value, file.id); XCTAssertEqual(q.first { $0.name == "transport" }?.value, "direct")
                let data = try MockProtocol.requestBody(req); offset += data.count; chunks.append(data.count)
            } else {
                let body = try JSONDecoder().decode(JSONValue.self, from: MockProtocol.requestBody(req)); XCTAssertEqual(body["id"].text, file.id)
                if body["action"].text == "start" { starts += 1 }
            }
            var result: JSONValue = .object(["id": .string(file.id), "offset": .number(Double(offset)), "chunkSize": .number(8 * 1024 * 1024), "complete": .bool(offset == bytes.count)])
            if offset < bytes.count { result["uploadURL"] = .string("https://www.googleapis.com/upload/drive/v3/files?upload_id=fixture") }
            return (HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!, try JSONEncoder().encode(result))
        }
        try await client.uploadMedia(file, parentID: "fixture-day") { _, _ in }
        XCTAssertEqual(offset, bytes.count); XCTAssertEqual(direct, 1); XCTAssertEqual(starts, 1); XCTAssertEqual(chunks, [1024 * 1024, 13])
    }
    @MainActor func testMediaPhotoCacheRevalidatesEveryOpenAndRevocationPurgesIt() async throws {
        let vault = MemorySession(); vault.token = String(repeating: "f", count: 43)
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [MockProtocol.self]
        let client = PayrollClient(baseURL: URL(string: "https://mock.example.invalid")!, vault: vault, configuration: config)
        let item = MediaItem(id: "photo-cache", name: "Foto ficticia.png", mimeType: "image/png", kind: "image", size: Int64(MediaFixture.photo.count), modifiedAt: "fixture-revision", thumbnailAvailable: true)
        var originals = 0, metadata = 0, revoked = false
        MockProtocol.handler = { req in
            let parts = URLComponents(url: req.url!, resolvingAgainstBaseURL: false)!
            if parts.queryItems?.contains(where: { $0.name == "metadata" }) == true {
                metadata += 1
                return (HTTPURLResponse(url: req.url!, statusCode: revoked ? 403 : 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!, revoked ? Data("{\"error\":\"Acceso retirado\"}".utf8) : try JSONEncoder().encode(["item": item]))
            }
            originals += 1; return (HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": item.mimeType])!, MediaFixture.photo)
        }
        defer { MockProtocol.handler = nil; try? client.clearSession() }
        for _ in 0..<2 { let document = try await client.mediaDocument(item); XCTAssertEqual(try Data(contentsOf: document.url), MediaFixture.photo); TemporaryDocuments.remove(document) }
        XCTAssertEqual(originals, 1); XCTAssertEqual(metadata, 1); let scope = try XCTUnwrap(client.mediaScope()); XCTAssertTrue(client.mediaOffline.hasFile(item, scope: scope))
        revoked = true
        do { _ = try await client.mediaDocument(item); XCTFail("A cached image must never bypass a confirmed 403") } catch { guard case APIError.forbidden = error else { return XCTFail(String(describing: error)) } }
        XCTAssertEqual(originals, 1); XCTAssertEqual(metadata, 2); XCTAssertFalse(client.mediaOffline.hasFile(item, scope: scope))
    }
    @MainActor func testMediaPhotoDownloadProgressAndPersistentCacheHitDoNotRedownload() async throws {
        let vault = MemorySession(); vault.token = String(repeating: "f", count: 43)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [MockProtocol.self]
        let cache = MediaOfflineCache(root: root)
        let client = PayrollClient(baseURL: URL(string: "https://progress.example.invalid")!, vault: vault, configuration: config, mediaOffline: cache)
        let item = MediaItem(id: "photo-progress", name: "Ficticia.png", mimeType: "image/png", kind: "image", size: Int64(MediaFixture.photo.count), modifiedAt: "fixture-progress", thumbnailAvailable: true)
        var originals = 0, metadata = 0
        MockProtocol.handler = { request in
            if request.url!.query?.contains("metadata=1") == true {
                metadata += 1
                return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!, try JSONEncoder().encode(["item": item]))
            }
            originals += 1
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": item.mimeType, "Content-Length": String(item.size)])!, MediaFixture.photo)
        }
        defer { MockProtocol.handler = nil; try? client.clearSession(); try? FileManager.default.removeItem(at: root) }
        var first: [(Int64, Int64)] = []
        let downloaded = try await client.mediaDocument(item) { first.append(($0, $1)) }
        XCTAssertEqual(try Data(contentsOf: downloaded.url), MediaFixture.photo); TemporaryDocuments.remove(downloaded)
        XCTAssertEqual(first.first?.0, 0); XCTAssertEqual(first.last?.0, item.size)
        XCTAssertTrue(first.allSatisfy { $0.0 >= 0 && $0.0 <= item.size && $0.1 == item.size })
        let reopened = PayrollClient(baseURL: client.baseURL, vault: vault, configuration: config, mediaOffline: MediaOfflineCache(root: root))
        var second: [(Int64, Int64)] = []
        let restored = try await reopened.mediaDocument(item) { second.append(($0, $1)) }
        XCTAssertEqual(try Data(contentsOf: restored.url), MediaFixture.photo); TemporaryDocuments.remove(restored)
        XCTAssertEqual(originals, 1); XCTAssertEqual(metadata, 1)
        XCTAssertEqual(second.map { $0.0 }, [0, item.size], "La copia no inventa pasos de descarga intermedios")
        XCTAssertTrue(second.allSatisfy { $0.1 == item.size })
    }
    @MainActor func testPhotoDataBridgeReportsMeasuredHalfBeforeCompletingAndRejectsOversize() async throws {
        MediaDataGateProtocol.reset()
        let configuration=URLSessionConfiguration.ephemeral;configuration.protocolClasses=[MediaDataGateProtocol.self]
        let session=URLSession(configuration:configuration)
        defer {MediaDataGateProtocol.complete();session.invalidateAndCancel();MediaDataGateProtocol.reset()}
        let request=URLRequest(url:URL(string:"https://progress-gate.example.invalid/preview")!)
        let total=Int64(MediaDataGateProtocol.bytes.count),partial=expectation(description:"La mitad real llega antes del final")
        var values:[Int64]=[],signalled=false,finished=false
        let observer=MediaDataProgressObserver(maximumBytes:Int(total)) {received,expected in
            XCTAssertEqual(expected,total);values.append(received)
            if received==total/2,!signalled {signalled=true;partial.fulfill()}
        }
        let loading=Task {let value=try await observer.data(session:session,request:request);finished=true;return value}
        defer {loading.cancel();observer.stop()}
        await fulfillment(of:[partial],timeout:4)
        XCTAssertFalse(finished)
        MediaDataGateProtocol.complete()
        let (data,response)=try await loading.value
        XCTAssertEqual(data,MediaDataGateProtocol.bytes);XCTAssertEqual(response.expectedContentLength,total)
        XCTAssertTrue(values.contains(total/2))
        let bounded=MediaDataProgressObserver(maximumBytes:64*1024) {_,_ in XCTFail("Una respuesta sobredimensionada no publica progreso")}
        defer {bounded.stop()}
        do {_ = try await bounded.data(session:session,request:request);XCTFail("Debe rechazar el Content-Length que supera el presupuesto")}
        catch {guard case APIError.invalid=error else {return XCTFail(String(describing:error))}}
        var redirected=true
        bounded.urlSession(session,task:session.dataTask(with:request),willPerformHTTPRedirection:HTTPURLResponse(url:request.url!,statusCode:302,httpVersion:nil,headerFields:nil)!,newRequest:URLRequest(url:URL(string:"https://other.example.invalid")!)) {redirected=$0 != nil}
        XCTAssertFalse(redirected)
    }

    @MainActor func testPhotoDataBridgeCancellationStopsPendingProgressAndLateCompletion() async throws {
        MediaDataGateProtocol.reset()
        let configuration=URLSessionConfiguration.ephemeral;configuration.protocolClasses=[MediaDataGateProtocol.self]
        let session=URLSession(configuration:configuration)
        defer {MediaDataGateProtocol.complete();session.invalidateAndCancel();MediaDataGateProtocol.reset()}
        let partial=expectation(description:"Respuesta parcial antes de cancelar")
        var values:[Int64]=[],signalled=false
        let observer=MediaDataProgressObserver(maximumBytes:512*1024) {received,_ in
            values.append(received)
            if received>0,!signalled {signalled=true;partial.fulfill()}
        }
        let loading=Task {try await observer.data(session:session,request:URLRequest(url:URL(string:"https://cancel-gate.example.invalid/preview")!))}
        defer {loading.cancel();observer.stop()}
        await fulfillment(of:[partial],timeout:4)
        loading.cancel()
        do {_ = try await loading.value;XCTFail("Cancelar debe detener la transferencia")}
        catch is CancellationError {}
        let before=values
        MediaDataGateProtocol.complete()
        for _ in 0..<20 {await Task.yield()}
        XCTAssertEqual(values,before,"Una finalización tardía no restaura progreso tras cancelar")
    }

    @MainActor func testMediaDownloadDelegateReportsActualBytesStopsLateCallbacksAndRejectsRedirects() async throws {
        let configuration = URLSessionConfiguration.ephemeral; configuration.protocolClasses = [MockProtocol.self]
        let session = URLSession(configuration: configuration)
        let request = URLRequest(url: URL(string: "https://download.example.invalid/ficticia")!)
        let task = session.downloadTask(with: request)
        defer { task.cancel(); session.invalidateAndCancel() }
        var values: [(Int64, Int64)] = []
        let received = expectation(description: "Bytes entregados por el delegado")
        let observer = MediaDownloadProgressObserver(total: 20) { count, total in values.append((count, total)); received.fulfill() }
        observer.urlSession(session, downloadTask: task, didWriteData: 7, totalBytesWritten: 7, totalBytesExpectedToWrite: 20)
        await fulfillment(of: [received], timeout: 2)
        XCTAssertEqual(values.map { $0.0 }, [7]); XCTAssertEqual(values.first?.1, 20)
        observer.stop()
        observer.urlSession(session, downloadTask: task, didWriteData: 5, totalBytesWritten: 12, totalBytesExpectedToWrite: 20)
        await Task.yield()
        XCTAssertEqual(values.map { $0.0 }, [7])
        var redirected = true
        observer.urlSession(session, task: task, willPerformHTTPRedirection: HTTPURLResponse(url: request.url!, statusCode: 302, httpVersion: nil, headerFields: nil)!, newRequest: URLRequest(url: URL(string: "https://other.example.invalid")!)) { redirected = $0 != nil }
        XCTAssertFalse(redirected)
    }
    @MainActor func testMediaDownloadBridgeDeliversIntermediateProgressBeforeFinishing() async throws {
        let configuration = URLSessionConfiguration.ephemeral; configuration.protocolClasses = [MediaDownloadChunkProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let total = Int64(MediaDownloadChunkProtocol.bytes.count)
        let partial = expectation(description: "La descarga real entrega progreso antes de terminar")
        var counts: [Int64] = [], signalled = false
        let observer = MediaDownloadProgressObserver(total: total) { received, expected in
            XCTAssertEqual(expected, total); counts.append(received)
            if received > 0 && received < total && !signalled { signalled = true; partial.fulfill() }
        }
        let loading = Task { try await observer.download(session: session, request: URLRequest(url: URL(string: "https://chunks.example.invalid/photo")!)) }
        defer { loading.cancel(); observer.stop() }
        await fulfillment(of: [partial], timeout: 4)
        let (document, response) = try await loading.value
        defer { TemporaryDocuments.remove(document) }
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
        XCTAssertEqual(try Data(contentsOf: document.url), MediaDownloadChunkProtocol.bytes)
        XCTAssertTrue(counts.contains { $0 > 0 && $0 < total })
    }
    func testMediaPreviewCacheTouchesRecencyAtMostEveryThirtySecondsAndPreservesPinnedCopies() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("ficticia.png"); try MediaFixture.photo.write(to: source)
        let scope = AgendaCacheScope(origin: "https://lru.example.invalid/media-offline-v1", token: String(repeating: "f", count: 43))
        let cache = MediaOfflineCache(root: root.appendingPathComponent("cache"))
        let item = MediaItem(id: "lru-photo", name: "Ficticia.png", mimeType: "image/png", kind: "image", size: Int64(MediaFixture.photo.count), modifiedAt: "fixture-lru", thumbnailAvailable: true)
        try cache.saveFile(source, item: item, scope: scope, preview: true)
        let indexURL = cache.root.appendingPathComponent(scope.id).appendingPathComponent("index.sealed")
        func accessTime() throws -> TimeInterval {
            let box = try AES.GCM.SealedBox(combined: Data(contentsOf: indexURL))
            let plain = try AES.GCM.open(box, using: scope.key, authenticating: Data("jac-media-index-v1".utf8))
            let index = try XCTUnwrap(JSONSerialization.jsonObject(with: plain) as? [String: Any])
            return try XCTUnwrap((index["previewAccess"] as? [String: Double])?[item.id])
        }
        let initial = try accessTime(), initialBytes = try Data(contentsOf: indexURL)
        let first = try XCTUnwrap(cache.document(item, scope: scope, accessedAt: initial + 10)); TemporaryDocuments.remove(first)
        XCTAssertEqual(try Data(contentsOf: indexURL), initialBytes)
        let touched = try XCTUnwrap(cache.document(item, scope: scope, accessedAt: initial + 31)); TemporaryDocuments.remove(touched)
        XCTAssertEqual(try accessTime(), initial + 31)
        let touchedBytes = try Data(contentsOf: indexURL)
        let again = try XCTUnwrap(cache.document(item, scope: scope, accessedAt: initial + 40)); TemporaryDocuments.remove(again)
        XCTAssertEqual(try Data(contentsOf: indexURL), touchedBytes)
        try cache.saveFile(source, item: item, scope: scope, preview: false)
        let pinnedBytes = try Data(contentsOf: indexURL)
        let pinned = try XCTUnwrap(cache.document(item, scope: scope, accessedAt: initial + 100)); TemporaryDocuments.remove(pinned)
        XCTAssertEqual(try Data(contentsOf: indexURL), pinnedBytes)
        XCTAssertTrue(cache.hasFile(item, scope: scope))
    }
    @MainActor func testDeletedPhotoMetadataRemovesOnlyThatCachedItemAndNeverFallsBackOffline() async throws {
        for status in [404, 410] {
            let vault = MemorySession(); vault.token = String(repeating: "f", count: 43)
            let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            let configuration = URLSessionConfiguration.ephemeral; configuration.protocolClasses = [MockProtocol.self]
            let cache = MediaOfflineCache(root: root)
            let client = PayrollClient(baseURL: URL(string: "https://deleted.example.invalid")!, vault: vault, configuration: configuration, mediaOffline: cache)
            let item = MediaItem(id: "deleted-photo", name: "Retirada.png", mimeType: "image/png", kind: "image", size: Int64(MediaFixture.photo.count), modifiedAt: "fixture-delete", thumbnailAvailable: true)
            let other = MediaItem(id: "other-photo", name: "Conservar.png", mimeType: "image/png", kind: "image", size: item.size, modifiedAt: "fixture-other", thumbnailAvailable: true)
            var removed = false, originals = 0
            MockProtocol.handler = { request in
                let parts = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!
                if parts.queryItems?.contains(where: { $0.name == "metadata" }) == true {
                    if removed { return (HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!, Data("{\"error\":\"Archivo retirado\"}".utf8)) }
                    return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!, try JSONEncoder().encode(["item": item]))
                }
                originals += 1
                return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "image/png"])!, MediaFixture.photo)
            }
            defer { MockProtocol.handler = nil; try? client.clearSession(); try? FileManager.default.removeItem(at: root) }
            for photo in [item, other] { let document = try await client.mediaDocument(photo); TemporaryDocuments.remove(document) }
            let scope = try XCTUnwrap(client.mediaScope()); XCTAssertTrue(cache.hasFile(item, scope: scope)); XCTAssertTrue(cache.hasFile(other, scope: scope))
            removed = true
            do { _ = try await client.mediaDocument(item); XCTFail("Una eliminación confirmada no usa la copia") }
            catch { XCTAssertTrue(error is MediaFileRemoved) }
            XCTAssertFalse(cache.hasFile(item, scope: scope)); XCTAssertTrue(cache.hasFile(other, scope: scope))
            XCTAssertFalse(FileManager.default.fileExists(atPath: cache.encryptedFile(item, scope: scope).path))
            client.beginOfflineRestore()
            do { _ = try await client.mediaDocument(item); XCTFail("No debe reaparecer sin conexión") } catch {}
            let available = try await client.mediaDocument(other); XCTAssertEqual(try Data(contentsOf: available.url), MediaFixture.photo); TemporaryDocuments.remove(available)
            XCTAssertEqual(originals, 2)
        }
    }
    @MainActor func testMediaStreamingAssetUsesAuthenticatedRangesAndRejectsChangedContent() async throws {
        let client = UITestBackend.client(), feed = try await client.media(folder: "media-day"), item = try XCTUnwrap(feed.items.first { $0.kind == "video" })
        try await client.validateMediaItem(item)
        let source = try MediaVideoStream(client: client, item: item); defer { source.cancel() }
        let tracks = try await source.asset.loadTracks(withMediaType: .video); XCTAssertEqual(tracks.count, 1)
        let data = try await client.mediaRange(item, offset: 0, count: min(1024, Int(item.size))); XCTAssertEqual(data, MediaFixture.video.prefix(data.count))
        try client.clearSession()
        do { _ = try await client.mediaRange(item, offset: 0, count: 16); XCTFail("A closed session cannot request another range") } catch { guard case APIError.unauthorized = error else { return XCTFail(String(describing: error)) } }
    }
    @MainActor func testLateCRMReadCannotRestoreFinancialCopyAfterASave() async throws {
        let vault=MemorySession();vault.token=String(repeating:"f",count:43)
        let config=URLSessionConfiguration.ephemeral;config.protocolClasses=[CRMDelayedProtocol.self]
        let client=PayrollClient(baseURL:UITestBackend.base,vault:vault,configuration:config)
        let pending=Task{try await client.crm(query:["id":"77777777-7777-4777-8777-777777777777"])}
        for _ in 0..<100{if CRMDelayedProtocol.pending() != nil{break};try await Task.sleep(for:.milliseconds(10))}
        let held=try XCTUnwrap(CRMDelayedProtocol.pending())
        _ = try await client.crmCommand("savePlan",record:.object([:]))
        held.respond(Data("{\"show\":{\"sale\":1}}".utf8))
        do{_ = try await pending.value;XCTFail("Una lectura anterior al guardado no debe volver a la interfaz o caché")}catch{XCTAssertTrue(error is CancellationError)}
        XCTAssertNil(client.cached(JSONValue.self,path:"api/crm",query:[URLQueryItem(name:"id",value:"77777777-7777-4777-8777-777777777777")]))
    }

    func testCRMAmountsAreEditableWithoutLeadingZeroAndPreserveCentavos() {
        XCTAssertTrue(CRMFields.money(0.5).contains("0,50"));XCTAssertTrue(CRMFields.money(140000000).contains("140.000.000"))
        XCTAssertEqual(CRMMoney.edit("")?.value,0);XCTAssertEqual(CRMMoney.edit("0140000000")?.text,"140.000.000")
        XCTAssertEqual(CRMMoney.edit("1.000,")?.text,"1.000,");XCTAssertEqual(CRMMoney.edit("1.000,50")?.value,1000.5)
        XCTAssertNil(CRMMoney.edit("-100"));XCTAssertNil(CRMMoney.edit("1,234"));XCTAssertNil(CRMMoney.edit("1000000000001"))
    }

    @MainActor func testCRMReusesContactsPaymentsPlansAndPrivateFilesWithStableRetries() async throws {
        let client=UITestBackend.client()
        let feed=try await client.crm(),show=try XCTUnwrap(feed["shows"].elements.first),contact=try XCTUnwrap(feed["contacts"].elements.first)
        XCTAssertEqual(CRMFields.matches("jose",in:feed["contacts"].elements).count,1)
        XCTAssertEqual(CRMFields.matches("eventos",in:feed["contacts"].elements).count,1)
        var record=CRMFields.showRecord(show);record["contactId"]=contact["id"];record["entrepreneur"]=contact["name"]
        _ = try await client.crmCommand("updateShow",record:record)
        let detail=try await client.crm(query:["id":show["id"].text]);XCTAssertEqual(detail["show"]["contactId"],contact["id"])
        let proof=NoticeUpload(filename:"Ficticio.pdf",data:Data("%PDF-1.4\nPRUEBA SIN DATOS REALES\n%%EOF".utf8))
        let payment:JSONValue = .object(["id":.string(UUID().uuidString.lowercased()),"showId":show["id"],"amount":.number(50000000),"paymentDate":.string(BoardingClock.today()),"note":.string("Ficticio"),"files":try client.crmUploads([proof])])
        _ = try await client.crmCommand("addPayment",record:payment);_ = try await client.crmCommand("addPayment",record:payment)
        let paid=try await client.crm(query:["id":show["id"].text]);XCTAssertEqual(paid["payments"].elements.count,1);XCTAssertEqual(paid["show"]["balance"].number,90000000)
        let plan=try await client.crm(query:["view":"workspace","id":show["id"].text]);XCTAssertTrue(plan["advance"]["done"].flag)
        var tasks=plan["tasks"].elements;tasks[0]["status"] = .string("done")
        _ = try await client.crmCommand("savePlan",record:.object(["showId":show["id"],"version":plan["version"],"budget":.null,"tasks":.array(tasks)]))
        let latest=try await client.crm(query:["view":"workspace","id":show["id"].text]);XCTAssertEqual(latest["tasks"].elements[0]["status"].text,"done")
        let p=try XCTUnwrap(paid["payments"].elements.first),file=try XCTUnwrap(p["files"].elements.first).decoded(NoticeAttachment.self)
        let document=try await client.crmFile(owner:p["id"].text,file:file,version:1,contact:false);XCTAssertEqual(try Data(contentsOf:document.url),proof.data);TemporaryDocuments.remove(document)
        let upload:JSONValue = .object(["id":.string(UUID().uuidString.lowercased()),"contactId":contact["id"],"version":contact["version"],"files":try client.crmUploads([proof])])
        _ = try await client.crmCommand("addContactFiles",record:upload);_ = try await client.crmCommand("addContactFiles",record:upload)
        let profile=try await client.crm(query:["view":"contact","id":contact["id"].text]);XCTAssertEqual(profile["files"].elements.count,1)
        let contract=try XCTUnwrap(profile["files"].elements.first).decoded(NoticeAttachment.self)
        let contractDoc=try await client.crmFile(owner:contact["id"].text,file:contract,version:2,contact:true);XCTAssertEqual(try Data(contentsOf:contractDoc.url),proof.data);TemporaryDocuments.remove(contractDoc)
    }
    @MainActor func testCRMOfflineCopyUsesSessionEncryptionAndDenialNeverFallsBackToSavedData() async throws {
        let cache=OfflineResponseCache(root:FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        let client=UITestBackend.client(contentCache:cache,downloadOffline:false),feed=try await client.crm(query:["month":CalendarClock.month(Date())])
        XCTAssertFalse(feed["shows"].elements.isEmpty)
        let (offline,vault)=relaunchFixture(cache);offline.beginOfflineRestore();MockProtocol.handler={_ in throw URLError(.notConnectedToInternet)}
        let restored=try await offline.crm(query:["month":CalendarClock.month(Date())]);XCTAssertEqual(restored,feed)
        do{_ = try await offline.crmCommand("syncSheets");XCTFail("No se permiten escrituras offline")}catch{}
        MockProtocol.handler={req in (HTTPURLResponse(url:req.url!,statusCode:403,httpVersion:nil,headerFields:["Content-Type":"application/json"])!,Data("{\"error\":\"Acceso retirado\"}".utf8))}
        do{_ = try await offline.crm(query:["month":CalendarClock.month(Date())],forceNetwork:true);XCTFail("La denegación no sirve la copia")}catch{guard case APIError.forbidden=error else{return XCTFail(error.localizedDescription)}}
        XCTAssertNotNil(vault.token);XCTAssertNil(offline.cached(JSONValue.self,path:"api/crm",query:[URLQueryItem(name:"month",value:CalendarClock.month(Date()))]))
        try offline.clearSession();XCTAssertTrue(cache.entries(OfflineResponseCache.scope(origin:UITestBackend.base.absoluteString,token:String(repeating:"f",count:43))).isEmpty)
    }

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
        #if os(iOS)
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        let blank = UIGraphicsImageRenderer(size: CGSize(width: 1000, height: 1000), format: format).image { context in UIColor.white.setFill(); context.fill(CGRect(x: 0, y: 0, width: 1000, height: 1000)) }
        #else
        let blank=NSImage(size:NSSize(width:1000,height:1000),flipped:false){rect in NSColor.white.setFill();rect.fill();return true}
        #endif
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
    func testReceiptConceptUsesMerchantHeadingAndExplicitCommercialName() {
        XCTAssertEqual(ReceiptParser.parse(["FACTURA ELECTRONICA", "Gracias por tu compra", "F r i s b y", "NIT 123456789", "FECHA 08/10/2026", "TOTAL 47600"]).concept, "Frisby")
        XCTAssertEqual(ReceiptParser.parse(["SOCIEDAD FICTICIA SAS", "Nombre comercial : Café Ficticio", "FECHA 08/10/2026"]).concept, "Café Ficticio")
        XCTAssertEqual(ReceiptParser.parse(["FACTURA ELECTRONICA", "Razón social: Comercio Ficticio SAS", "CAJERO: Persona ficticia"]).concept, "Comercio Ficticio SAS")
        XCTAssertEqual(ReceiptParser.parse(["Electrónica Ficticia", "TOTAL 10000"]).concept, "Electrónica Ficticia")
        XCTAssertNil(ReceiptParser.parse(["FACTURA ELECTRONICA", "NIT 123456789", "FECHA 08/10/2026", "Pollo con arroz", "TOTAL 47600"]).concept, "Un producto no reemplaza un nombre ilegible")
        XCTAssertNil(ReceiptParser.parse(["FACTURA ELECTRONICA", "08/10/2026", "Pollo con arroz", "TOTAL 47600"]).concept)
        XCTAssertNil(ReceiptParser.merchantCandidate("CAJERO: Persona ficticia"))
        XCTAssertNil(ReceiptParser.merchantCandidate("www.comercio.invalid"))
        XCTAssertEqual(ReceiptParser.merchantCandidate("Frisby S.A.S."), "Frisby")
        XCTAssertEqual(ReceiptParser.merchantCandidate("Frisby S.A.S. NIT 123456789"), "Frisby")
        XCTAssertEqual(ReceiptParser.merchantCandidate("Frisbee Ficticio"), "Frisbee Ficticio", "No adivinar otra marca por parecido")
    }
    func testReceiptMerchantUsesHeaderGeometryWithoutChoosingBodyOrUncertainLogo() {
        let header: [ReceiptOCR.Fragment] = [
            .init(text: "Gracias por tu compra", bounds: CGRect(x:0.2,y:0.94,width:0.6,height:0.025)),
            .init(text: "Frisby", bounds: CGRect(x:0.3,y:0.79,width:0.4,height:0.12)),
            .init(text: "SOCIEDAD FICTICIA SAS", bounds: CGRect(x:0.1,y:0.73,width:0.8,height:0.025)),
            .init(text: "NIT 123456789", bounds: CGRect(x:0.1,y:0.68,width:0.8,height:0.025)),
            .init(text: "Pollo con arroz", bounds: CGRect(x:0.1,y:0.35,width:0.8,height:0.18))]
        XCTAssertEqual(ReceiptOCR.merchant(in: header),"Frisby")
        let split: [ReceiptOCR.Fragment] = [.init(text:"F r i",bounds:CGRect(x:0.2,y:0.8,width:0.2,height:0.1)), .init(text:"s b y",bounds:CGRect(x:0.4,y:0.8,width:0.2,height:0.1))]
        XCTAssertEqual(ReceiptOCR.merchant(in:split),"Frisby")
        XCTAssertNil(ReceiptOCR.merchant(in:[.init(text:"Nombre ilegible",bounds:CGRect(x:0.2,y:0.8,width:0.5,height:0.1),confidence:0.1)]))
        XCTAssertNil(ReceiptOCR.merchant(in:[]))
    }
    @MainActor func testNativeVisionReadsStylizedMerchantWordAndPreservesDateTotalAndTime() async throws {
        MockProtocol.handler = { _ in XCTFail("El nombre se reconoce sin red"); throw URLError(.unsupportedURL) }
        let value = try await ReceiptOCR.readReceipt(ReceiptOCR.photograph(ReceiptOCR.fixture(logo: true)))
        XCTAssertEqual(value.concept,"Frisby");XCTAssertEqual(value.amount,47600);XCTAssertEqual(value.date,"2026-10-08");XCTAssertEqual(value.time,"13:45:20");XCTAssertEqual(value.kind,.food)
        let original = try await ReceiptOCR.readReceipt(ReceiptOCR.photograph(ReceiptOCR.fixture()))
        XCTAssertEqual(original.concept,"RESTAURANTE FICTICIO JAC");XCTAssertEqual(original.amount,47600)
    }
    func testCommissionContractIsOptionalForOldCopiesAndPreservesServerReviewedAmount() throws {
        let fields: [String:JSONValue] = ["rows":.array([]),"sale":.number(10000000),"total":.number(2000000),"gross":.number(2000000),"deductions":.number(0),"reimbursements":.number(0),"company":.string("Empresa ficticia"),"nit":.string("TEST")]
        var data=JSONValue.object(fields)
        XCTAssertNil(try data.decoded(PayrollCalculation.self).camiloCommission)
        data["camiloCommission"] = .object(["rate":.number(0.05),"sales":.number(10000000),"costs":.number(2000000),"promotionalCosts":.number(500000),"balance":.number(8000000),"base":.number(8000000),"amount":.number(400000),"shows":.array([]),"issues":.array([]),"unlinkedKilometers":.number(0)])
        let reviewed=try data.decoded(PayrollCalculation.self)
        XCTAssertEqual(reviewed.camiloCommission?.amount,400000);XCTAssertEqual(reviewed.total,2000000,"La comisión no se suma al neto")
        data["camiloCommission"]["amount"] = .null
        XCTAssertNil(try data.decoded(PayrollCalculation.self).camiloCommission?.amount)
        let show:JSONValue = .object(["id":.string("show"),"name":.string("Ficticio"),"date":.string("2026-10-01"),"sale":.number(0),"participants":.array([]),"promotional":.bool(true)])
        XCTAssertEqual(try show.decoded(PayrollShow.self).promotional,true)
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
            if client.offlineSyncMessage == "La última información y sus adjuntos están guardados en este \(JACDevice.name)." { return }
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

    @MainActor func testIdenticalWorkspaceDoesNotRewriteEncryptedCopyAndOfflineSyncIsThrottled() async throws {
        let cache = OfflineResponseCache(root: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        defer { try? FileManager.default.removeItem(at: cache.root) }
        let client = try await cachedFixture(cache), workspace = try XCTUnwrap(client.cachedWorkspace())
        let scope = OfflineResponseCache.scope(origin: UITestBackend.base.absoluteString, token: String(repeating: "f", count: 43))
        let entry = try XCTUnwrap(cache.entries(scope).first { $0.url.contains("workspace=1") })
        let before = try Data(contentsOf: cache.file(scope, key: entry.key))
        client.rememberWorkspace(workspace)
        XCTAssertEqual(try Data(contentsOf: cache.file(scope, key: entry.key)), before, "AES-GCM must not write a new nonce for identical data")
        client.synchronizeOfflineContent(workspace)
        XCTAssertFalse(client.syncingOffline)
        await Task.yield()
        XCTAssertFalse(client.syncingOffline, "A successful unchanged refresh does not restart a full offline scan")
        XCTAssertEqual(client.cachedWorkspace()?.version, workspace.version)
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

    @MainActor func testDeletedCalendarEventDisappearsFromDownloadedAgendaAndNextOfflineLaunch() async throws {
        let fixture = UITestBackend.client(), feed = try await fixture.agenda(month: CalendarClock.month(Date())), user = try await fixture.workspace().user
        XCTAssertFalse(feed.events.isEmpty)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let cache = AgendaOfflineCache(root: root), vault = MemorySession(); vault.token = token
        let client = makeClient(vault, cache: cache), scope = try XCTUnwrap(client.agendaScope())
        try cache.save(AgendaOfflineRecord(schema: 1, user: user, months: [SavedAgenda(data: feed, receivedAt: Date())]), scope: scope)
        let store = PayrollStore(client: client)
        XCTAssertFalse(try XCTUnwrap(store.cachedAgenda(month: feed.month, userID: user.id)).data.events.isEmpty)
        var value = try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(feed))
        value["events"] = .array([]); value["upcoming"] = .array([])
        value["updatedAt"] = .string("2099-01-01T12:00:00.000Z")
        let payload = try JSONEncoder().encode(value)
        MockProtocol.handler = { request in
            XCTAssertEqual(request.url?.host, "payroll.example.invalid")
            XCTAssertEqual(request.url?.path, "/api/calendar")
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, payload)
        }
        let refreshed = try await client.agenda(month: feed.month)
        try store.rememberAgenda(refreshed, userID: user.id, scope: scope)
        XCTAssertTrue(try XCTUnwrap(store.cachedAgenda(month: feed.month, userID: user.id)).data.events.isEmpty)
        XCTAssertTrue(try XCTUnwrap(cache.load(scope)?.latest).data.events.isEmpty)
        MockProtocol.handler = { _ in throw URLError(.notConnectedToInternet) }
        let reopened = PayrollStore(client: client)
        XCTAssertTrue(try XCTUnwrap(reopened.cachedAgenda(month: feed.month, userID: user.id)).data.events.isEmpty)
        XCTAssertTrue(try XCTUnwrap(reopened.cachedAgenda(month: feed.month, userID: user.id)).data.upcoming.isEmpty)
        client.beginOfflineRestore()
        let offline = try await client.agenda(month: feed.month)
        XCTAssertTrue(offline.events.isEmpty); XCTAssertTrue(offline.upcoming.isEmpty)
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
        for folder in ["https://untrusted.example.invalid", "r2_not-a-folder", "r2_" + id + "/child", "r2_" + id + "\n"] {
            hub.received(noticeID: id, kind: "media_folder", folderID: folder)
            XCTAssertNil(hub.noticeID); XCTAssertNil(hub.pendingMedia)
        }
        hub.received(noticeID: "invalid", kind: "media_folder", folderID: "r2_" + id)
        XCTAssertNil(hub.pendingMedia)
        hub.received(noticeID: id, kind: "unknown", folderID: "r2_" + id)
        XCTAssertNil(hub.noticeID); XCTAssertNil(hub.pendingMedia)
        hub.received(noticeID: id, kind: nil, folderID: nil)
        XCTAssertEqual(hub.noticeID, id.lowercased())
        hub.received(noticeID: id, kind: "media_folder", folderID: "r2_" + id)
        XCTAssertNil(hub.noticeID); XCTAssertEqual(hub.pendingMedia?.folderID, "r2_" + id.lowercased())
        hub.stop(); XCTAssertNil(hub.pendingMedia); XCTAssertNil(hub.mediaDestination)
        let vault = MemorySession(); vault.token = token
        MockProtocol.handler = { request in
            let body = try JSONDecoder().decode(JSONValue.self, from: MockProtocol.requestBody(request))
            XCTAssertEqual(body["action"].text, "logout"); XCTAssertEqual(body["notificationDeviceId"].text, JACNotifications.deviceID)
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, Data("{}".utf8))
        }
        try await makeClient(vault).logout(); XCTAssertNil(vault.token)
    }

    private func photoNotificationWorkspace(sections: [String] = ["media"]) throws -> Data {
        try JSONEncoder().encode(JSONValue.object([
            "version": .number(0), "company": .string("Prueba"), "periods": .array([]), "employees": .array([]),
            "user": .object(["id": .string("photo-fixture"), "username": .string("fotografia"), "email": .string("photo@example.invalid"), "displayName": .string("Fotografía ficticia"), "isOwner": .bool(false), "permissions": .array([]), "mediaOnly": .bool(true), "sections": .array(sections.map(JSONValue.string))]),
            "data": .object(["employees": .array([]), "periods": .array([]), "concepts": .array([]), "settings": .object(["company": .string("Prueba")])])
        ]))
    }
    private func photoNotificationFeed(_ folderID: String) throws -> Data {
        try JSONEncoder().encode(JSONValue.object([
            "connected": .bool(true), "canRead": .bool(true), "canUpload": .bool(false), "canConnect": .bool(false),
            "root": .object(["id": .string("jac_r2_root"), "name": .string("Fotografía")]),
            "folder": .object(["id": .string(folderID), "name": .string("Carpeta de prueba")]), "breadcrumbs": .array([]), "items": .array([]), "nextPageToken": .string(""), "provider": .string("r2"), "collectionID": .string("fixture-collection")
        ]))
    }
    @MainActor private func photoNotificationClient(_ vault: MemorySession, root: URL) -> PayrollClient {
        let configuration = URLSessionConfiguration.ephemeral; configuration.protocolClasses = [MockProtocol.self]
        return PayrollClient(baseURL: base, vault: vault, configuration: configuration, offlineCache: OfflineResponseCache(root: root.appendingPathComponent("content")), mediaOffline: MediaOfflineCache(root: root.appendingPathComponent("media")), automaticallyDownloadOffline: false)
    }
    @MainActor func testMediaFolderPushRoutesOnlyTheExactAuthorizedFolderAfterSessionRestoration() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let vault = MemorySession(), client = photoNotificationClient(vault, root: root), store = PayrollStore(client: client)
        let hub = JACNotifications(pushAvailable: true, registerRemote: {}, unregisterRemote: {})
        let folder = "r2_" + UUID().uuidString.lowercased(), workspace = try photoNotificationWorkspace(), feed = try photoNotificationFeed(folder)
        var paths: [String] = []
        MockProtocol.handler = { request in
            paths.append(request.url!.path)
            if request.url!.path == "/api/media" {
                XCTAssertEqual(URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "folder" })?.value, folder)
            }
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!, request.url!.path == "/api/media" ? feed : workspace)
        }
        hub.received(noticeID: UUID().uuidString, kind: "media_folder", folderID: folder)
        await hub.openPendingMedia(using: store)
        XCTAssertNotNil(hub.pendingMedia); XCTAssertNil(hub.mediaDestination); XCTAssertTrue(paths.isEmpty)
        vault.token = token
        await hub.openPendingMedia(using: store)
        XCTAssertEqual(paths, ["/api/mobile/payroll", "/api/media"])
        XCTAssertFalse(try XCTUnwrap(store.overview).user.hasNotices)
        XCTAssertEqual(hub.mediaDestination?.feed.folder?.id, folder)
        XCTAssertEqual(hub.mediaDestination?.stamp, try client.mediaAccessStamp())
        XCTAssertNil(hub.pendingMedia); XCTAssertNil(hub.noticeID)
        hub.stop()
    }
    @MainActor func testMediaOnlyNotificationRegistrationDoesNotGrantNoticeFeedAccess() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString), suite = "photo-push-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { try? FileManager.default.removeItem(at: root); defaults.removePersistentDomain(forName: suite) }
        let vault = MemorySession(); vault.token = token
        let client = photoNotificationClient(vault, root: root), workspace = try photoNotificationWorkspace(), permission = FakeNotificationPermission()
        var commands: [String] = [], remoteRequests = 0
        MockProtocol.handler = { request in
            if request.httpMethod == "POST" {
                commands.append(try JSONDecoder().decode(JSONValue.self, from: MockProtocol.requestBody(request))["action"].text)
                return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, Data("{}".utf8))
            }
            XCTAssertEqual(request.url?.path, "/api/mobile/payroll")
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, workspace)
        }
        _ = try await client.workspace(forceNetwork: true)
        XCTAssertTrue(try XCTUnwrap(client.accessUser).canReceiveNotifications)
        let hub = JACNotifications(defaults: defaults, permission: permission, allowsFixture: true, pushAvailable: true, registerRemote: { remoteRequests += 1 }, unregisterRemote: {})
        await hub.bind(client); await hub.register(String(repeating: "ab", count: 32))
        XCTAssertEqual(permission.requests, 1); XCTAssertEqual(remoteRequests, 1)
        do { _ = try await client.notices(); XCTFail("Fotografía no concede el feed de avisos") } catch APIError.forbidden { }
        do { try await client.noticeCommand(.object(["action": .string("read"), "id": .string(UUID().uuidString)])); XCTFail("Fotografía no concede lectura de avisos") } catch APIError.forbidden { }
        await hub.disable(client)
        XCTAssertEqual(commands, ["register", "unregister"]); XCTAssertFalse(hub.enabled)
    }
    @MainActor func testMediaFolderPushRejectsRevokedDeletedAndMismatchedFolders() async throws {
        for rejection in ["revoked", "deleted", "mismatched"] {
            let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: root) }
            let vault = MemorySession(); vault.token = token
            let client = photoNotificationClient(vault, root: root), store = PayrollStore(client: client), hub = JACNotifications(pushAvailable: true, registerRemote: {}, unregisterRemote: {})
            let folder = "r2_" + UUID().uuidString.lowercased(), original = try photoNotificationWorkspace(), revoked = try photoNotificationWorkspace(sections: []), wrong = try photoNotificationFeed("r2_" + UUID().uuidString.lowercased())
            client.rememberWorkspace(try JSONDecoder().decode(PayrollWorkspace.self, from: original))
            var mediaReads = 0
            MockProtocol.handler = { request in
                let media = request.url?.path == "/api/media"
                if media { mediaReads += 1 }
                return (HTTPURLResponse(url: request.url!, statusCode: media && rejection == "deleted" ? 410 : 200, httpVersion: nil, headerFields: nil)!, media ? rejection == "deleted" ? Data("{\"error\":\"Carpeta eliminada\"}".utf8) : wrong : rejection == "revoked" ? revoked : original)
            }
            hub.received(noticeID: UUID().uuidString, kind: "media_folder", folderID: folder)
            await hub.openPendingMedia(using: store)
            XCTAssertNil(hub.mediaDestination); XCTAssertNil(hub.noticeID); XCTAssertNil(hub.pendingMedia)
            XCTAssertNotNil(hub.routingError); XCTAssertEqual(mediaReads, rejection == "revoked" ? 0 : 1)
            hub.stop()
        }
    }
    @MainActor func testMediaFolderPushDiscardsAResponseAfterTheSessionChanges() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let vault = MemorySession(); vault.token = token
        let client = photoNotificationClient(vault, root: root), store = PayrollStore(client: client), hub = JACNotifications(pushAvailable: true, registerRemote: {}, unregisterRemote: {})
        let folder = "r2_" + UUID().uuidString.lowercased(), workspace = try photoNotificationWorkspace(), feed = try photoNotificationFeed(folder)
        MockProtocol.handler = { request in
            let media = request.url?.path == "/api/media"
            if media { vault.token = String(repeating: "b", count: 43) }
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, media ? feed : workspace)
        }
        hub.received(noticeID: UUID().uuidString, kind: "media_folder", folderID: folder)
        await hub.openPendingMedia(using: store)
        XCTAssertNil(hub.mediaDestination); XCTAssertNil(hub.noticeID); XCTAssertNil(hub.pendingMedia)
        hub.stop(); XCTAssertNil(hub.pendingMedia)
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
        #if os(macOS)
        let document=try TemporaryDocuments.save(Data("%PDF-1.4 fixture".utf8),filename:"Proteccion.pdf")
        defer{TemporaryDocuments.remove(document)}
        XCTAssertEqual((try FileManager.default.attributesOfItem(atPath:document.url.path)[.posixPermissions] as? NSNumber)?.intValue,0o600)
        let cache=OfflineResponseCache(root:FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        defer{try? FileManager.default.removeItem(at:cache.root)}
        let scope=OfflineResponseCache.scope(origin:base.absoluteString,token:token)
        try cache.save(OfflineResponse(key:"test",url:base.absoluteString,headers:[:],data:Data("fixture".utf8),receivedAt:Date(),revision:1),scope:scope)
        XCTAssertEqual((try FileManager.default.attributesOfItem(atPath:cache.file(scope,key:"test").path)[.posixPermissions] as? NSNumber)?.intValue,0o600)
        #elseif targetEnvironment(simulator)
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

    @MainActor func testUnlockAfterBackgroundLaunchRestoresSavedSessionAndOfflineWorkspace() async throws {
        let vault=MemorySession();vault.token=token
        let location=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let cache=OfflineResponseCache(root:location)
        let fixture=UITestBackend.client();let workspace=try await fixture.workspace()
        let config=URLSessionConfiguration.ephemeral;config.protocolClasses=[MockProtocol.self]
        let preparing=PayrollClient(baseURL:base,vault:vault,configuration:config,offlineCache:cache,automaticallyDownloadOffline:false)
        preparing.rememberWorkspace(workspace)
        vault.locked=true
        let restored=PayrollClient(baseURL:base,vault:vault,configuration:config,offlineCache:cache,automaticallyDownloadOffline:false)
        let store=PayrollStore(client:restored)
        XCTAssertFalse(store.hasSavedSession);XCTAssertNil(store.overview)
        vault.locked=false
        MockProtocol.handler={_ in throw URLError(.notConnectedToInternet)}
        defer{MockProtocol.handler=nil;try? FileManager.default.removeItem(at:location)}
        await store.restore()
        XCTAssertTrue(store.hasSavedSession);XCTAssertEqual(store.overview?.user.id,workspace.user.id)
        XCTAssertNotNil(store.workspace);XCTAssertTrue(store.isOffline);XCTAssertEqual(vault.token,token)
    }
    @MainActor func testUploadBackgroundControlAndSmallPhotoReceiptUseSameIDAfterExpiredPart() async throws {
        let vault = MemorySession(); vault.token = token
        let transport = ScriptedUploadTransport()
        let client = PayrollClient(baseURL: base, vault: vault, automaticallyDownloadOffline: false, mediaUploadTransport: transport)
        let source = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".jpg")
        let bytes = Data([0xff,0xd8,0xff,0xe0,1,2,3,4]); try bytes.write(to: source)
        defer { try? FileManager.default.removeItem(at: source) }
        let file = try MediaLocalFile.stage(source, quality: .original); defer { file.remove() }
        var puts = 0, starts = 0, statuses = 0, receivedReceipt = false
        let etag = "\"" + String(repeating: "a", count: 32) + "\""
        func signed() -> String {
            var p = URLComponents(string: "https://" + String(repeating:"1",count:32) + ".r2.cloudflarestorage.com/jac-fotografia/originals/" + file.id)!
            p.queryItems = [URLQueryItem(name:"uploadId",value:"fixture-parts"),URLQueryItem(name:"partNumber",value:"1"),URLQueryItem(name:"X-Amz-Algorithm",value:"AWS4-HMAC-SHA256"),URLQueryItem(name:"X-Amz-Credential",value:String(repeating:"2",count:32)+"/20261017/auto/s3/aws4_request"),URLQueryItem(name:"X-Amz-Date",value:"20261017T120000Z"),URLQueryItem(name:"X-Amz-Expires",value:"300"),URLQueryItem(name:"X-Amz-SignedHeaders",value:"content-length;content-type;host"),URLQueryItem(name:"X-Amz-Signature",value:String(repeating:"a",count:64))]
            return p.url!.absoluteString
        }
        transport.handler = { request, payload, key in
            XCTAssertFalse(key.contains(self.token))
            if request.url?.host == self.base.host {
                XCTAssertEqual(request.value(forHTTPHeaderField:"Cookie"),"__Host-jac_session="+self.token)
                let body = try JSONDecoder().decode(JSONValue.self,from:payload)
                XCTAssertEqual(body["id"].text,file.id)
                if body["action"].text == "start" { starts += 1 } else { statuses += 1 }
                let done = puts == 2
                if done {
                    XCTAssertEqual(body["partReceipt"]["etag"].text,etag)
                    XCTAssertEqual(body["partReceipt"]["partNumber"].number,1)
                    XCTAssertEqual(body["partReceipt"]["size"].number,Double(bytes.count)); receivedReceipt = true
                } else { XCTAssertEqual(body["partReceipt"],.null) }
                var state: JSONValue = .object(["id":.string(file.id),"provider":.string("r2"),"offset":.number(done ? Double(bytes.count):0),"chunkSize":.number(8*1024*1024),"complete":.bool(done)])
                if !done { state["uploadURL"] = .string(signed()) }
                return (try JSONEncoder().encode(state),HTTPURLResponse(url:request.url!,statusCode:200,httpVersion:nil,headerFields:nil)!)
            }
            puts += 1; XCTAssertEqual(payload,bytes)
            for header in ["Cookie","Authorization","Origin"] {XCTAssertNil(request.value(forHTTPHeaderField:header))}
            return (Data(),HTTPURLResponse(url:request.url!,statusCode:puts == 1 ? 403:200,httpVersion:nil,headerFields:["ETag":etag])!)
        }
        let provider = try await client.uploadMediaOriginal(file,parentID:"jac_r2_root") {_,_ in}
        XCTAssertEqual(provider,"r2");XCTAssertTrue(receivedReceipt);XCTAssertEqual(starts,1);XCTAssertEqual(statuses,2);XCTAssertEqual(puts,2)
    }
    #if os(iOS)
    @MainActor func testBackgroundTransportUsesFileBodyAndBoundsJACOrigin() async throws {
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [MockProtocol.self]
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let transport = MediaBackgroundTransport(identifier:"fixture-"+UUID().uuidString,root:root,origin:base,configuration:config)
        defer { transport.cancelAll(); MockProtocol.handler = nil; try? FileManager.default.removeItem(at:root) }
        var request = URLRequest(url:base.appendingPathComponent("api/media/upload")); request.httpMethod="POST"
        request.setValue("__Host-jac_session="+token,forHTTPHeaderField:"Cookie");request.setValue(base.absoluteString,forHTTPHeaderField:"Origin")
        request.setValue("application/json",forHTTPHeaderField:"Content-Type")
        let payload=Data("{\"id\":\"fixture\"}".utf8),expected=Data("{\"complete\":true}".utf8)
        MockProtocol.handler = { req in
            XCTAssertEqual(try MockProtocol.requestBody(req),payload)
            return(HTTPURLResponse(url:req.url!,statusCode:200,httpVersion:nil,headerFields:nil)!,expected)
        }
        XCTAssertTrue(MediaBackgroundTransport.allowed(request,origin:base))
        var other=request;other.url=URL(string:"https://attacker.invalid/api/media/upload");XCTAssertFalse(MediaBackgroundTransport.allowed(other,origin:base))
        other=request;other.url=base.appendingPathComponent("api/users");XCTAssertFalse(MediaBackgroundTransport.allowed(other,origin:base))
        let (received,response)=try await transport.send(request,body:payload,key:"fixture-control") {_ in}
        XCTAssertEqual(received,expected);XCTAssertEqual((response as? HTTPURLResponse)?.statusCode,200)
        XCTAssertEqual((try? FileManager.default.contentsOfDirectory(atPath:root.path)) ?? [],[])
    }
    @MainActor func testBackgroundTransportCancelThenRestartSameBodyDoesNotCancelReplacement() async throws {
        RestartUploadProtocol.reset()
        let config=URLSessionConfiguration.ephemeral;config.protocolClasses=[RestartUploadProtocol.self]
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let transport=MediaBackgroundTransport(identifier:"restart-"+UUID().uuidString,root:root,origin:base,configuration:config)
        defer{transport.cancelAll();try? FileManager.default.removeItem(at:root)}
        var request=URLRequest(url:base.appendingPathComponent("api/media/upload"));request.httpMethod="POST"
        request.setValue("__Host-jac_session="+token,forHTTPHeaderField:"Cookie");request.setValue(base.absoluteString,forHTTPHeaderField:"Origin")
        let payload=Data("same part".utf8)
        let first=Task{try await transport.send(request,body:payload,key:"same-key"){_ in}}
        let limit=Date().addingTimeInterval(5)
        while RestartUploadProtocol.started()==0 && Date()<limit {try await Task.sleep(for:.milliseconds(10))}
        XCTAssertEqual(RestartUploadProtocol.started(),1)
        first.cancel();transport.cancelAll()
        let (data,_)=try await transport.send(request,body:payload,key:"same-key"){_ in}
        XCTAssertEqual(data,Data("second-transfer".utf8));XCTAssertEqual(RestartUploadProtocol.started(),2)
        _=try? await first.value
    }
    #endif

}

extension PayrollClientTests {
    private func contractDraftFixture()->ContractDraft {
        var d=ContractDraft();d.company="EMPRESA FICTICIA JAC SAS";d.nit="900000001-0";d.representative="ANA MARÍA PRUEBA GÓMEZ";d.identity="100000001"
        d.eventDate="2026-10-31";d.venue="Escenario ficticio";d.municipality="Pereira";d.department="Risaralda";d.showTime="23:00";d.price=140000001;d.deposited=10000000;d.halfDeadline="2026-10-20"
        return d
    }
    func testContractDraftMatchesWebInputsFilenameAndHalfPaymentRules() throws {
        var d=contractDraftFixture(),payload=try d.payload()
        XCTAssertEqual(d.finalDate,"2026-10-26");XCTAssertEqual(d.price/2,70000000.5)
        XCTAssertEqual(d.filename,"Contrato JAC - Pereira - 31 de octubre 2026.pdf")
        XCTAssertEqual(Set(payload.fields.keys),Set(["company","nit","representative","identity","eventDate","venue","municipality","department","showTime","price","deposited","halfDeadline"]))
        XCTAssertEqual(payload["deposited"].number,10000000);XCTAssertEqual(payload["company"].text,"EMPRESA FICTICIA JAC SAS")
        d.price=10.5;XCTAssertThrowsError(try d.payload());d.price=140000000;d.deposited=70000001;XCTAssertThrowsError(try d.payload())
        d.deposited=0;d.halfDeadline="2026-10-27";XCTAssertThrowsError(try d.payload());d.halfDeadline="2026-10-26";_ = try d.payload()
        d.showTime="25:00";XCTAssertThrowsError(try d.payload());d.showTime="23:00";d.eventDate="2026-02-30";XCTAssertThrowsError(try d.payload())
        d.eventDate="2026-10-31";d.company="Nombre\nOmitido";XCTAssertThrowsError(try d.payload())
        d.company="FUNDACIÓN FICTICIA";d.municipality="../Pereira";XCTAssertFalse(d.filename.contains("/"));payload=try d.payload();XCTAssertFalse(payload.fields.keys.contains("rut"),"El PDF original del RUT nunca entra en el POST")
    }
    @MainActor func testContractUsesBearerOnlyAndPrivateTemporaryUTF8PDF() async throws {
        let vault=MemorySession();vault.token=token
        let config=URLSessionConfiguration.ephemeral;config.protocolClasses=[MockProtocol.self]
        let client=PayrollClient(baseURL:URL(string:"https://contracts.invalid")!,vault:vault,configuration:config,automaticallyDownloadOffline:false),draft=contractDraftFixture()
        var calls=0
        MockProtocol.handler={request in
            calls += 1;XCTAssertEqual(request.url?.path,"/api/mobile/contracts");XCTAssertEqual(request.httpMethod,"POST")
            XCTAssertEqual(request.value(forHTTPHeaderField:"Authorization"),"Bearer "+self.token);XCTAssertNil(request.value(forHTTPHeaderField:"Cookie"));XCTAssertEqual(request.value(forHTTPHeaderField:"Content-Type"),"application/json")
            let body=try JSONDecoder().decode(JSONValue.self,from:MockProtocol.requestBody(request));XCTAssertEqual(body["company"].text,draft.company);XCTAssertNil(body.fields["rut"])
            let name="Contrato JAC - Soracá - 31 de octubre 2026.pdf".addingPercentEncoding(withAllowedCharacters:.urlPathAllowed)!
            return(HTTPURLResponse(url:request.url!,statusCode:200,httpVersion:nil,headerFields:["Content-Type":"application/pdf","Content-Disposition":"attachment; filename*=UTF-8''"+name])!,Data("%PDF-1.4\nCONTRATO FICTICIO\n%%EOF".utf8))
        }
        defer{MockProtocol.handler=nil;try? client.clearSession()}
        let file=try await client.createContract(draft)
        XCTAssertEqual(file.url.lastPathComponent,"Contrato JAC - Soracá - 31 de octubre 2026.pdf");XCTAssertTrue(file.url.path.hasPrefix(TemporaryDocuments.root.path));XCTAssertTrue(FileManager.default.fileExists(atPath:file.url.path));XCTAssertEqual(calls,1)
        let scope=OfflineResponseCache.scope(origin:client.baseURL.absoluteString,token:token)
        XCTAssertFalse(client.offlineCache.entries(scope).contains{$0.url.contains("contracts")})
        try client.clearSession();XCTAssertFalse(FileManager.default.fileExists(atPath:file.url.path))
    }
    @MainActor func testContractRefusesServerDenialInvalidDocumentAndOfflineWrite() async throws {
        let vault=MemorySession();vault.token=token
        let config=URLSessionConfiguration.ephemeral;config.protocolClasses=[MockProtocol.self]
        let client=PayrollClient(baseURL:URL(string:"https://contract-denied.invalid")!,vault:vault,configuration:config,automaticallyDownloadOffline:false),draft=contractDraftFixture()
        defer{MockProtocol.handler=nil;try? client.clearSession()}
        let old=try TemporaryDocuments.save(Data("private".utf8),filename:"old.pdf")
        MockProtocol.handler={r in(HTTPURLResponse(url:r.url!,statusCode:403,httpVersion:nil,headerFields:["Content-Type":"application/json"])!,Data("{\"error\":\"Acceso CRM retirado\"}".utf8))}
        do{_ = try await client.createContract(draft);XCTFail("No se permite crear sin acceso")}catch{guard case APIError.forbidden=error else{return XCTFail(error.localizedDescription)}}
        XCTAssertFalse(FileManager.default.fileExists(atPath:old.url.path));XCTAssertEqual(vault.token,token)
        MockProtocol.handler={r in(HTTPURLResponse(url:r.url!,statusCode:200,httpVersion:nil,headerFields:["Content-Type":"application/pdf"])!,Data("<html>Incorrecto</html>".utf8))}
        do{_ = try await client.createContract(draft);XCTFail("No se acepta contenido ajeno a PDF")}catch{}
        var calls=0;MockProtocol.handler={_ in calls += 1;throw URLError(.notConnectedToInternet)};client.beginOfflineRestore()
        do{_ = try await client.createContract(draft);XCTFail("Generación requiere conexión")}catch{}
        XCTAssertEqual(calls,0,"No se intenta una escritura con la copia offline")
    }
    private func rutLayoutFixture(role:String="REPRS LEGAL PRIN",company:String="EMPRESA FICTICIA JAC SAS",document:String="Cédula de Ciudadanía 13")->[RutPageLayout] {
        func item(_ text:String,_ x:Double,_ y:Double,_ width:Double=100,_ height:Double=8)->RutTextItem {RutTextItem(text:text,x:x,y:y,width:width,height:height)}
        let first=[item("DIAN",500,10),item("5. Número de Identificación Tributaria",20,100,265),item("6. DV",300,100,30),item("12. Dirección seccional",350,100),item("900000001",30,113,150),item("0",307,113,5),item("24. Tipo de contribuyente",20,180,200),item("35. Razón social",20,220,150),item(company,20,233,300,10),item("36. Nombre comercial",20,250,200),item("41. Dirección principal",20,280,200)]
        let rep=[item("98. Representación",20,100,200),item("99. Fecha inicio ejercicio representación",300,100,250),item(role,20,113,180),item("100. Tipo de documento",20,127,150),item("101. Número de identificación",180,127,230),item("102. DV",450,127,50),item(document,20,140,140),item("100000001",200,140,180),item("104. Primer apellido",20,155,140),item("105. Segundo apellido",170,155,140),item("106. Primer nombre",320,155,120),item("107. Otros nombres",450,155,130),item("PRUEBA",20,169,100),item("GÓMEZ",170,169,100),item("ANA",320,169,80),item("MARÍA",450,169,90),item("108. Número de Identificación Tributaria",20,185,250)]
        return[RutPageLayout(width:612,height:792,items:first),RutPageLayout(width:612,height:792,items:rep)]
    }
    func testRutReadsLabelledCellsAndFillsOnlyUniquePrincipalWithEditableManualFallback() throws {
        let extraction=try RutParser.extract(rutLayoutFixture())
        XCTAssertEqual(extraction.company,"EMPRESA FICTICIA JAC SAS");XCTAssertEqual(extraction.nit,"900000001-0");XCTAssertEqual(extraction.representatives.count,1)
        let person=try XCTUnwrap(extraction.representatives.first);XCTAssertEqual(person.name,"ANA MARÍA PRUEBA GÓMEZ");XCTAssertEqual(person.identity,"100000001");XCTAssertEqual(person.kind,.principal);XCTAssertEqual(person.documentType,"Cédula de ciudadanía")
        var draft=ContractDraft();draft.apply(extraction);XCTAssertEqual(draft.representative,person.name);XCTAssertEqual(draft.identity,person.identity)
        draft.company="CORRECCIÓN MANUAL";XCTAssertEqual(draft.company,"CORRECCIÓN MANUAL")
        let alternate=try RutParser.extract(rutLayoutFixture(role:"REPRS LEGAL SUPL"));draft.apply(alternate);XCTAssertTrue(draft.representative.isEmpty);XCTAssertTrue(draft.identity.isEmpty);XCTAssertTrue(alternate.warnings.contains{$0.contains("No se encontró un representante legal principal")})
        let foreign=try RutParser.extract(rutLayoutFixture(document:"Pasaporte 41"));draft.apply(foreign);XCTAssertTrue(draft.identity.isEmpty);XCTAssertTrue(foreign.warnings.contains{$0.contains("distinto")})
    }
    func testRutRejectsMixedCompaniesAndNeverChoosesAmongMultiplePrincipals() throws {
        var pages=rutLayoutFixture();pages.append(contentsOf:rutLayoutFixture(company:"OTRA EMPRESA FICTICIA"));XCTAssertThrowsError(try RutParser.extract(pages))
        let base=try RutParser.extract(rutLayoutFixture());var multiple=base
        multiple.representatives.append(RutRepresentative(name:"OTRO FIRMANTE FICTICIO",identity:"100000002",kind:.principal,documentType:"Cédula de ciudadanía"))
        var draft=ContractDraft();draft.apply(multiple);XCTAssertTrue(draft.representative.isEmpty);XCTAssertTrue(draft.identity.isEmpty)
        var incomplete=base;incomplete.warnings=["Un representante tiene nombre o identificación incompletos. Revisa esa fila del RUT."];draft.apply(incomplete);XCTAssertTrue(draft.representative.isEmpty);XCTAssertTrue(draft.identity.isEmpty)
        var alpha=base;alpha.representatives=[RutRepresentative(name:"FIRMANTE FICTICIO",identity:"ABC-123",kind:.principal,documentType:"Cédula de ciudadanía")];draft.apply(alpha);XCTAssertTrue(draft.identity.isEmpty)
        XCTAssertThrowsError(try RutParser.extract([]));XCTAssertThrowsError(try RutParser.extract([RutPageLayout(width:612,height:792,items:[RutTextItem(text:"DIAN Otro documento",x:10,y:10,width:200,height:10)])]))
    }
    func testRutPDFKitReadsFictitiousLocalPDFWithNoOriginalInContractPayload() throws {
        let buffer=NSMutableData(),consumer=try XCTUnwrap(CGDataConsumer(data:buffer)),font=CTFontCreateWithName("Helvetica" as CFString,8,nil)
        var box=CGRect(x:0,y:0,width:612,height:792)
        let context=try XCTUnwrap(CGContext(consumer:consumer,mediaBox:&box,nil))
        for page in rutLayoutFixture() {
            context.beginPDFPage(nil);context.textMatrix = .identity
            for item in page.items {
                let text=NSAttributedString(string:item.text,attributes:[NSAttributedString.Key(kCTFontAttributeName as String):font])
                context.textPosition=CGPoint(x:item.x,y:792-item.y-8);CTLineDraw(CTLineCreateWithAttributedString(text),context)
            }
            context.endPDFPage()
        }
        context.closePDF()
        let file=try TemporaryDocuments.save(buffer as Data,filename:"RUT completamente ficticio.pdf");defer{TemporaryDocuments.remove(file)}
        let extraction=try RutParser.read(file.url)
        XCTAssertEqual(extraction.company,"EMPRESA FICTICIA JAC SAS");XCTAssertEqual(extraction.nit,"900000001-0");XCTAssertEqual(extraction.representatives.first?.name,"ANA MARÍA PRUEBA GÓMEZ")
        var draft=contractDraftFixture();draft.apply(extraction)
        XCTAssertEqual(try draft.payload()["representative"].text,"ANA MARÍA PRUEBA GÓMEZ")
        XCTAssertLessThan(try JSONEncoder().encode(draft.payload()).count,8192)
        XCTAssertThrowsError(try RutParser.read(URL(fileURLWithPath:"/not-a-real-file.invalid/RUT.pdf")))
    }
}

private final class ContractDelayedProtocol:URLProtocol {
    private static let lock=NSLock()
    private static var held:ContractDelayedProtocol?
    static func reset(){lock.lock();held=nil;lock.unlock()}
    static func pending()->ContractDelayedProtocol? {lock.lock();defer{lock.unlock()};return held}
    override class func canInit(with request:URLRequest)->Bool {request.url?.host?.hasSuffix(".invalid") == true}
    override class func canonicalRequest(for request:URLRequest)->URLRequest {request}
    override func startLoading(){Self.lock.lock();Self.held=self;Self.lock.unlock()}
    override func stopLoading(){}
    func reply() {client?.urlProtocol(self,didReceive:HTTPURLResponse(url:request.url!,statusCode:200,httpVersion:nil,headerFields:["Content-Type":"application/pdf"])!,cacheStoragePolicy:.notAllowed);client?.urlProtocol(self,didLoad:Data("%PDF-1.4\nFICTICIO\n%%EOF".utf8));client?.urlProtocolDidFinishLoading(self)}
}
extension PayrollClientTests {
    @MainActor func testContractLatePDFCannotSurviveLogout() async throws {
        ContractDelayedProtocol.reset();let vault=MemorySession();vault.token=token
        let config=URLSessionConfiguration.ephemeral;config.protocolClasses=[ContractDelayedProtocol.self]
        let client=PayrollClient(baseURL:URL(string:"https://contract-late.invalid")!,vault:vault,configuration:config,automaticallyDownloadOffline:false)
        let draft=contractDraftFixture(),task=Task{try await client.createContract(draft)}
        for _ in 0..<100 {if ContractDelayedProtocol.pending() != nil {break};try await Task.sleep(for:.milliseconds(10))}
        let pending=try XCTUnwrap(ContractDelayedProtocol.pending());try client.clearSession();pending.reply()
        do{_ = try await task.value;XCTFail("Un PDF de la sesión anterior no debe instalarse tras cerrar sesión")}catch{XCTAssertTrue(error is CancellationError)}
        XCTAssertNil(vault.token);ContractDelayedProtocol.reset()
    }
}

extension PayrollClientTests {
    @MainActor func testArchivedContractsUseBearerAndKeepSaveIdentityAndAssociation() async throws {
        let vault=MemorySession();vault.token=token
        let config=URLSessionConfiguration.ephemeral;config.protocolClasses=[MockProtocol.self]
        let client=PayrollClient(baseURL:URL(string:"https://contract-archive.invalid")!,vault:vault,configuration:config,automaticallyDownloadOffline:false)
        let id=UUID().uuidString,show=UUID().uuidString;var actions:[String]=[]
        MockProtocol.handler={r in
            XCTAssertEqual(r.value(forHTTPHeaderField:"Authorization"),"Bearer "+self.token);XCTAssertNil(r.value(forHTTPHeaderField:"Cookie"))
            if r.httpMethod == "POST" {
                let body=try JSONDecoder().decode(JSONValue.self,from:MockProtocol.requestBody(r));actions.append(body["action"].text);XCTAssertEqual(body["id"].text,id);XCTAssertEqual(body["showId"].text,show)
                if body["action"].text == "save" {XCTAssertEqual(body["input"]["company"].text,"EMPRESA FICTICIA JAC SAS");return(HTTPURLResponse(url:r.url!,statusCode:200,httpVersion:nil,headerFields:["Content-Type":"application/pdf"])!,Data("%PDF-1.4\nFICTICIO\n%%EOF".utf8))}
                XCTAssertEqual(body["version"].number,3)
            }
            return(HTTPURLResponse(url:r.url!,statusCode:200,httpVersion:nil,headerFields:["Content-Type":"application/json"])!,Data("{\"contracts\":[],\"next\":null}".utf8))
        }
        defer{MockProtocol.handler=nil;try? client.clearSession()}
        let file=try await client.createContract(contractDraftFixture(),id:id,showId:show);TemporaryDocuments.remove(file)
        _ = try await client.contractArchive();try await client.linkContract(id:id,showId:show,version:3)
        XCTAssertEqual(actions,["save","link"])
    }
    @MainActor func testArchivedContractDownloadValidatesPDFAndRevocationRemovesTemporary() async throws {
        let vault=MemorySession();vault.token=token
        let config=URLSessionConfiguration.ephemeral;config.protocolClasses=[MockProtocol.self]
        let client=PayrollClient(baseURL:URL(string:"https://archive-document.invalid")!,vault:vault,configuration:config,automaticallyDownloadOffline:false)
        defer{MockProtocol.handler=nil;try? client.clearSession()}
        MockProtocol.handler={r in(HTTPURLResponse(url:r.url!,statusCode:200,httpVersion:nil,headerFields:["Content-Type":"application/pdf"])!,Data("%PDF-1.4\nFICTICIO\n%%EOF".utf8))}
        let file=try await client.archivedContract(id:UUID().uuidString,filename:"../../Contrato privado.pdf");XCTAssertEqual(file.url.lastPathComponent,"Contrato privado.pdf")
        MockProtocol.handler={r in(HTTPURLResponse(url:r.url!,statusCode:403,httpVersion:nil,headerFields:["Content-Type":"application/json"])!,Data("{\"error\":\"Permiso retirado\"}".utf8))}
        do{_ = try await client.contractArchive();XCTFail("La revocación debe impedir leer el archivo")}catch{guard case APIError.forbidden=error else{return XCTFail(error.localizedDescription)}}
        XCTAssertFalse(FileManager.default.fileExists(atPath:file.url.path));XCTAssertEqual(vault.token,token)
    }
}

extension PayrollClientTests {
    @MainActor func testArchivedContractLastReadAvailableOfflineAnd403NeverFallsBack() async throws {
        let vault=MemorySession();vault.token=token
        let config=URLSessionConfiguration.ephemeral;config.protocolClasses=[MockProtocol.self]
        let client=PayrollClient(baseURL:URL(string:"https://contracts-offline.invalid")!,vault:vault,configuration:config,automaticallyDownloadOffline:false)
        defer{MockProtocol.handler=nil;try? client.clearSession()}
        var calls=0
        MockProtocol.handler={r in calls += 1;return(HTTPURLResponse(url:r.url!,statusCode:200,httpVersion:nil,headerFields:["Content-Type":"application/pdf"])!,Data("%PDF-1.4\nFICTICIO\n%%EOF".utf8))}
        let id=UUID().uuidString,first=try await client.archivedContract(id:id,filename:"Contrato.pdf");TemporaryDocuments.remove(first)
        client.beginOfflineRestore();MockProtocol.handler={_ in calls += 1;throw URLError(.notConnectedToInternet)}
        let saved=try await client.archivedContract(id:id,filename:"Contrato.pdf");XCTAssertEqual(calls,1);XCTAssertTrue(FileManager.default.fileExists(atPath:saved.url.path))
        // Revalidate explicitly: a forbidden response must discard this copy.
        let online=PayrollClient(baseURL:client.baseURL,vault:vault,configuration:config,offlineCache:client.offlineCache,automaticallyDownloadOffline:false)
        MockProtocol.handler={r in(HTTPURLResponse(url:r.url!,statusCode:403,httpVersion:nil,headerFields:["Content-Type":"application/json"])!,Data("{\"error\":\"CRM retirado\"}".utf8))}
        do{_ = try await online.archivedContract(id:id,filename:"Contrato.pdf");XCTFail("No debe usar PDF cacheado ante 403")}catch{}
        XCTAssertFalse(FileManager.default.fileExists(atPath:saved.url.path))
        let scope=OfflineResponseCache.scope(origin:client.baseURL.absoluteString,token:token);XCTAssertFalse(client.offlineCache.entries(scope).contains{$0.url.contains("contracts")})
    }
}

extension PayrollClientTests {
    @MainActor func testContractDeletionUsesBearerConfirmationAndEvictsOnlyItsPDFAndEveryCachedPage() async throws {
        let vault=MemorySession();vault.token=token
        let config=URLSessionConfiguration.ephemeral;config.protocolClasses=[MockProtocol.self]
        let client=PayrollClient(baseURL:URL(string:"https://contract-delete-cache.example.invalid")!,vault:vault,configuration:config,automaticallyDownloadOffline:false)
        defer{MockProtocol.handler=nil;try? client.clearSession()}
        let id=UUID().uuidString,other=UUID().uuidString
        let feed:JSONValue = .object(["contracts":.array([.object(["id":.string(id)]),.object(["id":.string(other)])]),"next":.null])
        var calls=0
        MockProtocol.handler={r in
            calls+=1;XCTAssertEqual(r.value(forHTTPHeaderField:"Authorization"),"Bearer "+self.token);XCTAssertNil(r.value(forHTTPHeaderField:"Cookie"))
            if r.httpMethod == "POST" {
                let command=try JSONDecoder().decode(JSONValue.self,from:MockProtocol.requestBody(r));XCTAssertEqual(command["action"].text,"delete");XCTAssertEqual(command["id"].text,id);XCTAssertEqual(command["confirmation"].text,id);XCTAssertEqual(command["version"].number,7)
                return(HTTPURLResponse(url:r.url!,statusCode:200,httpVersion:nil,headerFields:["Content-Type":"application/json"])!,Data("{\"ok\":true}".utf8))
            }
            if r.url?.query?.contains("id=") == true {return(HTTPURLResponse(url:r.url!,statusCode:200,httpVersion:nil,headerFields:["Content-Type":"application/pdf"])!,Data("%PDF-1.4\nFICTICIO\n%%EOF".utf8))}
            return(HTTPURLResponse(url:r.url!,statusCode:200,httpVersion:nil,headerFields:["Content-Type":"application/json"])!,try JSONEncoder().encode(feed))
        }
        _ = try await client.contractArchive(query:["offset":"0"]);_ = try await client.contractArchive(query:["offset":"50"])
        let first=try await client.archivedContract(id:id,filename:"A.pdf"),second=try await client.archivedContract(id:other,filename:"B.pdf")
        try await client.deleteArchivedContract(id:id,version:7)
        XCTAssertFalse(FileManager.default.fileExists(atPath:first.url.path));XCTAssertTrue(FileManager.default.fileExists(atPath:second.url.path))
        for offset in ["0","50"] {let page=try XCTUnwrap(client.cached(JSONValue.self,path:"api/mobile/contracts",query:[URLQueryItem(name:"offset",value:offset)]));XCTAssertEqual(page["contracts"].elements.map{$0["id"].text},[other])}
        client.beginOfflineRestore();let before=calls
        do{_ = try await client.archivedContract(id:id,filename:"A.pdf");XCTFail("Deleted PDF must never return from offline cache.")}catch{}
        _ = try await client.archivedContract(id:other,filename:"B.pdf");XCTAssertEqual(calls,before)
    }
    @MainActor func testContractDeletionConflictOrOfflineKeepsTheAllowedCopy() async throws {
        let vault=MemorySession();vault.token=token
        let config=URLSessionConfiguration.ephemeral;config.protocolClasses=[MockProtocol.self]
        let client=PayrollClient(baseURL:URL(string:"https://contract-delete-conflict.example.invalid")!,vault:vault,configuration:config,automaticallyDownloadOffline:false)
        defer{MockProtocol.handler=nil;try? client.clearSession()}
        let id=UUID().uuidString;var posts=0
        MockProtocol.handler={r in
            if r.httpMethod == "POST" {posts+=1;return(HTTPURLResponse(url:r.url!,statusCode:409,httpVersion:nil,headerFields:["Content-Type":"application/json"])!,Data("{\"error\":\"El contrato cambió\"}".utf8))}
            return(HTTPURLResponse(url:r.url!,statusCode:200,httpVersion:nil,headerFields:["Content-Type":"application/pdf"])!,Data("%PDF-1.4\nFICTICIO\n%%EOF".utf8))
        }
        let document=try await client.archivedContract(id:id,filename:"A.pdf")
        do{try await client.deleteArchivedContract(id:id,version:1);XCTFail("Stale delete must fail.")}catch APIError.conflict {}
        XCTAssertTrue(FileManager.default.fileExists(atPath:document.url.path));client.beginOfflineRestore()
        do{try await client.deleteArchivedContract(id:id,version:1);XCTFail("Deletion must require internet.")}catch{}
        XCTAssertEqual(posts,1);_ = try await client.archivedContract(id:id,filename:"A.pdf")
    }
    @MainActor func testLateContractListOrPDFCannotRepopulateAfterDeletion() async throws {
        for document in [false,true] {
            CRMDelayedProtocol.resetPending();let vault=MemorySession();vault.token=token
            let config=URLSessionConfiguration.ephemeral;config.protocolClasses=[CRMDelayedProtocol.self]
            let client=PayrollClient(baseURL:URL(string:"https://late-contract-\(UUID().uuidString.lowercased()).example.invalid")!,vault:vault,configuration:config,automaticallyDownloadOffline:false)
            let id=UUID().uuidString
            let reading=Task {if document {_ = try await client.archivedContract(id:id,filename:"Late.pdf")}else{_ = try await client.contractArchive(query:["offset":"0"])}}
            for _ in 0..<100 {if CRMDelayedProtocol.pending() != nil {break};try await Task.sleep(for:.milliseconds(10))}
            let held=try XCTUnwrap(CRMDelayedProtocol.pending());try await client.deleteArchivedContract(id:id,version:1)
            held.respond(Data("{\"contracts\":[{\"id\":\"\(id)\"}],\"next\":null}".utf8))
            do{try await reading.value;XCTFail("The response before deletion must not restore the contract.")}catch{XCTAssertTrue(error is CancellationError,error.localizedDescription)}
            XCTAssertNil(client.cached(JSONValue.self,path:"api/mobile/contracts",query:[URLQueryItem(name:"offset",value:"0")]))
            try client.clearSession();CRMDelayedProtocol.resetPending()
        }
    }
}


extension PayrollClientTests {
    func testMusicPermissionsDoNotGrantOtherSectionsAndUploadsRequireListening() {
        var user=PayrollUser(id:"music",email:"music@example.invalid",username:"music",displayName:"Música ficticia",isOwner:false,permissions:[],sections:["music"])
        XCTAssertTrue(user.canReadMusic);XCTAssertFalse(user.canUploadMusic);XCTAssertFalse(user.canReadMedia);XCTAssertFalse(user.hasSection(.payroll));XCTAssertEqual(user.firstDestination,"music")
        user.sections=["musicUpload"];XCTAssertFalse(user.canUploadMusic)
        user.sections=["music","musicUpload"];XCTAssertTrue(user.canUploadMusic)
        user.sections=nil;XCTAssertFalse(user.canReadMusic)
    }
    @MainActor func testMusicPlaybackAuthorizationSurvivesLockAndIsRemovedWithSession() async throws {
        let fixture=UITestBackend.client(),workspace=try await fixture.workspace()
        let vault=MemorySession();vault.token=token;let client=makeClient(vault);client.rememberWorkspace(workspace)
        let track=MusicTrack(id:UUID().uuidString.lowercased(),section:.tracks,title:"Pista ficticia",filename:"Pista.wav",mimeType:"audio/wav",size:128,revision:"r1",createdAt:"2026-10-19")
        MockProtocol.handler={ request in
            XCTAssertEqual(request.url?.path,"/api/music");XCTAssertEqual(request.value(forHTTPHeaderField:"Cookie"),"__Host-jac_session="+self.token)
            return (HTTPURLResponse(url:request.url!,statusCode:200,httpVersion:nil,headerFields:["Content-Type":"application/json"])!,Data("{\"url\":\"/api/music/file?id=fixture&lease=encrypted-fixture\"}".utf8))
        }
        try client.beginMusicPlayback();let scope=try XCTUnwrap(client.musicScope());vault.locked=true
        let result=try await client.musicPlayback(track);XCTAssertEqual(result.0.host,client.baseURL.host);XCTAssertNil(result.1);XCTAssertEqual(try client.musicScope()?.id,scope.id)
        vault.locked=false;try client.clearSession()
        do{_ = try await client.musicPlayback(track);XCTFail("Playback must stop after logout")}catch{}
        XCTAssertNil(try client.musicScope())
    }
    @MainActor func testMusicOfflineAudioIsEncryptedRevisionBoundAndCanBeDownloadedAgain() async throws {
        let fixture=UITestBackend.client(),workspace=try await fixture.workspace();let vault=MemorySession();vault.token=token;let client=makeClient(vault);client.rememberWorkspace(workspace)
        let track=MusicTrack(id:UUID().uuidString.lowercased(),section:.warmup,title:"Vocalización",filename:"Voz.wav",mimeType:"audio/wav",size:128,revision:"r1",createdAt:"2026-10-19")
        let source=try TemporaryDocuments.save(Data(repeating:72,count:128),filename:"Voz.wav"),scope=try XCTUnwrap(client.musicScope())
        try client.musicOffline.saveFile(source.url,item:track.mediaItem,scope:scope);try client.musicOffline.pinFile(track.mediaItem,scope:scope)
        XCTAssertTrue(client.musicHasDownload(track));let encrypted=try Data(contentsOf:client.musicOffline.encryptedFile(track.mediaItem,scope:scope));XCTAssertNil(encrypted.range(of:Data(repeating:72,count:64)))
        let opened=try XCTUnwrap(client.musicOffline.document(track.mediaItem,scope:scope,backgroundAudio:true));XCTAssertEqual(try Data(contentsOf:opened.url),Data(repeating:72,count:128));MusicPlaybackDocuments.remove(opened)
        let changed=MusicTrack(id:track.id,section:track.section,title:track.title,filename:track.filename,mimeType:track.mimeType,size:track.size,revision:"r2",createdAt:track.createdAt);XCTAssertFalse(client.musicHasDownload(changed))
        try client.forgetMusic(track);XCTAssertFalse(client.musicHasDownload(track));try client.musicOffline.saveFile(source.url,item:track.mediaItem,scope:scope);try client.musicOffline.pinFile(track.mediaItem,scope:scope);XCTAssertTrue(client.musicHasDownload(track))
        try client.clearSession();XCTAssertFalse(FileManager.default.fileExists(atPath:client.musicOffline.encryptedFile(track.mediaItem,scope:scope).path));TemporaryDocuments.remove(source)
    }
    func testMusicAlphabeticalSearchAndFileImportPreserveTheSource() throws {
        let ids=["b","a","c"],names=["Árbol 10","arbol 2","Zorro"]
        let tracks=zip(ids,names).map{MusicTrack(id:$0.0,section:.tracks,title:$0.1,filename:"Prueba.wav",mimeType:"audio/wav",size:128,revision:"r1",createdAt:"2026-10-19")}
        XCTAssertEqual(MusicTrack.sorted(tracks).map(\.title),["arbol 2","Árbol 10","Zorro"]);XCTAssertTrue(tracks[0].matches("arbol"))
        let source=try TemporaryDocuments.save(Data(repeating:3,count:128),filename:"Audio recibido.wav");defer{TemporaryDocuments.remove(source)}
        let file=try MusicImportFile.copy(source.url);defer{file.remove()};XCTAssertNotEqual(file.url,source.url);XCTAssertEqual(file.name,"Audio recibido.wav");XCTAssertEqual(file.size,128);XCTAssertTrue(FileManager.default.fileExists(atPath:source.url.path))
        XCTAssertThrowsError(try MusicImportFile.copy(URL(string:"https://untrusted.example.invalid/Audio.wav")!))
    }
}
