import XCTest

final class MailJourneyUITests: XCTestCase {
    @MainActor
    func testALetterWrittenFromTheUsTabCardShowsInTheSentList() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["PAEONIA_SCENARIO"] = "local-flow-paired"
        app.launchArguments += ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()

        let write = app.buttons["home.mail.write"]
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 20))
        for _ in 0..<6 where !write.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(write.waitForExistence(timeout: 5))
        write.tap()

        let missYou = app.buttons["mail.template.miss_you"]
        XCTAssertTrue(missYou.waitForExistence(timeout: 5))
        missYou.tap()
        let note = app.textViews["mail.composer.note"]
        XCTAssertTrue(note.waitForExistence(timeout: 5))
        XCTAssertEqual(note.value as? String, "I miss you.")

        let next = app.buttons["mail.composer.next"]
        next.tap()
        XCTAssertTrue(app.buttons["mail.composer.photo"].waitForExistence(timeout: 5))
        next.tap()
        let morning = app.buttons["mail.delivery.morning"]
        XCTAssertTrue(morning.waitForExistence(timeout: 5))
        morning.tap()
        XCTAssertTrue(morning.isSelected)
        app.buttons["mail.composer.send"].tap()

        let row = app.buttons["mail.mailbox.row"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        XCTAssertTrue(row.label.contains("I miss you."), row.label)
        XCTAssertTrue(row.label.contains("Arrives"), row.label)
    }
}
