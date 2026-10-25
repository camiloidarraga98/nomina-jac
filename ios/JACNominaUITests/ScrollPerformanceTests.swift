import XCTest

final class ScrollPerformanceTests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    @MainActor func testWarmPhotoAndBoardingListsKeepResponsiveScrolling() {
        let app = launch()
        openSection("media", app: app)
        let folder = app.buttons["media.item.r2_media-day"]
        XCTAssertTrue(folder.waitForExistence(timeout: 15)); folder.tap()
        let photos = app.scrollViews["media.gallery.scroll"]
        XCTAssertTrue(photos.waitForExistence(timeout: 10))
        let firstPhoto = app.buttons["media.item.r2_media-scroll-0"]
        XCTAssertTrue(firstPhoto.waitForExistence(timeout: 15))
        warmList(photos, first: firstPhoto, last: app.buttons["media.item.r2_media-scroll-79"])

        openSection("boarding", app: app)
        let passes = app.collectionViews["notices.list"]
        XCTAssertTrue(passes.waitForExistence(timeout: 15))
        let firstPass = app.buttons["notices.item.boarding-scroll-0"]
        XCTAssertTrue(firstPass.waitForExistence(timeout: 15))
        XCTAssertEqual(app.staticTexts["boarding.card.seat.boarding-scroll-0-pdf"].label, "1A")
        warmBoardingList(passes, first: firstPass, app: app)

