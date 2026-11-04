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

    @MainActor func testPrivateSniffOpensInsideBoardControls() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = [
            "-paeonia-scenario", "piccante-biting", "-paeonia-scenario-hide-controls", "YES",
            "-AppleLanguages", "(en)", "-AppleLocale", "en_US",
        ]
        app.launchWithExtraAccessibilityTools()
        let controls = app.buttons["piccante.controls.open"]
        XCTAssertTrue(controls.waitForExistence(timeout: 10))
        if !controls.isHittable { app.swipeUp() }
        controls.tap()
        let sniff = app.buttons["piccante.controls.sniff"]
        for _ in 0..<4 where !sniff.isHittable { app.swipeUp() }
        XCTAssertTrue(sniff.isHittable)
        sniff.tap()
        let tile = app.buttons["piccante.sniff.tile.8"]
        XCTAssertTrue(tile.waitForExistence(timeout: 5))
        tile.tap()
        app.buttons["piccante.sniff.confirm"].tap()
        XCTAssertTrue(app.buttons["piccante.controls.sniff"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["piccante.controls.sniff"].isEnabled)
        app.terminate()
    }

}
