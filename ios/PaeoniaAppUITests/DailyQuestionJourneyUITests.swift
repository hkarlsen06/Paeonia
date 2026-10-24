import XCTest

/// Answering a daily question the partner already answered, run through the real root in
/// the paired local flow. The answer reveals the partner's in place, and Open chat takes
/// the person to the question's chat.
final class DailyQuestionJourneyUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testAnsweringRevealsThePartnerAnswerAndOpensTheChat() throws {
        let app = XCUIApplication()
        app.launchEnvironment["PAEONIA_SCENARIO"] = "local-flow-paired"
        app.launch()

        // The local flow's partner answered yesterday's question, so it waits on the Home
        // card as a locked row.
        let lockedRow = app.buttons.matching(identifier: "daily.lockedRow").firstMatch
        XCTAssertTrue(lockedRow.waitForExistence(timeout: 10))
        lockedRow.tap()

        let answerField = app.descendants(matching: .any)["daily.answer.text"]
        XCTAssertTrue(answerField.waitForExistence(timeout: 5))
        answerField.tap()
        answerField.typeText("The lake walk")

        let send = app.buttons["daily.flow.primary"]
        XCTAssertTrue(send.waitForExistence(timeout: 5))
        send.tap()

        let openChat = app.buttons["daily.reveal.openChat"]
        XCTAssertTrue(openChat.waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["daily.reveal.done"].exists)
        openChat.tap()

        XCTAssertTrue(app.descendants(matching: .any)["chat.composer.field"].waitForExistence(timeout: 10))
    }
}
