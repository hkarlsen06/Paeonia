import XCTest

final class PrivacyDraftJourneyUITests: XCTestCase {
    @MainActor
    func testDismissingCorrectionSheetKeepsTheUnsentRequest() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["PAEONIA_SCENARIO"] = "local-flow-paired"
        app.launch()

        let tabs = app.tabBars.firstMatch
        XCTAssertTrue(tabs.waitForExistence(timeout: 10))
        tabs.buttons.element(boundBy: 4).tap()
        let privacy = app.buttons["settings.privacy"]
        for _ in 0..<8 where !privacy.isHittable { app.swipeUp() }
        XCTAssertTrue(privacy.waitForExistence(timeout: 5))
        privacy.tap()
        let open = app.buttons["privacy.correction.open"]
        XCTAssertTrue(open.waitForExistence(timeout: 5))
        open.tap()

        let field = app.descendants(matching: .any)["privacy.correction.details"].firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText("Please correct my relationship start date.")
        let cancel = app.buttons["privacy.correction.cancel"]
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.075))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.9))
        start.press(forDuration: 0.1, thenDragTo: end)
        XCTAssertTrue(cancel.waitForNonExistence(timeout: 5))
        open.tap()
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        XCTAssertEqual(field.value as? String, "Please correct my relationship start date.")
    }
}
