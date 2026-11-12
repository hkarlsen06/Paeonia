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

    @MainActor
    func testALetterOnItsWayIsChangedFromTheSentList() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["PAEONIA_SCENARIO"] = "local-flow-paired"
        app.launchArguments += ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        let row = sendALetterForTheMorning(in: app)

        row.swipeLeft()
        let change = app.buttons["Change"]
        XCTAssertTrue(change.waitForExistence(timeout: 5))
        change.tap()
        let note = app.textViews["mail.composer.note"]
        XCTAssertTrue(note.waitForExistence(timeout: 5))
        XCTAssertEqual(note.value as? String, "I miss you.")
        XCTAssertTrue(app.navigationBars["Change letter"].exists)
        note.tap()
        note.typeText(" See you Friday.")

        let next = app.buttons["mail.composer.next"]
        next.tap()
        XCTAssertTrue(app.buttons["mail.composer.photo"].waitForExistence(timeout: 5))
        next.tap()
        let save = app.buttons["mail.composer.send"]
        XCTAssertTrue(save.waitForExistence(timeout: 5))
        XCTAssertEqual(save.label, "Save changes")
        save.tap()

        // The row shows the new words once the change is saved, a moment after the composer closes.
        let changedRow = NSPredicate(
            format: "identifier == %@ AND label CONTAINS %@", "mail.mailbox.row", "I miss you. See you Friday."
        )
        let changed = app.buttons.matching(changedRow).firstMatch
        XCTAssertTrue(changed.waitForExistence(timeout: 10))
        XCTAssertTrue(changed.label.contains("Arrives"), changed.label)
        XCTAssertEqual(app.buttons.matching(identifier: "mail.mailbox.row").count, 1)
    }

    /// Writes a "Miss you" letter for the partner's morning from the Us tab card, and returns its
    /// row in the Sent list.
    @MainActor
    private func sendALetterForTheMorning(in app: XCUIApplication) -> XCUIElement {
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
        let next = app.buttons["mail.composer.next"]
        XCTAssertTrue(next.waitForExistence(timeout: 5))
        next.tap()
        XCTAssertTrue(app.buttons["mail.composer.photo"].waitForExistence(timeout: 5))
        next.tap()
        let morning = app.buttons["mail.delivery.morning"]
        XCTAssertTrue(morning.waitForExistence(timeout: 5))
        morning.tap()
        app.buttons["mail.composer.send"].tap()
        let row = app.buttons["mail.mailbox.row"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        return row
    }
}
