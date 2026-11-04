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
        let app = XCUIApplication()
        app.launchEnvironment["PAEONIA_SCENARIO"] = "local-flow-game-conversation"
        app.launchArguments += [
            "-AppleLanguages", "(en)", "-AppleLocale", "en_US", "-paeonia-scenario-hide-controls", "YES",
        ]
        app.launch()

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

    @MainActor
    private func attach(_ app: XCUIApplication, named name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
