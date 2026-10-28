import XCTest

/// Answering daily questions through the real root in the paired local flow. When the
/// partner already answered, the answer turns the cover into the question's chat, where
/// the partner's answer shows, and closing it goes back to the screen that opened the
/// flow. When the partner hasn't answered, the cover closes and the card opens the chat.
final class DailyQuestionJourneyUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testAnsweringOpensTheChatInTheCoverAndClosingReturnsHome() throws {
        let app = XCUIApplication()
        app.launchEnvironment["PAEONIA_SCENARIO"] = "local-flow-paired"
        app.launch()

        // With five tabs the system tab bar drops the tabs' accessibility identifiers, so
        // Home is found by its place: the first of home, questions, games, memories, us.
        let homeTab = app.tabBars.firstMatch.buttons.element(boundBy: 0)
        XCTAssertTrue(homeTab.waitForExistence(timeout: 10))
        XCTAssertTrue(homeTab.isSelected)

        // The local flow's partner answered yesterday's question, so it waits on the Home
        // card as a locked row.
        let lockedRow = app.buttons.matching(identifier: "daily.lockedRow").firstMatch
        XCTAssertTrue(lockedRow.waitForExistence(timeout: 10))
        lockedRow.tap()

        let answerField = app.descendants(matching: .any)["daily.answer.text"]
        let fieldExists = answerField.waitForExistence(timeout: 5)
        capture(app, named: "Daily answer composer")
        XCTAssertTrue(fieldExists, app.debugDescription)
        answerField.tap()
        answerField.typeText("The lake walk")
        capture(app, named: "Daily answer with keyboard")

        let send = app.buttons["daily.flow.primary"]
        XCTAssertTrue(send.waitForExistence(timeout: 5))
        send.tap()

        // The cover turns into the question's chat, with the partner's answer and the composer.
        XCTAssertTrue(app.descendants(matching: .any)["chat.composer.field"].waitForExistence(timeout: 10))
        let partnerAnswer = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS %@", "started pouring"))
            .firstMatch
        XCTAssertTrue(partnerAnswer.waitForExistence(timeout: 5))

        let close = app.buttons["daily.chat.close"]
        XCTAssertTrue(close.exists)
        close.tap()

        // Closing lands back on Home, where the row was tapped, not on the Questions tab.
        XCTAssertTrue(close.waitForNonExistence(timeout: 5))
        XCTAssertTrue(homeTab.waitForExistence(timeout: 5))
        XCTAssertTrue(homeTab.isSelected)
    }

    @MainActor
    func testFirstAnswerClosesTheCoverAndTheQuestionsCardOpensTheConversation() throws {
        let app = XCUIApplication()
        app.launchEnvironment["PAEONIA_SCENARIO"] = "local-flow-paired"
        app.launch()
        let questions = app.tabBars.firstMatch.buttons.element(boundBy: 1)
        XCTAssertTrue(questions.waitForExistence(timeout: 10))
        questions.tap()
        let open = app.buttons["home.dailyPrompt.action"]
        XCTAssertTrue(open.waitForExistence(timeout: 5))
        open.tap()
        let answer = app.descendants(matching: .any)["daily.answer.text"]
        XCTAssertTrue(answer.waitForExistence(timeout: 5))
        let prompt = app.staticTexts["daily.answer.question"].label
        answer.tap()
        answer.typeText("The first coffee together")
        app.buttons["daily.flow.primary"].tap()

        // The partner hasn't answered, so the chat would only show this answer. The
        // cover closes instead, and the card shows the question as answered.
        XCTAssertTrue(answer.waitForNonExistence(timeout: 10))
        XCTAssertFalse(app.buttons["daily.chat.close"].exists)
        let ownAnswer = app.buttons["daily.done.openConversation"]
        XCTAssertTrue(ownAnswer.waitForExistence(timeout: 10))
        XCTAssertTrue(ownAnswer.label.contains(prompt))
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "label CONTAINS %@", prompt)).count, 1)
        capture(app, named: "Completed daily question")
        ownAnswer.tap()
        XCTAssertTrue(app.staticTexts["The first coffee together"].waitForExistence(timeout: 5))
        XCTAssertFalse(answer.exists)
    }

    @MainActor
    func testPhotoAndCaptionOpenTheirConversationWithTheAttachmentKeptWhileTyping() throws {
        let app = XCUIApplication()
        app.launchEnvironment["PAEONIA_SCENARIO"] = "question-answer-flow"
        app.launchArguments += ["-paeonia-answer-format", "photo-text", "-paeonia-answer-seeded", "YES"]
        app.launch()
        let photo = app.buttons["daily.answer.photo.remove"]
        XCTAssertTrue(photo.waitForExistence(timeout: 10))
        capture(app, named: "Photo and text before typing")
        let answer = app.descendants(matching: .any)["daily.answer.text"]
        XCTAssertTrue(answer.waitForExistence(timeout: 5))
        answer.tap()
        answer.typeText("Wish you were sitting here too")
        XCTAssertTrue(photo.exists)
        XCTAssertTrue(app.descendants(matching: .any)["daily.answer.question"].exists)
        capture(app, named: "Photo and text with keyboard")
        app.buttons["daily.flow.primary"].tap()
        XCTAssertTrue(app.buttons["daily.chat.close"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Wish you were sitting here too"].waitForExistence(timeout: 5))
        capture(app, named: "Photo answer conversation")
    }

    @MainActor
    private func capture(_ app: XCUIApplication, named name: String) {
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = name
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

}
