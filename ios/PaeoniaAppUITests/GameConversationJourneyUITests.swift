import XCTest

final class GameConversationJourneyUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testStartFromFinishedGameAndReopenFromChats() throws {
        let app = XCUIApplication()
        app.launchEnvironment["PAEONIA_SCENARIO"] = "local-flow-game-conversation"
        app.launchArguments += ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        let tabs = app.tabBars.firstMatch
        XCTAssertTrue(tabs.waitForExistence(timeout: 10))
        tabs.buttons.element(boundBy: 2).tap()

        let game = app.buttons["games.hub.mindMeld"]
        for _ in 0..<4 where !game.isHittable { app.scrollViews["games.hub"].swipeUp() }
        XCTAssertTrue(game.waitForExistence(timeout: 10))
        game.tap()
        let tutorial = app.buttons["games.tutorial.next"]
        for _ in 0..<3 where tutorial.waitForExistence(timeout: 1) { tutorial.tap() }

        let start = app.buttons["Start a conversation"]
        XCTAssertTrue(start.waitForExistence(timeout: 10), app.debugDescription)
        start.tap()
        let field = app.descendants(matching: .any)["chat.composer.field"]
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        for word in ["OCEAN", "SUSHI", "SALT", "FISH", "SEA", "NET", "BOAT"] {
            XCTAssertTrue(app.staticTexts[word].firstMatch.waitForExistence(timeout: 5))
        }
        field.tap()
        field.typeText("What was that?")
        tapSendAboveKeyboard(in: app)
        XCTAssertTrue(app.staticTexts["What was that?"].waitForExistence(timeout: 5))

        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.navigationBars.buttons.element(boundBy: 0).tap()
        tabs.buttons.element(boundBy: 1).tap()
        let conversation = app.buttons["chat.conversation.aaaaaaaa-1000-4000-8000-000000000005"]
        XCTAssertTrue(conversation.waitForExistence(timeout: 10), app.debugDescription)
        conversation.tap()
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["What was that?"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["game.conversation.result"].firstMatch.exists)

        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Game conversation reopened from Chats"
        attachment.lifetime = .keepAlways
        add(attachment)
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
