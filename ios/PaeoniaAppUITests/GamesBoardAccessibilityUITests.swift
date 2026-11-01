import CoreGraphics
import XCTest

final class GamesBoardAccessibilityUITests: XCTestCase {
    @MainActor
    func testDotsNativeSidesCloseABoxAndPreserveTheExtraTurn() throws {
        continueAfterFailure = false
        let app = launch("dots-and-boxes-extra-turn")
        defer { app.terminate() }
        openControls(in: app)
        viewBox(11, in: app)
        let closingSide = app.buttons["dotsAndBoxes.box.11.side.3"]
        scrollTo(closingSide, in: app)
        let box = app.staticTexts["dotsAndBoxes.box.11.state"]
        let openBox = box.label
        XCTAssertTrue(closingSide.isEnabled)
        closingSide.tap()
        waitFor(box, matching: NSPredicate(format: "label != %@", openBox))
        XCTAssertFalse(closingSide.isEnabled)

        viewBox(0, in: app)
        XCTAssertFalse(app.buttons["dotsAndBoxes.box.0.side.0"].isEnabled,
                       "Already owned boxes stay inspectable without offering a move")
        viewBox(14, in: app)
        let nextSide = app.buttons["dotsAndBoxes.box.14.side.1"]
        scrollTo(nextSide, in: app)
        let remainingSide = app.buttons["dotsAndBoxes.box.14.side.2"]
        scrollTo(remainingSide, in: app)
        XCTAssertTrue(remainingSide.isEnabled)
        scrollTo(nextSide, in: app, scrollsDown: false)
        waitFor(nextSide, matching: NSPredicate(format: "enabled == true"))
        nextSide.tap()
        scrollTo(remainingSide, in: app)
        waitFor(remainingSide, matching: NSPredicate(format: "enabled == false"))
    }

    @MainActor
    func testUltimateNativeSelectionInspectsBoardsAndCommitsOnlyTheChosenSquare() {
        continueAfterFailure = false
        let app = launch("ultimate-tic-tac-toe-forced")
        defer { app.terminate() }
        openControls(in: app)
        viewBoard(0, in: app)
        let closedBoardCell = app.buttons["ultimateTicTacToe.native.cell.1"]
        scrollTo(closedBoardCell, in: app)
        XCTAssertFalse(closedBoardCell.isEnabled)
        viewBoard(6, in: app)
        let first = app.buttons["ultimateTicTacToe.native.cell.54"]
        scrollTo(first, in: app)
        first.tap()
        waitFor(first, matching: NSPredicate(format: "isSelected == true"))
        let chosen = app.buttons["ultimateTicTacToe.native.cell.62"]
        scrollTo(chosen, in: app)
        let emptySquare = chosen.label
        chosen.tap()
        waitFor(chosen, matching: NSPredicate(format: "isSelected == true"))
        scrollTo(first, in: app, scrollsDown: false)
        XCTAssertFalse(first.isSelected)
        app.buttons["games.board.controls.close"].tap()
        let commit = app.buttons["ultimateTicTacToe.lockIn"]
        XCTAssertTrue(commit.isEnabled)
        commit.tap()
        // Hidden SwiftUI controls can remain queryable on iOS 27. Verify the move itself below.
        waitFor(commit, matching: NSPredicate(format: "enabled == false"))

        openControls(in: app)
        viewBoard(6, in: app)
        let played = app.buttons["ultimateTicTacToe.native.cell.62"]
        scrollTo(played, in: app)
        XCTAssertNotEqual(played.label, emptySquare)
        XCTAssertFalse(played.isEnabled)
    }

    @MainActor
    func testConsensioNativeStepsChangeTheValueAndCanLockPlacement() throws {
        continueAfterFailure = false
        let app = launch("consensio-place")
        defer { app.terminate() }
        let slider = app.sliders["consensio.position.slider"]
        XCTAssertTrue(slider.waitForExistence(timeout: 5))
        let initialValue = try XCTUnwrap(slider.value as? String)
        let stepper = app.steppers["consensio.position.stepper"]
        let increase = stepper.buttons["consensio.position.stepper-Increment"]
        // The spoken middle covers a short range. Continue until a real value
        // change is exposed, without assuming where that range ends.
        for _ in 0..<8 {
            increase.tap()
            if slider.value as? String != initialValue { break }
        }
        XCTAssertNotEqual(slider.value as? String, initialValue)
        stepper.buttons["consensio.position.stepper-Decrement"].tap()
        waitFor(slider, matching: NSPredicate(format: "value == %@", initialValue))
        app.buttons["consensio.place.lock"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["consensio.waiting.guess"].firstMatch
            .waitForExistence(timeout: 5))
    }

