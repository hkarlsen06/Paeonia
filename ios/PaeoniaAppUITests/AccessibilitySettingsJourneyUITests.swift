import XCTest

final class AccessibilitySettingsJourneyUITests: XCTestCase {
    @MainActor
    func testOptionalToolsCanBeTurnedOnIndependentlyPersistAndTurnOff() throws {
        continueAfterFailure = false
        // This journey changes both preferences repeatedly and verifies them across app relaunches.
        executionTimeAllowance = 240
        let app = XCUIApplication()
        app.launchEnvironment["PAEONIA_SCENARIO"] = "local-flow-paired"
        app.launchArguments = [
            "-AppleLanguages", "(en)", "-AppleLocale", "en_US",
            "-paeonia-scenario-hide-controls", "YES",
            "-paeonia-scenario-assistive-technology", "none",
        ]
        app.launch()
        defer { app.terminate() }

        openSettings(app)
        set("controls", isOn: false, in: app)
        set("media", isOn: false, in: app)
        openDrawing(app)
        XCTAssertFalse(app.buttons["drawing.compose"].exists)
        XCTAssertFalse(app.staticTexts["widgetDrawing.description"].exists)
        capture(app, "Default drawing without additional controls")
        app.navigationBars.buttons.firstMatch.tap()

        openSettings(app)
        set("media", isOn: true, in: app)
        openDrawing(app)
        XCTAssertFalse(app.buttons["drawing.compose"].exists)
        let editDescription = app.buttons["widgetDrawing.description.edit"]
        XCTAssertTrue(editDescription.waitForExistence(timeout: 5))
        scrollTo(editDescription, in: app)
        editDescription.tap()
        let field = app.descendants(matching: .any)["widgetDrawing.description.text"].firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText("A small sun")
        app.buttons["widgetDrawing.description.done"].tap()
        XCTAssertEqual(app.staticTexts["widgetDrawing.description"].label, "A small sun")
        capture(app, "Descriptions enabled without shape controls")
        app.navigationBars.buttons.firstMatch.tap()

        openSettings(app)
        set("media", isOn: false, in: app)
        set("controls", isOn: true, in: app)
        openDrawing(app)
        XCTAssertTrue(app.buttons["drawing.compose"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["widgetDrawing.description"].exists)
        capture(app, "Drawing with controls enabled and media alternatives automatic")
        let compose = app.buttons["drawing.compose"]
        scrollTo(compose, in: app)
        compose.tap()
        let addMark = app.buttons["drawing.compose.apply"]
        scrollTo(addMark, in: app)
        addMark.tap()
        let undo = app.buttons["drawing.compose.undo"]
        scrollTo(undo, in: app)
        XCTAssertTrue(undo.isEnabled)
        app.buttons["drawing.compose.done"].tap()
        app.navigationBars.buttons.firstMatch.tap()

        openSettings(app)
        set("media", isOn: true, in: app)
        openDrawing(app)
        XCTAssertTrue(app.staticTexts["widgetDrawing.description"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["widgetDrawing.description"].label, "A small sun",
                       "Hiding the field and editing shapes must retain the authored description")
        app.terminate()
        app.launch()
        openDrawing(app)
        XCTAssertTrue(app.buttons["drawing.compose"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["widgetDrawing.description"].exists)
        app.navigationBars.buttons.firstMatch.tap()

        openSettings(app)
        set("controls", isOn: false, in: app)
        set("media", isOn: false, in: app)
        openDrawing(app)
        XCTAssertFalse(app.buttons["drawing.compose"].exists)
        XCTAssertFalse(app.staticTexts["widgetDrawing.description"].exists)
        capture(app, "Drawing after restoring automatic presentation")
        app.terminate()
        app.launchEnvironment["PAEONIA_SCENARIO"] = "dots-and-boxes-extra-turn"
        app.launch()
        let tutorial = app.buttons["games.tutorial.next"]
        for _ in 0..<3 where tutorial.waitForExistence(timeout: 1) { tutorial.tap() }
        XCTAssertFalse(tutorial.exists)
        XCTAssertTrue(app.descendants(matching: .any)["dotsAndBoxes.box.0"].firstMatch
            .waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["games.board.controls"].exists)
        capture(app, "Default board without the additional controls button")
    }

    @MainActor
    func testAutomaticShowsToolsForASimulatedActiveAssistiveTechnology() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["PAEONIA_SCENARIO"] = "widget-drawing"
        app.launchArguments = [
            "-paeonia-scenario-hide-controls", "YES",
            "-paeonia-scenario-assistive-technology", "active",
            "-accessibility.alwaysShowControls", "NO", "-accessibility.alwaysShowMediaAlternatives", "NO",
            "-AppleLanguages", "(en)", "-AppleLocale", "en_US",
        ]
        app.launch()
        defer { app.terminate() }
        XCTAssertTrue(app.buttons["drawing.compose"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["widgetDrawing.description.edit"].exists)
        capture(app, "Automatic with a simulated active assistive technology")
    }

    @MainActor
    private func openSettings(_ app: XCUIApplication) {
        let tabs = app.tabBars.firstMatch
        XCTAssertTrue(tabs.waitForExistence(timeout: 10))
        tabs.buttons.element(boundBy: tabs.buttons.count - 1).tap()
        let page = app.descendants(matching: .any)["settings.accessibility.form"].firstMatch
        if page.exists { return }
        let row = app.buttons["settings.accessibility"]
        scrollTo(row, in: app)
        row.tap()
        XCTAssertTrue(page.waitForExistence(timeout: 5))
    }

    @MainActor
    private func set(_ preference: String, isOn: Bool, in app: XCUIApplication) {
        let toggle = app.switches["settings.accessibility.\(preference)"]
        scrollTo(toggle, in: app)
        if (toggle.value as? String == "1") != isOn {
            toggle.switches.firstMatch.tap()
        }
        XCTAssertEqual(toggle.value as? String, isOn ? "1" : "0")
    }

    @MainActor
    private func openDrawing(_ app: XCUIApplication) {
        app.tabBars.firstMatch.buttons.element(boundBy: 0).tap()
        let drawing = app.buttons["home.widgetDrawing"]
        scrollTo(drawing, in: app)
        drawing.tap()
        XCTAssertTrue(app.buttons["widgetDrawing.undo"].waitForExistence(timeout: 5))
    }

    @MainActor
    private func scrollTo(_ element: XCUIElement, in app: XCUIApplication, scrollsDown: Bool = true) {
        let viewport = gameJourneyViewport(in: app)
        let scrollView = app.scrollViews.firstMatch
        let collection = app.collectionViews.firstMatch
        let container = scrollView.exists ? scrollView : collection.exists ? collection : app
        for _ in 0..<12 {
            // Native Form rows can report hittable while their tap point is below the tab bar.
            if element.exists && element.isHittable,
               viewport.contains(CGPoint(x: element.frame.midX, y: element.frame.midY)) { return }
            // Form unloads offscreen rows. Use their known order until they reappear.
            let goesUp = element.exists ? element.frame.midY > viewport.midY : scrollsDown
            // Keep scroll gestures outside PencilKit when this helper visits the drawing.
            let start = container.coordinate(withNormalizedOffset: CGVector(dx: 0.98, dy: goesUp ? 0.8 : 0.2))
            let end = container.coordinate(withNormalizedOffset: CGVector(dx: 0.98, dy: goesUp ? 0.2 : 0.8))
            start.press(forDuration: 0.01, thenDragTo: end)
        }
        XCTAssertTrue(element.isHittable)
        XCTAssertTrue(viewport.contains(CGPoint(x: element.frame.midX, y: element.frame.midY)))
    }

    @MainActor
    private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
