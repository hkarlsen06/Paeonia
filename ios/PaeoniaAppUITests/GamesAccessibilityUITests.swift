import XCTest

/// Exercises native alternatives without using board coordinates or drag gestures.
final class GamesAccessibilityUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testFourInARowCanDropUsingANativeButton() {
        let app = launch("connect-four-your-turn")
        app.buttons["games.board.controls"].tap()
        let drop = app.buttons["connectFour.drop.0"]
        XCTAssertTrue(drop.waitForExistence(timeout: 5))
        XCTAssertTrue(drop.isEnabled)
        drop.tap()
        // The same move path hands over the turn, disabling another drop.
        let disabled = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == false"), object: drop)
        XCTAssertEqual(XCTWaiter.wait(for: [disabled], timeout: 5), .completed)
    }

    @MainActor
    func testMapCoordinatesSelectInBothAuthorAndGuessing() {
        for scenario in ["guess-my-spot-check-missing", "guess-my-spot-guess"] {
            let app = launch(scenario)
            let confirm = app.buttons[scenario == "guess-my-spot-guess"
                ? "guessMySpot.guess.lock" : "guessMySpot.check.send"]
            XCTAssertFalse(confirm.isEnabled)
            let choose = app.buttons["guessMySpot.choosePlace"]
            XCTAssertTrue(choose.waitForExistence(timeout: 5))
            choose.tap()
            let latitude = app.textFields["guessMySpot.place.latitude"]
            let longitude = app.textFields["guessMySpot.place.longitude"]
            XCTAssertTrue(latitude.waitForExistence(timeout: 5))
            latitude.tap()
            latitude.typeText("-33.86")
            longitude.tap()
            longitude.typeText("151.21\n")
            let select = app.buttons["guessMySpot.place.select"]
            if !select.isHittable { app.swipeUp() }
            XCTAssertTrue(select.isEnabled)
            select.tap()
            XCTAssertTrue(confirm.waitForExistence(timeout: 5))
            XCTAssertTrue(confirm.isEnabled)
            app.terminate()
        }
    }

    @MainActor
    func testLudoExposesNativeRollAndAllPawnState() {
        let app = launch("ludo-your-turn")
        app.buttons["games.board.controls"].tap()
        let roll = app.buttons["ludo.roll"]
        XCTAssertTrue(roll.waitForExistence(timeout: 5))
        // Both partners' pawns in base must remain inspectable before they can move.
        for player in 1...2 {
            for pawn in 0..<2 {
                XCTAssertTrue(app.staticTexts["ludo.pawn.state.\(player).\(pawn)"].exists)
            }
        }
        roll.tap()
        XCTAssertFalse(roll.exists)
    }

    @MainActor
    private func launch(_ scenario: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-paeonia-scenario", scenario, "-paeonia-scenario-hide-controls", "YES",
                               "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        let next = app.buttons["games.tutorial.next"]
        for _ in 0..<3 where next.waitForExistence(timeout: 1) { next.tap() }
        return app
    }
}
