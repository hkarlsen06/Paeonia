import XCTest

final class GameConversationJourneyUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testChatSheetOverGameKeepsUnfinishedWord() throws {
        let app = launchGameFlow()
        let word = app.textFields["mindMeld.field"]
        XCTAssertTrue(word.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        word.tap()
        word.typeText("CLOUD")
        app.buttons["game.conversation.open"].firstMatch.tap()
        replyToFinishedRound(in: app)

        app.buttons["chat.sheet.close"].tap()
        XCTAssertTrue(word.waitForExistence(timeout: 5))
        XCTAssertEqual(word.value as? String, "CLOUD")

        // A partner message's banner opens the same sheet over the game.
        app.buttons["developer.gameChat.receive"].tap()
        let banner = app.buttons["app.banner.open"]
        XCTAssertTrue(banner.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(banner.label.contains("Your move!"))
        banner.tap()
        XCTAssertTrue(app.staticTexts["What was that?"].waitForExistence(timeout: 5))
        let moves = app.tables.firstMatch.staticTexts.matching(NSPredicate(format: "label == %@", "Your move!"))
        XCTAssertTrue(moves.firstMatch.waitForExistence(timeout: 5))
        assertChatSheetOverGame(in: app)
        swipeDownChatSheet(in: app)
        XCTAssertTrue(word.waitForExistence(timeout: 5))
        XCTAssertEqual(word.value as? String, "CLOUD")

        // A message that arrives while its chat is on screen shows no banner.
        app.buttons["developer.gameChat.receiveLater"].tap()
        app.buttons["game.conversation.open"].firstMatch.tap()
        assertChatSheetOverGame(in: app)
        let secondMove = XCTNSPredicateExpectation(predicate: NSPredicate(format: "count == 2"), object: moves)
        XCTAssertEqual(XCTWaiter.wait(for: [secondMove], timeout: 10), .completed, app.debugDescription)
        XCTAssertFalse(banner.waitForExistence(timeout: 2))
        app.buttons["chat.sheet.close"].tap()
        XCTAssertTrue(word.waitForExistence(timeout: 5))
        XCTAssertEqual(word.value as? String, "CLOUD")
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Unfinished game kept under the chat sheet"
        attachment.lifetime = .keepAlways
        add(attachment)

        reopenFromChats(in: app)
    }

    /// Reading a partner's message, in the sheet over the game or in Chats, clears its unread mark.
    @MainActor
    func testReadingGameChatClearsUnreadMark() throws {
        let app = launchGameFlow()
        XCTAssertTrue(app.textFields["mindMeld.field"].waitForExistence(timeout: 10), app.debugDescription)
        let open = app.buttons["game.conversation.open"].firstMatch
        let banner = app.buttons["app.banner.open"]
        let moves = app.tables.firstMatch.staticTexts.matching(NSPredicate(format: "label == %@", "Your move!"))

        app.buttons["developer.gameChat.receive"].tap()
        assertUnread(open, true)
        dismissBanner(banner)
        open.tap()
        assertChatSheetOverGame(in: app)
        XCTAssertTrue(moves.firstMatch.waitForExistence(timeout: 5))
        app.buttons["chat.sheet.close"].tap()
        assertUnread(open, false)

        app.navigationBars.buttons.element(boundBy: 0).tap()
        let tabs = app.tabBars.firstMatch
        XCTAssertTrue(tabs.waitForExistence(timeout: 5))
        tabs.buttons.element(boundBy: 1).tap()
        app.buttons["developer.gameChat.receive"].tap()
        let conversation = app.buttons["chat.conversation.11181706-63f4-43d9-5210-140fa90e1fce"]
        for _ in 0..<4 where !conversation.isHittable { app.swipeUp() }
        assertUnread(conversation, true)
        dismissBanner(banner)
        conversation.tap()
        let secondMove = XCTNSPredicateExpectation(predicate: NSPredicate(format: "count == 2"), object: moves)
        XCTAssertEqual(XCTWaiter.wait(for: [secondMove], timeout: 10), .completed, app.debugDescription)
        app.navigationBars.buttons.element(boundBy: 0).tap()
        assertUnread(conversation, false)
    }

    /// A message banner stays until it is swiped away, and it covers the top bar.
    @MainActor
    private func dismissBanner(_ banner: XCUIElement) {
        XCTAssertTrue(banner.waitForExistence(timeout: 5))
        // A quick swipe can land as a tap, which opens the chat.
        let start = banner.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        start.press(forDuration: 0.1, thenDragTo: start.withOffset(CGVector(dx: 0, dy: -150)))
        XCTAssertTrue(banner.waitForNonExistence(timeout: 5))
    }

    @MainActor
    private func assertUnread(_ element: XCUIElement, _ unread: Bool, line: UInt = #line) {
        let format = unread ? "label CONTAINS %@" : "NOT (label CONTAINS %@)"
        let predicate = NSPredicate(format: format, "New message from")
        let state = XCTNSPredicateExpectation(predicate: predicate, object: element)
        XCTAssertEqual(XCTWaiter.wait(for: [state], timeout: 10), .completed, element.debugDescription, line: line)
    }

    @MainActor
    func testEmptyGameChatSheetOverUnfinishedStory() throws {
        let app = launchGameFlow(gameID: "storyChain")
        let draft = app.textViews.firstMatch
        XCTAssertTrue(draft.waitForExistence(timeout: 10))
        XCTAssertFalse(app.tabBars.firstMatch.exists)
        draft.tap()
        draft.typeText("The ladder led to another door.")
        app.buttons["game.conversation.open"].firstMatch.tap()

        let emptyState = app.descendants(matching: .any)["game.conversation.empty"].firstMatch
        XCTAssertTrue(emptyState.waitForExistence(timeout: 10), app.debugDescription)
        assertChatSheetOverGame(in: app)
        let message = app.descendants(matching: .any)["chat.composer.field"].firstMatch
        message.tap()
        message.typeText("Where should the story go next?")
        tapSendAboveKeyboard(in: app)
        XCTAssertTrue(app.staticTexts["Where should the story go next?"].waitForExistence(timeout: 5))
        XCTAssertFalse(emptyState.exists)

        app.buttons["chat.sheet.close"].tap()
        XCTAssertTrue(draft.waitForExistence(timeout: 5))
        XCTAssertEqual(draft.value as? String, "The ladder led to another door.")
        XCTAssertFalse(app.keyboards.firstMatch.exists)
        XCTAssertFalse(app.tabBars.firstMatch.exists)

        app.buttons["game.conversation.open"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Where should the story go next?"].waitForExistence(timeout: 5))
        assertChatSheetOverGame(in: app)
        swipeDownChatSheet(in: app)
        XCTAssertTrue(draft.waitForExistence(timeout: 5))
        XCTAssertEqual(draft.value as? String, "The ladder led to another door.")
        XCTAssertFalse(app.tabBars.firstMatch.exists)
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Story draft and full-screen game kept under the chat sheet"
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
        assertChatSheetOverGame(in: app)
        let result = app.buttons["game.conversation.result.a9000000-0000-4000-8000-000000000001"]
        XCTAssertTrue(result.waitForExistence(timeout: 10), app.debugDescription)
        // The latest finished game opens with the conversation. The board under the sheet
        // shows some of the same words, so look only in the chat.
        let chat = app.tables.firstMatch
        for word in ["OCEAN", "SUSHI", "SALT", "FISH", "SEA", "NET", "BOAT"] {
            XCTAssertTrue(chat.staticTexts[word].firstMatch.waitForExistence(timeout: 5))
        }
        let reply = app.buttons["game.conversation.result.reply"]
        // The half-height sheet can leave the card's header under its navigation bar.
        for _ in 0..<5 where !reply.isHittable {
            let center = chat.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            let distance: CGFloat = reply.frame.midY < chat.frame.midY ? 150 : -150
            center.press(forDuration: 0.05, thenDragTo: center.withOffset(CGVector(dx: 0, dy: distance)))
        }
        XCTAssertTrue(reply.waitForExistence(timeout: 5))
        reply.tap()
        field.tap()
        field.typeText("What was that?")
        tapSendAboveKeyboard(in: app)
        XCTAssertTrue(app.staticTexts["What was that?"].waitForExistence(timeout: 5))
    }

    /// Leaves the game, then opens its chat from Chats, where it still opens in the tab.
    @MainActor
    private func reopenFromChats(in app: XCUIApplication) {
        app.navigationBars.buttons.element(boundBy: 0).tap()
        let tabs = app.tabBars.firstMatch
        XCTAssertTrue(tabs.waitForExistence(timeout: 5))
        tabs.buttons.element(boundBy: 1).tap()
        let conversation = app.buttons["chat.conversation.11181706-63f4-43d9-5210-140fa90e1fce"]
        for _ in 0..<4 where !conversation.isHittable { app.swipeUp() }
        XCTAssertTrue(conversation.waitForExistence(timeout: 10), app.debugDescription)
        conversation.tap()
        XCTAssertTrue(app.staticTexts["What was that?"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["chat.sheet.close"].exists)
        XCTAssertTrue(tabs.buttons.element(boundBy: 1).isSelected)
    }

    /// The chat is a sheet over the game: the Games tab stays selected, so its tab bar stays hidden.
    @MainActor
    private func assertChatSheetOverGame(in app: XCUIApplication) {
        XCTAssertTrue(app.buttons["chat.sheet.close"].waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertFalse(app.tabBars.firstMatch.exists)
    }

    @MainActor
    private func swipeDownChatSheet(in app: XCUIApplication) {
        let close = app.buttons["chat.sheet.close"]
        let bar = close.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .withOffset(CGVector(dx: 120, dy: 0))
        bar.press(forDuration: 0.1, thenDragTo: bar.withOffset(CGVector(dx: 0, dy: 700)))
        XCTAssertTrue(close.waitForNonExistence(timeout: 5))
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
