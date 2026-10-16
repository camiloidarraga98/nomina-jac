import XCTest

final class MacLaunchTests:XCTestCase {
    @MainActor func testRootUploadAndFolderMenuKeepSeparateDestinationsAndAccountInConfiguration() {
        let app=XCUIApplication();app.launchArguments=["--uitest-payroll","--uitest-media-only","--uitest-media-two-folders","--uitest-wide-window","-ApplePersistenceIgnoreState","YES"];app.terminate();app.launch();app.activate()
        XCTAssertTrue(app.buttons["media.item.media-other"].waitForExistence(timeout:20));XCTAssertFalse(app.buttons["media.offline"].exists);XCTAssertFalse(app.descendants(matching:.any)["mac.nav.account"].exists)
        click(app,"media.options.media-other");click(app,"media.offline");XCTAssertTrue(app.staticTexts["2026-10-17 · BOGOTÁ"].waitForExistence(timeout:10));click(app,"media.transfer.begin")
        XCTAssertTrue(app.staticTexts["1 de 1 archivos disponibles sin conexión."].waitForExistence(timeout:20))
        click(app,"media.add");click(app,"media.destination.media-day");click(app,"media.fixture");click(app,"media.upload")
        XCTAssertTrue(app.buttons.matching(NSPredicate(format:"identifier BEGINSWITH %@ AND label CONTAINS %@","media.item.","Foto de prueba.png")).firstMatch.waitForExistence(timeout:20))
        click(app,"media.folder.media-root");click(app,"media.item.media-other");XCTAssertTrue(app.buttons["media.item.media-other-photo"].waitForExistence(timeout:15));XCTAssertFalse(app.buttons.matching(NSPredicate(format:"identifier BEGINSWITH %@ AND label CONTAINS %@","media.item.","Foto de prueba.png")).firstMatch.exists)
        shot(app,"mac-galeria-destinos-contextuales");click(app,"mac.nav.management");click(app,"management.account");XCTAssertTrue(app.buttons["Cerrar sesión"].waitForExistence(timeout:10))
    }
    @MainActor func testModernHybridSidebarOpensMediaAndItinerariesWithoutFinancialOrBoardingAccess() {
        let app=XCUIApplication();app.launchArguments=["--uitest-payroll","--uitest-sections=media,itineraries,alerts","-ApplePersistenceIgnoreState","YES"];app.launch();app.activate()
        XCTAssertTrue(app.descendants(matching:.any)["mac.nav.itineraries"].waitForExistence(timeout:20));XCTAssertTrue(app.descendants(matching:.any)["mac.nav.media"].exists)
        for section in ["crm","payroll","agenda"] {XCTAssertFalse(app.descendants(matching:.any)["mac.nav."+section].exists)}
        XCTAssertFalse(app.buttons["boarding.open"].exists);click(app,"mac.nav.media");XCTAssertTrue(app.buttons["media.item.media-day"].waitForExistence(timeout:15));XCTAssertFalse(app.buttons["media.createFolder"].exists);XCTAssertFalse(app.buttons["media.files"].exists)
        click(app,"media.item.media-day");click(app,"media.item.media-photo");click(app,"media.preview.close");click(app,"mac.nav.alerts");XCTAssertTrue(app.staticTexts["Lo importante, cerca."].waitForExistence(timeout:10));shot(app,"mac-secciones-hibridas")
    }
    @MainActor func testModernCalendarOnlyAndAlertsOnlySidebarRemainIsolated() {
        let app=XCUIApplication();app.launchArguments=["--uitest-payroll","--uitest-sections=calendar","-ApplePersistenceIgnoreState","YES"];app.launch();app.activate()
        XCTAssertTrue(app.descendants(matching:.any)["mac.nav.agenda"].waitForExistence(timeout:20));XCTAssertTrue(app.buttons["Hoy"].waitForExistence(timeout:15))
        for section in ["crm","payroll","itineraries","alerts","media","account"] {XCTAssertFalse(app.descendants(matching:.any)["mac.nav."+section].exists)}
        app.terminate();app.launchArguments=["--uitest-payroll","--uitest-sections=alerts","-ApplePersistenceIgnoreState","YES"];app.launch();app.activate()
        XCTAssertTrue(app.descendants(matching:.any)["mac.nav.alerts"].waitForExistence(timeout:20));XCTAssertTrue(app.staticTexts["Lo importante, cerca."].waitForExistence(timeout:15))
        for section in ["crm","payroll","agenda","itineraries","media"] {XCTAssertFalse(app.descendants(matching:.any)["mac.nav."+section].exists)}
        click(app,"mac.nav.management");XCTAssertFalse(app.buttons["management.expenses"].exists);XCTAssertFalse(app.buttons["management.archive"].exists);shot(app,"mac-solo-alertas")
    }
    @MainActor func testPhotographerOnlyGalleryCreatesFolderUploadsAndPreviewsPhotoAndMovie() {
        let app = XCUIApplication(); app.launchArguments = ["--uitest-payroll", "--uitest-media-only", "-ApplePersistenceIgnoreState", "YES"]; app.launch(); app.activate()
        XCTAssertTrue(app.buttons["media.item.media-day"].waitForExistence(timeout: 20))
        for section in ["crm", "payroll", "agenda", "itineraries", "account"] { XCTAssertFalse(app.descendants(matching: .any)["mac.nav." + section].exists) }
        XCTAssertTrue(app.descendants(matching: .any)["mac.nav.media"].exists);XCTAssertTrue(app.descendants(matching:.any)["mac.nav.management"].exists);XCTAssertFalse(app.descendants(matching:.any)["mac.nav.account"].exists)
        click(app, "media.item.media-day"); click(app, "media.item.media-photo"); click(app, "media.preview.close")
        click(app, "media.item.media-video"); if !app.descendants(matching: .any)["media.video"].waitForExistence(timeout: 15) { print(app.debugDescription) }; XCTAssertTrue(app.descendants(matching: .any)["media.video"].exists); shot(app, "mac-fotografia-video-nativo"); click(app, "media.preview.close")
        click(app,"media.folder.media-root");click(app,"media.add");click(app, "media.createFolder"); let name = app.textFields["media.folder.name"]; XCTAssertTrue(name.waitForExistence(timeout: 10)); name.click(); name.typeText("Ensayo ficticio")
        click(app, "media.folder.save"); click(app, "media.fixture"); click(app, "media.upload")
        let uploaded = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label CONTAINS %@", "media.item.", "Foto de prueba.png")).firstMatch
        XCTAssertTrue(uploaded.waitForExistence(timeout: 15)); XCTAssertTrue(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label CONTAINS %@", "media.item.", "Video de prueba.mov")).firstMatch.waitForExistence(timeout: 15))
        XCTAssertGreaterThanOrEqual(uploaded.frame.minX,app.buttons["media.folder.media-root"].frame.minX-2,"La primera tarjeta debe conservar el margen de la galería.");shot(app, "mac-fotografia-fotografo")
    }
    @MainActor func testAdministratorGalleryAllowsUploadAndDownloadsWholeFolder() {
        let app=XCUIApplication();app.launchArguments=["--uitest-payroll","--uitest-wide-window","-ApplePersistenceIgnoreState","YES"];app.terminate();app.launch();app.activate()
        let ready=app.buttons["period.fixture-period"].waitForExistence(timeout:20);if !ready {print(app.debugDescription)};XCTAssertTrue(ready);click(app,"mac.nav.media")
        XCTAssertTrue(app.buttons["media.item.media-day"].waitForExistence(timeout: 15)); XCTAssertTrue(app.buttons["media.add"].exists);XCTAssertFalse(app.buttons["media.files"].exists)
        click(app,"media.options.media-day");click(app, "media.offline"); click(app, "media.transfer.begin")
        XCTAssertTrue(app.staticTexts["2 de 2 archivos disponibles sin conexión."].waitForExistence(timeout: 20))
        click(app,"media.item.media-day");click(app, "media.item.media-photo"); click(app, "media.preview.close")
        click(app,"media.add");click(app,"media.destination.current");click(app,"media.fixture");click(app,"media.upload")
        XCTAssertTrue(app.buttons.matching(NSPredicate(format:"identifier BEGINSWITH %@ AND label CONTAINS %@","media.item.","Foto de prueba.png")).firstMatch.waitForExistence(timeout:15))
        XCTAssertTrue(app.buttons.matching(NSPredicate(format:"identifier BEGINSWITH %@ AND label CONTAINS %@","media.item.","Video de prueba.mov")).firstMatch.waitForExistence(timeout:15));shot(app,"mac-fotografia-administrador-sube")
    }
    override func setUpWithError() throws {continueAfterFailure=false}
    @MainActor private func fixture(_ extra:[String]=[])->XCUIApplication {
        let app=XCUIApplication();app.launchArguments=["--uitest-payroll","--uitest-wide-window","-ApplePersistenceIgnoreState","YES"]+extra;app.terminate();app.launch();app.activate()
        let ready=app.buttons["period.fixture-period"].waitForExistence(timeout:20)
        if !ready {print(app.debugDescription)}
        XCTAssertTrue(ready)
        return app
    }
    @MainActor private func go(_ app:XCUIApplication,_ name:String) {
        expectation(for:NSPredicate(format:"exists == false"),evaluatedWith:app.sheets.firstMatch)
        waitForExpectations(timeout:10)
        app.typeKey(name,modifierFlags:.command)
    }
    @MainActor private func click(_ app:XCUIApplication,_ id:String) {
        app.activate()
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
    @MainActor func testCRMSidebarTableSearchAndNativeFormsAreDirectlyAccessible() {
        let app=fixture()
        XCTAssertTrue(app.descendants(matching:.any)["mac.nav.crm"].exists)
        click(app,"mac.nav.crm")
        click(app,"crm.layout.table")
        XCTAssertTrue(app.descendants(matching:.any)["crm.table"].waitForExistence(timeout:15))
        let row="crm.show.77777777-7777-4777-8777-777777777777"
        XCTAssertTrue(app.descendants(matching:.any)[row].waitForExistence(timeout:10))
        shot(app,"mac-ux-crm-tabla")
        let search=app.searchFields.firstMatch
        XCTAssertTrue(search.exists);search.click();search.typeText("sin resultados locales")
        XCTAssertTrue(app.staticTexts["Sin resultados"].waitForExistence(timeout:10))
        search.typeKey("a",modifierFlags:.command);search.typeKey(.delete,modifierFlags:[])
        click(app,row);XCTAssertTrue(app.buttons["crm.openShow"].isEnabled)
        click(app,"crm.openShow");XCTAssertTrue(app.buttons["crm.price"].waitForExistence(timeout:10))
        click(app,"crm.price");XCTAssertTrue(app.textFields["crm.entrepreneur"].waitForExistence(timeout:10));shot(app,"mac-ux-precio")
        app.buttons["Cerrar"].firstMatch.click()
        go(app,"5")
        XCTAssertTrue(app.buttons["management.employees"].waitForExistence(timeout:10));shot(app,"mac-ux-configuracion")
        click(app,"management.archive");XCTAssertTrue(app.staticTexts["Archivo de quincenas"].waitForExistence(timeout:10))
        go(app,"6");click(app,"crm.layout.table");click(app,"crm.create")
        XCTAssertTrue(app.textFields["crm.create.title"].waitForExistence(timeout:10));shot(app,"mac-ux-crear-show")
        app.buttons["Cerrar"].firstMatch.click()
        click(app,"crm.quickPayment")
        let picker=app.popUpButtons["crm.payment.show"]
        picker.click()
        let option=picker.menuItems.element(boundBy:1)
        XCTAssertTrue(option.waitForExistence(timeout:10));option.click()
        XCTAssertTrue((picker.value as? String ?? "").contains("PEREIRA"))
        let amount=app.textFields["crm.amount.Valor del abono (COP)"];amount.click();amount.typeText("50000000")
        click(app,"travel.fixture");click(app,"crm.editor.save")
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format:"label CONTAINS %@ OR value CONTAINS %@","90.000.000","90.000.000")).firstMatch.waitForExistence(timeout:10))
        shot(app,"mac-ux-abono-registrado")
    }
    @MainActor func testCompactDarkWindowKeepsCRMAndFormsUsable() {
        let app=fixture(["--uitest-dark","--uitest-compact-window"])
        let window=app.windows.firstMatch
        XCTAssertLessThanOrEqual(window.frame.width,1050);XCTAssertLessThanOrEqual(window.frame.height,780)
        click(app,"mac.nav.crm")
        XCTAssertTrue(app.buttons["crm.create"].waitForExistence(timeout:10));XCTAssertTrue(app.buttons["crm.create"].isHittable)
        XCTAssertTrue(app.buttons["crm.quickPayment"].isHittable)
        shot(app,"mac-ux-crm-compacto-oscuro")
        click(app,"crm.quickPayment");XCTAssertTrue(app.buttons["crm.editor.save"].waitForExistence(timeout:10));XCTAssertTrue(app.buttons["crm.editor.save"].isHittable)
        shot(app,"mac-ux-abono-oscuro");app.buttons["Cerrar"].firstMatch.click()
        go(app,"5");XCTAssertTrue(app.buttons["management.expenses"].waitForExistence(timeout:10))
        shot(app,"mac-ux-configuracion-oscura")
    }
    @MainActor func testJACShowCardsOpenDirectlyAndKeepTheTableAvailable() {
        let app=fixture(["--uitest-crm-design","--uitest-wide-window"])
        click(app,"mac.nav.crm")
        let card=app.buttons["crm.card.77777777-7777-4777-8777-777777777777"]
        XCTAssertTrue(card.waitForExistence(timeout:15));XCTAssertTrue(app.descendants(matching:.any)["crm.hero"].exists)
        shot(app,"mac-crm12-fichas")
        card.coordinate(withNormalizedOffset:CGVector(dx:0.95,dy:0.8)).click()
        XCTAssertTrue(app.buttons["crm.price"].waitForExistence(timeout:10))
        go(app,"5");go(app,"6");click(app,"crm.layout.table")
        XCTAssertTrue(app.descendants(matching:.any)["crm.table"].waitForExistence(timeout:10))
        shot(app,"mac-crm12-tabla")
    }
    @MainActor func testDateSelectorsAndAgendaRespondAcrossTheWholeDayCell() {
        let app=fixture();go(app,"6");click(app,"crm.quickPayment")
        let field=app.buttons["date.open.Fecha del abono"]
        for (offset,point) in [(1,CGVector(dx:0.08,dy:0.2)),(2,CGVector(dx:0.92,dy:0.2)),(3,CGVector(dx:0.08,dy:0.8)),(4,CGVector(dx:0.92,dy:0.8))] {
            XCTAssertTrue(field.waitForExistence(timeout:10));field.coordinate(withNormalizedOffset:CGVector(dx:0.97,dy:0.5)).click()
            let day=app.buttons["date.day."+civilDay(offset)]
            XCTAssertTrue(day.waitForExistence(timeout:10));day.coordinate(withNormalizedOffset:point).click()
            XCTAssertEqual(field.value as? String,dateLabel(offset),"También el borde de la celda debe seleccionar la fecha.")
            expectation(for:NSPredicate(format:"exists == false"),evaluatedWith:app.buttons["date.close"]);waitForExpectations(timeout:5)
        }
        field.coordinate(withNormalizedOffset:CGVector(dx:0.97,dy:0.5)).click();let input=app.textFields["date.input"];XCTAssertTrue(input.waitForExistence(timeout:10));input.click();input.typeText(formatDate(5,"dd/MM/yyyy"));click(app,"date.apply")
        XCTAssertEqual(field.value as? String,dateLabel(5))
        expectation(for:NSPredicate(format:"exists == false"),evaluatedWith:app.buttons["date.close"]);waitForExpectations(timeout:5)
        field.coordinate(withNormalizedOffset:CGVector(dx:0.97,dy:0.5)).click();XCTAssertTrue(app.buttons["date.close"].waitForExistence(timeout:10));shot(app,"mac-crm12-selector-fechas");click(app,"date.close")
        expectation(for:NSPredicate(format:"exists == false"),evaluatedWith:app.buttons["date.close"]);waitForExpectations(timeout:5)
        app.buttons["Cerrar"].firstMatch.click();go(app,"2")
        let day=app.buttons["agenda.day."+civilDay(1)]
        XCTAssertTrue(day.waitForExistence(timeout:10));day.coordinate(withNormalizedOffset:CGVector(dx:0.08,dy:0.5)).click()
        XCTAssertEqual(day.value as? String,"Seleccionado")
        shot(app,"mac-crm12-agenda-dia")
    }
    private func civilDay(_ offset:Int)->String {formatDate(offset,"yyyy-MM-dd")}
    private func dateLabel(_ offset:Int)->String {formatDate(offset,"d MMM yyyy").capitalized}
    private func formatDate(_ offset:Int,_ pattern:String)->String {
        var c=Calendar(identifier:.gregorian);c.timeZone=TimeZone(identifier:"America/Bogota")!
        let f=DateFormatter();f.locale=Locale(identifier:"es_CO");f.timeZone=c.timeZone;f.dateFormat=pattern
        return f.string(from:c.date(byAdding:.day,value:offset,to:Date())!)
    }
    @MainActor func testReaderCannotCreatePayrollOrEnterCRM() {
        let app=fixture(["--uitest-reader"])
        XCTAssertFalse(app.buttons["period.create"].exists)
        XCTAssertFalse(app.descendants(matching:.any)["mac.nav.crm"].exists)
        let menu=app.menuBars.menuBarItems["JAC"];menu.click()
        XCTAssertFalse(menu.menuItems["CRM"].exists)
        app.typeKey(.escape,modifierFlags:[])
        go(app,"5");XCTAssertTrue(app.buttons["management.expenses"].waitForExistence(timeout:10))
        XCTAssertFalse(app.buttons["management.crm"].exists);XCTAssertFalse(app.buttons["Usuarios y permisos"].exists)
        shot(app,"mac-permisos-lector")
    }
}
