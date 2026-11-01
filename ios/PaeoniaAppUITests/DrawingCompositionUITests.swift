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
        XCTAssertTrue(app.buttons["drawing.compose.undo"].isEnabled)
        let description = app.descendants(matching: .any)["drawing.description"].firstMatch
        if !description.isHittable { app.swipeUp() }
        description.tap()
        description.typeText("A circle like the sun")
        let keyboardDone = app.buttons.matching(NSPredicate(
            format: "label == %@ AND identifier != %@", "Done", "drawing.compose.done"
        )).firstMatch
        if keyboardDone.exists { keyboardDone.tap() }
        let undo = app.buttons["drawing.compose.undo"]
        if !undo.isHittable { app.swipeDown() }
        XCTAssertTrue(undo.isEnabled, "Typing a description must preserve the shape editing history")
        app.buttons["drawing.compose.done"].tap()
        XCTAssertTrue(app.buttons["widgetDrawing.send"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["widgetDrawing.send"].isEnabled)
    }
}
