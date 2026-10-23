import XCTest
import UIKit

final class LaunchTests: XCTestCase {
    @MainActor private func waitFor(_ element: XCUIElement, predicate: NSPredicate, timeout: TimeInterval) -> Bool {
        XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: element)], timeout: timeout) == .completed
    }
    @MainActor func testPhoneSidebarShowsAllModulesAndCanBeDismissed() {
        let app=fixture()
        XCTAssertEqual(app.tabBars.count, 0)
        XCTAssertEqual(Set(navigationSections(app)), Set(["crm","payroll","agenda","itineraries","alerts","boarding","media","music","management"].map {"phone.section."+$0}))
        XCTAssertTrue(showMenu(app));attachScreen(app, name:"iphone-menu-lateral")
        app.coordinate(withNormalizedOffset:CGVector(dx:0.96,dy:0.5)).tap()
        XCTAssertTrue(waitForMenu(app, visible:false))
        XCTAssertTrue(showMenu(app));app.scrollViews["phone.sidebar.scroll"].swipeLeft()
        XCTAssertTrue(waitForMenu(app, visible:false))
        openSection(app,"Música");XCTAssertTrue(app.buttons["music.section.tracks"].waitForExistence(timeout:15))
        attachScreen(app,name:"iphone-musica-sin-barra-inferior")
    }
    @MainActor func testPhoneSidebarKeepsMusicAndNestedAccountState() {
        let app=XCUIApplication();app.launchArguments=["--uitest-payroll","--uitest-sections=calendar,media,music"];app.launch()
        XCTAssertTrue(app.buttons["Hoy"].waitForExistence(timeout:20))
        openSection(app,"Música");tap(app,"music.section.tracks")
        XCTAssertTrue(app.buttons["music.download.section"].waitForExistence(timeout:10))
        openSection(app,"Gestión");tap(app,"management.account")
        XCTAssertTrue(app.buttons["Cambiar contraseña"].waitForExistence(timeout:10))
        openSection(app,"Música");XCTAssertTrue(app.buttons["music.download.section"].waitForExistence(timeout:5))
        openSection(app,"Fotografía");XCTAssertTrue(app.buttons["media.item.media-day"].waitForExistence(timeout:15))
        openSection(app,"Gestión");XCTAssertTrue(app.buttons["Cambiar contraseña"].waitForExistence(timeout:5))
        XCTAssertFalse(hasSection(app,"Quincena"));XCTAssertFalse(hasSection(app,"CRM"));XCTAssertFalse(hasSection(app,"Pases"))
    }
    @MainActor func testMusicSectionsAndGlobalSearchRespectListeningPermission() {
        let app=XCUIApplication();app.launchArguments=["--uitest-payroll","--uitest-reader","--uitest-sections=music"];app.launch()
        XCTAssertTrue(app.buttons["music.section.warmup"].waitForExistence(timeout:20))
        for section in ["tracks","demos","studio"] {XCTAssertTrue(app.buttons["music.section."+section].exists)}
        XCTAssertFalse(app.buttons["music.import"].exists)
        app.swipeDown();let search=app.searchFields.firstMatch;XCTAssertTrue(search.waitForExistence(timeout:5));search.tap();search.typeText("arbol")
        XCTAssertTrue(app.buttons["music.track.00000000-0000-4000-8000-000000000001"].waitForExistence(timeout:5))
        XCTAssertFalse(app.buttons["music.track.00000000-0000-4000-8000-000000000000"].exists)
    }
    @MainActor func testMusicSectionSearchAndUploaderControls() {
        let app=XCUIApplication();app.launchArguments=["--uitest-payroll","--uitest-reader","--uitest-sections=music,musicUpload"];app.launch()
        XCTAssertTrue(app.buttons["music.import"].waitForExistence(timeout:20));tap(app,"music.section.tracks")
        XCTAssertTrue(app.buttons["music.download.section"].waitForExistence(timeout:5));XCTAssertTrue(app.buttons["music.track.00000000-0000-4000-8000-000000000001"].exists)
        XCTAssertFalse(app.buttons["music.track.00000000-0000-4000-8000-000000000002"].exists)
    }
    @MainActor func testVideoOptimizationCanBeReviewedAndCancelledBeforeUpload() {
        let app = XCUIApplication()
        app.launchArguments = ["--uitest-payroll", "--uitest-reader", "--uitest-sections=media,mediaUpload"]
        app.launch()
        XCTAssertTrue(app.buttons["media.add"].waitForExistence(timeout: 20))
        tap(app, "media.add")
        XCTAssertTrue(app.staticTexts["media.video.required"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.switches["media.video.optimize"].exists)
        tap(app, "media.fixture")
        let result = app.staticTexts.matching(NSPredicate(format: "identifier BEGINSWITH %@", "media.video.result.")).firstMatch
        XCTAssertTrue(result.waitForExistence(timeout: 30))
        XCTAssertTrue(result.label.contains("MP4 para web")); XCTAssertFalse(result.label.contains("Original conservado"))
        let preview = app.buttons["Ver video antes de subir"]
        if !preview.isHittable { app.swipeUp() }
        XCTAssertTrue(preview.isHittable); preview.tap()
        XCTAssertTrue(app.navigationBars["Revisar video"].waitForExistence(timeout: 10))
        tap(app, "Listo")
        tap(app, "media.composer.cancel")
        XCTAssertTrue(app.buttons["media.add"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.descendants(matching: .any)["media.upload.progress"].exists)
    }
    @MainActor func testExpandedPhotographyFolderScrollsAndKeepsSelectionUsable() {
        let app = XCUIApplication()
        app.launchArguments = ["--uitest-payroll", "--uitest-media-only", "--uitest-media-r2", "--uitest-media-scroll"]
        app.launch()
        tap(app, "media.item.r2_media-day")
        let first = app.buttons["media.item.r2_media-scroll-0"]
        XCTAssertTrue(first.waitForExistence(timeout: 15)); XCTAssertTrue(first.isHittable)
        let scroll = app.scrollViews.firstMatch
        scroll.swipeUp(); scroll.swipeUp()
        XCTAssertFalse(first.isHittable)
        scroll.swipeDown(); scroll.swipeDown()
        if !first.isHittable { scroll.swipeDown() }
        XCTAssertTrue(first.waitForExistence(timeout: 15)); XCTAssertTrue(first.isHittable)
        first.press(forDuration: 0.65)
        XCTAssertEqual(app.staticTexts["media.selection.count"].label, "1 seleccionado")
        tap(app, "media.selection.cancel")
        XCTAssertFalse(app.staticTexts["media.selection.count"].exists)
    }
    @MainActor override func tearDownWithError() throws {
        if let run = testRun, run.failureCount > 0 {
            print("JAC failure accessibility hierarchy:\n" + XCUIApplication().debugDescription)
        }
        try super.tearDownWithError()
    }
    @MainActor func testPhotographyKeepsThumbnailsOrderAndPagesAcrossRefreshAndScrolling() {
        let app = XCUIApplication()
        app.launchArguments = ["--uitest-payroll", "--uitest-media-only", "--uitest-media-r2", "--uitest-media-stability"]
        app.launch(); tap(app, "media.item.r2_media-day")
        let first = app.buttons["media.item.r2_media-scroll-0"]
        let thumbnailReady = NSPredicate(format: "value == %@", "Miniatura cargada")
        XCTAssertTrue(first.waitForExistence(timeout: 15))
        XCTAssertTrue(waitFor(first, predicate: thumbnailReady, timeout: 10), "Una miniatura inicialmente pendiente debe reintentarse")
        let scroll = app.scrollViews.containing(.button, identifier: "media.item.r2_media-day").firstMatch
        let more = app.buttons["Cargar más"]
        for _ in 0..<10 { if more.exists && more.isHittable { break }; scroll.swipeUp() }
        XCTAssertTrue(more.isHittable); more.tap()
        let secondPage = app.buttons["media.item.r2_media-scroll-12"]
        for _ in 0..<8 { if secondPage.exists && secondPage.isHittable { break }; scroll.swipeUp() }
        XCTAssertTrue(secondPage.isHittable)
        XCTAssertTrue(waitFor(secondPage, predicate: thumbnailReady, timeout: 10))
        let visible = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "media.item.r2_media-scroll-")).allElementsBoundByIndex.filter(\.isHittable)
        let ids = visible.map(\.identifier), positions = visible.map(\.frame)
        XCTAssertFalse(ids.isEmpty)
        // Exercise the real 30-second periodic refresh while the folder header
        // and its first page are outside the viewport. No test-only timer.
        let header = app.buttons["media.item.r2_media-day"]
        let previousLabel = header.label
        XCTAssertTrue(waitFor(header, predicate: NSPredicate(format: "label != %@ AND label CONTAINS %@", previousLabel, "Carpeta actualizada"), timeout: 45))
        XCTAssertTrue(waitFor(secondPage, predicate: thumbnailReady, timeout: 10))
        let after = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "media.item.r2_media-scroll-")).allElementsBoundByIndex.filter(\.isHittable)
        XCTAssertEqual(after.map(\.identifier), ids)
        for (element, position) in zip(visible, positions) {
            XCTAssertTrue(element.isHittable)
            XCTAssertEqual(element.frame.minY, position.minY, accuracy: 2, "Actualizar no debe mover el contenido")
        }
        for _ in 0..<12 { if first.exists && first.isHittable { break }; scroll.swipeDown() }
        XCTAssertTrue(first.isHittable); XCTAssertTrue(waitFor(first, predicate: thumbnailReady, timeout: 10))
        first.press(forDuration: 0.65)
        XCTAssertEqual(app.staticTexts["media.selection.count"].label, "1 seleccionado")
        tap(app, "media.selection.cancel")
        XCTAssertTrue(waitFor(first, predicate: thumbnailReady, timeout: 5))
        attachScreen(app, name: "fotografia-miniaturas-orden-paginacion-estables")
    }
    @MainActor func testLongPressSelectsMixedMediaAndCancelRestoresThePhotoViewer() {
        let app = XCUIApplication(); app.launchArguments = ["--uitest-payroll", "--uitest-media-only", "--uitest-media-r2"]; app.launch()
        tap(app, "media.item.r2_media-day")
        let photo = app.buttons["media.item.r2_media-photo"], video = app.buttons["media.item.r2_media-video"]
        XCTAssertTrue(photo.waitForExistence(timeout: 15)); photo.press(forDuration: 0.65)
        XCTAssertTrue(app.staticTexts["media.selection.count"].waitForExistence(timeout: 5)); XCTAssertEqual(app.staticTexts["media.selection.count"].label, "1 seleccionado")
        XCTAssertFalse(app.buttons["media.preview.close"].exists, "Lifting a long press must not open the viewer")
        video.tap(); XCTAssertEqual(app.staticTexts["media.selection.count"].label, "2 seleccionados")
        XCTAssertTrue(photo.isSelected); XCTAssertTrue(video.isSelected)
        photo.tap(); XCTAssertEqual(app.staticTexts["media.selection.count"].label, "1 seleccionado")
        XCTAssertFalse(app.buttons["media.selection.delete"].exists, "An uploader does not gain administrative deletion")
        tap(app, "media.selection.cancel"); photo.tap()
        XCTAssertTrue(app.buttons["media.preview.close"].waitForExistence(timeout: 15)); tap(app, "media.preview.close")
        video.press(forDuration: 0.65); XCTAssertEqual(app.staticTexts["media.selection.count"].label, "1 seleccionado")
        XCTAssertFalse(app.buttons["media.preview.close"].exists)
        attachScreen(app, name: "fotografia-seleccion-multiple-foto-video")
    }
    @MainActor func testSelectedPhotosAndVideosDownloadOnlyThatGroupToPhotosAndOffline() {
        let app = XCUIApplication(); app.launchArguments = ["--uitest-payroll", "--uitest-media-only", "--uitest-media-r2", "--uitest-media-slideshow"]; app.launch()
        tap(app, "media.item.r2_media-day")
        let photo = app.buttons["media.item.r2_media-photo"]
        XCTAssertTrue(photo.waitForExistence(timeout: 15)); photo.press(forDuration: 0.65)
        tap(app, "media.item.r2_media-video"); tap(app, "media.selection.download"); tap(app, "Guardar en Fotos")
        XCTAssertTrue(app.staticTexts["2 archivos seleccionados"].waitForExistence(timeout: 10)); tap(app, "media.transfer.begin")
        XCTAssertTrue(app.staticTexts["2 de 2 archivos guardados en Fotos."].waitForExistence(timeout: 20))
        tap(app, "media.selection.download"); tap(app, "Guardar sin conexión"); tap(app, "media.transfer.begin")
        XCTAssertTrue(app.staticTexts["2 de 2 archivos disponibles sin conexión."].waitForExistence(timeout: 20))
        XCTAssertTrue(app.buttons["media.item.r2_media-photo-2"].exists, "The unselected photo remains in the gallery")
        attachScreen(app, name: "fotografia-descarga-seleccionada-fotos-offline")
    }
    @MainActor func testAdministratorCancelsThenDeletesOnlyTheSelectedPhotoAndVideo() {
        let app = XCUIApplication(); app.launchArguments = ["--uitest-payroll", "--uitest-media-r2", "--uitest-media-slideshow", "--uitest-media-two-folders"]; app.launch()
        XCTAssertTrue(hasSection(app, "Fotografía", timeout: 20)); openSection(app, "Fotografía")
        tap(app, "media.item.r2_media-day")
        let photo = app.buttons["media.item.r2_media-photo"], video = app.buttons["media.item.r2_media-video"], kept = app.buttons["media.item.r2_media-photo-2"]
        XCTAssertTrue(photo.waitForExistence(timeout: 15)); photo.press(forDuration: 0.65); video.tap()
        tap(app, "media.selection.delete"); XCTAssertTrue(app.alerts["Eliminar selección"].waitForExistence(timeout: 5))
        app.alerts.buttons["Cancelar"].tap(); XCTAssertTrue(photo.exists); XCTAssertTrue(video.exists); XCTAssertTrue(kept.exists)
        tap(app, "media.selection.delete"); app.alerts.buttons.matching(identifier: "media.selection.delete.confirm").firstMatch.tap()
        XCTAssertTrue(app.staticTexts["2 de 2 archivos eliminados."].waitForExistence(timeout: 20))
        XCTAssertTrue(kept.waitForExistence(timeout: 15)); XCTAssertFalse(photo.exists); XCTAssertFalse(video.exists)
        XCTAssertTrue(app.buttons["media.item.r2_media-day"].exists); XCTAssertTrue(app.buttons["media.item.r2_media-other"].exists)
        attachScreen(app, name: "fotografia-borrado-seleccion-conserva-resto")
    }
    @MainActor func testPhotoUploadQueueSurvivesLeavingGalleryAndGoingHome() {
        let app=XCUIApplication()
        app.launchArguments=["--uitest-payroll","--uitest-reader","--uitest-sections=calendar,alerts,media,mediaUpload","--uitest-slow-media-upload"]
        app.launch()
        openSection(app, "Fotografía")
        XCTAssertTrue(app.buttons["media.item.media-day"].waitForExistence(timeout:20))
        tap(app,"media.add")
        let field=app.textFields["media.folder.name"];XCTAssertTrue(field.waitForExistence(timeout:10));field.tap();field.typeText("Cola ficticia")
        tap(app,"media.fixture");tap(app,"media.upload")
        XCTAssertTrue(app.descendants(matching:.any)["media.upload.progress"].waitForExistence(timeout:10))
        openSection(app, "Agenda")
        XCTAssertTrue(app.buttons["Hoy"].waitForExistence(timeout:10))
        XCUIDevice.shared.press(.home)
        Thread.sleep(forTimeInterval:6)
        app.activate()
        XCTAssertTrue(app.wait(for:.runningForeground,timeout:10))
        openSection(app, "Fotografía")
        XCTAssertTrue(app.descendants(matching:.any)["media.upload.progress"].waitForExistence(timeout:10))
        XCTAssertTrue(app.staticTexts["2 de 2 completados"].waitForExistence(timeout:20))
        let folder=app.buttons.matching(NSPredicate(format:"identifier BEGINSWITH %@ AND label CONTAINS %@","media.item.","Cola ficticia")).firstMatch
        XCTAssertTrue(folder.waitForExistence(timeout:20))
        if folder.value as? String != "Abierta" { folder.tap() }
        XCTAssertEqual(folder.value as? String,"Abierta")
        let photo=app.buttons.matching(NSPredicate(format:"identifier BEGINSWITH %@ AND label CONTAINS %@","media.item.","Foto de prueba.png")).firstMatch
        let video=app.buttons.matching(NSPredicate(format:"identifier BEGINSWITH %@ AND label CONTAINS %@","media.item.","Video de prueba.mp4")).firstMatch
        XCTAssertTrue(photo.waitForExistence(timeout:20));XCTAssertTrue(video.waitForExistence(timeout:20))
        attachScreen(app,name:"fotografia-cola-conservada-al-salir")
    }
    @MainActor func testVisiblePhotoThumbnailsWakeWhenSlowSessionRestoresOnline() {
        let app=XCUIApplication(),base=["--uitest-payroll","--uitest-media-only","--uitest-offline-content"]
        app.launchArguments=base+["--uitest-reset-content","--uitest-reset-media"];app.launch()
        let day=app.buttons["media.item.media-day"];XCTAssertTrue(day.waitForExistence(timeout:20));day.tap()
        XCTAssertTrue(app.buttons["media.item.media-photo"].waitForExistence(timeout:10));app.terminate()
        app.launchArguments=base+["--uitest-async-slow-workspace"]
        let reopenedAt=Date();app.launch()
        // The fixture returns media immediately while workspace validation
        // remains pending for eight seconds, without blocking URLProtocol.
        XCTAssertTrue(day.exists,"La carpeta descargada debe estar visible antes de validar la sesión.");day.tap()
        XCTAssertTrue(app.buttons["media.item.media-photo"].exists)
        XCTAssertTrue(app.buttons["media.add"].exists);XCTAssertFalse(app.buttons["media.add"].isEnabled,"El botón permanece visible sin permitir subir antes de validar.")
        let thumbnail=app.descendants(matching:.any).matching(identifier:"media.thumbnail.media-photo").firstMatch
        XCTAssertTrue(app.descendants(matching:.any).matching(identifier:"media.placeholder.media-photo").firstMatch.exists)
        XCTAssertFalse(thumbnail.exists)
        XCTAssertFalse(app.staticTexts["media.offline.status"].exists)
        XCTAssertTrue(thumbnail.waitForExistence(timeout:max(0,15-Date().timeIntervalSince(reopenedAt))),"Al validar la sesión, la miniatura debe aparecer sin esperar treinta segundos ni abrir el original.")
        XCTAssertTrue(app.buttons["media.add"].waitForExistence(timeout:max(0,15-Date().timeIntervalSince(reopenedAt))))
        XCTAssertTrue(app.buttons["media.add"].isEnabled)
        attachScreen(app,name:"fotografia-miniaturas-al-recuperar-sesion")
    }
    @MainActor func testPhotographerGalleryRestoresImmediatelyAndRevalidatesBeforePolling() {
        verifyCachedGalleryRevalidation(photographer:true)
    }
    @MainActor func testAdministratorGalleryRevalidatesWhileVisibleDuringSlowSessionRestore() {
        verifyCachedGalleryRevalidation(photographer:false)
    }
    @MainActor private func verifyCachedGalleryRevalidation(photographer:Bool) {
        let app=XCUIApplication()
        let base=["--uitest-payroll","--uitest-offline-content"]+(photographer ? ["--uitest-media-only"]:[])
        app.launchArguments=base+["--uitest-reset-content","--uitest-reset-media"];app.launch()
        if !photographer {
            XCTAssertTrue(hasSection(app, "Fotografía", timeout: 20));openSection(app, "Fotografía")
        }
        XCTAssertTrue(app.buttons["media.item.media-day"].waitForExistence(timeout:20))
        XCTAssertFalse(app.buttons["media.item.media-other"].exists)
        app.terminate()
        // The network workspace takes eight seconds, and its gallery contains
        // a new folder. A cached gallery must render first, then revalidate
        // without a manual refresh or the thirty-second polling interval.
        app.launchArguments=base+["--uitest-slow-content","--uitest-slow-media","--uitest-media-two-folders"]
        let reopenedAt=Date();app.launch()
        if !photographer {
            XCTAssertTrue(hasSection(app, "Fotografía", timeout: 3));openSection(app, "Fotografía")
            XCTAssertTrue(hasSection(app, "Quincena"))
        }
        XCTAssertTrue(app.buttons["media.item.media-day"].waitForExistence(timeout:3),"La carpeta descargada debe aparecer mientras se revalida la sesión lenta.")
        XCTAssertFalse(app.textFields["login.username"].exists)
        XCTAssertFalse(app.staticTexts["media.offline.status"].exists,"Consultar la copia mientras llega la red no debe anunciar un fallo de conexión.")
        XCTAssertFalse(app.buttons["media.item.media-other"].exists,"Primero debe mostrarse la copia guardada, que todavía no incluye BOGOTÁ.")
        let revalidated=app.buttons["media.item.media-other"].waitForExistence(timeout:max(0,15-Date().timeIntervalSince(reopenedAt)))
        if !revalidated {
            attachScreen(app,name:"fotografia-revalidacion-no-completada")
            let hierarchy=XCTAttachment(string:app.debugDescription);hierarchy.name="fotografia-revalidacion-jerarquia";hierarchy.lifetime = .keepAlways;add(hierarchy)
        }
        XCTAssertTrue(revalidated,"La galería visible debe actualizarse al validar la sesión, sin esperar los treinta segundos del sondeo.")
        XCTAssertTrue(app.buttons["media.add"].waitForExistence(timeout:max(0,15-Date().timeIntervalSince(reopenedAt))));XCTAssertTrue(app.buttons["media.add"].isEnabled)
        if photographer {XCTAssertFalse(hasSection(app, "Quincena"));XCTAssertFalse(hasSection(app, "Agenda"))}
        attachScreen(app,name:photographer ? "fotografia-cache-revalidada-fotografo":"fotografia-cache-revalidada-administrador")
    }
    @MainActor func testRootUploadChoosesExistingFolderAndContextMenuDownloadsOnlyItsTarget() {
        let app=XCUIApplication();app.launchArguments=["--uitest-payroll","--uitest-media-only","--uitest-media-two-folders"];app.launch()
        XCTAssertTrue(app.buttons["media.item.media-other"].waitForExistence(timeout:20));XCTAssertEqual(app.buttons.matching(NSPredicate(format:"identifier BEGINSWITH %@","media.item.")).element(boundBy:0).identifier,"media.item.media-other")
        XCTAssertFalse(app.buttons["media.offline"].exists);XCTAssertFalse(app.buttons["media.savePhotos"].exists)
        tap(app,"media.options.media-other");tap(app,"media.offline");XCTAssertTrue(app.staticTexts["2026-10-17 · BOGOTÁ"].waitForExistence(timeout:10));tap(app,"media.transfer.begin")
        XCTAssertTrue(app.staticTexts["1 de 1 archivos disponibles sin conexión."].waitForExistence(timeout:20))
        tap(app,"media.options.media-day");tap(app,"media.upload.here");XCTAssertFalse(app.textFields["media.folder.name"].exists,"Subir aquí debe recibir la carpeta seleccionada desde la primera apertura");tap(app,"media.fixture");tap(app,"media.upload")
        XCTAssertTrue(app.buttons.matching(NSPredicate(format:"identifier BEGINSWITH %@ AND label CONTAINS %@","media.item.","Foto de prueba.png")).firstMatch.waitForExistence(timeout:20));XCTAssertFalse(app.buttons["media.item.media-other-photo"].exists)
        tap(app,"media.item.media-day");tap(app,"media.item.media-other");XCTAssertTrue(app.buttons["media.item.media-other-photo"].waitForExistence(timeout:15));XCTAssertFalse(app.buttons.matching(NSPredicate(format:"identifier BEGINSWITH %@ AND label CONTAINS %@","media.item.","Foto de prueba.png")).firstMatch.exists)
        attachScreen(app,name:"fotografia-destino-y-menu-por-carpeta")
        tap(app,"media.item.media-other");tap(app,"media.add");let newName=app.textFields["media.folder.name"];newName.tap();newName.typeText("Nuevo show ficticio");tap(app,"media.fixture");tap(app,"media.upload")
        XCTAssertTrue(app.buttons.matching(NSPredicate(format:"identifier BEGINSWITH %@ AND label CONTAINS %@","media.item.","Foto de prueba.png")).firstMatch.waitForExistence(timeout:20))
    }
    @MainActor func testInlinePhotoFoldersExpandTogetherAndCancelledComposerCreatesNothing() {
        let app=XCUIApplication();app.launchArguments=["--uitest-payroll","--uitest-media-only","--uitest-media-two-folders","--uitest-media-r2"];app.launch()
        tap(app,"media.item.r2_media-other");tap(app,"media.item.r2_media-day")
        XCTAssertTrue(app.buttons["media.item.r2_media-other-photo"].waitForExistence(timeout:15));XCTAssertTrue(app.buttons["media.item.r2_media-photo"].waitForExistence(timeout:15));attachScreen(app,name:"fotografia-carpetas-abiertas")
        XCTAssertFalse(app.staticTexts["media.heading"].exists);XCTAssertFalse(app.buttons["media.folder.r2_media-root"].exists)
        tap(app,"media.item.r2_media-day");XCTAssertFalse(app.buttons["media.item.r2_media-photo"].exists);XCTAssertTrue(app.buttons["media.item.r2_media-other-photo"].exists)
        tap(app,"media.item.r2_media-other");attachScreen(app,name:"fotografia-carpetas-simplificadas")
        tap(app,"media.add");let name=app.textFields["media.folder.name"];XCTAssertTrue(name.exists);name.tap();name.typeText("No crear esta carpeta");tap(app,"media.fixture");XCTAssertTrue(app.buttons["media.library"].exists);XCTAssertTrue(app.buttons["media.files"].exists)
        attachScreen(app,name:"fotografia-subir-una-sola-hoja");tap(app,"media.composer.cancel")
        XCTAssertEqual(app.buttons.matching(NSPredicate(format:"identifier BEGINSWITH %@","media.item.")).count,2);XCTAssertFalse(app.staticTexts["No crear esta carpeta"].exists)
    }
    @MainActor func testEmptyProfileCanReachAccountAndLogOutThroughManagement() {
        let app=XCUIApplication();app.launchArguments=["--uitest-payroll","--uitest-sections="];app.launch()
        XCTAssertTrue(hasSection(app, "Gestión", timeout: 20));XCTAssertEqual(navigationSections(app).count,1);XCTAssertFalse(hasSection(app, "Mi cuenta"))
        tap(app,"management.account");XCTAssertTrue(app.buttons["Cerrar sesión"].waitForExistence(timeout:10));tap(app,"Cerrar sesión")
        let confirm=app.sheets.buttons["Cerrar sesión"];XCTAssertTrue(confirm.waitForExistence(timeout:10));confirm.tap();XCTAssertTrue(app.textFields["login.username"].waitForExistence(timeout:15))
    }
    @MainActor func testModernHybridSectionsShowMediaAndItinerariesWithoutFinanceOrBoarding() {
        let app=XCUIApplication();app.launchArguments=["--uitest-payroll","--uitest-sections=media,itineraries,alerts"];app.launch()
        XCTAssertTrue(hasSection(app, "Itinerarios", timeout: 20));XCTAssertTrue(hasSection(app, "Fotografía"))
        XCTAssertFalse(hasSection(app, "Quincena"));XCTAssertFalse(hasSection(app, "Agenda"));XCTAssertFalse(app.buttons["boarding.open"].exists)
        openSection(app, "Fotografía");XCTAssertTrue(app.buttons["media.item.media-day"].waitForExistence(timeout:15));XCTAssertFalse(app.buttons["media.createFolder"].exists);XCTAssertFalse(app.buttons["media.files"].exists)
        tap(app,"media.item.media-day");tap(app,"media.item.media-photo");tap(app,"media.preview.close")
        openSection(app, "Gestión");XCTAssertTrue(app.buttons["notices.alerts"].waitForExistence(timeout:10));XCTAssertFalse(app.buttons["management.archive"].exists);XCTAssertFalse(app.buttons["management.employees"].exists);XCTAssertFalse(app.buttons["management.crm"].exists)
        attachScreen(app,name:"secciones-hibridas-sin-finanzas")
    }
    @MainActor func testAlexAgendaDatesRemainUsableAfterSwitchingMenusAndBackground() {
        let app=XCUIApplication();app.launchArguments=["--uitest-payroll","--uitest-reader","--uitest-sections=calendar,alerts,media,mediaUpload","--uitest-media-r2"];app.launch()
        XCTAssertTrue(app.buttons["Hoy"].waitForExistence(timeout:20))
        for title in ["Agenda","Alertas","Fotografía","Gestión"] {XCTAssertTrue(hasSection(app, title))}
        for title in ["Quincena","Itinerarios","Pases"] {XCTAssertFalse(hasSection(app, title))}
        let formatter=DateFormatter();formatter.calendar=Calendar(identifier:.gregorian);formatter.timeZone=TimeZone(identifier:"America/Bogota");formatter.dateFormat="yyyy-MM-dd"
        let current=formatter.string(from:Date()),prefix=String(current.prefix(8))
        for (index,menu) in ["Fotografía","Alertas","Gestión"].enumerated() {
            openSection(app, menu)
            if menu=="Fotografía" {XCTAssertTrue(app.buttons["media.item.r2_media-day"].waitForExistence(timeout:15))}
            if menu=="Gestión" {XCTAssertTrue(app.buttons["management.account"].waitForExistence(timeout:10));tap(app,"management.account");for _ in 0..<4 {if app.buttons["Cerrar sesión"].exists {break};app.swipeUp()};XCTAssertTrue(app.buttons["Cerrar sesión"].waitForExistence(timeout:10))}
            openSection(app, "Agenda");let cell=app.buttons["agenda.day."+prefix+String(format:"%02d",index+1)]
            XCTAssertTrue(cell.waitForExistence(timeout:15));cell.tap();XCTAssertEqual(cell.value as? String,"Seleccionado");XCTAssertTrue(app.wait(for:.runningForeground,timeout:5))
            app.buttons["Hoy"].tap();tap(app,"agenda.event.fixture-concert");XCTAssertTrue(app.staticTexts["Concierto simulado"].waitForExistence(timeout:10));XCTAssertFalse(app.buttons["agenda.edit"].exists);tap(app,"Listo");XCTAssertTrue(app.wait(for:.runningForeground,timeout:5))
        }
        XCUIDevice.shared.press(.home);app.activate();XCTAssertTrue(app.buttons["Hoy"].waitForExistence(timeout:15));let today=app.buttons["agenda.day."+current];today.tap();XCTAssertEqual(today.value as? String,"Seleccionado")
        tap(app,"agenda.event.fixture-concert");XCTAssertTrue(app.staticTexts["Concierto simulado"].waitForExistence(timeout:10));app.buttons["Listo"].tap()
        openSection(app, "Fotografía");openSection(app, "Agenda");XCTAssertTrue(app.buttons["agenda.day."+current].waitForExistence(timeout:10));attachScreen(app,name:"alex-agenda-fechas-cambio-menu")
    }
    @MainActor func testCalendarOnlyAndAlertsOnlyAccountsStayInTheirOwnSections() {
        let app=XCUIApplication();app.launchArguments=["--uitest-payroll","--uitest-sections=calendar"];app.launch()
        XCTAssertTrue(app.buttons["Hoy"].waitForExistence(timeout:20));XCTAssertTrue(hasSection(app, "Agenda"))
        for title in ["Quincena","Itinerarios","Fotografía","Mi cuenta","Alertas"] {XCTAssertFalse(hasSection(app, title))}
        app.terminate();app.launchArguments=["--uitest-payroll","--uitest-sections=alerts"];app.launch()
        XCTAssertTrue(hasSection(app, "Alertas", timeout: 20));XCTAssertTrue(app.staticTexts.matching(NSPredicate(format:"label ==[c] %@","Avisos del equipo")).firstMatch.waitForExistence(timeout:15))
        for title in ["Quincena","Agenda","Itinerarios","Fotografía"] {XCTAssertFalse(hasSection(app, title))}
        openSection(app, "Gestión");XCTAssertTrue(app.buttons["notices.alerts"].waitForExistence(timeout:10));XCTAssertFalse(app.buttons["management.expenses"].exists);XCTAssertFalse(app.buttons["management.archive"].exists);XCTAssertFalse(app.buttons["management.media"].exists)
        attachScreen(app,name:"solo-alertas-sin-modulos-adicionales")
    }
    @MainActor func testAdministratorCanCancelThenDeleteFolderFromItsMenu() {
        let app=XCUIApplication();app.launchArguments=["--uitest-payroll"];app.launch()
        XCTAssertTrue(hasSection(app, "Fotografía", timeout: 20));openSection(app, "Fotografía")
        tap(app,"media.options.media-day");tap(app,"media.delete.folder");XCTAssertTrue(app.alerts["Eliminar carpeta"].waitForExistence(timeout:10));app.alerts.buttons["Cancelar"].tap();XCTAssertTrue(app.buttons["media.item.media-day"].exists)
        tap(app,"media.options.media-day");tap(app,"media.delete.folder");let confirm=app.alerts["Eliminar carpeta"].buttons.matching(identifier:"media.delete.confirm").firstMatch;XCTAssertTrue(confirm.waitForExistence(timeout:10));confirm.tap()
        expectation(for:NSPredicate(format:"exists == false"),evaluatedWith:app.buttons["media.item.media-day"]);waitForExpectations(timeout:20)
        XCTAssertTrue(app.staticTexts["Carpeta eliminada."].exists)
    }
    @MainActor func testPhotographerCannotDeleteFolders() {
        let app=XCUIApplication();app.launchArguments=["--uitest-payroll","--uitest-media-only"];app.launch();tap(app,"media.options.media-day");XCTAssertFalse(app.buttons["media.delete.folder"].exists)
    }
    @MainActor func testImageQualityPreferenceCanBeSelectedAndPersistsAcrossRelaunch() {
        let app=XCUIApplication();app.launchArguments=["--uitest-payroll","--uitest-media-only"];app.launch()
        XCTAssertTrue(hasSection(app, "Gestión", timeout: 20));openSection(app, "Gestión");tap(app,"management.imageQuality")
        XCTAssertTrue(app.buttons["media.quality.option.0"].waitForExistence(timeout:10));XCTAssertEqual(app.buttons["media.quality.option.0"].label,"Sin compresión");tap(app,"media.quality.option.6000000")
        app.terminate();app.launch();openSection(app, "Gestión");tap(app,"management.imageQuality")
        let selected=app.buttons["media.quality.option.6000000"];XCTAssertTrue(selected.waitForExistence(timeout:10));XCTAssertEqual(selected.value as? String,"Seleccionado","La preferencia debe persistir al relanzar")
        tap(app,"media.quality.option.2000000")
    }
    @MainActor func testPhotoSlideshowMovesBothWaysWithinTheSameSheet() {
        let app=XCUIApplication();app.launchArguments=["--uitest-payroll","--uitest-media-only","--uitest-media-slideshow"];app.launch()
        tap(app,"media.item.media-day");tap(app,"media.item.media-photo")
        XCTAssertTrue(app.staticTexts["media.preview.counter"].waitForExistence(timeout:15));XCTAssertEqual(app.staticTexts["media.preview.counter"].label,"1 de 2")
        let image=app.descendants(matching:.any).matching(identifier:"media.photo.document").firstMatch;XCTAssertTrue(image.waitForExistence(timeout:10));image.swipeLeft();XCTAssertTrue(app.staticTexts["Segunda foto ficticia.png"].waitForExistence(timeout:15));XCTAssertEqual(app.staticTexts["media.preview.counter"].label,"2 de 2");XCTAssertFalse(app.buttons["media.preview.next"].isEnabled)
        image.swipeRight();expectation(for:NSPredicate(format:"label == %@","1 de 2"),evaluatedWith:app.staticTexts["media.preview.counter"]);waitForExpectations(timeout:15);XCTAssertEqual(app.staticTexts["media.preview.counter"].label,"1 de 2");XCTAssertFalse(app.buttons["media.preview.previous"].isEnabled)
        image.doubleTap();expectation(for:NSPredicate(format:"value == %@","Ampliada"),evaluatedWith:image);waitForExpectations(timeout:10);image.swipeLeft();XCTAssertEqual(app.staticTexts["media.preview.counter"].label,"1 de 2");image.doubleTap();expectation(for:NSPredicate(format:"value == %@","Tamaño original"),evaluatedWith:image);waitForExpectations(timeout:10)
        tap(app,"media.preview.next");XCTAssertTrue(app.staticTexts["Segunda foto ficticia.png"].waitForExistence(timeout:15));tap(app,"media.preview.previous");attachScreen(app,name:"fotografia-visor-deslizar-y-flechas");tap(app,"media.preview.close");XCTAssertTrue(app.buttons["media.item.media-photo"].exists)
    }
    @MainActor func testFullscreenPhotoChangesImmediatelyShowsProgressAndReusesViewedCache() {
        let app=XCUIApplication();app.launchArguments=["--uitest-payroll","--uitest-media-only","--uitest-media-slideshow","--uitest-media-r2","--uitest-slow-photo-preview"];app.launch()
        tap(app,"media.item.r2_media-day");tap(app,"media.item.r2_media-photo")
        let image=app.descendants(matching:.any).matching(identifier:"media.photo.document").firstMatch
        XCTAssertTrue(image.waitForExistence(timeout:15));XCTAssertFalse(hasSection(app, "Fotografía"))
        image.swipeLeft()
        XCTAssertEqual(app.staticTexts["media.preview.counter"].label,"2 de 2");XCTAssertEqual(app.staticTexts["media.preview.name"].label,"Segunda foto ficticia.png")
        let ring=app.descendants(matching:.any).matching(identifier:"media.photo.progress.r2_media-photo-2").firstMatch
        XCTAssertTrue(ring.waitForExistence(timeout:3));expectation(for:NSPredicate(format:"value == %@","50 %"),evaluatedWith:ring);waitForExpectations(timeout:5)
        attachScreen(app,name:"fotografia-pantalla-completa-progreso-real")
        let pager=app.scrollViews["media.photo.pager"];pager.swipeRight();XCTAssertEqual(app.staticTexts["media.preview.counter"].label,"1 de 2");XCTAssertTrue(image.exists)
        pager.swipeLeft();XCTAssertEqual(app.staticTexts["media.preview.counter"].label,"2 de 2");XCTAssertTrue(image.waitForExistence(timeout:20))
        attachScreen(app,name:"fotografia-pantalla-completa-foto");tap(app,"media.preview.close")
        tap(app,"media.item.r2_media-photo");XCTAssertTrue(image.waitForExistence(timeout:5));tap(app,"media.preview.next")
        XCTAssertEqual(app.staticTexts["media.preview.counter"].label,"2 de 2");XCTAssertTrue(image.waitForExistence(timeout:5),"La copia vista debe abrir sin repetir la descarga ficticia de doce segundos.")
        tap(app,"media.preview.close");XCTAssertTrue(app.buttons["media.item.r2_media-day"].exists)
    }
    @MainActor func testPhotographerCreatesFolderUploadsAndReadsNativePhotoVideoWithoutFinance() {
        let app = XCUIApplication(); app.launchArguments = ["--uitest-payroll", "--uitest-media-only", "--uitest-slow-media-upload"]; app.launch()
        XCTAssertTrue(app.buttons["media.item.media-day"].waitForExistence(timeout: 20))
        XCTAssertTrue(hasSection(app, "Fotografía"));XCTAssertTrue(hasSection(app, "Gestión"));XCTAssertFalse(hasSection(app, "Mi cuenta"))
        for forbidden in ["Quincena", "Agenda", "Itinerarios", "Mi cuenta"] { XCTAssertFalse(hasSection(app, forbidden)) }
        tap(app, "media.item.media-day"); tap(app, "media.item.media-photo"); tap(app, "media.preview.close")
        tap(app, "media.item.media-video"); XCTAssertTrue(app.descendants(matching: .any)["media.video"].waitForExistence(timeout: 15)); attachScreen(app, name: "fotografia-video-nativo"); tap(app, "media.preview.close")
        tap(app,"media.item.media-day");tap(app,"media.add"); let field = app.textFields["media.folder.name"]; XCTAssertTrue(field.waitForExistence(timeout: 10)); field.tap(); field.typeText("Ensayo ficticio")
        XCTAssertTrue(app.buttons["media.fixture"].waitForExistence(timeout: 15)); tap(app, "media.fixture"); tap(app, "media.upload");XCTAssertTrue(app.descendants(matching:.any)["media.upload.progress"].waitForExistence(timeout:10));XCTAssertTrue(app.staticTexts["media.upload.speed"].exists);attachScreen(app,name:"fotografia-progreso-general")
        let uploaded = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label CONTAINS %@", "media.item.", "Foto de prueba.png")).firstMatch
        XCTAssertTrue(uploaded.waitForExistence(timeout: 15)); XCTAssertTrue(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label CONTAINS %@", "media.item.", "Video de prueba.mp4")).firstMatch.waitForExistence(timeout: 15)); attachScreen(app, name: "fotografia-subida-multiple-nativa")
        openAccount(app); XCTAssertTrue(app.staticTexts["Fotografía JAC"].waitForExistence(timeout: 10)); XCTAssertFalse(app.staticTexts["Administrador de JAC"].exists)
    }
    @MainActor func testFolderDownloadCanExcludeVideosOrIncludeTheWholeFolder() {
        let app = XCUIApplication()
        app.launchArguments = ["--uitest-payroll", "--uitest-media-only", "--uitest-media-r2", "--uitest-reset-content", "--uitest-reset-media"]
        app.launch()
        tap(app, "media.options.r2_media-day"); tap(app, "media.savePhotosOnly")
        XCTAssertTrue(app.staticTexts["media.transfer.photosOnly"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Foto ficticia.png"].exists)
        XCTAssertFalse(app.staticTexts["Video ficticio.mov"].exists)
        tap(app, "media.transfer.begin")
        XCTAssertTrue(app.staticTexts["1 de 1 archivos guardados en Fotos."].waitForExistence(timeout: 20))
        tap(app, "media.options.r2_media-day"); tap(app, "media.savePhotos")
        XCTAssertTrue(app.staticTexts["Video ficticio.mov"].waitForExistence(timeout: 10))
        tap(app, "media.transfer.begin")
        XCTAssertTrue(app.staticTexts["2 de 2 archivos guardados en Fotos."].waitForExistence(timeout: 20))
    }

    @MainActor func testFolderShareCanBeCreatedAndRevoked() {
        let app = XCUIApplication()
        app.launchArguments = ["--uitest-payroll", "--uitest-media-only", "--uitest-media-r2", "--uitest-reset-content", "--uitest-reset-media"]
        app.launch()
        tap(app, "media.options.r2_media-day"); tap(app, "media.share.folder")
        let create = app.buttons["media.share.create"]
        XCTAssertTrue(create.waitForExistence(timeout: 10))
        for _ in 0..<50 where !create.isEnabled { Thread.sleep(forTimeInterval: 0.1) }
        create.tap()
        let link = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "media.share.link.")).firstMatch
        XCTAssertTrue(link.waitForExistence(timeout: 10))
        let revoke = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "media.share.revoke.")).firstMatch
        XCTAssertTrue(revoke.waitForExistence(timeout: 10)); revoke.tap()
        XCTAssertTrue(link.waitForNonExistence(timeout: 10))
    }

    @MainActor func testPhotographerDownloadsFolderOfflineAndSavesPhotosThroughFakeWriter() {
        let app = XCUIApplication(); let base = ["--uitest-payroll", "--uitest-media-only", "--uitest-offline-content", "--uitest-media-r2"]
        app.launchArguments = base + ["--uitest-reset-content", "--uitest-reset-media"]; app.launch()
        XCTAssertTrue(app.buttons["media.item.r2_media-day"].waitForExistence(timeout: 20));tap(app,"media.options.r2_media-day")
        tap(app, "media.offline"); tap(app, "media.transfer.begin")
        XCTAssertTrue(app.staticTexts["2 de 2 archivos disponibles sin conexión."].waitForExistence(timeout: 20))
        tap(app,"media.options.r2_media-day");tap(app, "media.savePhotos"); tap(app, "media.transfer.begin")
        XCTAssertTrue(app.staticTexts["2 de 2 archivos guardados en Fotos."].waitForExistence(timeout: 20))
        let folder=app.buttons["media.item.r2_media-day"];XCTAssertFalse(app.staticTexts["media.heading"].exists);XCTAssertGreaterThanOrEqual(folder.frame.minX,app.frame.minX+12);XCTAssertLessThanOrEqual(folder.frame.maxX,app.frame.maxX-12)
        attachScreen(app, name: "carpeta-guardada-fotos-sin-biblioteca-real")
        app.terminate(); app.launchArguments = base + ["--uitest-offline"]; app.launch()
        XCTAssertTrue(app.buttons["media.item.r2_media-day"].waitForExistence(timeout: 20)); tap(app, "media.item.r2_media-day")
        tap(app, "media.item.r2_media-photo"); XCTAssertTrue(app.buttons["media.preview.close"].waitForExistence(timeout: 15)); attachScreen(app, name: "fotografia-reapertura-sin-internet"); tap(app, "media.preview.close")
        tap(app, "media.item.r2_media-video"); XCTAssertTrue(app.descendants(matching: .any)["media.video"].waitForExistence(timeout: 15)); tap(app, "media.preview.close")
        XCTAssertFalse(app.buttons["media.upload"].exists); XCTAssertFalse(app.buttons["media.createFolder"].exists)
    }
    @MainActor func testAdministratorGalleryAllowsUploadAndPreview() {
        let app = fixture();openSection(app, "Fotografía")
        XCTAssertTrue(app.buttons["media.item.media-day"].waitForExistence(timeout: 15)); XCTAssertTrue(app.buttons["media.add"].exists);XCTAssertFalse(app.buttons["media.files"].exists)
        tap(app, "media.item.media-day"); tap(app, "media.item.media-photo"); tap(app, "media.preview.close")
        tap(app,"media.item.media-day");tap(app,"media.options.media-day");tap(app,"media.upload.here");XCTAssertFalse(app.textFields["media.folder.name"].exists,"Subir aquí debe recibir la carpeta seleccionada desde la primera apertura");tap(app,"media.fixture");tap(app,"media.upload")
        XCTAssertTrue(app.buttons.matching(NSPredicate(format:"identifier BEGINSWITH %@ AND label CONTAINS %@","media.item.","Foto de prueba.png")).firstMatch.waitForExistence(timeout:15))
        XCTAssertTrue(app.buttons.matching(NSPredicate(format:"identifier BEGINSWITH %@ AND label CONTAINS %@","media.item.","Video de prueba.mp4")).firstMatch.waitForExistence(timeout:15));attachScreen(app,name:"fotografia-administrador-sube")
    }
    @MainActor func testAgendaDayEdgesSelectTheWholeVisibleCell() {
        let app=fixture();openSection(app, "Agenda")
        var c=Calendar(identifier:.gregorian);c.timeZone=TimeZone(identifier:"America/Bogota")!
        let f=DateFormatter();f.timeZone=c.timeZone;f.dateFormat="yyyy-MM-dd"
        let date=c.date(byAdding:.day,value:1,to:Date())!
        let cell=app.buttons["agenda.day."+f.string(from:date)]
        XCTAssertTrue(cell.waitForExistence(timeout:15));cell.coordinate(withNormalizedOffset:CGVector(dx:0.08,dy:0.5)).tap()
        XCTAssertEqual(cell.value as? String,"Seleccionado")
    }
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

    @MainActor func testKeepSignedInChoiceIsOptionalAndSurvivesBackground() {
        let app = XCUIApplication(); app.launch()
        let toggle = app.switches["login.keepSignedIn"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 20))
        XCTAssertEqual(toggle.value as? String, "0")
        // SwiftUI exposes the label row as the switch; tap its trailing control.
        toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        XCTAssertEqual(toggle.value as? String, "1")
        XCUIDevice.shared.press(.home); app.activate()
        XCTAssertTrue(toggle.waitForExistence(timeout: 10)); XCTAssertTrue(toggle.isHittable)
        XCTAssertEqual(toggle.value as? String, "1")
        attachScreen(app, name: "mantener-sesion-iniciada")
        toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        XCTAssertEqual(toggle.value as? String, "0")
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

    @MainActor func testCRMNativeAutocompleteBudgetPreparationAndPrivateReceipt() {
        let app=fixture();openSection(app, "Gestión");tap(app,"management.crm")
        attachScreen(app,name:"nuevo-crm-acciones")
        let show="77777777-7777-4777-8777-777777777777",contact="88888888-8888-4888-8888-888888888888"
        tap(app,"crm.show."+show);tap(app,"crm.price");fill(app,"crm.entrepreneur","jose");tap(app,"crm.suggestion."+contact)
        XCTAssertEqual(app.textFields["crm.entrepreneur"].value as? String,"José · Empresario ficticio")
        XCUIDevice.shared.press(.home);app.activate();XCTAssertTrue(app.textFields["crm.entrepreneur"].waitForExistence(timeout:10));tap(app,"crm.editor.save")
        XCTAssertTrue(app.buttons["crm.payment"].waitForExistence(timeout:10));tap(app,"crm.payment")
        fill(app,"crm.amount.Valor del abono (COP)","50000000");tap(app,"travel.fixture");tap(app,"crm.editor.save")
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format:"label CONTAINS %@","90.000.000")).firstMatch.waitForExistence(timeout:10))
        tap(app,"Rentabilidad")
        let commission=app.staticTexts["Comisión de toda la quincena"]
        // On compact iPhones this section is below the budget fields. Exercise
        // the same scroll a person uses; retain the original presence check.
        for _ in 0..<8 { if commission.exists {break};app.swipeUp() }
        XCTAssertTrue(commission.waitForExistence(timeout:10));attachScreen(app,name:"crm-rentabilidad-nativa")
        tap(app,"Preparación");tap(app,"crm.plan.save")
        let saved=app.staticTexts["Presupuesto y preparación guardados."];for _ in 0..<8 {if saved.exists{break};app.swipeDown()};XCTAssertTrue(saved.waitForExistence(timeout:10))
    }
    @MainActor func testCRMContactFilesWeeklyAndReaderRestriction() {
        let app=fixture();openSection(app, "Gestión");tap(app,"management.crm");tap(app,"Empresarios")
        tap(app,"crm.contact.88888888-8888-4888-8888-888888888888");tap(app,"crm.contact.files");tap(app,"travel.fixture");tap(app,"crm.editor.save")
        XCTAssertTrue(app.buttons.matching(NSPredicate(format:"identifier BEGINSWITH 'crm.file.'")).firstMatch.waitForExistence(timeout:10))
        app.buttons.matching(NSPredicate(format:"identifier BEGINSWITH 'crm.file.'")).firstMatch.tap();XCTAssertTrue(app.navigationBars["Documento"].waitForExistence(timeout:10));tap(app,"Listo")
        attachScreen(app,name:"crm-empresario-nativo")
        app.terminate();let reader=fixture(["--uitest-reader"]);openSection(reader, "Gestión");XCTAssertFalse(reader.buttons["management.crm"].exists)
    }

    @MainActor func testCRMCreateSingleDayShowFirstPaymentAndWeeklySummary() {
        let app=fixture();openSection(app, "Gestión");tap(app,"management.crm");tap(app,"crm.add");tap(app,"Crear show")
        fill(app,"crm.create.title","PEREIRA · Nuevo ficticio");fill(app,"crm.amount.Valor de venta (COP)","140000000")
        fill(app,"crm.entrepreneur","jose");attachScreen(app,name:"crm-autocompletar-legible");tap(app,"crm.suggestion.88888888-8888-4888-8888-888888888888")
        let first=app.switches["crm.firstPayment"];for _ in 0..<5{if first.exists && first.isHittable{break};app.swipeUp()};XCTAssertTrue(first.exists);first.coordinate(withNormalizedOffset:CGVector(dx:0.9,dy:0.5)).tap();XCTAssertEqual(first.value as? String,"1")
        fill(app,"crm.amount.Valor del abono (COP)","50000000");tap(app,"travel.fixture");tap(app,"crm.editor.save")
        XCTAssertTrue(app.textFields["crm.search"].waitForExistence(timeout:10));fill(app,"crm.search","Nuevo ficticio")
        XCTAssertTrue(app.staticTexts["PEREIRA · Nuevo ficticio"].waitForExistence(timeout:10));XCTAssertTrue(app.staticTexts.matching(NSPredicate(format:"label CONTAINS %@","90.000.000")).firstMatch.exists)
        tap(app,"Semana");XCTAssertTrue(app.staticTexts["Resumen semanal"].waitForExistence(timeout:10));XCTAssertTrue(app.staticTexts["Gastos por fecha de registro"].exists);XCTAssertTrue(app.staticTexts.matching(NSPredicate(format:"label CONTAINS %@","50.000.000")).firstMatch.exists);attachScreen(app,name:"crm-resumen-semanal-nativo")
    }

    @MainActor func testDeleteArchivedContractRequiresConfirmationAndKeepsShow() {
        let app=fixture(["--uitest-contract-archive"]),id="11111111-1234-4234-8234-111111111111"
        openSection(app, "Gestión");tap(app,"management.crm");tap(app,"Contratos")
        tap(app,"contracts.delete."+id);XCTAssertTrue(app.alerts["Eliminar contrato"].waitForExistence(timeout:10))
        attachScreen(app,name:"contrato-eliminar-confirmacion-ficticia");tap(app,"contracts.delete.cancel")
        XCTAssertTrue(app.buttons["contracts.open."+id].exists)
        tap(app,"contracts.open."+id);XCTAssertTrue(app.navigationBars["Contrato JAC"].waitForExistence(timeout:10));tap(app,"contracts.preview.close")
        tap(app,"contracts.delete."+id);tap(app,"contracts.delete.confirm")
        XCTAssertTrue(app.buttons["contracts.open."+id].waitForNonExistence(timeout:10))
        XCTAssertTrue(app.staticTexts["Aquí aparecerán los contratos que generes a partir de ahora."].exists)
        tap(app,"Shows");XCTAssertTrue(app.buttons["crm.show.77777777-7777-4777-8777-777777777777"].waitForExistence(timeout:10))
        tap(app,"Contratos");XCTAssertFalse(app.buttons["contracts.open."+id].exists)
    }

    @MainActor func testCRMContractsRUTEditableFieldsManualEntryAndPDFPreview() {
        let app=fixture();openSection(app, "Gestión");tap(app,"management.crm");tap(app,"Contratos");tap(app,"contracts.create")
        XCTAssertTrue(app.buttons["contracts.rut.upload"].waitForExistence(timeout:10))
        XCTAssertTrue(app.textFields["contracts.company"].exists,"Los campos manuales deben existir sin cargar RUT")
        tap(app,"contracts.rut.fixture")
        XCTAssertEqual(app.textFields["contracts.company"].value as? String,"EMPRESA FICTICIA JAC SAS")
        XCTAssertEqual(app.textFields["contracts.nit"].value as? String,"900000001-0")
        XCTAssertEqual(app.textFields["contracts.representative"].value as? String,"ANA MARÍA PRUEBA GÓMEZ")
        fill(app,"contracts.company","EMPRESA CORREGIDA A MANO")
        XCTAssertEqual(app.textFields["contracts.company"].value as? String,"EMPRESA CORREGIDA A MANO")
        XCUIDevice.shared.press(.home);app.activate()
        // SwiftUI briefly exposes both the privacy snapshot and the live form
        // while returning from Home. Wait for the live, unchanged draft.
        let restored=app.textFields.matching(identifier:"contracts.company").matching(NSPredicate(format:"value == %@","EMPRESA CORREGIDA A MANO")).firstMatch
        XCTAssertTrue(restored.waitForExistence(timeout:10));XCTAssertEqual(restored.value as? String,"EMPRESA CORREGIDA A MANO","El borrador debe conservarse al volver a la app")
        XCTAssertTrue(app.images["privacy.cover"].waitForNonExistence(timeout:10))
        fill(app,"contracts.venue","Escenario ficticio");fill(app,"contracts.municipality","Pereira");fill(app,"contracts.department","Risaralda")
        fill(app,"crm.amount.Precio del contrato (COP)","140000000");fill(app,"crm.amount.Consignado a la fecha (COP)","10000000")
        tap(app,"contracts.generate")
        XCTAssertTrue(app.navigationBars["Contrato JAC"].waitForExistence(timeout:15));XCTAssertTrue(app.buttons["contracts.share"].exists)
        let pdfText=app.descendants(matching:.any).matching(NSPredicate(format:"label CONTAINS %@","Itinerario simulado")).firstMatch
        XCTAssertTrue(pdfText.waitForExistence(timeout:15),"La vista previa debe mostrar el contenido PDF, no solo su barra de navegación")
        attachScreen(app,name:"contrato-nativo-pdf-ficticio");tap(app,"contracts.preview.close")
        XCTAssertTrue(app.buttons["contracts.generate"].waitForExistence(timeout:10))
        tap(app,"contracts.form.close")
        let open=app.buttons.matching(NSPredicate(format:"identifier BEGINSWITH %@","contracts.open.")).firstMatch
        XCTAssertTrue(open.waitForExistence(timeout:10),"El PDF generado debe aparecer en el archivo")
        let assign=app.buttons.matching(NSPredicate(format:"identifier BEGINSWITH %@","contracts.assign.")).firstMatch
        assign.tap();tap(app,"contracts.show.picker");let option=app.buttons.matching(NSPredicate(format:"label BEGINSWITH %@","PEREIRA · Show ficticio")).firstMatch;XCTAssertTrue(option.waitForExistence(timeout:10));option.tap()
        tap(app,"contracts.assign.save")
        XCTAssertTrue(app.staticTexts["Show: PEREIRA · Show ficticio"].waitForExistence(timeout:10))
        open.tap();XCTAssertTrue(app.navigationBars["Contrato JAC"].waitForExistence(timeout:10));XCTAssertTrue(pdfText.waitForExistence(timeout:15));attachScreen(app,name:"contratos-archivo-nativo-ficticio")
    }

    @MainActor private func sectionID(_ title: String) -> String {
        ["CRM":"crm", "Quincena":"payroll", "Agenda":"agenda", "Itinerarios":"itineraries", "Pases":"boarding", "Alertas":"alerts", "Fotografía":"media", "Música":"music", "Gestión":"management"][title] ?? title
    }
    @MainActor private func menuVisible(_ app: XCUIApplication) -> Bool {
        let close=app.buttons["phone.menu.close"]
        return close.exists && app.windows.firstMatch.frame.contains(close.frame)
    }
    @MainActor private func waitForMenu(_ app: XCUIApplication, visible: Bool) -> Bool {
        waitFor(app, predicate:NSPredicate {_,_ in self.menuVisible(app) == visible}, timeout:5)
    }
    @MainActor private func showMenu(_ app: XCUIApplication, timeout: TimeInterval = 20) -> Bool {
        if menuVisible(app) { return true }
        let opener=app.buttons["phone.menu.open"]
        guard opener.waitForExistence(timeout: timeout) else { return false }
        let frame=opener.frame,screen=app.windows.firstMatch.frame
        guard frame.width >= 44,frame.height >= 44,screen.contains(frame) else { return false }
        // After focus returns, XCTest may include the full header/status area
        // in the button frame. The actual 44pt control is at its bottom-left;
        // tap its center without requiring an exposed SF Symbol child.
        // One bounded retry handles an event lost during cold launch;
        // both attempts must open the real panel, never a synthetic state.
        for _ in 0..<2 {
            opener.coordinate(withNormalizedOffset:CGVector(dx:0,dy:1)).withOffset(CGVector(dx:22,dy:-22)).tap()
            if waitForMenu(app, visible:true) {return true}
            if !opener.exists {return false}
        }
        return false
    }
    @MainActor private func navigationSections(_ app: XCUIApplication) -> [String] {
        guard showMenu(app) else { return [] }
        let result=app.buttons.matching(NSPredicate(format:"identifier BEGINSWITH %@", "phone.section.")).allElementsBoundByIndex.map(\.identifier)
        app.buttons["phone.menu.close"].tap();return result
    }
    @MainActor private func hasSection(_ app: XCUIApplication, _ title: String, timeout: TimeInterval = 1) -> Bool {
        guard showMenu(app, timeout: timeout) else { return false }
        var result=app.buttons["phone.section."+sectionID(title)].exists
        if title == "Pases" {let legacy=app.buttons["phone.section.itineraries"];result = result || (legacy.exists && legacy.label == "Pases")}
        app.buttons["phone.menu.close"].tap();return result
    }
    @MainActor private func openSection(_ app: XCUIApplication, _ title: String) {
        XCTAssertTrue(showMenu(app), "Debe abrirse el menú lateral")
        var button=app.buttons["phone.section."+sectionID(title)]
        if title == "Pases" && !button.exists {button=app.buttons["phone.section.itineraries"]}
        XCTAssertTrue(button.waitForExistence(timeout: 5), "Debe existir la sección \(title)")
        let scroll=app.scrollViews["phone.sidebar.scroll"]
        for _ in 0..<5 {if button.isHittable {break};scroll.swipeUp()}
        XCTAssertTrue(button.isHittable);button.tap()
        XCTAssertTrue(app.buttons["phone.menu.open"].waitForExistence(timeout: 5))
    }
    @MainActor private func fixture(_ arguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication(); app.launchArguments = ["--uitest-payroll"] + arguments; app.launch()
        XCTAssertTrue(app.buttons["period.fixture-period"].waitForExistence(timeout: 20))
        return app
    }
    @MainActor private func openAccount(_ app:XCUIApplication) {
        openSection(app, "Gestión");tap(app,"management.account")
    }
    @MainActor private func tap(_ app: XCUIApplication, _ label: String) {
        if !label.hasPrefix("crm.suggestion."),label != "crm.keyboard.done",app.keyboards.firstMatch.exists,app.buttons["crm.keyboard.done"].exists {app.buttons["crm.keyboard.done"].tap()}
        let button = app.buttons[label].firstMatch
        for _ in 0..<8 { if button.exists && button.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(button.waitForExistence(timeout: 10), "Debe existir el botón \(label)")
        XCTAssertTrue(button.isHittable, "Debe poderse tocar \(label)"); button.tap()
    }
    @MainActor private func fill(_ app: XCUIApplication, _ id: String, _ value: String) {
        if id.hasPrefix("crm.") || id.hasPrefix("contracts."),app.keyboards.firstMatch.exists,app.buttons["crm.keyboard.done"].exists {app.buttons["crm.keyboard.done"].tap()}
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
    @MainActor func testSidebarAndManagementKeepArchiveTeamAndAccountAccessible() {
        let app = fixture()
        XCTAssertEqual(navigationSections(app).count, 9)
        for title in ["Quincena", "Agenda", "Itinerarios", "Fotografía", "Gestión"] { XCTAssertTrue(hasSection(app, title)) }
        XCTAssertFalse(hasSection(app, "Archivo")); XCTAssertFalse(hasSection(app, "Equipo"))
        attachScreen(app,name:"nueva-quincena-inicio")
        openAccount(app)
        XCTAssertTrue(app.buttons["Cambiar contraseña"].waitForExistence(timeout: 10))
        app.navigationBars.buttons.firstMatch.tap();openSection(app, "Gestión"); attachScreen(app,name:"nueva-gestion-tarjetas"); tap(app, "management.archive")
        XCTAssertTrue(app.navigationBars["Archivo"].waitForExistence(timeout: 10))
        app.navigationBars.buttons.firstMatch.tap(); tap(app, "management.employees")
        XCTAssertTrue(app.navigationBars["Equipo JAC"].waitForExistence(timeout: 10))
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(app.buttons["notices.alerts"].exists); XCTAssertTrue(app.buttons["Correos y Gmail"].exists)
        attachScreen(app, name: "cinco-pestanas-y-gestion")
    }

    @MainActor func testEntireDownloadedAppSurvivesOfflineRelaunchIncludingPrivatePDFs() {
        let app = fixture(["--uitest-offline-content", "--uitest-reset-content"])
        openAccount(app)
        let status = app.staticTexts["offline.sync.status"]
        for _ in 0..<5 { if status.exists { break }; app.swipeUp() }
        XCTAssertTrue(status.waitForExistence(timeout: 10))
        let complete = NSPredicate(format: "label == %@", "La última información y sus adjuntos están guardados en este iPhone.")
        expectation(for: complete, evaluatedWith: status); waitForExpectations(timeout: 30)
        app.terminate()
        app.launchArguments = ["--uitest-payroll", "--uitest-offline-content", "--uitest-offline"]
        app.launch()
        XCTAssertTrue(app.buttons["period.fixture-period"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.textFields["login.username"].exists)
        XCTAssertFalse(app.buttons["period.create"].isEnabled)
        XCTAssertFalse(app.descendants(matching:.any)["offline.copy"].exists)
        tap(app, "period.fixture-period")
        XCTAssertTrue(app.staticTexts["Neto en preparación"].waitForExistence(timeout: 5))
        for _ in 0..<8 { if app.buttons["period.close"].exists { break }; app.swipeUp() }
        XCTAssertTrue(app.buttons["period.close"].exists); XCTAssertFalse(app.buttons["period.close"].isEnabled)
        attachScreen(app, name: "nomina-descargada-sin-internet")
        openSection(app, "Agenda")
        XCTAssertTrue(app.segmentedControls["agenda.mode"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["agenda.create"].exists)
        tap(app, "agenda.event.fixture-concert")
        XCTAssertTrue(app.staticTexts["Teatro simulado"].waitForExistence(timeout: 5))
        tap(app, "Listo")
        openSection(app, "Itinerarios")
        tap(app, "notices.item.33333333-3333-4333-8333-333333333333")
        tap(app, "notices.pdf")
        XCTAssertTrue(app.navigationBars["Itinerario PDF"].waitForExistence(timeout: 5))
        attachScreen(app, name: "itinerario-pdf-sin-internet")
        tap(app, "notices.pdf.close")
        for _ in 0..<4 { if app.buttons["notices.confirm"].exists { break }; app.swipeUp() }
        XCTAssertTrue(app.buttons["notices.confirm"].exists); XCTAssertFalse(app.buttons["notices.confirm"].isEnabled)
        tap(app, "notices.detail.close")
        tap(app, "boarding.open"); tap(app, "notices.item.boarding-fixture-0")
        XCTAssertTrue(app.navigationBars["Pase de abordar PDF"].waitForExistence(timeout: 5))
        attachScreen(app, name: "pase-de-abordar-pdf-sin-internet")
        tap(app, "notices.pdf.close")
        openSection(app, "Gestión"); tap(app, "notices.alerts")
        XCTAssertTrue(app.staticTexts["Alerta guardada de prueba"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["notices.create"].isEnabled)
        attachScreen(app, name: "alertas-descargadas-sin-internet")
        XCUIDevice.shared.press(.home); app.activate()
        XCTAssertTrue(app.staticTexts["Alerta guardada de prueba"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.textFields["login.username"].exists)
    }

    @MainActor func testFullCopyAppearsImmediatelyWhileStartupInternetIsSlow() {
        let app = fixture(["--uitest-offline-content", "--uitest-reset-content"])
        openAccount(app)
        let status = app.staticTexts["offline.sync.status"]
        for _ in 0..<5 { if status.exists { break }; app.swipeUp() }
        let complete = NSPredicate(format: "label == %@", "La última información y sus adjuntos están guardados en este iPhone.")
        expectation(for: complete, evaluatedWith: status); waitForExpectations(timeout: 30)
        app.terminate()
        app.launchArguments = ["--uitest-payroll", "--uitest-offline-content", "--uitest-slow-content"]
        app.launch()
        XCTAssertTrue(app.buttons["period.fixture-period"].waitForExistence(timeout: 3), "El arranque debe mostrar la copia antes de que termine la red lenta")
        XCTAssertFalse(app.textFields["login.username"].exists)
        XCTAssertFalse(app.buttons["period.create"].isEnabled)
        XCTAssertFalse(app.descendants(matching:.any)["offline.copy"].exists)
        XCTAssertFalse(app.staticTexts["Sin conexión · Consulta de la copia guardada"].exists)
        attachScreen(app, name: "copia-completa-mientras-revalida-sesion")
        let writable = NSPredicate { _, _ in app.buttons["period.create"].exists && app.buttons["period.create"].isEnabled }
        let resumed = XCTNSPredicateExpectation(predicate: writable, object: app)
        let result = XCTWaiter.wait(for: [resumed], timeout: 45)
        attachScreen(app, name: "estado-despues-de-recuperar-conexion")
        let hierarchy = XCTAttachment(string: app.debugDescription); hierarchy.name = "estado-de-controles-tras-revalidacion"; hierarchy.lifetime = .keepAlways; add(hierarchy)
        XCTAssertEqual(result, .completed, "Al reconectar se recuperan las acciones autorizadas")
        XCTAssertTrue(app.buttons["period.create"].isEnabled)
    }

    @MainActor func testAgendaSurvivesOfflineRelaunchAndDisplaysCacheDuringInternetRefresh() {
        let app = fixture(["--uitest-agenda-cache", "--uitest-reset-agenda"])
        openSection(app, "Agenda")
        XCTAssertTrue(app.segmentedControls["agenda.mode"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.buttons["agenda.create"].waitForExistence(timeout: 10))
        app.terminate()
        app.launchArguments = ["--uitest-payroll", "--uitest-agenda-cache", "--uitest-offline"]
        app.launch()
        XCTAssertTrue(app.navigationBars["Agenda"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.segmentedControls["agenda.mode"].waitForExistence(timeout: 5))
        for _ in 0..<3 { if app.buttons["Mes siguiente"].isHittable { break }; app.swipeDown() }
        XCTAssertFalse(app.buttons["agenda.create"].exists, "Sin conexión la copia es de consulta")
        tap(app, "Mes siguiente")
        XCTAssertTrue(app.staticTexts["Mes sin descargar"].waitForExistence(timeout: 10))
        tap(app, "Volver a la agenda descargada")
        tap(app, "agenda.event.fixture-concert")
        XCTAssertTrue(app.staticTexts["Teatro simulado"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["agenda.edit"].exists)
        attachScreen(app, name: "agenda-descargada-sin-senal")
        app.terminate()
        app.launchArguments = ["--uitest-payroll", "--uitest-agenda-cache", "--uitest-slow-agenda"]
        app.launch()
        XCTAssertTrue(app.segmentedControls["agenda.mode"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["agenda.updating"].waitForExistence(timeout: 5), "La copia debe verse mientras la red sigue pendiente")
        attachScreen(app, name: "agenda-descargada-mientras-actualiza")
        for _ in 0..<3 { if app.staticTexts["Concierto actualizado"].exists { break }; app.swipeUp() }
        XCTAssertTrue(app.staticTexts["Concierto actualizado"].waitForExistence(timeout: 20))
        XCTAssertTrue(app.buttons["agenda.create"].exists)
        attachScreen(app, name: "agenda-actualizada-desde-fixture")
    }

    @MainActor func testCloseArchiveAndReopenWithoutRealEmailsOrData() {
        let app = fixture()
        tap(app, "period.fixture-period"); tap(app, "period.close")
        tap(app, "Cerrar quincena")
        XCTAssertTrue(app.staticTexts["Neto del cierre"].waitForExistence(timeout: 15))
        openSection(app, "Gestión"); tap(app, "management.archive"); tap(app, "period.fixture-period")
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
        openSection(app, "Gestión"); tap(app, "management.employees"); XCTAssertFalse(app.buttons["employee.create"].exists)
        app.navigationBars.buttons.firstMatch.tap(); XCTAssertFalse(app.buttons["Usuarios y permisos"].exists)
        tap(app, "Conceptos y reglas"); XCTAssertFalse(app.buttons["concept.create"].exists)
        openSection(app, "Agenda"); XCTAssertTrue(app.segmentedControls["agenda.mode"].waitForExistence(timeout: 15)); XCTAssertFalse(app.buttons["agenda.configure"].exists); XCTAssertTrue(app.buttons["agenda.create"].exists)
        attachScreen(app, name: "permisos-solo-consulta")
    }
    @MainActor func testAgendaMonthUpcomingDetailsAndAccountRemainAccessible() {
        let app = fixture()
        openSection(app, "Agenda")
        XCTAssertTrue(app.segmentedControls["agenda.mode"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.buttons["Mes siguiente"].isHittable, "El calendario aparece al abrir Agenda, sin bloques previos.")
        XCTAssertFalse(app.staticTexts["Agenda simulada"].exists)
        XCTAssertFalse(app.staticTexts["Actualizando agenda…"].exists)
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Última descarga:")).firstMatch.exists)
        attachScreen(app, name: "agenda-calendario-primero")
        tap(app, "agenda.event.fixture-concert")
        XCTAssertTrue(app.staticTexts["Teatro simulado"].waitForExistence(timeout: 10))
        attachScreen(app, name: "agenda-detalle-concierto"); tap(app, "Listo")
        let upcoming = app.segmentedControls["agenda.mode"].buttons["Próximos"]
        for _ in 0..<4 { if upcoming.isHittable { break }; app.swipeDown() }
        upcoming.tap()
        tap(app, "agenda.upcoming.fixture-concert"); tap(app, "Listo")
        attachScreen(app, name: "agenda-proximos")
        openAccount(app)
        XCTAssertTrue(app.buttons["Cambiar contraseña"].waitForExistence(timeout: 10))
    }
    @MainActor func testCreateAndEditAgendaEventKeepNativeFormsAndSharedFeed() {
        let app = fixture(); openSection(app, "Agenda")
        XCTAssertTrue(app.segmentedControls["agenda.mode"].waitForExistence(timeout: 15))
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
        openSection(app, "Gestión"); tap(app, "management.archive")
        XCTAssertTrue(app.navigationBars["Archivo"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.descendants(matching: .any)["error.inline"].exists, "Una consulta cancelada no debe dejar un error en Archivo")
        openSection(app, "Quincena")
        app.navigationBars.buttons.firstMatch.tap(); tap(app, "period.fixture-period")
        XCTAssertTrue(app.staticTexts["Neto en preparación"].waitForExistence(timeout: 10))
        openSection(app, "Agenda")
        XCTAssertTrue(app.navigationBars["Agenda"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.descendants(matching: .any)["error.inline"].exists)
        tap(app, "Actualizar agenda")
        XCTAssertTrue(app.segmentedControls["agenda.mode"].waitForExistence(timeout: 10))
        openSection(app, "Itinerarios")
        XCTAssertTrue(app.navigationBars["Itinerarios"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.descendants(matching: .any)["error.inline"].exists)
        openSection(app, "Quincena"); openSection(app, "Itinerarios")
        XCTAssertTrue(app.buttons["notices.item.33333333-3333-4333-8333-333333333333"].waitForExistence(timeout: 10))
        tap(app, "notices.item.33333333-3333-4333-8333-333333333333")
        tap(app, "notices.detail.close")
        openSection(app, "Gestión"); app.navigationBars.buttons.firstMatch.tap(); tap(app, "Correos y Gmail")
        XCTAssertTrue(app.buttons["Actualizar estados"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.descendants(matching: .any)["error.inline"].exists)
        tap(app, "Actualizar estados")
        XCTAssertTrue(app.staticTexts["Remitente"].waitForExistence(timeout: 10))
        app.navigationBars.buttons.firstMatch.tap(); tap(app, "Usuarios y permisos")
        XCTAssertTrue(app.navigationBars["Usuarios y permisos"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.descendants(matching: .any)["error.inline"].exists)
        app.navigationBars.buttons.firstMatch.tap(); tap(app, "management.archive")
        XCTAssertFalse(app.descendants(matching: .any)["error.inline"].exists)
        attachScreen(app, name: "archivo-sin-error-de-consulta-cancelada")
    }

    @MainActor func testItineraryPDFAndSelectiveAlertAreAccessibleInManagement() {
        let app = fixture(); openSection(app, "Itinerarios")
        attachScreen(app,name:"nuevos-itinerarios")
        tap(app, "notices.item.33333333-3333-4333-8333-333333333333")
        tap(app, "notices.pdf"); XCTAssertTrue(app.navigationBars["Itinerario PDF"].waitForExistence(timeout: 15))
        attachScreen(app, name: "itinerario-pdf"); tap(app, "notices.pdf.close"); tap(app, "notices.detail.close")
        openSection(app, "Gestión"); tap(app, "notices.alerts"); tap(app, "notices.create")
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
        let app = fixture(["--uitest-reader", "--uitest-push-settings"]); openSection(app, "Itinerarios")
        XCTAssertFalse(app.buttons["notices.enable"].exists); XCTAssertFalse(app.buttons["notices.disable"].exists)
        app.buttons["notices.item.33333333-3333-4333-8333-333333333333"].swipeLeft(); XCTAssertFalse(app.buttons["notices.list.delete.33333333-3333-4333-8333-333333333333"].exists); tap(app, "notices.item.33333333-3333-4333-8333-333333333333"); XCTAssertTrue(app.buttons["notices.pdf"].waitForExistence(timeout: 10)); tap(app, "notices.detail.close")
        openSection(app, "Gestión"); tap(app, "notices.alerts")
        XCTAssertFalse(app.buttons["notices.enable"].exists); XCTAssertFalse(app.buttons["notices.create"].exists)
        app.navigationBars.buttons.firstMatch.tap(); tap(app, "management.notifications")
        XCTAssertTrue(app.buttons["notices.enable"].waitForExistence(timeout: 10)); XCTAssertTrue(app.buttons["notices.disable"].exists)
    }

    @MainActor func testSuspendedPushShowsStatusWithoutPermissionOrActivationControls() {
        let app = fixture(["--uitest-push-unavailable"])
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        XCTAssertFalse(springboard.alerts.firstMatch.exists)
        openSection(app, "Gestión"); tap(app, "management.notifications")
        XCTAssertTrue(app.staticTexts["notifications.suspended"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["notices.enable"].exists); XCTAssertFalse(app.buttons["notices.disable"].exists)
        attachScreen(app, name: "push-suspendido-personal-team")
        XCUIDevice.shared.press(.home); app.activate()
        XCTAssertTrue(app.staticTexts["notifications.suspended"].waitForExistence(timeout: 10))
        XCTAssertFalse(springboard.alerts.firstMatch.exists)
        openSection(app, "Itinerarios")
        tap(app, "notices.item.33333333-3333-4333-8333-333333333333")
        tap(app, "notices.pdf"); XCTAssertTrue(app.navigationBars["Itinerario PDF"].waitForExistence(timeout: 15))
    }

    @MainActor func testNotificationPermissionAppearsAfterAuthenticatedStartupWithoutOpeningItineraries() {
        let app = fixture(["--uitest-push-permission"])
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let alert = springboard.alerts.firstMatch
        XCTAssertTrue(alert.waitForExistence(timeout: 15), "El permiso debe solicitarse tras restaurar la sesión ficticia, sin abrir Itinerarios.")
        attachScreen(springboard, name: "permiso-ios-al-entrar")
        let deny = alert.buttons.matching(NSPredicate(format: "label IN %@", ["Don’t Allow", "Don't Allow", "No permitir"])).firstMatch
        XCTAssertTrue(deny.exists, springboard.debugDescription); deny.tap()
        openSection(app, "Gestión"); tap(app, "management.notifications")
        XCTAssertTrue(app.staticTexts["notifications.status"].waitForExistence(timeout: 10))
        XCUIDevice.shared.press(.home); app.activate()
        XCTAssertFalse(springboard.alerts.firstMatch.exists, "No se debe repetir un permiso rechazado al volver a primer plano.")
        attachScreen(app, name: "notificaciones-en-gestion")
    }

    @MainActor func testAlertComposerIncludesPendingJhonAndAlexWithoutSending() {
        let app=fixture(); openSection(app, "Gestión"); tap(app,"notices.alerts"); tap(app,"notices.create")
        for id in ["77777777-7777-4777-8777-777777777777","88888888-8888-4888-8888-888888888888"] {
            let recipient=app.switches["notices.recipient."+id]
            for _ in 0..<5 { if recipient.exists && recipient.isHittable { break }; app.swipeUp() }
            XCTAssertTrue(recipient.exists); XCTAssertTrue(recipient.isHittable); XCTAssertTrue(recipient.label.contains("Pendiente de activación"))
        }
        attachScreen(app,name:"alertas-jhon-alex-pendientes")
    }

    @MainActor func testManualItineraryWithAttachmentAndDeleteConfirmation() {
        let app = fixture(); openSection(app, "Gestión"); tap(app,"notices.alerts"); tap(app,"notices.create")
        app.segmentedControls["notices.editor.kind"].buttons["Itinerario"].tap()
        fill(app,"notices.editor.title","Itinerario manual ficticio"); app.textFields["notices.editor.title"].typeText("\n")
        tap(app,"notices.editor.fixture"); XCTAssertTrue(app.staticTexts["Prueba.pdf"].waitForExistence(timeout:10)); app.swipeUp(); tap(app,"notices.editor.save")
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

    @MainActor private func tapVisibleWalletControl(_ element:XCUIElement,in app:XCUIApplication) -> Bool {
        guard element.waitForExistence(timeout:5),waitFor(element,predicate:NSPredicate(format:"enabled == true"),timeout:5) else {
            XCTFail("El control de Wallet debe existir y estar habilitado.");return false
        }
        let frame=element.frame,window=app.windows.firstMatch
        guard window.exists,!frame.isEmpty,!frame.isNull,!frame.isInfinite,window.frame.contains(frame) else {
            XCTFail("El control de Wallet debe estar completamente dentro de la ventana visible.");return false
        }
        if element.isHittable {element.tap()}
        else {
            // Some SwiftUI Menu buttons have a valid enabled native frame while
            // accessibility reports hittable=false. Exercise that control's
            // own center; do not guess a coordinate elsewhere on the screen.
            print("Wallet UI: tapping visible native control \(element.identifier) at its relative center; frame=\(frame)")
            element.coordinate(withNormalizedOffset:CGVector(dx:0.5,dy:0.5)).tap()
        }
        return true
    }

    @MainActor func testBoardingWalletMenuOpensEditableFlightDetailsWithoutShowingTheCode() {
        let app=XCUIApplication()
        app.launchArguments=["--uitest-payroll","--uitest-sections=boarding","--uitest-wallet-menu"]
        app.launch()
        let menu=app.buttons["boarding.menu.boarding-fixture-0-pdf"]
        XCTAssertTrue(menu.waitForExistence(timeout:20))
        // SwiftUI exposes the Menu's identified accessibility wrapper and its
        // native button separately. Tap the actual button inside that wrapper.
        let descendant=menu.descendants(matching:.button).firstMatch
        let menuButton=descendant.exists ? descendant:menu
        guard tapVisibleWalletControl(menuButton,in:app) else {return}
        var walletAction=app.buttons["boarding.wallet.menu.boarding-fixture-0-pdf"].firstMatch
        if !walletAction.waitForExistence(timeout:3) {
            // UIKit menu actions may expose the visible label instead of the
            // SwiftUI identifier. This label is unique in the open menu.
            walletAction=app.buttons["Añadir a Apple Wallet"].firstMatch
        }
        guard tapVisibleWalletControl(walletAction,in:app) else {return}
        let passenger=app.textFields["boarding.wallet.passenger"]
        XCTAssertTrue(passenger.waitForExistence(timeout:30))
        XCTAssertTrue(waitFor(passenger,predicate:NSPredicate(format:"value CONTAINS[c] %@","Fixture"),timeout:20))
        for (id,value) in [("origin","BOG"),("destination","MDE"),("departureTime","18:45"),("boardingTime","18:05")] {
            let field=app.textFields["boarding.wallet."+id]
            for _ in 0..<6 {if field.exists && field.isHittable {break};app.swipeUp()}
            XCTAssertEqual(field.value as? String,value)
        }
        let seat=app.textFields["boarding.wallet.seat"]
        for _ in 0..<6 {if seat.exists && seat.isHittable {break};app.swipeUp()}
        XCTAssertTrue(["12A","012A"].contains(seat.value as? String ?? ""))
        XCTAssertFalse(app.images["boarding.code.image"].exists)
        XCTAssertFalse(app.navigationBars["Pase de abordar PDF"].exists)
        XCTAssertFalse(app.descendants(matching:.any)["boarding.wallet.error"].exists)
        for _ in 0..<6 {if passenger.isHittable {break};app.swipeDown()}
        for (id,value) in [("passenger","Fixture Traveller Dos"),("departureTime","19:10"),("boardingTime","18:30"),("seat","14C")] {
            let key="boarding.wallet."+id
            fill(app,key,value);XCTAssertEqual(app.textFields[key].value as? String,value)
            tap(app,"boarding.wallet.keyboard.done")
        }
        XCTAssertFalse(app.descendants(matching:.any)["boarding.wallet.error"].exists)
        attachScreen(app,name:"wallet-menu-datos-del-vuelo-editables")
        tap(app,"boarding.wallet.close")
        XCTAssertTrue(menu.waitForExistence(timeout:10));XCTAssertFalse(passenger.exists)
        tap(app,"boarding.code.boarding-fixture-0-pdf")
        XCTAssertTrue(app.images["boarding.code.image"].waitForExistence(timeout:30))
        XCTAssertFalse(app.buttons["boarding.wallet.add"].exists)
        tap(app,"boarding.code.close")
        XCTAssertTrue(menu.waitForExistence(timeout:10))
    }

    @MainActor func testBoardingCodesFullScreenMultiplePagesAndReturnToFullPDF() {
        let app=XCUIApplication();app.launchArguments=["--uitest-payroll","--uitest-boarding-code"];app.launch()
        openSection(app, "Itinerarios");tap(app,"boarding.open");tap(app,"boarding.code.boarding-fixture-0-pdf")
        XCTAssertTrue(app.images["boarding.code.image"].waitForExistence(timeout:30))
        XCTAssertTrue(app.staticTexts["1 de 2 · QR · Pág. 1"].exists)
        attachScreen(app,name:"pase-codigo-qr-ficticio")
        tap(app,"Código siguiente");XCTAssertTrue(app.staticTexts["2 de 2 · PDF417 · Pág. 2"].exists)
        XCUIDevice.shared.press(.home);app.activate()
        XCTAssertTrue(app.images["boarding.code.image"].waitForExistence(timeout:15))
        XCTAssertTrue(app.staticTexts["2 de 2 · PDF417 · Pág. 2"].exists)
        tap(app,"boarding.code.fullpass")
        XCTAssertTrue(app.navigationBars["Pase de abordar PDF"].waitForExistence(timeout:15));tap(app,"notices.pdf.close")
        tap(app,"boarding.code.boarding-fixture-0-pdf")
        XCTAssertTrue(app.images["boarding.code.image"].waitForExistence(timeout:30));tap(app,"boarding.code.close")
        XCTAssertTrue(app.buttons["notices.item.boarding-fixture-0"].waitForExistence(timeout:10))
    }

    @MainActor func testBoardingWithoutCodeOffersOriginalPDFInsteadOfAFabricatedCode() {
        let app=fixture();openSection(app, "Itinerarios");tap(app,"boarding.open");tap(app,"boarding.code.boarding-fixture-0-pdf")
        XCTAssertTrue(app.staticTexts["boarding.code.error"].waitForExistence(timeout:30));XCTAssertFalse(app.images["boarding.code.image"].exists)
        tap(app,"boarding.code.fullpass");XCTAssertTrue(app.navigationBars["Pase de abordar PDF"].waitForExistence(timeout:15))
        tap(app,"notices.pdf.close");XCTAssertTrue(app.buttons["notices.item.boarding-fixture-0"].waitForExistence(timeout:10))
    }

    @MainActor func testBoardingPassesTodayFutureHiddenHistoryAndPrivatePDF() {
        let app=fixture(); openSection(app, "Itinerarios"); tap(app,"boarding.open")
        XCTAssertTrue(app.staticTexts["Pases de abordar para hoy · 2"].waitForExistence(timeout:10))
        XCTAssertTrue(app.buttons["notices.item.boarding-fixture-0"].exists); XCTAssertFalse(app.buttons["notices.item.boarding-fixture-3"].exists)
        tap(app,"notices.item.boarding-fixture-0"); XCTAssertFalse(app.buttons["notices.delete"].exists); XCTAssertFalse(app.buttons["notices.detail.close"].exists)
        XCTAssertTrue(app.navigationBars["Pase de abordar PDF"].waitForExistence(timeout:15)); tap(app,"notices.pdf.close")
        app.swipeUp(); tap(app,"boarding.history"); XCTAssertTrue(app.buttons["notices.item.boarding-fixture-3"].waitForExistence(timeout:10)); attachScreen(app,name:"pases-historial-privado")
    }

    @MainActor func testTomorrowPassesHavePriorityWithoutTodayAndOpenPDFDirectly() {
        let app=XCUIApplication(); app.launchArguments=["--uitest-payroll","--uitest-boarding-tomorrow"]; app.launch(); openSection(app, "Itinerarios"); tap(app,"boarding.open")
        let tomorrow=app.staticTexts["Pases de abordar para mañana · 1"],today=app.staticTexts["Pases de abordar para hoy · 0"]
        XCTAssertTrue(tomorrow.waitForExistence(timeout:15)); XCTAssertTrue(today.exists); XCTAssertLessThan(tomorrow.frame.minY,today.frame.minY)
        XCTAssertTrue(app.staticTexts["Pereira → Bogota"].exists); attachScreen(app,name:"nuevo-pase-tipo-boleto"); tap(app,"notices.item.boarding-fixture-2")
        XCTAssertTrue(app.navigationBars["Pase de abordar PDF"].waitForExistence(timeout:15)); XCTAssertFalse(app.buttons["notices.detail.close"].exists); XCTAssertFalse(app.buttons["notices.delete"].exists); attachScreen(app,name:"pase-manana-pdf-directo")
    }

    @MainActor func testAccountWithoutPayrollCanReadAgendaAndAlertsButCannotAdminister() {
        let app=XCUIApplication(); app.launchArguments=["--uitest-payroll","--uitest-reader","--uitest-itineraries-only"]; app.launch()
        XCTAssertTrue(hasSection(app, "Itinerarios", timeout: 15)); XCTAssertFalse(hasSection(app, "Quincena")); XCTAssertTrue(hasSection(app, "Agenda"))
        openSection(app, "Gestión"); XCTAssertTrue(app.buttons["management.notifications"].waitForExistence(timeout:10)); XCTAssertFalse(app.buttons["management.archive"].exists); XCTAssertTrue(app.buttons["notices.alerts"].exists)
        tap(app,"notices.alerts"); XCTAssertTrue(app.navigationBars["Alertas"].waitForExistence(timeout:10)); XCTAssertFalse(app.buttons["notices.create"].exists)
        openSection(app, "Agenda"); XCTAssertTrue(app.segmentedControls["agenda.mode"].waitForExistence(timeout:15)); XCTAssertFalse(app.buttons["agenda.create"].exists); XCTAssertFalse(app.buttons["agenda.configure"].exists); attachScreen(app,name:"alex-agenda-sin-nomina")
    }

    @MainActor func testManualPrivateBoardingPassWithRecipientAndAttachment() {
        let app=fixture(); openSection(app, "Gestión"); tap(app,"notices.alerts"); tap(app,"notices.create")
        app.segmentedControls["notices.editor.kind"].buttons["Pase"].tap(); fill(app,"notices.editor.title","Pase privado manual ficticio"); app.textFields["notices.editor.title"].typeText("\n"); tap(app,"notices.editor.fixture"); XCTAssertTrue(app.staticTexts["Prueba.pdf"].waitForExistence(timeout:10),"El PDF ficticio debe quedar adjunto antes de guardar")
        app.swipeUp(); tap(app,"boarding.recipient"); app.buttons["Camilo simulado"].tap(); tap(app,"notices.editor.save")
        let item=app.buttons.matching(NSPredicate(format:"label CONTAINS %@","Pase privado manual ficticio")).firstMatch
        for _ in 0..<8 { if item.exists && item.isHittable { break }; app.swipeUp() }; XCTAssertTrue(item.waitForExistence(timeout:15)); XCTAssertTrue(item.isHittable); item.tap(); XCTAssertFalse(app.buttons["notices.delete"].exists); XCTAssertFalse(app.buttons["notices.detail.close"].exists); XCTAssertTrue(app.navigationBars["Pase de abordar PDF"].waitForExistence(timeout:15)); attachScreen(app,name:"pase-manual-pdf-privado")
    }

    @MainActor func testDeletePrivatePassFromListConfirmsAndRefreshDoesNotRestoreIt() {
        let app=fixture(); openSection(app, "Itinerarios"); tap(app,"boarding.open")
        let item=app.buttons["notices.item.boarding-fixture-0"]
        XCTAssertTrue(item.waitForExistence(timeout:15)); XCTAssertFalse(app.buttons["notices.list.delete.boarding-fixture-0"].exists); XCTAssertFalse(app.buttons["Eliminar pase de abordar"].exists); item.swipeLeft(); attachScreen(app,name:"pase-accion-deslizar"); tap(app,"Eliminar pase de abordar")
        XCTAssertTrue(app.staticTexts["¿Estás seguro de que quieres eliminar este pase de abordar?"].exists); tap(app,"notices.list.delete.cancel"); XCTAssertTrue(item.exists)
        item.press(forDuration:1.2); attachScreen(app,name:"pase-menu-mantener-pulsado"); tap(app,"Eliminar pase de abordar"); tap(app,"notices.list.delete.confirm")
        XCTAssertTrue(app.staticTexts["Pase de abordar eliminado."].waitForExistence(timeout:15)); XCTAssertFalse(item.exists)
        XCTAssertTrue(app.buttons["notices.item.boarding-fixture-1"].exists)
        app.swipeDown(); XCTAssertFalse(item.exists); tap(app,"notices.item.boarding-fixture-1")
        XCTAssertTrue(app.navigationBars["Pase de abordar PDF"].waitForExistence(timeout:15)); tap(app,"notices.pdf.close")
        app.navigationBars.buttons.firstMatch.tap(); let itinerary=app.buttons["notices.item.33333333-3333-4333-8333-333333333333"]; XCTAssertFalse(app.buttons["notices.list.delete.33333333-3333-4333-8333-333333333333"].exists); XCTAssertFalse(app.buttons["Eliminar itinerario"].exists); itinerary.swipeLeft(); tap(app,"Eliminar itinerario")
        tap(app,"notices.list.delete.cancel"); XCTAssertTrue(app.buttons["notices.item.33333333-3333-4333-8333-333333333333"].exists)
        itinerary.press(forDuration:1.2); tap(app,"Eliminar itinerario"); tap(app,"notices.list.delete.confirm")
        XCTAssertTrue(app.staticTexts["Itinerario eliminado para todo el equipo."].waitForExistence(timeout:15)); XCTAssertFalse(app.buttons["notices.item.33333333-3333-4333-8333-333333333333"].exists)
        attachScreen(app,name:"borrado-manual-pase-itinerario")
    }

    @MainActor func testExplicitReceiptAndUpdatedItineraryRequireNewConfirmation() {
        let app=fixture();openSection(app, "Itinerarios");tap(app,"notices.item.33333333-3333-4333-8333-333333333333");tap(app,"notices.confirm")
        XCTAssertTrue(app.buttons["notices.confirm"].waitForExistence(timeout:10));XCTAssertEqual(app.buttons["notices.confirm"].label,"✓ Recibido")
        tap(app,"notices.update")
        let summary=app.descendants(matching:.any).matching(identifier:"itinerary.update.summary").firstMatch
        XCTAssertTrue(summary.waitForExistence(timeout:10));summary.tap();summary.typeText("Salida a las 07:30")
        tap(app,"travel.fixture");tap(app,"itinerary.update.save")
        XCTAssertTrue(app.staticTexts["Salida a las 07:30"].waitForExistence(timeout:15));XCTAssertEqual(app.buttons["notices.confirm"].label,"Confirmar recibido")
        attachScreen(app,name:"itinerario-actualizado-confirmacion-pendiente")
        XCUIDevice.shared.press(.home);app.activate();XCTAssertTrue(app.buttons["notices.confirm"].waitForExistence(timeout:10));tap(app,"notices.confirm")
        XCTAssertEqual(app.buttons["notices.confirm"].label,"✓ Recibido")
    }
    @MainActor func testTravelExpenseWithReceiptCanBeSubmittedAndReviewed() {
        let app=fixture();openSection(app, "Gestión");tap(app,"management.expenses");tap(app,"expenses.create")
        fill(app,"expenses.concept","Taxi ficticio");fill(app,"expenses.amount","35000");tap(app,"travel.fixture");tap(app,"expenses.submit")
        XCTAssertTrue(app.staticTexts["Taxi ficticio"].waitForExistence(timeout:15));let created=app.buttons.matching(NSPredicate(format:"identifier BEGINSWITH %@","expense.")).firstMatch;XCTAssertTrue(created.waitForExistence(timeout:10));created.tap()
        XCTAssertTrue(app.staticTexts["Pendiente de revisión"].waitForExistence(timeout:10))
        tap(app,"expenses.employee");tap(app,"Música simulada");tap(app,"expenses.period");tap(app,"Quincena simulada");tap(app,"expenses.approve")
        XCTAssertTrue(app.staticTexts["Aprobado e incorporado a nómina"].waitForExistence(timeout:15));attachScreen(app,name:"gasto-con-comprobante-aprobado")
    }

    @MainActor func testPromotionalShowAndLinkedExpenseCanBeCreatedWithoutAddingPayrollPayment() {
        let app=fixture(["--uitest-commission"])
        tap(app,"period.fixture-period")
        XCTAssertTrue(app.staticTexts["Comisión de Camilo · 5%"].waitForExistence(timeout:10))
        tap(app,"Actividad");tap(app,"activity.shows");tap(app,"activity.add")
        fill(app,"editor.name","Show promocional ficticio")
        tap(app,"Listo")
        let toggle=app.switches["editor.promotional"]
        for _ in 0..<8 { if toggle.isHittable { break };app.swipeUp() }
        XCTAssertTrue(toggle.exists);XCTAssertTrue(toggle.isHittable,app.debugDescription);toggle.coordinate(withNormalizedOffset:CGVector(dx:0.9,dy:0.5)).tap()
        XCTAssertEqual(toggle.value as? String,"1");tap(app,"editor.save")
        XCTAssertTrue(app.staticTexts["Promocional"].waitForExistence(timeout:15))
        app.navigationBars.buttons.firstMatch.tap();tap(app,"activity.expenses");tap(app,"activity.add")
        XCTAssertTrue(app.buttons["editor.showId"].exists)
        fill(app,"editor.concept","Hotel de prueba vinculado");tap(app,"Listo");fill(app,"editor.amount","300000");tap(app,"editor.save")
        XCTAssertTrue(app.staticTexts["Hotel de prueba vinculado"].waitForExistence(timeout:15))
        let linked=app.descendants(matching:.any)["expense.linkedShow"].firstMatch
        XCTAssertTrue(linked.waitForExistence(timeout:10),app.debugDescription)
        XCTAssertTrue(linked.label.contains("Show promocional ficticio"),linked.label)
        attachScreen(app,name:"gasto-de-show-promocional-ficticio")
    }

    @MainActor func testReceiptStylizedMerchantConceptCanBeAppliedAndReviewed() {
        let app=fixture(["--uitest-offline-content","--uitest-reset-content"])
        openSection(app, "Gestión");tap(app,"management.expenses");tap(app,"expenses.create");tap(app,"expenses.scan");tap(app,"receipt.logoFixture")
        let concept=app.descendants(matching:.any)["receipt.concept"].firstMatch
        XCTAssertTrue(concept.waitForExistence(timeout:30));XCTAssertTrue(concept.label.contains("Frisby"),app.debugDescription)
        attachScreen(app,name:"factura-encabezado-estilizado-ficticio")
        tap(app,"receipt.apply")
        XCTAssertEqual(app.textFields["expenses.concept"].value as? String,"Frisby")
        XCTAssertEqual(app.textFields["expenses.amount"].value as? String,"47600")
        XCTAssertEqual(app.textFields["expenses.time"].value as? String,"13:45:20")
        fill(app,"expenses.concept","Frisby · almuerzo revisado")
        XCTAssertEqual(app.textFields["expenses.concept"].value as? String,"Frisby · almuerzo revisado")
    }

    @MainActor func testReceiptOCRReviewOfflineDraftRelaunchAndExplicitSubmission() {
        let app=fixture(["--uitest-offline-content","--uitest-reset-content"])
        openSection(app, "Gestión");tap(app,"management.expenses");tap(app,"expenses.create");tap(app,"expenses.scan")
        tap(app,"receipt.fixture")
        let suggested=app.descendants(matching:.any)["receipt.concept"].firstMatch
        XCTAssertTrue(suggested.waitForExistence(timeout:30),app.debugDescription)
        XCTAssertTrue(suggested.label.contains("RESTAURANTE FICTICIO JAC"),app.debugDescription)
        attachScreen(app,name:"factura-ocr-datos-sugeridos")
        tap(app,"receipt.apply")
        XCTAssertEqual(app.textFields["expenses.amount"].value as? String,"47600")
        XCTAssertEqual(app.textFields["expenses.concept"].value as? String,"RESTAURANTE FICTICIO JAC")
        XCTAssertTrue(app.buttons["expenses.kind"].exists)
        XCTAssertEqual(app.textFields["expenses.time"].value as? String,"13:45:20")
        fill(app,"expenses.concept","Almuerzo ficticio revisado")
        XCUIDevice.shared.press(.home);app.activate()
        XCTAssertEqual(app.textFields["expenses.concept"].value as? String,"Almuerzo ficticio revisado")
        tap(app,"expenses.saveDraft")
        XCTAssertTrue(app.buttons["expenses.create"].waitForExistence(timeout:10))
        XCTAssertEqual(app.buttons["expenses.create"].label,"Continuar borrador")
        XCTAssertFalse(app.staticTexts["Almuerzo ficticio revisado"].exists,"El borrador todavía no se envía")
        app.terminate();app.launchArguments=["--uitest-payroll","--uitest-offline-content","--uitest-offline"];app.launch()
        XCTAssertTrue(hasSection(app, "Gestión", timeout: 15));openSection(app, "Gestión")
        tap(app,"management.expenses");tap(app,"expenses.create")
        XCTAssertEqual(app.textFields["expenses.concept"].value as? String,"Almuerzo ficticio revisado")
        XCTAssertEqual(app.textFields["expenses.amount"].value as? String,"47600")
        XCTAssertEqual(app.textFields["expenses.time"].value as? String,"13:45:20")
        tap(app,"expenses.scan");tap(app,"receipt.fixture")
        XCTAssertTrue(app.descendants(matching:.any)["receipt.concept"].firstMatch.waitForExistence(timeout:30),"Vision también lee sin conexión")
        XCTAssertTrue(app.descendants(matching:.any)["receipt.concept"].firstMatch.label.contains("RESTAURANTE FICTICIO JAC"),app.debugDescription)
        tap(app,"Cancelar")
        tap(app,"expenses.saveDraft")
        tap(app,"expenses.create")
        let submit=app.buttons["expenses.submit"];for _ in 0..<5 { if submit.isHittable { break };app.swipeUp() }
        XCTAssertFalse(submit.isEnabled);XCTAssertTrue(app.staticTexts["Factura.jpg"].exists)
        attachScreen(app,name:"factura-borrador-sin-internet");tap(app,"expenses.saveDraft")
        app.terminate();app.launchArguments=["--uitest-payroll","--uitest-offline-content"];app.launch()
        XCTAssertTrue(hasSection(app, "Gestión", timeout: 15));openSection(app, "Gestión")
        tap(app,"management.expenses");tap(app,"expenses.create")
        fill(app,"expenses.time","25:75");tap(app,"expenses.submit")
        for _ in 0..<4 { if app.textFields["expenses.time"].isHittable { break };app.swipeDown() }
        XCTAssertTrue(app.textFields["expenses.time"].isEnabled,"Una hora inválida debe permitir corregir el borrador sin bloquearlo como enviado")
        XCTAssertTrue(app.staticTexts["Revisa la hora de factura: usa HH:mm o HH:mm:ss, por ejemplo 13:45."].exists)
        fill(app,"expenses.time","13:45:20");tap(app,"expenses.submit")
        XCTAssertTrue(app.staticTexts["Almuerzo ficticio revisado"].waitForExistence(timeout:15))
        XCTAssertEqual(app.buttons["expenses.create"].label,"Registrar gasto")
        let created=app.buttons.matching(NSPredicate(format:"identifier BEGINSWITH %@","expense.")).firstMatch;created.tap()
        let metadata=app.staticTexts.matching(NSPredicate(format:"label CONTAINS %@ AND label CONTAINS %@","Tipo de gasto: Alimentación","Hora de factura: 13:45:20")).firstMatch
        XCTAssertTrue(metadata.waitForExistence(timeout:10))
        XCTAssertTrue(app.staticTexts["Pendiente de revisión"].exists)
        XCTAssertTrue(app.buttons["Factura.jpg"].exists)
        attachScreen(app,name:"factura-ocr-enviada-a-revision")
    }

}

// Tablet-specific flows use the same intercepted backend and account contracts.
// Existing iPhone checks remain unchanged; these run only on a real iPad idiom.
final class IPadTests: XCTestCase {
    @MainActor func testAdministratorCanCancelThenDeleteFolderFromItsMenu() {
        let app=XCUIApplication();app.launchArguments=["--uitest-payroll"];app.launch()
        tap(app,"ipad.section.media")
        tap(app,"media.options.media-day");tap(app,"media.delete.folder");XCTAssertTrue(app.alerts["Eliminar carpeta"].waitForExistence(timeout:10));app.alerts.buttons["Cancelar"].tap();XCTAssertTrue(app.buttons["media.item.media-day"].exists)
        tap(app,"media.options.media-day");tap(app,"media.delete.folder");let confirm=app.alerts["Eliminar carpeta"].buttons.matching(identifier:"media.delete.confirm").firstMatch;XCTAssertTrue(confirm.waitForExistence(timeout:10));confirm.tap()
        expectation(for:NSPredicate(format:"exists == false"),evaluatedWith:app.buttons["media.item.media-day"]);waitForExpectations(timeout:20)
        XCTAssertTrue(app.staticTexts["Carpeta eliminada."].exists)
    }
    @MainActor func testPhotographerCannotDeleteFolders() {
        let app=XCUIApplication();app.launchArguments=["--uitest-payroll","--uitest-media-only"];app.launch();tap(app,"media.item.media-day");tap(app,"media.current.options");XCTAssertFalse(app.buttons["media.delete.folder"].exists)
    }

    @MainActor func testImageQualityPreferenceCanBeSelectedAndPersistsAcrossRelaunch() {
        let app=XCUIApplication();app.launchArguments=["--uitest-payroll","--uitest-media-only"];app.launch()
        tap(app,"media.current.options");tap(app,"media.quality")
        XCTAssertTrue(app.buttons["media.quality.option.0"].waitForExistence(timeout:10));XCTAssertEqual(app.buttons["media.quality.option.0"].label,"Sin compresión");tap(app,"media.quality.option.6000000")
        tap(app,"media.quality.close");app.terminate();app.launch();tap(app,"media.current.options");tap(app,"media.quality")
        let selected=app.buttons["media.quality.option.6000000"];XCTAssertTrue(selected.waitForExistence(timeout:10));XCTAssertEqual(selected.value as? String,"Seleccionado","La preferencia debe persistir al relanzar")
        tap(app,"media.quality.option.2000000");tap(app,"media.quality.close")
    }

    @MainActor func testPhotoSlideshowMovesBothWaysWithinTheSameSheet() {
        let app=XCUIApplication();app.launchArguments=["--uitest-payroll","--uitest-media-only","--uitest-media-slideshow"];app.launch()
        tap(app,"media.item.media-day");tap(app,"media.item.media-photo")
        XCTAssertTrue(app.staticTexts["media.preview.counter"].waitForExistence(timeout:15));XCTAssertEqual(app.staticTexts["media.preview.counter"].label,"1 de 2")
        tap(app,"media.preview.next");XCTAssertTrue(app.staticTexts["Segunda foto ficticia.png"].waitForExistence(timeout:15));XCTAssertEqual(app.staticTexts["media.preview.counter"].label,"2 de 2");XCTAssertFalse(app.buttons["media.preview.next"].isEnabled)
        tap(app,"media.preview.previous");XCTAssertEqual(app.staticTexts["media.preview.counter"].label,"1 de 2");XCTAssertFalse(app.buttons["media.preview.previous"].isEnabled)
        capture("ipad-fotografia-visor-anterior-siguiente");tap(app,"media.preview.close");XCTAssertTrue(app.buttons["media.item.media-photo"].exists)
    }

    @MainActor override func setUpWithError() throws {
        continueAfterFailure = false
        guard UIDevice.current.userInterfaceIdiom == .pad else { throw XCTSkip("Este recorrido verifica la presentación nativa de iPad.") }
        XCUIDevice.shared.orientation = .landscapeLeft
    }
    @MainActor override func tearDownWithError() throws { XCUIDevice.shared.orientation = .portrait }
    @MainActor private func tap(_ app: XCUIApplication, _ id: String) {
        let button = app.buttons[id]; XCTAssertTrue(button.waitForExistence(timeout: 20), id); button.tap()
    }
    @MainActor private func capture(_ name: String) { let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); attachment.name = name; attachment.lifetime = .keepAlways; add(attachment) }
    @MainActor func testTabletPhotographyLongPressSelectsAndVideosHaveDeleteAction() {
        let app = XCUIApplication(); app.launchArguments = ["--uitest-payroll", "--uitest-media-only", "--uitest-media-manager", "--uitest-media-r2"]; app.launch()
        let section = app.buttons["ipad.section.media"]; if section.waitForExistence(timeout: 10) { section.tap() }
        tap(app, "media.item.r2_media-day")
        let photo = app.buttons["media.item.r2_media-photo"], video = app.buttons["media.item.r2_media-video"]
        XCTAssertTrue(photo.waitForExistence(timeout: 15)); photo.press(forDuration: 0.7)
        XCTAssertEqual(app.staticTexts["media.selection.count"].label, "1 seleccionado")
        video.tap(); XCTAssertEqual(app.staticTexts["media.selection.count"].label, "2 seleccionados")
        tap(app, "media.selection.cancel")
        photo.tap(); XCTAssertTrue(app.descendants(matching: .any)["media.photo.document"].waitForExistence(timeout: 15)); tap(app, "media.preview.close")
        tap(app, "media.photo.options.r2_media-video")
        tap(app, "media.photo.delete")
        XCTAssertTrue(app.alerts["Eliminar video"].waitForExistence(timeout: 10))
        app.alerts["Eliminar video"].buttons["Cancelar"].tap()
        capture("ipad-photography-longpress-video-menu")
    }
    @MainActor func testTabletSidebarCalendarRotationAndCRM() {
        let app = XCUIApplication(); app.launchArguments = ["--uitest-payroll"]; app.launch()
        for id in ["crm", "payroll", "agenda", "itineraries", "media", "management"] { XCTAssertTrue(app.buttons["ipad.section." + id].waitForExistence(timeout: 20)) }
        XCTAssertFalse(app.tabBars.buttons["Quincena"].exists)
        tap(app, "ipad.section.agenda"); XCTAssertTrue(app.buttons["Hoy"].waitForExistence(timeout: 20))
        if app.frame.width >= 1300 { XCTAssertTrue(app.descendants(matching: .any)["ipad.agenda.columns"].exists) }
        let day = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "agenda.day.")).element(boundBy: 12)
        XCTAssertTrue(day.exists); let id = day.identifier
        day.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.12)).tap()
        XCTAssertEqual(day.value as? String, "Seleccionado"); capture("ipad-agenda-horizontal")
        XCUIDevice.shared.orientation = .portrait
        XCTAssertTrue(app.buttons[id].waitForExistence(timeout: 10)); XCTAssertEqual(app.buttons[id].value as? String, "Seleccionado")
        capture("ipad-agenda-vertical")
        tap(app, "ipad.section.crm"); XCTAssertTrue(app.buttons["crm.quickPayment"].waitForExistence(timeout: 20))
        tap(app, "crm.show.77777777-7777-4777-8777-777777777777"); XCTAssertTrue(app.buttons["crm.payment"].waitForExistence(timeout: 15)); capture("ipad-crm-show")
        tap(app, "ipad.section.management"); tap(app, "management.account")
        XCTAssertTrue(app.navigationBars["Mi cuenta"].waitForExistence(timeout: 10)); capture("ipad-cuenta-desde-gestion")
    }
    @MainActor func testTabletPhotographerUploadAndNativePreviewsRemainRestricted() {
        let app = XCUIApplication(); app.launchArguments = ["--uitest-payroll", "--uitest-media-only"]; app.launch()
        XCTAssertTrue(app.buttons["ipad.section.media"].waitForExistence(timeout: 20)); XCTAssertTrue(app.buttons["ipad.section.management"].exists)
        for id in ["crm", "payroll", "agenda", "itineraries"] { XCTAssertFalse(app.buttons["ipad.section." + id].exists) }
        tap(app, "media.item.media-day"); tap(app, "media.item.media-photo"); tap(app, "media.preview.close")
        tap(app, "media.item.media-video"); XCTAssertTrue(app.descendants(matching: .any)["media.video"].waitForExistence(timeout: 15)); capture("ipad-video-nativo"); tap(app, "media.preview.close")
        tap(app, "media.add"); tap(app, "media.destination.current"); tap(app, "media.fixture"); tap(app, "media.upload")
        for name in ["Foto de prueba.png", "Video de prueba.mov"] { XCTAssertTrue(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label CONTAINS %@", "media.item.", name)).firstMatch.waitForExistence(timeout: 20)) }
        capture("ipad-fotografia-subidas"); tap(app, "ipad.section.management"); tap(app, "management.account")
        XCTAssertTrue(app.navigationBars["Mi cuenta"].waitForExistence(timeout: 10)); XCTAssertFalse(app.staticTexts["Administrador de JAC"].exists)
    }
    @MainActor func testTabletItineraryPrivatePassAndAlertsUseNativeNavigation() {
        let app = XCUIApplication(); app.launchArguments = ["--uitest-payroll"]; app.launch()
        tap(app, "ipad.section.itineraries"); tap(app, "notices.item.33333333-3333-4333-8333-333333333333"); tap(app, "notices.pdf")
        XCTAssertTrue(app.navigationBars["Itinerario PDF"].waitForExistence(timeout: 15)); capture("ipad-itinerario-pdf")
        tap(app, "notices.pdf.close"); tap(app, "notices.detail.close"); tap(app, "boarding.open")
        XCTAssertTrue(app.staticTexts["Pases de abordar para hoy · 2"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["notices.item.boarding-fixture-3"].exists)
        tap(app, "notices.item.boarding-fixture-0")
        XCTAssertTrue(app.navigationBars["Pase de abordar PDF"].waitForExistence(timeout: 15)); XCTAssertFalse(app.buttons["notices.detail.close"].exists)
        capture("ipad-pase-privado-directo"); tap(app, "notices.pdf.close")
        tap(app, "ipad.section.management"); tap(app, "notices.alerts")
        XCTAssertTrue(app.buttons["notices.create"].waitForExistence(timeout: 10)); capture("ipad-alertas")
        tap(app, "ipad.section.agenda"); XCTAssertTrue(app.buttons["Hoy"].waitForExistence(timeout: 10))
    }
    @MainActor func testTabletDownloadedGalleryAndAgendaSurviveOfflineRelaunch() {
        let app = XCUIApplication(), base = ["--uitest-payroll", "--uitest-offline-content", "--uitest-fake-photos", "--uitest-media-r2"]
        app.launchArguments = base + ["--uitest-reset-content", "--uitest-reset-media"]; app.launch()
        tap(app, "ipad.section.agenda"); XCTAssertTrue(app.buttons["Hoy"].waitForExistence(timeout: 20))
        tap(app, "ipad.section.media"); tap(app, "media.options.r2_media-day"); tap(app, "media.offline"); tap(app, "media.transfer.begin")
        XCTAssertTrue(app.staticTexts["2 de 2 archivos disponibles sin conexión."].waitForExistence(timeout: 20))
        tap(app, "media.options.r2_media-day"); tap(app, "media.savePhotos"); tap(app, "media.transfer.begin")
        XCTAssertTrue(app.staticTexts["2 de 2 archivos guardados en Fotos."].waitForExistence(timeout: 20))
        app.terminate(); app.launchArguments = base + ["--uitest-offline"]; app.launch()
        XCTAssertTrue(app.buttons["ipad.section.agenda"].waitForExistence(timeout: 20)); XCTAssertFalse(app.textFields["login.username"].exists)
        tap(app, "ipad.section.agenda"); XCTAssertTrue(app.buttons["Hoy"].waitForExistence(timeout: 15))
        tap(app, "ipad.section.media"); tap(app, "media.item.r2_media-day"); tap(app, "media.item.r2_media-photo"); tap(app, "media.preview.close")
        tap(app, "media.item.r2_media-video"); XCTAssertTrue(app.descendants(matching: .any)["media.video"].waitForExistence(timeout: 15)); capture("ipad-video-sin-conexion"); tap(app, "media.preview.close")
        XCTAssertFalse(app.buttons["media.add"].exists); capture("ipad-galeria-sin-conexion")
    }
    @MainActor func testTabletEditorSurvivesBackgroundAndPrivacyCoversSheet() {
        let app = XCUIApplication(); app.launchArguments = ["--uitest-payroll"]; app.launch()
        tap(app, "period.fixture-period"); tap(app, "Actividad"); tap(app, "activity.shows"); tap(app, "activity.add")
        let field = app.textFields["editor.name"]; XCTAssertTrue(field.waitForExistence(timeout: 10)); field.tap(); field.typeText("Borrador iPad")
        let value = field.value as? String
        XCUIDevice.shared.press(.home); app.activate()
        XCTAssertTrue(field.waitForExistence(timeout: 10)); XCTAssertEqual(field.value as? String, value); XCTAssertTrue(field.isHittable)
        XCTAssertFalse(app.images["privacy.cover"].exists)
        let bottom = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.995)), middle = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        bottom.press(forDuration: 0.1, thenDragTo: middle, withVelocity: .slow, thenHoldForDuration: 1)
        XCTAssertTrue(app.images["privacy.cover"].waitForExistence(timeout: 10)); capture("ipad-privacidad-sobre-formulario")
        app.activate(); XCTAssertTrue(field.waitForExistence(timeout: 10)); XCTAssertEqual(field.value as? String, value)
    }
}
