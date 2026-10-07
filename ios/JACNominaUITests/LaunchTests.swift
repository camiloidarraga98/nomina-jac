import XCTest

final class LaunchTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor func testLoginIsVisibleAndUsableAfterLaunchAndResume() {
        // Runs on a fresh CI simulator, without a saved session or network login.
        let app = XCUIApplication()
        app.launch()

        let username = app.textFields["login.username"]
        XCTAssertTrue(username.waitForExistence(timeout: 20), "El arranque debe mostrar el formulario de acceso.")
        XCTAssertTrue(username.isHittable, "La protección de privacidad debe retirarse al activar la app.")
        XCTAssertTrue(app.secureTextFields["login.password"].exists)
        XCTAssertTrue(app.buttons["login.submit"].exists)
        attachScreen(app, name: "inicio-de-sesion")
        XCTAssertFalse(app.staticTexts["No se pudo leer la sesión segura de este iPhone."].exists, "El arranque debe poder consultar el Llavero.")

        username.tap()
        username.typeText("prueba-local")
        XCTAssertEqual(username.value as? String, "prueba-local")

        XCUIDevice.shared.press(.home)
        app.activate()
        let visible = NSPredicate(format: "hittable == true")
        expectation(for: visible, evaluatedWith: username)
        waitForExpectations(timeout: 10)
        XCTAssertEqual(app.state, .runningForeground)
        attachScreen(app, name: "regreso-a-la-app")
        XCTAssertEqual(username.value as? String, "prueba-local", "El regreso debe conservar el formulario, sin relanzar la app.")
        for suffix in ["-uno", "-dos"] {
            username.tap(); username.typeText(suffix)
            let value = username.value as? String
            XCUIDevice.shared.press(.home); app.activate()
            XCTAssertTrue(username.waitForExistence(timeout: 10))
            XCTAssertTrue(username.isHittable)
            XCTAssertEqual(username.value as? String, value, "Cada regreso debe conservar el texto y el foco utilizable.")
        }
    }

    @MainActor func testActivationNavigationAndFocusedPasswordSurviveBackground() {
        let app = XCUIApplication(); app.launch()
        XCTAssertTrue(app.textFields["login.username"].waitForExistence(timeout: 20))
        tap(app, "Activar cuenta o restablecer contraseña")
        let password = app.secureTextFields["Nueva contraseña"]
        XCTAssertTrue(password.waitForExistence(timeout: 10))
        password.tap(); password.typeText("solo-prueba-local")
        let value = password.value as? String
        XCUIDevice.shared.press(.home); app.activate()
        XCTAssertTrue(app.navigationBars["Activar cuenta"].waitForExistence(timeout: 10))
        XCTAssertTrue(password.isHittable)
        XCTAssertEqual(password.value as? String, value, "La navegación y el formulario deben sobrevivir al regreso.")
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(app.textFields["login.username"].waitForExistence(timeout: 10))
    }

    @MainActor func testPrivacyCoverAndPayrollEditorSurviveAppSwitcher() {
        let app = fixture()
        let bottom = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.995))
        let middle = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        bottom.press(forDuration: 0.1, thenDragTo: middle, withVelocity: .slow, thenHoldForDuration: 1)
        let cover = app.images["privacy.cover"]
        XCTAssertTrue(cover.waitForExistence(timeout: 10), "La escena inactiva debe conservar la cubierta de privacidad.")
        let snapshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        snapshot.name = "privacidad-en-selector-de-apps"; snapshot.lifetime = .keepAlways; add(snapshot)
        app.activate()
        XCTAssertTrue(app.buttons["period.fixture-period"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.images["privacy.cover"].exists)
        tap(app, "period.fixture-period"); tap(app, "Actividad"); tap(app, "activity.shows"); tap(app, "activity.add")
        let title = app.textFields["editor.name"]
        XCTAssertTrue(title.waitForExistence(timeout: 10))
        title.tap(); title.typeText("Borrador local")
        let value = title.value as? String
        XCUIDevice.shared.press(.home); app.activate()
        XCTAssertTrue(title.waitForExistence(timeout: 10))
        XCTAssertTrue(title.isHittable)
        XCTAssertEqual(title.value as? String, value, "El borrador debe conservarse sin guardar ni enviar datos.")
        XCTAssertFalse(app.images["privacy.cover"].exists)
        bottom.press(forDuration: 0.1, thenDragTo: middle, withVelocity: .slow, thenHoldForDuration: 1)
        XCTAssertTrue(app.images["privacy.cover"].waitForExistence(timeout: 10), "La cubierta debe quedar también por encima de las hojas.")
        let editorSnapshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        editorSnapshot.name = "privacidad-de-borrador-en-selector-de-apps"
        editorSnapshot.lifetime = .keepAlways; add(editorSnapshot)
        app.activate()
        XCTAssertTrue(title.waitForExistence(timeout: 10))
        XCTAssertTrue(title.isHittable)
        XCTAssertEqual(title.value as? String, value)
    }

    @MainActor private func attachScreen(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor private func fixture(_ arguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication(); app.launchArguments = ["--uitest-payroll"] + arguments; app.launch()
        XCTAssertTrue(app.buttons["period.fixture-period"].waitForExistence(timeout: 20))
        return app
    }
    @MainActor private func tap(_ app: XCUIApplication, _ label: String) {
        let button = app.buttons[label].firstMatch
        for _ in 0..<8 { if button.exists && button.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(button.waitForExistence(timeout: 10), "Debe existir el botón \(label)")
        XCTAssertTrue(button.isHittable, "Debe poderse tocar \(label)"); button.tap()
    }
    @MainActor private func fill(_ app: XCUIApplication, _ id: String, _ value: String) {
        let field = app.textFields[id].firstMatch
        for _ in 0..<8 { if field.exists && field.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        // Right-aligned numbers end at the trailing inset. A tap farther left
        // puts the cursor before the number, where backspace cannot clear it.
        field.coordinate(withNormalizedOffset: CGVector(dx: 0.99, dy: 0.5)).tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5), "El campo debe recibir el foco del teclado.")
        let old = (field.value as? String) ?? ""
        let count = old == field.placeholderValue ? 0 : old.count
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: count) + value)
        if ["editor.km", "editor.hourDivisor", "editor.counts.0"].contains(id) {
            XCTAssertEqual(field.value as? String, value, "El importe debe conservar el valor escrito.")
        }
    }
    @MainActor func testCreatePeriodAndManageItsActivitiesWithNativeForms() {
        let app = fixture()
        tap(app, "period.create"); tap(app, "editor.save")
        XCTAssertTrue(app.staticTexts["Neto en preparación"].waitForExistence(timeout: 15))
        tap(app, "Actividad"); tap(app, "activity.shows"); tap(app, "activity.add")
        fill(app, "editor.name", "Show simulado iPhone"); tap(app, "editor.save")
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label ==[c] %@", "Show simulado iPhone")).firstMatch.waitForExistence(timeout: 15), app.debugDescription)
        attachScreen(app, name: "show-guardado")
        app.navigationBars.buttons.firstMatch.tap()
        tap(app, "activity.routes"); tap(app, "Editar"); fill(app, "editor.km", "120"); tap(app, "editor.save")
        let distance = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@ OR value == %@", "120 km", "120 km")).firstMatch
        XCTAssertTrue(distance.waitForExistence(timeout: 15), app.debugDescription)
        attachScreen(app, name: "recorrido-compartido")
        app.navigationBars.buttons.firstMatch.tap()
        tap(app, "activity.movements"); tap(app, "activity.add")
        fill(app, "editor.concept", "Novedad simulada iPhone"); tap(app, "editor.save")
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label ==[c] %@", "Novedad simulada iPhone")).firstMatch.waitForExistence(timeout: 15), app.debugDescription)
        app.navigationBars.buttons.firstMatch.tap()
        tap(app, "activity.hours"); tap(app, "Registrar horas y novedades")
        fill(app, "editor.counts.0", "2"); tap(app, "editor.save")
        XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "Recargo nocturno")).firstMatch.waitForExistence(timeout: 15), app.debugDescription)
        attachScreen(app, name: "horas-guardadas")
    }
    @MainActor func testCloseArchiveAndReopenWithoutRealEmailsOrData() {
        let app = fixture()
        tap(app, "period.fixture-period"); tap(app, "period.close")
        tap(app, "Cerrar quincena")
        XCTAssertTrue(app.staticTexts["Neto del cierre"].waitForExistence(timeout: 15))
        app.tabBars.buttons["Archivo"].tap(); tap(app, "period.fixture-period")
        tap(app, "Documentos")
        XCTAssertTrue(app.buttons["Resumen PDF"].waitForExistence(timeout: 10))
        attachScreen(app, name: "archivo-documentos")
        tap(app, "period.reopen"); tap(app, "Reabrir para corregir")
        XCTAssertTrue(app.staticTexts["Neto en preparación"].waitForExistence(timeout: 15))
        tap(app, "Corregir parámetros de este corte")
        XCTAssertTrue(app.textFields["editor.hourDivisor"].waitForExistence(timeout: 10))
        fill(app, "editor.hourDivisor", "200"); tap(app, "editor.save")
        attachScreen(app, name: "correccion-historica")
    }
    @MainActor func testPayrollReaderHasNoPayrollOrOwnerActionsButCanEditAgenda() {
        let app = fixture(["--uitest-reader"])
        XCTAssertFalse(app.buttons["period.create"].exists)
        tap(app, "period.fixture-period")
        XCTAssertFalse(app.buttons["period.close"].exists); XCTAssertFalse(app.buttons["period.delete"].exists)
        tap(app, "Actividad"); tap(app, "activity.shows"); XCTAssertFalse(app.buttons["activity.add"].exists)
        app.tabBars.buttons["Equipo"].tap(); XCTAssertFalse(app.buttons["employee.create"].exists)
        app.tabBars.buttons["Gestión"].tap(); XCTAssertFalse(app.buttons["Usuarios y permisos"].exists)
        tap(app, "Conceptos y reglas"); XCTAssertFalse(app.buttons["concept.create"].exists)
        app.tabBars.buttons["Agenda"].tap(); XCTAssertTrue(app.staticTexts["Agenda simulada"].waitForExistence(timeout: 15)); XCTAssertFalse(app.buttons["agenda.configure"].exists); XCTAssertTrue(app.buttons["agenda.create"].exists)
        attachScreen(app, name: "permisos-solo-consulta")
    }
    @MainActor func testAgendaMonthUpcomingDetailsAndAccountRemainAccessible() {
        let app = fixture()
        app.tabBars.buttons["Agenda"].tap()
        XCTAssertTrue(app.staticTexts["Agenda simulada"].waitForExistence(timeout: 15))
        tap(app, "agenda.event.fixture-concert")
        XCTAssertTrue(app.staticTexts["Teatro simulado"].waitForExistence(timeout: 10))
        attachScreen(app, name: "agenda-detalle-concierto"); tap(app, "Listo")
        let upcoming = app.segmentedControls["agenda.mode"].buttons["Próximos"]
        for _ in 0..<4 { if upcoming.isHittable { break }; app.swipeDown() }
        upcoming.tap()
        tap(app, "agenda.upcoming.fixture-concert"); tap(app, "Listo")
        attachScreen(app, name: "agenda-proximos")
        app.tabBars.buttons["Gestión"].tap(); tap(app, "Mi cuenta")
        XCTAssertTrue(app.buttons["Cambiar contraseña"].waitForExistence(timeout: 10))
    }
    @MainActor func testCreateAndEditAgendaEventKeepNativeFormsAndSharedFeed() {
        let app = fixture(); app.tabBars.buttons["Agenda"].tap()
        XCTAssertTrue(app.staticTexts["Agenda simulada"].waitForExistence(timeout: 15))
        tap(app, "agenda.create"); fill(app, "agenda.editor.title", "Evento móvil de prueba"); fill(app, "agenda.editor.location", "Lugar de prueba")
        attachScreen(app, name: "agenda-crear-evento"); tap(app, "agenda.editor.save")
        XCTAssertTrue(app.staticTexts["Evento creado en Google Calendar."].waitForExistence(timeout: 15))
        tap(app, "agenda.event.fixture-concert"); tap(app, "agenda.edit")
        XCTAssertTrue(app.staticTexts["Editarás solo esta ocurrencia. Los demás eventos de la serie se conservan."].waitForExistence(timeout: 10))
        fill(app, "agenda.editor.title", "Concierto actualizado de prueba"); attachScreen(app, name: "agenda-editar-evento"); tap(app, "agenda.editor.save")
        // Agenda keeps the list position after dismissing the editor. Its notice
        // is the first row, and SwiftUI does not expose offscreen List rows.
        XCTAssertTrue(app.navigationBars["Agenda"].waitForExistence(timeout: 15), app.debugDescription)
        let notice = app.staticTexts["Evento actualizado en Google Calendar."]
        for _ in 0..<8 { if notice.exists { break }; app.swipeDown() }
        XCTAssertTrue(notice.waitForExistence(timeout: 10), app.debugDescription)
        tap(app, "agenda.event.fixture-concert")
        XCTAssertTrue(app.staticTexts["Concierto actualizado de prueba"].waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(app.staticTexts["Teatro simulado"].exists, "Editar el título debe conservar el lugar.")
        tap(app, "Listo")
        attachScreen(app, name: "agenda-identidad-jac")
    }
    @MainActor func testCancelledMenuReadsDoNotLeakErrorsIntoArchiveAndCanReload() {
        let app = fixture(["--uitest-cancelled-reads"])
        tap(app, "period.fixture-period")
        XCTAssertTrue(app.navigationBars["Quincena"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.descendants(matching: .any)["error.inline"].exists)
        app.tabBars.buttons["Archivo"].tap()
        XCTAssertTrue(app.navigationBars["Archivo"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.descendants(matching: .any)["error.inline"].exists, "Una consulta cancelada no debe dejar un error en Archivo")
        app.tabBars.buttons["Quincenas"].tap()
        app.navigationBars.buttons.firstMatch.tap(); tap(app, "period.fixture-period")
        XCTAssertTrue(app.staticTexts["Neto en preparación"].waitForExistence(timeout: 10))
        app.tabBars.buttons["Agenda"].tap()
        XCTAssertTrue(app.navigationBars["Agenda"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.descendants(matching: .any)["error.inline"].exists)
        tap(app, "Actualizar agenda")
        XCTAssertTrue(app.segmentedControls["agenda.mode"].waitForExistence(timeout: 10))
        app.tabBars.buttons["Gestión"].tap(); tap(app, "notices.itineraries")
        XCTAssertTrue(app.navigationBars["Itinerarios"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.descendants(matching: .any)["error.inline"].exists)
        app.navigationBars.buttons.firstMatch.tap(); tap(app, "notices.itineraries")
        XCTAssertTrue(app.buttons["notices.item.33333333-3333-4333-8333-333333333333"].waitForExistence(timeout: 10))
        tap(app, "notices.item.33333333-3333-4333-8333-333333333333")
        tap(app, "notices.detail.close")
        app.navigationBars.buttons.firstMatch.tap(); tap(app, "Correos y Gmail")
        XCTAssertTrue(app.buttons["Actualizar estados"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.descendants(matching: .any)["error.inline"].exists)
        tap(app, "Actualizar estados")
        XCTAssertTrue(app.staticTexts["Remitente"].waitForExistence(timeout: 10))
        app.navigationBars.buttons.firstMatch.tap(); tap(app, "Usuarios y permisos")
        XCTAssertTrue(app.navigationBars["Usuarios y permisos"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.descendants(matching: .any)["error.inline"].exists)
        app.tabBars.buttons["Archivo"].tap()
        XCTAssertFalse(app.descendants(matching: .any)["error.inline"].exists)
        attachScreen(app, name: "archivo-sin-error-de-consulta-cancelada")
    }

    @MainActor func testItineraryPDFAndSelectiveAlertAreAccessibleInManagement() {
        let app = fixture(); app.tabBars.buttons["Gestión"].tap(); tap(app, "notices.itineraries")
        tap(app, "notices.item.33333333-3333-4333-8333-333333333333")
        tap(app, "notices.pdf"); XCTAssertTrue(app.navigationBars["Itinerario PDF"].waitForExistence(timeout: 15))
        attachScreen(app, name: "itinerario-pdf"); tap(app, "notices.pdf.close"); tap(app, "notices.detail.close")
        app.navigationBars.buttons.firstMatch.tap(); tap(app, "notices.alerts"); tap(app, "notices.create")
        fill(app, "notices.editor.title", "Alerta simulada iPhone")
        let message = app.descendants(matching: .any).matching(identifier: "notices.editor.message").firstMatch
        XCTAssertTrue(message.waitForExistence(timeout: 10)); message.tap(); message.typeText("Mensaje para el equipo simulado")
        app.swipeUp()
        let recipient = app.switches["notices.recipient.11111111-1111-4111-8111-111111111111"]
        XCTAssertTrue(recipient.waitForExistence(timeout: 10)); recipient.tap()
        attachScreen(app, name: "alerta-destinatarios"); tap(app, "notices.editor.save")
        XCTAssertTrue(app.staticTexts["Alerta guardada para los destinatarios elegidos."].waitForExistence(timeout: 15))
        attachScreen(app, name: "alerta-guardada")
    }
    @MainActor func testReaderCanOpenItineraryAndHasNoCreateAlertButton() {
        let app = fixture(["--uitest-reader"]); app.tabBars.buttons["Gestión"].tap(); tap(app, "notices.itineraries")
        tap(app, "notices.item.33333333-3333-4333-8333-333333333333"); XCTAssertTrue(app.buttons["notices.pdf"].waitForExistence(timeout: 10)); tap(app, "notices.detail.close")
        app.navigationBars.buttons.firstMatch.tap(); tap(app, "notices.alerts")
        XCTAssertTrue(app.buttons["notices.enable"].waitForExistence(timeout: 10)); XCTAssertFalse(app.buttons["notices.create"].exists)
    }

    @MainActor func testManualItineraryWithAttachmentAndDeleteConfirmation() {
        let app = fixture(); app.tabBars.buttons["Gestión"].tap(); tap(app,"notices.alerts"); tap(app,"notices.create")
        app.segmentedControls["notices.editor.kind"].buttons["Itinerario"].tap()
        fill(app,"notices.editor.title","Itinerario manual ficticio")
        tap(app,"notices.editor.fixture"); app.swipeUp(); tap(app,"notices.editor.save")
        XCTAssertTrue(app.staticTexts["Itinerario publicado para todo el equipo."].waitForExistence(timeout:15))
        let item = app.buttons.matching(NSPredicate(format:"label CONTAINS %@", "Itinerario manual ficticio")).firstMatch
        XCTAssertTrue(item.waitForExistence(timeout:15)); item.tap(); tap(app,"notices.pdf")
        XCTAssertTrue(app.navigationBars["Itinerario PDF"].waitForExistence(timeout:15)); tap(app,"notices.pdf.close")
        tap(app,"notices.delete"); tap(app,"notices.delete.cancel"); XCTAssertTrue(app.buttons["notices.pdf"].exists)
        tap(app,"notices.delete"); tap(app,"notices.delete.confirm")
        XCTAssertTrue(app.navigationBars["Itinerarios"].waitForExistence(timeout:15))
        XCTAssertFalse(app.staticTexts["Itinerario manual ficticio"].exists)
        attachScreen(app,name:"itinerario-manual-eliminado")
    }

}
