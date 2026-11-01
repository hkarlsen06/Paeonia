import XCTest

final class GameConversationJourneyUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testChatDuringGameAndReturnToUnfinishedWord() throws {
        let app = launchGameFlow()
        let word = app.textFields["mindMeld.field"]
        XCTAssertTrue(word.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        word.tap()
        word.typeText("CLOUD")
        app.buttons["game.conversation.open"].firstMatch.tap()
        replyToFinishedRound(in: app)

        app.buttons["game.conversation.return"].tap()
        XCTAssertTrue(word.waitForExistence(timeout: 5))
        XCTAssertEqual(word.value as? String, "CLOUD")
        app.buttons["developer.gameChat.receive"].tap()
        let banner = app.buttons["app.banner.open"]
        XCTAssertTrue(banner.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(banner.label.contains("Your move!"))
        banner.tap()
        XCTAssertTrue(app.staticTexts["What was that?"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Your move!"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(app.tabBars.firstMatch.buttons.element(boundBy: 1).isSelected)

        app.buttons["developer.gameChat.receive"].tap()
        XCTAssertFalse(banner.waitForExistence(timeout: 2))
        reopenFromChats(in: app)
        app.buttons["game.conversation.return"].tap()
        XCTAssertTrue(word.waitForExistence(timeout: 5))
        XCTAssertEqual(word.value as? String, "CLOUD")
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Unfinished game retained after messages and Chats"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor
    func testEmptyGameChatAndReturnToUnfinishedStory() throws {
        let app = launchGameFlow(gameID: "storyChain")
        let draft = app.textViews.firstMatch
        XCTAssertTrue(draft.waitForExistence(timeout: 10))
        draft.tap()
        draft.typeText("The ladder led to another door.")
        app.buttons["game.conversation.open"].firstMatch.tap()

        let emptyState = app.descendants(matching: .any)["game.conversation.empty"].firstMatch
        XCTAssertTrue(emptyState.waitForExistence(timeout: 10), app.debugDescription)
        let message = app.descendants(matching: .any)["chat.composer.field"].firstMatch
        message.tap()
        message.typeText("Where should the story go next?")
        tapSendAboveKeyboard(in: app)
        XCTAssertTrue(app.staticTexts["Where should the story go next?"].waitForExistence(timeout: 5))
        XCTAssertFalse(emptyState.exists)

        app.buttons["game.conversation.return"].tap()
        XCTAssertTrue(draft.waitForExistence(timeout: 5))
        XCTAssertEqual(draft.value as? String, "The ladder led to another door.")
        XCTAssertFalse(app.keyboards.firstMatch.exists)
        let tabs = app.tabBars.firstMatch
        XCTAssertTrue(tabs.waitForExistence(timeout: 5))
        XCTAssertTrue(tabs.buttons.element(boundBy: 2).isSelected)

        tabs.buttons.element(boundBy: 1).tap()
        XCTAssertTrue(app.staticTexts["Where should the story go next?"].waitForExistence(timeout: 5))
        tabs.buttons.element(boundBy: 2).tap()
        XCTAssertTrue(draft.waitForExistence(timeout: 5))
        XCTAssertEqual(draft.value as? String, "The ladder led to another door.")
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Story draft and game tabs retained after chat"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor
    private func launchGameFlow(gameID: String = "mindMeld") -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["PAEONIA_SCENARIO"] = "local-flow-game-conversation"
        app.launchArguments += ["-AppleLanguages", "(en)", "-AppleLocale", "en_US",
                                "-paeonia-scenario-hide-controls", "YES", "-paeonia-game-chat-test-events", "YES"]
        app.launch()
        let tabs = app.tabBars.firstMatch
        XCTAssertTrue(tabs.waitForExistence(timeout: 10))
        tabs.buttons.element(boundBy: 2).tap()
        let game = app.buttons["games.hub.\(gameID)"]
        for _ in 0..<4 where !game.isHittable { app.scrollViews["games.hub"].swipeUp() }
        XCTAssertTrue(game.waitForExistence(timeout: 10))
        game.tap()
        let tutorial = app.buttons["games.tutorial.next"]
        for _ in 0..<3 where tutorial.waitForExistence(timeout: 1) { tutorial.tap() }
        return app
    }

    @MainActor
    private func replyToFinishedRound(in app: XCUIApplication) {
        let field = app.descendants(matching: .any)["chat.composer.field"]
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        XCTAssertTrue(app.tabBars.firstMatch.buttons.element(boundBy: 1).isSelected)
        let result = app.buttons["game.conversation.result.a9000000-0000-4000-8000-000000000001"]
        XCTAssertTrue(result.waitForExistence(timeout: 10), app.debugDescription)
        result.tap()
        for word in ["OCEAN", "SUSHI", "SALT", "FISH", "SEA", "NET", "BOAT"] {
            XCTAssertTrue(app.staticTexts[word].firstMatch.waitForExistence(timeout: 5))
        }
        let reply = app.buttons["game.conversation.result.reply"]
        for _ in 0..<5 where !reply.isHittable { app.swipeUp() }
        XCTAssertTrue(reply.waitForExistence(timeout: 5))
        reply.tap()
        field.tap()
        field.typeText("What was that?")
        tapSendAboveKeyboard(in: app)
        XCTAssertTrue(app.staticTexts["What was that?"].waitForExistence(timeout: 5))
    }

    @MainActor
    private func reopenFromChats(in app: XCUIApplication) {
        app.navigationBars.buttons.element(boundBy: 0).tap()
        let conversation = app.buttons["chat.conversation.11181706-63f4-43d9-5210-140fa90e1fce"]
        for _ in 0..<4 where !conversation.isHittable { app.swipeUp() }
        XCTAssertTrue(conversation.waitForExistence(timeout: 10), app.debugDescription)
        conversation.tap()
        XCTAssertTrue(app.staticTexts["What was that?"].waitForExistence(timeout: 5))
    }

    @MainActor
    private func tapSendAboveKeyboard(in app: XCUIApplication) {
        let keyboard = app.keyboards.firstMatch
        XCTAssertTrue(keyboard.waitForExistence(timeout: 5))
        let send = app.buttons["chat.composer.send"]
        let position = NSPredicate { _, _ in
            send.isHittable && send.frame.maxY <= keyboard.frame.minY
        }
        let ready = XCTNSPredicateExpectation(predicate: position, object: send)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 5), .completed)
        send.tap()
    }
}
