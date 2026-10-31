import XCTest

/// Production game views and their real draft/outbox logic. This does not run assistive technology.
final class GameDrawingDescriptionUITests: XCTestCase {
    @MainActor
    func testDescriptionsRemainEditableAcrossTheirSheetAndTravelWithNativeDrawingCreation() {
        continueAfterFailure = false
        for scenario in ["draw-drawing", "corpse-draw-head"] {
            let app = XCUIApplication()
            app.launchArguments = ["-paeonia-scenario", scenario, "-paeonia-scenario-hide-controls", "YES",
                                   "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
            app.launch()
            let tutorial = app.buttons["games.tutorial.next"]
            for _ in 0..<3 where tutorial.waitForExistence(timeout: 1) { tutorial.tap() }
            let open = app.buttons["game.drawing.description.open"]
            scrollTo(open, in: app)
            open.tap()
            let field = app.descendants(matching: .any)["game.drawing.description.text"].firstMatch
            XCTAssertTrue(field.waitForExistence(timeout: 5))
            field.tap()
            field.typeText("A red circle above a short line.")
            app.buttons["game.drawing.description.done"].tap()
            scrollTo(open, in: app)
            open.tap()
            XCTAssertEqual(field.value as? String, "A red circle above a short line.")
            app.buttons["game.drawing.description.done"].tap()

            let compose = app.buttons["drawing.compose"]
            scrollTo(compose, in: app)
            compose.tap()
            let add = app.buttons["drawing.compose.apply"]
            scrollTo(add, in: app)
            add.tap()
            app.buttons["drawing.compose.done"].tap()
            let send = app.buttons[scenario == "draw-drawing" ? "draw.done" : "corpse.done"]
            scrollTo(send, in: app)
            XCTAssertTrue(send.isEnabled)
            send.tap()
            let sent = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: send)
            XCTAssertEqual(XCTWaiter.wait(for: [sent], timeout: 5), .completed)
            if scenario == "draw-drawing" {
                let description = app.staticTexts["A red circle above a short line."]
                scrollTo(description, in: app)
                XCTAssertTrue(description.exists)
            } else {
                XCTAssertFalse(app.staticTexts["A red circle above a short line."].exists,
                               "A full part description stays out of the unfinished creature presentation")
            }
            app.terminate()
        }
    }

    @MainActor
    private func scrollTo(_ element: XCUIElement, in app: XCUIApplication) {
        XCTAssertTrue(element.waitForExistence(timeout: 10))
        for _ in 0..<8 where !element.isHittable { app.swipeUp() }
        XCTAssertTrue(element.isHittable)
    }
}
