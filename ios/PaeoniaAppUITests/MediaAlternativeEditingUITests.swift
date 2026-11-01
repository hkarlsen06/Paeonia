import XCTest

final class MediaAlternativeEditingUITests: XCTestCase {
    @MainActor
    func testOwnStoryDescriptionCanBeCorrectedCancelledAndCleared() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["PAEONIA_SCENARIO"] = "avatar-stories-new"
        app.launchArguments = [
            "-paeonia-scenario-hide-controls", "YES", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"
        ]
        app.launch()
        defer { app.terminate() }
        let own = app.buttons["stories.own"]
        XCTAssertTrue(own.waitForExistence(timeout: 15))
        own.tap()
        let pause = app.buttons["story.viewer.pause"]
        if pause.waitForExistence(timeout: 2) { pause.tap() }
        let open = app.buttons["media.alternative.open"]
        XCTAssertTrue(open.waitForExistence(timeout: 5))
        open.tap()
        let field = app.descendants(matching: .any)["media.alternative.text"].firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        let description = "Two people standing beside the opera house."
        field.typeText(description)
        app.buttons["media.alternative.save"].tap()
        XCTAssertTrue(open.waitForExistence(timeout: 5))
        open.tap()
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        XCTAssertEqual(field.value as? String, description)
        app.buttons["media.alternative.clear"].tap()
        app.buttons["media.alternative.cancel"].tap()
        open.tap()
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        XCTAssertEqual(field.value as? String, description)
        app.buttons["media.alternative.clear"].tap()
        app.buttons["media.alternative.save"].tap()
        open.tap()
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        XCTAssertFalse((field.value as? String)?.contains(description) == true)
        app.buttons["media.alternative.cancel"].tap()
    }
}
