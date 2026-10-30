import XCTest

final class AvatarStylingJourneyUITests: XCTestCase {
    @MainActor
    func testDecorationSavesAcrossScreensAndStoryActionsStaySeparate() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["PAEONIA_SCENARIO"] = "avatar-stories-new"
        app.launchArguments += ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()

        let own = app.buttons["stories.own"]
        XCTAssertTrue(own.waitForExistence(timeout: 20))
        checkStoryActions(app)

        app.tabBars.firstMatch.buttons.element(boundBy: 4).tap()
        checkDecorationPicker(app)
        app.tabBars.firstMatch.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(own.waitForExistence(timeout: 5))
        XCTAssertEqual(own.value as? String, "Ribbon")
        XCTAssertTrue(app.buttons["stories.add"].isHittable)
        own.tap()
        XCTAssertTrue(app.buttons["story.viewer.close"].waitForExistence(timeout: 5))
    }

    @MainActor
    private func checkStoryActions(_ app: XCUIApplication) {
        app.buttons["stories.add"].tap()
        let cancelComposer = app.buttons["story.composer.cancel"]
        XCTAssertTrue(cancelComposer.waitForExistence(timeout: 5))
        cancelComposer.tap()
        app.buttons["stories.own"].tap()
        let closeViewer = app.buttons["story.viewer.close"]
        XCTAssertTrue(closeViewer.waitForExistence(timeout: 5))
        closeViewer.tap()

        let partner = app.buttons["stories.partner"]
        XCTAssertEqual(partner.value as? String, "New")
        partner.tap()
        XCTAssertTrue(closeViewer.waitForExistence(timeout: 5))
        closeViewer.tap()
        XCTAssertEqual(partner.value as? String, "Seen")
    }

    @MainActor
    private func checkDecorationPicker(_ app: XCUIApplication) {
        let styleRow = app.buttons["settings.avatarDecoration"]
        XCTAssertTrue(styleRow.waitForExistence(timeout: 5))
        styleRow.tap()
        let ribbon = app.buttons["avatarDecoration.choice.ribbon"]
        XCTAssertTrue(ribbon.waitForExistence(timeout: 5))
        ribbon.tap()
        app.buttons["avatarDecoration.save"].tap()
        XCTAssertTrue(styleRow.waitForExistence(timeout: 5))
        styleRow.tap()
        XCTAssertTrue(ribbon.waitForExistence(timeout: 5))
        XCTAssertTrue(ribbon.isSelected)
        app.buttons["avatarDecoration.choice.none"].tap()
        app.buttons["avatarDecoration.cancel"].tap()
    }
}
