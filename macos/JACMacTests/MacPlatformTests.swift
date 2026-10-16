import XCTest
import AppKit
@testable import JACMac

final class MacPlatformTests:XCTestCase {
    func testModernSectionsOverrideCompatibilityFlagsInSidebarAndSettings() {
        var hybrid=PayrollUser(id:"hybrid",email:"hybrid@example.invalid",username:"hybrid",displayName:"Híbrido",isOwner:false,permissions:["payroll"],itinerariesOnly:true,mediaOnly:true,sections:["media","itineraries","alerts"])
        XCTAssertEqual(MacSection.sidebar(for:hybrid),[.itineraries,.alerts,.media,.account,.management]);XCTAssertFalse(MacSettingsRoute.archive.allowed(hybrid));XCTAssertTrue(MacSettingsRoute.expenses.allowed(hybrid));XCTAssertFalse(hybrid.canUploadMedia)
        hybrid.sections=["calendar"];XCTAssertEqual(MacSection.sidebar(for:hybrid),[.agenda,.account]);XCTAssertTrue(MacSettingsRoute.allCases.allSatisfy{!$0.allowed(hybrid)})
        hybrid.sections=["alerts"];XCTAssertEqual(MacSection.sidebar(for:hybrid),[.alerts,.account,.management]);XCTAssertFalse(MacSettingsRoute.expenses.allowed(hybrid))
        hybrid.sections=["media","mediaUpload"];XCTAssertTrue(hybrid.canUploadMedia);XCTAssertEqual(MacSection.sidebar(for:hybrid),[.media,.account])
    }
    func testDateCalendarLimitsAndPreservesTimeInColombia() throws {
        let c=CalendarClock.calendar
        XCTAssertNil(MacDateSelection.parse("31/02/2026",calendar:c))
        XCTAssertEqual(MacDateSelection.parse("16/10/2026",calendar:c).map(PayrollDates.iso),"2026-10-16")
        XCTAssertEqual(MacDateSelection.parse("1/2/2026",calendar:c).map(PayrollDates.iso),"2026-02-01")
        let lower=try XCTUnwrap(CalendarClock.instant("2026-10-16T08:30:00-05:00")),upper=try XCTUnwrap(CalendarClock.instant("2026-10-20T18:00:00-05:00"))
        let original=try XCTUnwrap(CalendarClock.instant("2026-10-17T14:45:00-05:00")),range=lower...upper
        XCTAssertFalse(MacDateSelection.permits(PayrollDates.parse("2026-10-15"),range:range,calendar:c))
        XCTAssertTrue(MacDateSelection.permits(PayrollDates.parse("2026-10-16"),range:range,calendar:c))
        XCTAssertFalse(MacDateSelection.permits(PayrollDates.parse("2026-10-21"),range:range,calendar:c))
        let selected=MacDateSelection.select(PayrollDates.parse("2026-10-19"),preserving:original,range:range,calendar:c)
        XCTAssertEqual(PayrollDates.iso(selected),"2026-10-19");XCTAssertEqual(c.component(.hour,from:selected),14);XCTAssertEqual(c.component(.minute,from:selected),45)
        XCTAssertEqual(MacDateSelection.select(PayrollDates.parse("2026-10-14"),preserving:original,range:range,calendar:c),lower)
        XCTAssertEqual(MacDateSelection.select(PayrollDates.parse("2026-10-22"),preserving:original,range:range,calendar:c),upper)
        let days=MacDateSelection.days(in:PayrollDates.parse("2026-10-01"),calendar:c)
        XCTAssertEqual(days.count,42);XCTAssertEqual(c.component(.weekday,from:days[0]),2)
        XCTAssertEqual(days.filter{c.component(.month,from:$0)==10}.count,31)
    }
    func testMacNavigationPreservesFinancialRestrictionEvenForOwnerFlag() {
        var user=PayrollUser(id:"fixture",email:"fixture@example.invalid",username:"fixture",displayName:"Ficticio",isOwner:true,permissions:[],itinerariesOnly:true)
        XCTAssertFalse(MacSection.payroll.allowed(user));XCTAssertFalse(MacSection.crm.allowed(user))
        for section in [MacSection.agenda,.itineraries,.alerts,.account,.management]{XCTAssertTrue(section.allowed(user))}
        user.itinerariesOnly=false;XCTAssertTrue(MacSection.payroll.allowed(user));XCTAssertTrue(MacSection.crm.allowed(user))
    }
    func testSidebarMatchesWebAndSettingsRespectEveryAccountRole() {
        let owner=PayrollUser(id:"owner",email:"owner@example.invalid",username:"owner",displayName:"Owner",isOwner:true,permissions:[])
        let reader=PayrollUser(id:"reader",email:"reader@example.invalid",username:"reader",displayName:"Reader",isOwner:false,permissions:[])
        var restricted=owner;restricted.itinerariesOnly=true
        XCTAssertEqual(MacSection.sidebar(for:owner),[.crm,.payroll,.agenda,.itineraries,.alerts,.media,.account,.management])
        XCTAssertEqual(MacSection.sidebar(for:reader),[.payroll,.agenda,.itineraries,.alerts,.account,.management])
        XCTAssertEqual(MacSection.sidebar(for:restricted),[.agenda,.itineraries,.alerts,.account,.management])
        XCTAssertFalse(MacSettingsRoute.users.allowed(reader));XCTAssertFalse(MacSettingsRoute.connections.allowed(reader))
        XCTAssertEqual(MacSettingsRoute.allCases.filter{$0.allowed(restricted)},[.expenses,.alerts,.notifications])
    }
    func testPhotographerSidebarContainsOnlyGalleryAndAccountEvenWithOwnerFlag() {
        let photographer = PayrollUser(id: "photo", email: "anderson@example.invalid", username: "anderson", displayName: "Anderson ficticio", isOwner: true, permissions: ["payroll"], itinerariesOnly: true, mediaOnly: true)
        XCTAssertEqual(MacSection.sidebar(for: photographer), [.media, .account])
        XCTAssertTrue(MacSettingsRoute.allCases.allSatisfy { !$0.allowed(photographer) })
        XCTAssertFalse(MacSection.crm.allowed(photographer)); XCTAssertFalse(MacSection.agenda.allowed(photographer)); XCTAssertFalse(MacSection.alerts.allowed(photographer))
    }
    func testCRMTableFiltersDatesStatusAndSearchButUsesServerBalancesVerbatim() {
        let show:JSONValue = .object(["id":.string("show"),"title":.string("PEREIRA"),"showDate":.string("2026-10-17"),"entrepreneur":.string("José"),"status":.string("active"),"sale":.number(140000000),"paid":.number(50000000),"balance":.number(777)])
        var old=show;old["id"] = .string("old");old["showDate"] = .string("2026-10-14")
        var ignored=show;ignored["id"] = .string("ignored");ignored["status"] = .string("ignored")
        var deleted=show;deleted["id"] = .string("deleted");deleted["sourceState"] = .string("deleted")
        var unpriced=show;unpriced["id"] = .string("unpriced");unpriced["sale"] = .null;unpriced["balance"] = .null
        let feed=[show,old,ignored,deleted,unpriced]
        let rows=MacCRMRow.visible(feed,today:"2026-10-15",query:"jose",filter:.all)
        XCTAssertEqual(rows.map(\.id),["show","unpriced"]);XCTAssertEqual(rows[0].balance,777);XCTAssertEqual(rows[0].paid,50000000)
        XCTAssertEqual(MacCRMRow.visible(feed,today:"2026-10-15",query:"",filter:.pending).map(\.id),["show"])
        XCTAssertEqual(MacCRMRow.visible(feed,today:"2026-10-15",query:"",filter:.unpriced).map(\.id),["unpriced"])
        XCTAssertTrue(MacCRMRow.visible(feed,today:"2026-10-15",query:"sin resultados",filter:.all).isEmpty)
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
