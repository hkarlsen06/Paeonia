import XCTest

final class WidgetHistoryDescriptionUITests: XCTestCase {
    @MainActor
    func testOwnDescriptionCanBeCorrectedReopenedCancelledAndClearedInHistory() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-paeonia-scenario", "widget-history-populated",
                               "-paeonia-scenario-hide-controls", "YES",
                               "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        defer { app.terminate() }
        let edit = app.buttons["media.alternative.edit"].firstMatch
        scrollTo(edit, app: app)
        edit.tap()
        let field = app.descendants(matching: .any)["media.alternative.text"].firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText("A sun above two hills")
        app.buttons["media.alternative.save"].tap()
        XCTAssertTrue(app.staticTexts["A sun above two hills"].waitForExistence(timeout: 5))
        scrollTo(edit, app: app)
        edit.tap()
        XCTAssertEqual(field.value as? String, "A sun above two hills")
        app.buttons["media.alternative.cancel"].tap()
        scrollTo(edit, app: app)
        edit.tap()
        let clear = app.buttons["media.alternative.clear"]
        scrollTo(clear, app: app)
        clear.tap()
        app.buttons["media.alternative.save"].tap()
        scrollTo(edit, app: app)
        edit.tap()
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        // Reopening resets the Form scroll position. Find the row before reading its state.
        scrollTo(clear, app: app)
        XCTAssertFalse(clear.isEnabled)
        app.buttons["media.alternative.cancel"].tap()
    }

    @MainActor
    private func scrollTo(_ element: XCUIElement, app: XCUIApplication) {
        for _ in 0..<20 where !element.exists || !element.isHittable {
            if element.exists && element.frame.midY < app.windows.firstMatch.frame.midY {
                app.swipeDown()
            } else {
                app.swipeUp()
            }
        }
        XCTAssertTrue(element.isHittable)
    }
}
