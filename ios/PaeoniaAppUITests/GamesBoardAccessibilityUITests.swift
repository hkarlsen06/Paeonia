import XCTest

final class GamesBoardAccessibilityUITests: XCTestCase {
    @MainActor
    func testDotsNativeSidesCloseABoxAndPreserveTheExtraTurn() throws {
        continueAfterFailure = false
        let app = launch("dots-and-boxes-extra-turn")
        defer { app.terminate() }
        openControls(in: app)
        let closingSide = app.buttons["dotsAndBoxes.box.11.side.3"]
        scrollTo(closingSide, in: app)
        let box = app.staticTexts["dotsAndBoxes.box.11.state"]
        let openBox = box.label
        XCTAssertTrue(closingSide.isEnabled)
        closingSide.tap()
        waitFor(box, matching: NSPredicate(format: "label != %@", openBox))
        XCTAssertFalse(closingSide.isEnabled)

        let nextSide = app.buttons["dotsAndBoxes.box.14.side.1"]
        scrollTo(nextSide, in: app)
        let remainingSide = app.buttons["dotsAndBoxes.box.14.side.2"]
        scrollTo(remainingSide, in: app)
        waitFor(nextSide, matching: NSPredicate(format: "enabled == true"))
        XCTAssertTrue(remainingSide.isEnabled)
        nextSide.tap()
        waitFor(remainingSide, matching: NSPredicate(format: "enabled == false"))
    }

    @MainActor
    func testUltimateNativeSelectionInspectsBoardsAndCommitsOnlyTheChosenSquare() {
        continueAfterFailure = false
        let app = launch("ultimate-tic-tac-toe-forced")
        defer { app.terminate() }
        openControls(in: app)
        viewBoard(0, in: app)
        XCTAssertFalse(app.buttons["ultimateTicTacToe.native.cell.1"].isEnabled)
        viewBoard(6, in: app)
        let first = app.buttons["ultimateTicTacToe.native.cell.54"]
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
        XCTAssertTrue(app.buttons["drawing.compose.undo"].isEnabled)
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
            "-paeonia-scenario-hide-controls", "YES", "-AppleLanguages", "(en)", "-AppleLocale", "en_US",
            "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryL"
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
    private func viewBoard(_ index: Int, in app: XCUIApplication) {
        app.buttons["ultimateTicTacToe.native.board"].tap()
        let choose = app.buttons["ultimateTicTacToe.native.board.\(index)"]
        XCTAssertTrue(choose.waitForExistence(timeout: 5))
        choose.tap()
    }

    @MainActor
    private func scrollTo(_ element: XCUIElement, in app: XCUIApplication, scrollsDown: Bool = true) {
        for _ in 0..<12 where !element.isHittable {
            if scrollsDown { app.swipeUp() }
            else { app.swipeDown() }
        }
        XCTAssertTrue(element.isHittable)
    }

    @MainActor
    private func waitFor(_ element: XCUIElement, matching predicate: NSPredicate) {
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 5), .completed)
    }
}
