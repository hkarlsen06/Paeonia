import XCTest

final class GuessMySpotDescriptionUITests: XCTestCase {
    @MainActor
    func testAuthoredSceneReachesTheQueuedRoundAndFullImageViewer() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["PAEONIA_SCENARIO"] = "guess-my-spot-check-found"
        app.launchArguments = [
            "-paeonia-scenario-hide-controls", "YES", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"
        ]
        app.launch()
        defer { app.terminate() }
        let next = app.buttons["games.tutorial.next"]
        for _ in 0..<5 {
            guard next.waitForExistence(timeout: 2) else { break }
            next.tap()
        }
        let describe = app.buttons["guessMySpot.description.open"]
        XCTAssertTrue(describe.waitForExistence(timeout: 5))
        describe.tap()
        let field = app.descendants(matching: .any)["guessMySpot.description.text"].firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        let description = "An authored scene clue without a location."
        field.typeText(description)
        app.buttons["guessMySpot.description.done"].tap()
        app.buttons["guessMySpot.check.send"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["guessMySpot.waiting.guess"].firstMatch
            .waitForExistence(timeout: 5))
        let read = app.buttons["guessMySpot.description.read"]
        XCTAssertTrue(read.waitForExistence(timeout: 5))
        read.tap()
        XCTAssertTrue(app.staticTexts[description].waitForExistence(timeout: 5))
        app.buttons["guessMySpot.description.read.close"].tap()
        app.buttons["guessMySpot.photo.open"].tap()
        let photo = app.descendants(matching: .any)["imageViewer.photo"].firstMatch
        XCTAssertTrue(photo.waitForExistence(timeout: 5))
        XCTAssertEqual(photo.label, description)
        app.buttons["imageViewer.close"].tap()
    }
}
