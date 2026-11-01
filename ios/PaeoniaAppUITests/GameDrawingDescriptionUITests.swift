import CoreGraphics
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
            let undo = app.buttons["drawing.compose.undo"]
            scrollTo(undo, in: app)
            XCTAssertTrue(undo.isEnabled, "Creating a shape must add a real editable mark")
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
        let viewport = gameJourneyViewport(in: app)
        for _ in 0..<20 {
            if element.exists && element.isHittable,
               viewport.contains(CGPoint(x: element.frame.midX, y: element.frame.midY)) { return }
            let goesUp = !element.exists || element.frame.midY > viewport.midY
            // A drag over PencilKit draws. Scroll in the outer margin instead.
            let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.98, dy: goesUp ? 0.8 : 0.2))
            let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.98, dy: goesUp ? 0.2 : 0.8))
            start.press(forDuration: 0.01, thenDragTo: end)
        }
        XCTAssertTrue(element.isHittable)
    }
}
