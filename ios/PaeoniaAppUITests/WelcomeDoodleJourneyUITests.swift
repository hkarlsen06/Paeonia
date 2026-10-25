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

    /// Kept with the test result, so the doodle can be checked by eye.
    @MainActor
    private func attachScreenshot(_ app: XCUIApplication, named name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
