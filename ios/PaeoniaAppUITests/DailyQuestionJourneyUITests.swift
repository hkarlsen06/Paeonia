import XCTest

/// Answering a daily question the partner already answered, run through the real root in
/// the paired local flow. The answer turns the cover into the question's chat, where the
/// partner's answer shows, and closing it goes back to the screen that opened the flow.
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
        XCTAssertTrue(answerField.waitForExistence(timeout: 5))
        answerField.tap()
        answerField.typeText("The lake walk")

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
}
