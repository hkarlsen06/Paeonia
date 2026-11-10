import XCTest

/// Planning a visit from the Us tab card in the paired local flow: the card asks when the
/// partners meet next, the editor saves a visit, and the card counts down to it.
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

        let plan = app.buttons["home.visit.plan"]
        XCTAssertTrue(plan.waitForExistence(timeout: 15))
        scrollUntilHittable(plan, in: app)
        XCTAssertTrue(app.staticTexts["When do you meet next?"].exists)
        plan.tap()

        // A new visit starts two weeks out and lasts four days, so it saves as it is.
        let save = app.buttons["visit.editor.save"]
        XCTAssertTrue(save.waitForExistence(timeout: 5))
        XCTAssertTrue(save.isEnabled)
        save.tap()

        let card = app.buttons["home.visit.card"]
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        XCTAssertTrue(card.label.contains("14 days to go"), card.label)
        XCTAssertFalse(app.buttons["home.visit.plan"].exists)
    }

    @MainActor
    private func scrollUntilHittable(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<6 where !element.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(element.isHittable)
    }
}
