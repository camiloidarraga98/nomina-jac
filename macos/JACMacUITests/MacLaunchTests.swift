import XCTest

final class MacLaunchTests:XCTestCase {
    override func setUpWithError() throws {continueAfterFailure=false}
    @MainActor private func fixture(_ extra:[String]=[])->XCUIApplication {
        let app=XCUIApplication();app.launchArguments=["--uitest-payroll"]+extra;app.launch()
        XCTAssertTrue(app.buttons["period.fixture-period"].waitForExistence(timeout:20))
        return app
    }
    @MainActor private func go(_ app:XCUIApplication,_ name:String) {
        app.typeKey(name,modifierFlags:.command)
    }
    @MainActor private func click(_ app:XCUIApplication,_ id:String) {
        let element=app.descendants(matching:.any).matching(identifier:id).firstMatch
        XCTAssertTrue(element.waitForExistence(timeout:15),id);element.click()
    }
    @MainActor private func shot(_ app:XCUIApplication,_ name:String) {let a=XCTAttachment(screenshot:app.windows.firstMatch.screenshot());a.name=name;a.lifetime = .keepAlways;add(a)}
    @MainActor func testDesktopPayrollAgendaCRMAndAttachments() throws {
        let app=fixture();shot(app,"mac-quincenas")
        click(app,"period.fixture-period")
        XCTAssertTrue(app.buttons["period.close"].waitForExistence(timeout:10))
        go(app,"2")
        XCTAssertTrue(app.buttons["Hoy"].waitForExistence(timeout:15));shot(app,"mac-agenda")
        go(app,"3")
        XCTAssertTrue(app.buttons["boarding.open"].waitForExistence(timeout:15));shot(app,"mac-itinerarios")
        click(app,"boarding.open")
        XCTAssertTrue(app.buttons.matching(NSPredicate(format:"identifier BEGINSWITH %@","notices.item.")).firstMatch.waitForExistence(timeout:10))
        app.buttons.matching(NSPredicate(format:"identifier BEGINSWITH %@","notices.item.")).firstMatch.click()
        XCTAssertTrue(app.buttons["notices.pdf.close"].waitForExistence(timeout:10))
        XCTAssertTrue(app.buttons["Guardar una copia…"].exists);shot(app,"mac-pase-pdf")
        click(app,"notices.pdf.close")
        go(app,"6")
        XCTAssertTrue(app.buttons["crm.quickPayment"].waitForExistence(timeout:15));shot(app,"mac-crm")
        click(app,"crm.quickPayment")
        XCTAssertTrue(app.buttons["crm.editor.save"].waitForExistence(timeout:10))
        XCTAssertTrue(app.buttons["Elegir PDF o imágenes de Archivos"].exists)
        shot(app,"mac-abono");app.buttons["Cerrar"].firstMatch.click()
        go(app,"5");XCTAssertTrue(app.buttons["management.expenses"].waitForExistence(timeout:10));shot(app,"mac-gestion")
    }
    @MainActor func testDesktopEditorSurvivesDeactivationAndCoversSheets() {
        let app=fixture();click(app,"period.create")
        XCTAssertTrue(app.buttons["editor.save"].waitForExistence(timeout:10))
        let other=XCUIApplication(bundleIdentifier:"com.apple.finder");other.activate()
        XCTAssertTrue(app.images["privacy.cover"].waitForExistence(timeout:10),"Debe cubrir también la hoja de edición")
        shot(app,"mac-privacidad")
        app.activate()
        XCTAssertTrue(app.buttons["editor.save"].waitForExistence(timeout:10));XCTAssertTrue(app.buttons["editor.save"].isHittable)
        XCTAssertFalse(app.images["privacy.cover"].exists)
        app.buttons["Cancelar"].firstMatch.click()
        XCTAssertTrue(app.buttons["period.fixture-period"].waitForExistence(timeout:10))
    }
    @MainActor func testDownloadedWorkspaceAndPrivatePassSurviveOfflineRelaunch() {
        let app=fixture(["--uitest-offline-content","--uitest-reset-content"])
        go(app,"4")
        let status=app.staticTexts["offline.sync.status"]
        XCTAssertTrue(status.waitForExistence(timeout:15))
        let complete=NSPredicate(format:"label == %@ OR value == %@","La última información y sus adjuntos están guardados en este Mac.","La última información y sus adjuntos están guardados en este Mac.")
        expectation(for:complete,evaluatedWith:status);waitForExpectations(timeout:30)
        app.terminate();app.launchArguments=["--uitest-payroll","--uitest-offline-content","--uitest-offline"];app.launch()
        XCTAssertTrue(app.buttons["period.fixture-period"].waitForExistence(timeout:5));XCTAssertFalse(app.textFields["login.username"].exists)
        XCTAssertFalse(app.buttons["period.create"].isEnabled)
        go(app,"3");click(app,"boarding.open");click(app,"notices.item.boarding-fixture-0")
        XCTAssertTrue(app.buttons["notices.pdf.close"].waitForExistence(timeout:10));XCTAssertTrue(app.buttons["Guardar una copia…"].exists)
        shot(app,"mac-pase-sin-internet");click(app,"notices.pdf.close")
        go(app,"2");XCTAssertTrue(app.descendants(matching:.any)["agenda.mode"].waitForExistence(timeout:10));XCTAssertFalse(app.buttons["agenda.create"].exists)
        shot(app,"mac-agenda-sin-internet")
    }
    @MainActor func testReaderCannotCreatePayrollOrEnterCRM() {
        let app=fixture(["--uitest-reader"])
        XCTAssertFalse(app.buttons["period.create"].exists)
        let menu=app.menuBars.menuBarItems["JAC"];menu.click()
        XCTAssertFalse(menu.menuItems["CRM"].exists)
        app.typeKey(.escape,modifierFlags:[])
        go(app,"5");XCTAssertTrue(app.buttons["management.expenses"].waitForExistence(timeout:10))
        XCTAssertFalse(app.buttons["management.crm"].exists);XCTAssertFalse(app.buttons["Usuarios y permisos"].exists)
        shot(app,"mac-permisos-lector")
    }
}
