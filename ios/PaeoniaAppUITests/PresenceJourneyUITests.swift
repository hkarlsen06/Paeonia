import XCTest

/// The partner's avatar through the real root, with a partner who stays in Mind Meld. A tap
/// on the avatar opens its toolbar, Message slides "Just us" over Us without a switch of tab, and Join
/// from the toolbar over the chat opens Mind Meld.
final class PresenceJourneyUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testAvatarOpensJustUsAndJoinsThePartnersGame() throws {
        let app = launch(scenario: "local-flow-presence")

        let avatar = app.descendants(matching: .any)["presence.avatar"].firstMatch
        XCTAssertTrue(avatar.waitForExistence(timeout: 15), app.debugDescription)
        XCTAssertTrue(avatar.label.contains("Mind Meld"), avatar.label)
        avatar.tap()

        let message = app.buttons["presence.message"]
        XCTAssertTrue(message.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(app.buttons["presence.join"].exists, app.debugDescription)
        attach(app, named: "The toolbar open over Us")
        message.tap()

        let field = app.descendants(matching: .any)["chat.composer.field"].firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(app.navigationBars["Just us"].exists, app.debugDescription)
        XCTAssertTrue(app.buttons["chat.slideOver.back"].exists, app.debugDescription)
        attach(app, named: "Just us slid over Us")

        avatar.tap()
        let join = app.buttons["presence.join"]
        XCTAssertTrue(join.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertFalse(app.buttons["presence.message"].exists, app.debugDescription)
        join.tap()

        let tutorial = app.buttons["games.tutorial.next"]
        for _ in 0..<3 where tutorial.waitForExistence(timeout: 1) { tutorial.tap() }
        XCTAssertTrue(app.textFields["mindMeld.field"].waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(field.waitForNonExistence(timeout: 5), app.debugDescription)
        XCTAssertFalse(join.exists, app.debugDescription)
        attach(app, named: "Mind Meld opened from Join")
    }

    @MainActor
    private func launch(scenario: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["PAEONIA_SCENARIO"] = scenario
        app.launchArguments += [
            "-AppleLanguages", "(en)", "-AppleLocale", "en_US", "-paeonia-scenario-hide-controls", "YES",
        ]
        app.launch()
        return app
    }

    @MainActor
    private func attach(_ app: XCUIApplication, named name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
