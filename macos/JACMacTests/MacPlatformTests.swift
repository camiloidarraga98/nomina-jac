import XCTest
import AppKit
@testable import JACMac

final class MacPlatformTests:XCTestCase {
    func testMacNavigationPreservesFinancialRestrictionEvenForOwnerFlag() {
        var user=PayrollUser(id:"fixture",email:"fixture@example.invalid",username:"fixture",displayName:"Ficticio",isOwner:true,permissions:[],itinerariesOnly:true)
        XCTAssertFalse(MacSection.payroll.allowed(user));XCTAssertFalse(MacSection.crm.allowed(user))
        for section in [MacSection.agenda,.itineraries,.alerts,.account,.management]{XCTAssertTrue(section.allowed(user))}
        user.itinerariesOnly=false;XCTAssertTrue(MacSection.payroll.allowed(user));XCTAssertTrue(MacSection.crm.allowed(user))
    }
    func testFinderUploadsRejectWebLinksDirectoriesAndInvalidContentBeforeSending() throws {
        XCTAssertThrowsError(try NoticeUpload.readLocalFiles([URL(string:"https://example.invalid/file.pdf")!]))
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true);defer{try? FileManager.default.removeItem(at:root)}
        XCTAssertThrowsError(try NoticeUpload.readLocalFiles([root]))
        let file=root.appendingPathComponent("Recibo.pdf")
        try Data("<html>no es PDF</html>".utf8).write(to:file)
        XCTAssertThrowsError(try NoticeUpload.readLocalFiles([file]))
        try Data("%PDF-1.4 fixture only".utf8).write(to:file)
        let incoming=try NoticeUpload.readLocalFiles([file]);XCTAssertEqual(incoming.count,1);XCTAssertEqual(incoming[0].filename,"Recibo.pdf")
        XCTAssertThrowsError(try NoticeUpload.readLocalFiles(Array(repeating:file,count:6)))
        try (Data("%PDF-1.4".utf8)+Data(repeating:0,count:10*1024*1024)).write(to:file)
        XCTAssertThrowsError(try NoticeUpload.readLocalFiles([file]))
    }
    @MainActor func testMacReceiptFileUsesNativeImageAndRejectsRemoteURL() throws {
        XCTAssertThrowsError(try MacReceiptImages.file(URL(string:"https://example.invalid/receipt.jpg")!))
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true);defer{try? FileManager.default.removeItem(at:root)}
        let file=root.appendingPathComponent("Factura.jpg"),bytes=try ReceiptOCR.photograph(ReceiptOCR.fixture())
        try bytes.write(to:file)
        let image=try MacReceiptImages.file(file)
        XCTAssertGreaterThan(image.size.width,100);XCTAssertNoThrow(try MacReceiptImages.photograph(image))
        let pdf=root.appendingPathComponent("Factura.pdf");try JACPlatform.fixturePDF().write(to:pdf)
        XCTAssertNoThrow(try MacReceiptImages.file(pdf))
    }
}
