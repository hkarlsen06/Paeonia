import XCTest

final class RecapJourneyUITests: XCTestCase {
    /// The anniversary push tapped while the app is not running: the link arrives before the Us tab has
    /// read its recaps, and the recap still opens.
    @MainActor
    func testTheAnniversaryLinkOpensTheRecapOnALaunch() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["PAEONIA_SCENARIO"] = "local-flow-paired"
        app.launchEnvironment["PAEONIA_LAUNCH_LINK"] = "paeonia://recap/2026-09-14"
        app.launchArguments += ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()

        let intro = app.descendants(matching: .any)["recap.page.intro"]
        XCTAssertTrue(intro.waitForExistence(timeout: 20))
        app.buttons["recap.done"].tap()
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 5))
    }
}
