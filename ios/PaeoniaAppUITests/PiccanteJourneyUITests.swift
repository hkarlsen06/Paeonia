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
        let choice = app.buttons["piccante.tile.8"]
        if !choice.isHittable { app.swipeDown() }
        choice.tap()
        XCTAssertTrue(choice.isSelected)
        XCTAssertFalse(tile.isSelected)
        let confirm = app.buttons["piccante.sniff.confirm"]
        if !confirm.isHittable { app.swipeUp() }
        confirm.tap()
        XCTAssertTrue(app.descendants(matching: .any)["piccante.sniff.answer"].waitForExistence(timeout: 5))
        if !tile.isHittable { app.swipeDown() }
        XCTAssertTrue(tile.isSelected)
        XCTAssertFalse(choice.isSelected)
        app.terminate()
    }

    @MainActor func testPrivateSniffWorksInsideBoardControls() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = [
            "-paeonia-scenario", "piccante-biting", "-paeonia-scenario-hide-controls", "YES",
            "-AppleLanguages", "(en)", "-AppleLocale", "en_US", "-paeonia.games.tutorialShown.v1.piccante", "YES",
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
        let tile = app.buttons["piccante.sniff.list.8"]
        for _ in 0..<4 where !(tile.exists && tile.isHittable) { app.swipeDown() }
        XCTAssertTrue(tile.isHittable)
        tile.tap()
        let confirm = app.buttons["piccante.controls.sniff.confirm"]
        for _ in 0..<4 where !confirm.isHittable { app.swipeUp() }
        confirm.tap()
        XCTAssertTrue(app.buttons["piccante.controls.sniff"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["piccante.controls.sniff"].isEnabled)
        app.terminate()
    }

}
