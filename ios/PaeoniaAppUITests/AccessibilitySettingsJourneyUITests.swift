import XCTest

final class AccessibilitySettingsJourneyUITests: XCTestCase {
    @MainActor
    func testOptionalToolsCanBeEnabledIndependentlyPersistAndReturnToAutomatic() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["PAEONIA_SCENARIO"] = "local-flow-paired"
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        defer { app.terminate() }

        openSettings(app)
        choose("controls", mode: "automatic", in: app)
        choose("media", mode: "automatic", in: app)
        openDrawing(app)
        XCTAssertFalse(app.buttons["drawing.compose"].exists)
        XCTAssertFalse(app.staticTexts["widgetDrawing.description"].exists)
        capture(app, "Default drawing without additional controls")
        app.navigationBars.buttons.firstMatch.tap()

        openSettings(app)
        choose("controls", mode: "always", in: app)
        openDrawing(app)
        XCTAssertTrue(app.buttons["drawing.compose"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["widgetDrawing.description"].exists)
        capture(app, "Drawing with controls enabled and media alternatives automatic")
        app.buttons["drawing.compose"].tap()
        let addMark = app.buttons["drawing.compose.apply"]
        scrollTo(addMark, in: app)
        addMark.tap()
        let undo = app.buttons["drawing.compose.undo"]
        scrollTo(undo, in: app)
        XCTAssertTrue(undo.isEnabled)
        app.buttons["drawing.compose.done"].tap()
        app.navigationBars.buttons.firstMatch.tap()

        openSettings(app)
        choose("media", mode: "always", in: app)
        openDrawing(app)
        XCTAssertTrue(app.staticTexts["widgetDrawing.description"].waitForExistence(timeout: 5))
        app.terminate()
        app.launch()
        openDrawing(app)
        XCTAssertTrue(app.buttons["drawing.compose"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["widgetDrawing.description"].exists)
        app.navigationBars.buttons.firstMatch.tap()

        openSettings(app)
        choose("controls", mode: "automatic", in: app)
        choose("media", mode: "automatic", in: app)
        openDrawing(app)
        XCTAssertFalse(app.buttons["drawing.compose"].exists)
        XCTAssertFalse(app.staticTexts["widgetDrawing.description"].exists)
        capture(app, "Drawing after restoring automatic presentation")
        app.terminate()
        app.launchEnvironment["PAEONIA_SCENARIO"] = "dots-and-boxes-extra-turn"
        app.launch()
        XCTAssertTrue(app.descendants(matching: .any)["dotsAndBoxes.box.0"].firstMatch
            .waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["games.board.controls"].exists)
        capture(app, "Default board without the additional controls button")
    }

    @MainActor
    private func openSettings(_ app: XCUIApplication) {
        let tabs = app.tabBars.firstMatch
        XCTAssertTrue(tabs.waitForExistence(timeout: 10))
        tabs.buttons.element(boundBy: tabs.buttons.count - 1).tap()
        let controls = app.buttons["settings.accessibility.controls"]
        if controls.exists { return }
        let row = app.buttons["settings.accessibility"]
        scrollTo(row, in: app)
        row.tap()
        XCTAssertTrue(controls.waitForExistence(timeout: 5))
    }

    @MainActor
    private func choose(_ preference: String, mode: String, in app: XCUIApplication) {
        let picker = app.buttons["settings.accessibility.\(preference)"]
        scrollTo(picker, in: app)
        picker.tap()
        let option = app.buttons["settings.accessibility.\(preference).\(mode)"]
        XCTAssertTrue(option.waitForExistence(timeout: 5))
        option.tap()
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
    private func scrollTo(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<12 where !element.exists || !element.isHittable {
            if element.exists && element.frame.midY < app.windows.firstMatch.frame.midY { app.swipeDown() }
            else { app.swipeUp() }
        }
        XCTAssertTrue(element.isHittable)
    }

    @MainActor
    private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
