import XCTest

/// The partner's avatar through the real root, with a partner who stays in a game. A tap on the
/// avatar opens its toolbar. Message slides "Just us" over Us without a switch of tab, and opens the
/// game's own chat inside a game. Join from the toolbar over the chat opens the partner's game.
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

    /// In a game, Message opens the game's chat over the board. With that chat open, Message
    /// opens "Just us".
    @MainActor
    func testMessageInAGameOpensItsChatThenJustUs() throws {
        let app = launch(scenario: "local-flow-presence-game-chat")

        let avatar = app.descendants(matching: .any)["presence.avatar"].firstMatch
        XCTAssertTrue(avatar.waitForExistence(timeout: 15), app.debugDescription)
        avatar.tap()

        let message = app.buttons["presence.message"]
        XCTAssertTrue(message.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(message.label.contains("Four in a Row"), message.label)
        message.tap()

        let field = app.descendants(matching: .any)["chat.composer.field"].firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertFalse(app.buttons["chat.slideOver.back"].exists, app.debugDescription)
        attach(app, named: "The game's chat over the board")

        avatar.tap()
        XCTAssertTrue(message.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(message.label.contains("Just us"), message.label)
        message.tap()

        XCTAssertTrue(app.buttons["chat.slideOver.back"].waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(app.navigationBars["Just us"].exists, app.debugDescription)
        attach(app, named: "Just us slid over the game")
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
