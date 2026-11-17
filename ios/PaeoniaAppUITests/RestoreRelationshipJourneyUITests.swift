import XCTest

/// A former partner used the invite and asked to bring back what the two had. The
/// inviter answers through the real root in a local flow and lands in the paired app.
final class RestoreRelationshipJourneyUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testBringingItBackOpensThePairedAppWithoutTheFirstDay() throws {
        let app = XCUIApplication()
        app.launchEnvironment["PAEONIA_SCENARIO"] = "local-flow-restore-request"
        app.launchArguments += ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()

        let bringBack = app.buttons["pairing.restore.request.bringBack"]
        XCTAssertTrue(bringBack.waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Robin wants to bring back what you had"].exists)
        XCTAssertFalse(app.buttons["pairing.share"].exists)

        bringBack.tap()

        // The couple came back, so there is no celebration or first day, only the tabs.
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 15))
        XCTAssertFalse(bringBack.exists)
    }
}