    @MainActor
    func testCustomMarkCanBeCreatedAndSavedWithoutTracing() {
        continueAfterFailure = false
        let app = launch("board-game-mark-editor")
        defer { app.terminate() }
        let compose = app.buttons["drawing.compose"]
        scrollTo(compose, in: app)
        compose.tap()
        let add = app.buttons["drawing.compose.apply"]
        scrollTo(add, in: app)
        add.tap()
        let undo = app.buttons["drawing.compose.undo"]
        scrollTo(undo, in: app)
        XCTAssertTrue(undo.isEnabled)
        app.buttons["drawing.compose.done"].tap()
        let save = app.buttons["boardGames.mark.save"]
        XCTAssertTrue(save.waitForExistence(timeout: 5))
        XCTAssertTrue(save.isEnabled)
        save.tap()
        XCTAssertTrue(save.waitForNonExistence(timeout: 10))
        XCTAssertTrue(app.buttons["games.board.controls"].exists)
    }

    @MainActor
    private func launch(_ scenario: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["PAEONIA_SCENARIO"] = scenario
        app.launchArguments = [
            "-paeonia-scenario-hide-controls", "YES", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"
        ]
        app.launch()
        let next = app.buttons["games.tutorial.next"]
        for _ in 0..<5 {
            guard next.waitForExistence(timeout: 2) else { break }
            XCTAssertTrue(next.isHittable)
            next.tap()
        }
        return app
    }

    @MainActor
    private func openControls(in app: XCUIApplication) {
        let open = app.buttons["games.board.controls"]
        XCTAssertTrue(open.waitForExistence(timeout: 5))
        open.tap()
        XCTAssertTrue(app.buttons["games.board.controls.close"].waitForExistence(timeout: 5))
    }

    @MainActor
    private func viewBox(_ index: Int, in app: XCUIApplication) {
        let boxes = app.descendants(matching: .any)["dotsAndBoxes.native.box"].firstMatch
        scrollTo(boxes, in: app, scrollsDown: false)
        boxes.tap()
        let choose = app.descendants(matching: .any)["dotsAndBoxes.native.box.\(index)"].firstMatch
        // Native lists can reopen around the selected row. Row zero is above that position.
        scrollTo(choose, in: app, scrollsDown: index > 0)
        choose.tap()
        let state = app.staticTexts["dotsAndBoxes.box.\(index).state"]
        scrollTo(state, in: app)
        XCTAssertTrue(state.exists)
    }

    @MainActor
    private func viewBoard(_ index: Int, in app: XCUIApplication) {
        let boards = app.descendants(matching: .any)["ultimateTicTacToe.native.board"].firstMatch
        scrollTo(boards, in: app, scrollsDown: false)
        boards.tap()
        let choose = app.descendants(matching: .any)["ultimateTicTacToe.native.board.\(index)"].firstMatch
        scrollTo(choose, in: app, scrollsDown: index > 0)
        choose.tap()
    }

    @MainActor
    private func scrollTo(_ element: XCUIElement, in app: XCUIApplication, scrollsDown: Bool = true) {
        let viewport = gameJourneyViewport(in: app)
        for _ in 0..<32 {
            if element.exists && element.isHittable,
               viewport.contains(CGPoint(x: element.frame.midX, y: element.frame.midY)) { return }
            let goesUp: Bool
            if element.exists {
                goesUp = element.frame.midY > viewport.midY
            } else {
                goesUp = scrollsDown
            }
            // The outer margin belongs to the ScrollView, rather than the drawing canvas.
            let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.98, dy: goesUp ? 0.8 : 0.2))
            let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.98, dy: goesUp ? 0.2 : 0.8))
            start.press(forDuration: 0.01, thenDragTo: end)
        }
        XCTAssertTrue(element.isHittable)
    }

    @MainActor
    private func waitFor(_ element: XCUIElement, matching predicate: NSPredicate) {
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 5), .completed)
    }
}
