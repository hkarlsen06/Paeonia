import XCTest

/// Planning a visit from the Us tab in the paired local flow: a row asks when the partners
/// meet next, the visit screen opens the editor, and after the save the card counts down.
final class VisitJourneyUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testPlanningAVisitFromTheUsTabShowsTheCountdown() throws {
        let app = XCUIApplication()
        app.launchEnvironment["PAEONIA_SCENARIO"] = "local-flow-paired"
        // English, so the card's words can be checked.
        app.launchArguments += ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()

        let prompt = app.buttons["home.visit.prompt"]
        XCTAssertTrue(prompt.waitForExistence(timeout: 15))
        scrollUntilHittable(prompt, in: app)
        XCTAssertTrue(prompt.label.contains("When do you meet next?"), prompt.label)
        prompt.tap()

        let plan = app.buttons["visit.detail.plan"]
        XCTAssertTrue(plan.waitForExistence(timeout: 5))
        plan.tap()

        // A new visit starts two weeks out and lasts four days, so it saves as it is.
        let save = app.buttons["visit.editor.save"]
        XCTAssertTrue(save.waitForExistence(timeout: 5))
        XCTAssertTrue(save.isEnabled)
        save.tap()

        // The editor closes onto the visit screen, which now shows the visit.
        XCTAssertTrue(save.waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.buttons["visit.detail.edit"].exists)
        app.buttons["visit.detail.done"].tap()

        let card = app.buttons["home.visit.card"]
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        XCTAssertTrue(card.label.contains("14 days to go"), card.label)
        XCTAssertFalse(app.buttons["home.visit.prompt"].exists)
    }

    @MainActor
    private func scrollUntilHittable(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<6 where !element.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(element.isHittable)
    }
}
