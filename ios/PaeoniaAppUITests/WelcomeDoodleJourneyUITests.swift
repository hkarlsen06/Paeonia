import XCTest

/// A doodle on the welcome screen's widget comes along to the first drawing, run
/// through the real root in the fresh local flow: doodle on the widget, Start our
/// space, pick the date, and the drawing step opens with the doodle on its canvas,
/// where undo takes it off like any stroke.
final class WelcomeDoodleJourneyUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testWelcomeDoodleCarriesIntoTheFirstDrawingAndUndoes() throws {
        let app = XCUIApplication()
        app.launchEnvironment["PAEONIA_SCENARIO"] = "local-flow-fresh"
        app.launch()

        let tile = app.descendants(matching: .any)["welcome.doodle"]
        XCTAssertTrue(tile.waitForExistence(timeout: 10))
        // The canvas is the tile's upper part, above the name and time.
        tile.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.25))
            .press(forDuration: 0.05, thenDragTo: tile.coordinate(withNormalizedOffset: CGVector(dx: 0.7, dy: 0.6)))
        attachScreenshot(app, named: "welcome-egg")

        app.buttons["welcome.start"].tap()

        // Continue saves the date and plays the days count, which moves on by itself.
        let continueDate = app.buttons["welcome.startDate.continue"]
        XCTAssertTrue(continueDate.waitForExistence(timeout: 5))
        continueDate.tap()

        let canvas = app.otherElements["widgetDrawing.canvas"].firstMatch
        XCTAssertTrue(canvas.waitForExistence(timeout: 10))
        let undo = app.buttons["widgetDrawing.undo"]
        XCTAssertTrue(undo.waitForExistence(timeout: 5))
        XCTAssertTrue(undo.isEnabled, "The doodle should be on the canvas as a stroke undo can take off")
        attachScreenshot(app, named: "welcome-egg-carried")

        undo.tap()
        XCTAssertFalse(undo.isEnabled, "Undo should take the doodle's one stroke off")
    }

    @MainActor
    func testWelcomeDoodleSurvivesTextSizeReflowAndAnotherStroke() throws {
        try SimulatorTextSizeSettings(testCase: self).withSize(.standard) {
            let app = XCUIApplication()
            app.launchEnvironment["PAEONIA_SCENARIO"] = "local-flow-fresh"
            app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
            app.launch()
            defer { app.terminate() }
            let tile = app.descendants(matching: .any)["welcome.doodle"].firstMatch
            XCTAssertTrue(tile.waitForExistence(timeout: 10))
            trace(on: tile)
            try SimulatorTextSizeSettings(testCase: self).growToLargestAccessibility()
            app.activate()
            XCTAssertTrue(tile.waitForExistence(timeout: 10))
            trace(on: tile)
            let start = app.buttons["welcome.start"]
            scrollTo(start, in: app)
            start.tap()
            let date = app.buttons["welcome.startDate.continue"]
            XCTAssertTrue(date.waitForExistence(timeout: 5))
            scrollTo(date, in: app)
            date.tap()
            let compose = app.buttons["drawing.compose"]
            XCTAssertTrue(compose.waitForExistence(timeout: 15))
            scrollTo(compose, in: app)
            compose.tap()
            let secondMark = app.staticTexts["drawing.geometry.mark.1"]
            scrollTo(secondMark, in: app)
            XCTAssertTrue(app.staticTexts["drawing.geometry.mark.0"].exists)
            XCTAssertTrue(secondMark.exists, "Both strokes must reach the first drawing after reflow")
            attachScreenshot(app, named: "welcome-two-strokes-after-AX5-reflow")
        }
    }

    @MainActor
    func testWelcomeShapeCreationCarriesIntoTheFirstDrawingWithoutTracing() throws {
        try SimulatorTextSizeSettings(testCase: self).withSize(.standard) {
            let app = XCUIApplication()
            app.launchEnvironment["PAEONIA_SCENARIO"] = "local-flow-fresh"
            app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
            app.launchWithExtraAccessibilityTools()
            defer { app.terminate() }
            let compose = app.buttons["drawing.compose"]
            XCTAssertTrue(compose.waitForExistence(timeout: 10))
            scrollTo(compose, in: app)
            compose.tap()
            let add = app.buttons["drawing.compose.apply"]
            scrollTo(add, in: app)
            add.tap()
            app.buttons["drawing.compose.done"].tap()
            let start = app.buttons["welcome.start"]
            scrollTo(start, in: app)
            start.tap()
            let date = app.buttons["welcome.startDate.continue"]
            XCTAssertTrue(date.waitForExistence(timeout: 5))
            scrollTo(date, in: app)
            date.tap()
            XCTAssertTrue(compose.waitForExistence(timeout: 15))
            scrollTo(compose, in: app)
            compose.tap()
            let mark = app.staticTexts["drawing.geometry.mark.0"]
            scrollTo(mark, in: app)
            XCTAssertTrue(mark.exists)
            attachScreenshot(app, named: "welcome-native-shape-carried")
        }
    }

    @MainActor
    private func trace(on tile: XCUIElement) {
        tile.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.25))
            .press(forDuration: 0.05, thenDragTo: tile.coordinate(withNormalizedOffset: CGVector(dx: 0.7, dy: 0.6)))
    }

    @MainActor
    private func scrollTo(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<14 where !element.exists || !element.isHittable { app.swipeUp() }
        XCTAssertTrue(element.isHittable)
    }

    /// Kept with the test result, so the doodle can be checked by eye.
    @MainActor
    private func attachScreenshot(_ app: XCUIApplication, named name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
