import XCTest

final class DrawingCompositionUITests: XCTestCase {
    @MainActor
    func testNativeControlsCreateADrawingWithoutCanvasGestures() {
        let app = XCUIApplication()
        app.launchEnvironment["PAEONIA_SCENARIO"] = "widget-drawing"
        app.launchArguments = [
            "-paeonia-scenario-hide-controls", "YES", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"
        ]
        app.launch()
        let compose = app.buttons["drawing.compose"]
        XCTAssertTrue(compose.waitForExistence(timeout: 10))
        compose.tap()
        let add = app.buttons["drawing.compose.apply"]
        for _ in 0..<4 where !add.exists || !add.isHittable { app.swipeUp() }
        XCTAssertTrue(add.waitForExistence(timeout: 5))
        add.tap()
        let undo = app.buttons["drawing.compose.undo"]
        scrollTo(undo, in: app)
        XCTAssertTrue(undo.isEnabled)
        let description = app.descendants(matching: .any)["drawing.description"].firstMatch
        scrollTo(description, in: app)
        description.tap()
        description.typeText("A circle like the sun")
        let keyboardDone = app.buttons.matching(NSPredicate(
            format: "label == %@ AND identifier != %@", "Done", "drawing.compose.done"
        )).firstMatch
        if keyboardDone.exists { keyboardDone.tap() }
        scrollTo(undo, in: app)
        XCTAssertTrue(undo.isEnabled, "Typing a description must preserve the shape editing history")
        app.buttons["drawing.compose.done"].tap()
        XCTAssertTrue(app.buttons["widgetDrawing.send"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["widgetDrawing.send"].isEnabled)
    }
    @MainActor
    private func scrollTo(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<14 where !element.exists || !element.isHittable {
            if element.exists && element.frame.midY < app.windows.firstMatch.frame.midY {
                app.swipeDown()
            } else {
                app.swipeUp()
            }
        }
        XCTAssertTrue(element.isHittable)
    }
}