        var cleanPhotoWindows = 0, cleanPassWindows = 0
        let options = XCTMeasureOptions(); options.iterationCount = 4
        // This records actual system scroll/deceleration signposts. There is
        // deliberately no device-dependent milliseconds/FPS pass threshold.
        measure(metrics: [XCTOSSignpostMetric.scrollDecelerationMetric], options: options) {
            openSection("media", app: app)
            XCTAssertEqual(folder.value as? String, "Abierta", "Returning preserves the expanded folder.")
            let photoBefore = settledSnapshot(app)
            photos.swipeUp(); XCTAssertFalse(firstPhoto.isHittable)
            photos.swipeDown()
            let photoAfter = snapshot(app)
            if verifyWarmWindow(photoBefore, photoAfter, name: "80-photo list") { cleanPhotoWindows += 1 }

            openSection("boarding", app: app)
            let passBefore = settledSnapshot(app)
            let row = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "notices.item.boarding-scroll-")).allElementsBoundByIndex.first(where: \.isHittable)
            let passY = row?.frame.minY
            passes.swipeUp()
            XCTAssertNotNil(row)
            if let row, let passY { XCTAssertTrue(!row.isHittable || abs(row.frame.minY - passY) > 4, "The actual list must move during scrolling.") }
            passes.swipeDown()
            if verifyWarmWindow(passBefore, snapshot(app), name: "40-pass list") { cleanPassWindows += 1 }
        }
        XCTAssertGreaterThan(cleanPhotoWindows, 0, "At least one fully idle photo interval must enforce the zero-I/O budget.")
        XCTAssertGreaterThan(cleanPassWindows, 0, "At least one fully idle boarding interval must enforce the zero-I/O budget.")
        attach(app, name: "scroll-warm-40-pases")
        openSection("media", app: app); attach(app, name: "scroll-warm-80-fotos")
    }

    @MainActor func testHiddenSectionsSuspendPollingAndPrefetchWhileSidebarScrolls() {
        let app = launch(extra: ["--uitest-scroll-sidebar", "--uitest-scroll-slow-thumbnails"])
        openSection("boarding", app: app)
        XCTAssertTrue(app.staticTexts["boarding.card.seat.boarding-scroll-0-pdf"].waitForExistence(timeout: 15))
        openSection("itineraries", app: app)
        XCTAssertTrue(app.navigationBars["Itinerarios"].waitForExistence(timeout: 15))
        openSection("media", app: app)
        let folder = app.buttons["media.item.r2_media-day"]
        XCTAssertTrue(folder.waitForExistence(timeout: 15)); folder.tap()
        XCTAssertTrue(app.buttons["media.item.r2_media-scroll-0"].waitForExistence(timeout: 15))
        showMenu(app)
        let sidebar = app.scrollViews["phone.sidebar.scroll"]
        XCTAssertTrue(sidebar.waitForExistence(timeout: 10))
        let agenda = app.buttons["phone.section.agenda"], management = app.buttons["phone.section.management"]
        XCTAssertGreaterThan(management.frame.maxY - agenda.frame.minY, sidebar.frame.height, "The large-text fixture must make the sidebar genuinely scrollable.")
        for batch in 0..<4 {
            // Section navigation deliberately retains this scroll position.
            // Opening Photography may therefore leave the drawer at its end.
            // Start every measured upward drag from an actual top anchor.
            for _ in 0..<6 { if agenda.isHittable && agenda.frame.minY >= sidebar.frame.minY { break }; sidebar.swipeDown() }
            XCTAssertTrue(agenda.isHittable)
            XCTAssertGreaterThanOrEqual(agenda.frame.minY, sidebar.frame.minY, "The Agenda anchor must be visible before a vertical batch.")
            let before = agenda.frame.minY
            sidebar.swipeUp()
            XCTAssertLessThan(agenda.frame.minY, before - 4, "Vertical sidebar batch \(batch + 1) must move content.")
            XCTAssertTrue(menuVisible(app), "A vertical drag must not dismiss the sidebar.")
            sidebar.swipeDown()
            XCTAssertTrue(menuVisible(app))
        }
        let before = settledSnapshot(app)
        XCTAssertGreaterThan(before["requests.thumbnails", default: 0], 0, "The folder starts downloading its thumbnails on opening.")
        XCTAssertLessThan(before["requests.thumbnails", default: 0], 80, "Opening the menu must interrupt the still-running producer.")
        let elapsed = expectation(description: "Wait through the real 30-second automatic refresh interval")
        DispatchQueue.main.asyncAfter(deadline: .now() + 31) { elapsed.fulfill() }
        wait(for: [elapsed], timeout: 35)
        let after = snapshot(app)
        for feed in ["calendar", "media", "boarding", "notices", "music", "thumbnails"] {
            XCTAssertEqual(after["requests." + feed, default: 0], before["requests." + feed, default: 0], "Hidden \(feed) must perform zero requests over the actual polling interval.")
        }
        XCTAssertTrue(menuVisible(app)); attach(app, name: "sidebar-vertical-4-batches-polling-pausado")
        app.buttons["phone.menu.close"].tap()
        XCTAssertEqual(folder.value as? String, "Abierta", "Pausing retains the gallery's expanded folder and items.")
        XCTAssertTrue(app.buttons["media.item.r2_media-scroll-0"].waitForExistence(timeout: 10))
    }

    @MainActor private func launch(extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--uitest-payroll", "--uitest-media-r2", "--uitest-scroll-performance"] + extra
        app.launch()
        XCTAssertTrue(app.navigationBars["Agenda"].waitForExistence(timeout: 20))
        return app
    }
    @MainActor private func menuVisible(_ app: XCUIApplication) -> Bool {
        let close = app.buttons["phone.menu.close"]
        return close.exists && app.windows.firstMatch.frame.contains(close.frame)
    }
    @MainActor private func showMenu(_ app: XCUIApplication) {
        if menuVisible(app) { return }
        let button = app.buttons["phone.menu.open"]
        XCTAssertTrue(button.waitForExistence(timeout: 10)); XCTAssertTrue(button.isEnabled)
        let wrapper = app.navigationBars.descendants(matching: .other).matching(identifier: "phone.menu.open").firstMatch
        let screen = app.windows.firstMatch.frame
        let wrapperVisible = wrapper.exists && wrapper.frame.width >= 44 && wrapper.frame.height >= 44 && screen.contains(wrapper.frame)
        let target = wrapperVisible ? wrapper : button
        XCTAssertTrue(screen.contains(target.frame)); XCTAssertGreaterThanOrEqual(target.frame.height, 44)
        target.coordinate(withNormalizedOffset: CGVector(dx: 0, dy: 1)).withOffset(CGVector(dx: 22, dy: -22)).tap()
        let visible = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in self.menuVisible(app) }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [visible], timeout: 5), .completed)
    }
    @MainActor private func openSection(_ id: String, app: XCUIApplication) {
        showMenu(app)
        let button = app.buttons["phone.section." + id], sidebar = app.scrollViews["phone.sidebar.scroll"]
        XCTAssertTrue(button.waitForExistence(timeout: 5))
        for _ in 0..<6 { if button.isHittable { break }; sidebar.swipeUp() }
        if !button.isHittable { for _ in 0..<6 { if button.isHittable { break }; sidebar.swipeDown() } }
        XCTAssertTrue(button.isHittable); button.tap()
        let hidden = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in !self.menuVisible(app) }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [hidden], timeout: 5), .completed)
    }
    @MainActor private func warmList(_ scroll: XCUIElement, first: XCUIElement, last: XCUIElement) {
        for _ in 0..<32 { if last.exists && last.isHittable { break }; scroll.swipeUp() }
        XCTAssertTrue(last.exists && last.isHittable, "The full fixture must be reachable by real scrolling.")
        for _ in 0..<32 { if first.exists && first.isHittable { break }; scroll.swipeDown() }
        XCTAssertTrue(first.exists && first.isHittable)
    }
    @MainActor private func warmBoardingList(_ scroll: XCUIElement, first: XCUIElement, app: XCUIApplication) {
        let prefix = "boarding.card.seat.boarding-scroll-"
        let expected = Set((0..<40).map { prefix + "\($0)-pdf" })
        let readySeats = app.staticTexts.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label MATCHES %@", prefix, "[1-9][0-9]*A"))
        var warmed = Set<String>()
        for _ in 0..<64 {
            // One filtered accessibility query per viewport: the actual seat
            // value appears only after this card's authorised load completes.
            // An arbitrary final fixture ID does not prove all 40 were read.
            warmed.formUnion(readySeats.allElementsBoundByIndex.map(\.identifier))
            if warmed.isSuperset(of: expected) { break }
            let start = scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.8))
            let end = scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.4))
            start.press(forDuration: 0.05, thenDragTo: end, withVelocity: XCUIGestureVelocity(rawValue: 500), thenHoldForDuration: 0.15)
        }
        print("JAC boarding warm-up ready card IDs: \(warmed.sorted())")
        XCTAssertTrue(warmed.isSuperset(of: expected), "Every one of the 40 seat values must be ready before measuring warm rendering. Missing: \(expected.subtracting(warmed).sorted())")
        for _ in 0..<32 { if first.exists && first.isHittable { break }; scroll.swipeDown() }
        XCTAssertTrue(first.exists && first.isHittable)
    }
    @MainActor private func snapshot(_ app: XCUIApplication) -> [String: Int] {
        let control = app.buttons["debug.scroll.snapshot"]
        XCTAssertTrue(control.waitForExistence(timeout: 10)); control.tap()
        guard let text = control.value as? String, let data = text.data(using: .utf8), let values = try? JSONSerialization.jsonObject(with: data) as? [String: Int] else {
            XCTFail("The opt-in probe must expose real aggregate counters."); return [:]
        }
        return values
    }
    @MainActor private func settledSnapshot(_ app: XCUIApplication) -> [String: Int] {
        var previous = snapshot(app)
        for _ in 0..<5 {
            let current = snapshot(app)
            if current.filter({ $0.key != "sample" }) == previous.filter({ $0.key != "sample" }) { return current }
            previous = current
        }
        XCTFail("Counters must settle after warming before measuring rendering.")
        return previous
    }
    @MainActor private func verifyWarmWindow(_ before: [String: Int], _ after: [String: Int], name: String) -> Bool {
        // The independent global session revalidation may start during a
        // sample. Record that interval, but do not misattribute its Keychain
        // validation to rendering; the deterministic core tests cover all 40
        // warmed cards through 500 render loops without any network activity.
        let requests = after.filter { $0.key.hasPrefix("requests.") }.contains { $0.value != before[$0.key, default: 0] }
        print("JAC scroll interval \(name): before=\(before) after=\(after) noNewRequests=\(!requests)")
        for operation in ["diskRead", "diskWrite", "keyDerivation", "jsonDecode", "jsonEncode"] {
            XCTAssertEqual(after["main." + operation, default: 0], before["main." + operation, default: 0], "\(name): warmed scrolling must not do \(operation) on the main thread.")
        }
        if !requests {
            XCTAssertEqual(after["main.expensive", default: 0], before["main.expensive", default: 0], "\(name): a warmed idle interval has a zero main-thread I/O budget.")
        }
        return !requests
    }
    @MainActor private func attach(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot()); attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}
