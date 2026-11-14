import XCTest

/// The couple chat ("Just us") through the real root, with only the chat's remote endpoint
/// replaced: its card is pinned at the top of Chats, it opens the chat, and a sent message
/// comes back to the card as its newest line.
final class CoupleChatJourneyUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testOpeningJustUsFromChatsAndSendingAMessage() throws {
        let app = launchApp()

        // With five tabs the system tab bar drops the tabs' identifiers, so Chats is found by its place.
        let tabs = app.tabBars.firstMatch
        XCTAssertTrue(tabs.waitForExistence(timeout: 10))
        tabs.buttons.element(boundBy: 1).tap()

        let card = app.buttons["chats.coupleChat"]
        XCTAssertTrue(card.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(card.label.contains("Just us"))
        XCTAssertTrue(card.label.contains("about anything"), card.label)
        card.tap()

        let field = app.descendants(matching: .any)["chat.composer.field"].firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(app.navigationBars["Just us"].exists, app.debugDescription)
        field.tap()
        field.typeText("Dinner at eight?")
        let send = app.buttons["chat.composer.send"]
        XCTAssertTrue(send.waitForExistence(timeout: 5))
        send.tap()
        XCTAssertTrue(app.staticTexts["Dinner at eight?"].waitForExistence(timeout: 5))
        attach(app, named: "Just us open with the sent message")

        app.navigationBars.buttons.element(boundBy: 0).tap()
        let preview = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label CONTAINS %@", "You: Dinner at eight?"), object: card)
        XCTAssertEqual(XCTWaiter.wait(for: [preview], timeout: 10), .completed, card.debugDescription)

        attach(app, named: "Just us pinned with the newest message")
    }

    /// A swipe in from the right edge pulls Just us over a game in progress, and its back
    /// button returns to the game as it was, unfinished word included.
    @MainActor
    func testSwipingInFromTheRightEdgeOpensJustUsOverAGame() throws {
        let app = launchApp()
        let tabs = app.tabBars.firstMatch
        XCTAssertTrue(tabs.waitForExistence(timeout: 10))
        tabs.buttons.element(boundBy: 2).tap()
        let game = app.buttons["games.hub.mindMeld"]
        XCTAssertTrue(game.waitForExistence(timeout: 10))
        game.tap()
        let tutorial = app.buttons["games.tutorial.next"]
        for _ in 0..<3 where tutorial.waitForExistence(timeout: 1) { tutorial.tap() }
        let word = app.textFields["mindMeld.field"]
        XCTAssertTrue(word.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        word.tap()
        word.typeText("CLOUD")

        let edge = app.coordinate(withNormalizedOffset: CGVector(dx: 0.995, dy: 0.3))
        edge.press(
            forDuration: 0.1,
            thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.3)),
            withVelocity: .fast,
            thenHoldForDuration: 0
        )

        let field = app.descendants(matching: .any)["chat.composer.field"].firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(app.navigationBars["Just us"].exists, app.debugDescription)
        field.tap()
        // The composer rises with the keyboard, and a tap on Send while it moves misses.
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        field.typeText("See you at the station")
        let send = app.buttons["chat.composer.send"]
        XCTAssertTrue(send.waitForExistence(timeout: 5))
        send.tap()
        let sent = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "See you at the station"))
        XCTAssertTrue(sent.firstMatch.waitForExistence(timeout: 5), app.debugDescription)
        attach(app, named: "Just us pulled in over Mind Meld")

        app.buttons["chat.slideOver.back"].tap()
        XCTAssertTrue(field.waitForNonExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(word.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertEqual(word.value as? String, "CLOUD")
    }

    @MainActor
    private func launchApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["PAEONIA_SCENARIO"] = "local-flow-game-conversation"
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
