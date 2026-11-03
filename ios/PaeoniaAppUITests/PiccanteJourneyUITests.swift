import XCTest

final class PiccanteJourneyUITests: XCTestCase {
    @MainActor func testPrivateSniffChoiceDoesNotMoveLiftedBiteSelection() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = [
            "-paeonia-scenario", "piccante-biting", "-paeonia-scenario-hide-controls", "YES",
            "-AppleLanguages", "(en)", "-AppleLocale", "en_US", "-paeonia.games.tutorialShown.v1.piccante", "YES",
        ]
        app.launch()
        let tile = app.buttons["piccante.tile.6"]
        XCTAssertTrue(tile.waitForExistence(timeout: 10))
        tile.tap()
        let sniff = app.buttons["piccante.sniff"]
        if !sniff.isHittable { app.swipeUp() }
        XCTAssertTrue(sniff.waitForExistence(timeout: 5))
        sniff.tap()
        let choice = app.buttons["piccante.sniff.tile.8"]
        XCTAssertTrue(choice.waitForExistence(timeout: 5))
        choice.tap()
        app.buttons["piccante.sniff.confirm"].tap()
        XCTAssertTrue(app.staticTexts["piccante.sniff.answer"].waitForExistence(timeout: 5))
        if !tile.isHittable { app.swipeDown() }
        XCTAssertTrue(tile.isSelected)
        app.terminate()
    }
}
