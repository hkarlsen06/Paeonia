import XCTest

/// Home's "Things to try together" card after the first day, run through the real root in
/// the paired local flow. A row opens its feature, and the close button hides the card.
final class FirstStepsJourneyUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testARowOpensItsTabAndClosingHidesTheCard() throws {
        let app = XCUIApplication()
        app.launchEnvironment["PAEONIA_SCENARIO"] = "local-flow-paired"
        app.launch()

        // With five tabs the system tab bar drops the tabs' accessibility identifiers, so
        // the tabs are found by place: home, questions, games, memories, us.
        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 10))
        let homeTab = tabBar.buttons.element(boundBy: 0)
        let memoriesTab = tabBar.buttons.element(boundBy: 3)

        let memoryRow = app.buttons["home.firstSteps.memory"]
        XCTAssertTrue(memoryRow.waitForExistence(timeout: 10))
        scrollUntilHittable(memoryRow, in: app)
        memoryRow.tap()
        XCTAssertTrue(memoriesTab.waitForSelection(timeout: 5))

        homeTab.tap()
        let close = app.buttons["home.firstSteps.close"]
        XCTAssertTrue(close.waitForExistence(timeout: 5))
        scrollUntilHittable(close, in: app)
        close.tap()
        XCTAssertTrue(memoryRow.waitForNonExistence(timeout: 5))
    }

    /// The card sits under today's question, which can push it below the fold.
    @MainActor
    private func scrollUntilHittable(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<4 where !element.isHittable {
            app.swipeUp()
        }
    }
}

private extension XCUIElement {
    func waitForSelection(timeout: TimeInterval) -> Bool {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "isSelected == true"), object: self)
        return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
    }
}
