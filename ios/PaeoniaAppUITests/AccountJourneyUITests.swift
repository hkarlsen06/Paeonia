import XCTest

/// The account actions on the profile screen, run through the real root in the
/// paired local flow. Each one ends the paired app and lands on the screen the
/// person should see next.
final class AccountJourneyUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// Sign-in for someone returning, with a way back to the welcome screen.
    @MainActor
    func testLoggingOutReturnsToSignIn() throws {
        let app = openProfileInPairedApp()

        confirm(app, row: "settings.account.logout", button: "settings.account.logout.confirm")

        XCTAssertTrue(app.buttons["auth.signIn.apple"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.staticTexts["welcome.signIn.title"].label, "Welcome back")
        app.buttons["welcome.signIn.back"].tap()
        XCTAssertTrue(app.buttons["welcome.start"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testLeavingTheRelationshipReturnsToPairing() throws {
        let app = openProfileInPairedApp()

        confirm(app, row: "settings.account.leave", button: "settings.account.leave.confirm")

        XCTAssertTrue(app.buttons["pairing.share"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.tabBars.firstMatch.exists)
    }

    /// The account is gone, so the phone starts over at the welcome screen.
    @MainActor
    func testDeletingTheAccountReturnsToWelcome() throws {
        let app = openProfileInPairedApp()

        confirm(app, row: "settings.account.delete", button: "settings.account.delete.confirm")

        XCTAssertTrue(app.buttons["welcome.start"].waitForExistence(timeout: 10))
    }

    @MainActor
    private func openProfileInPairedApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["PAEONIA_SCENARIO"] = "local-flow-paired"
        // English, so the headlines can be checked.
        app.launchArguments += ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()

        // With five tabs the system tab bar drops the tabs' accessibility identifiers, so
        // the Us tab is found by its place: the last of home, questions, games, memories, us.
        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 10))
        let usTab = tabBar.buttons.element(boundBy: 4)
        XCTAssertTrue(usTab.waitForExistence(timeout: 5))
        usTab.tap()

        let profileRow = app.buttons["settings.profile"]
        XCTAssertTrue(profileRow.waitForExistence(timeout: 5))
        profileRow.tap()
        return app
    }

    /// The account rows sit below the name and photo, so swipe until the row shows.
    @MainActor
    private func confirm(_ app: XCUIApplication, row: String, button: String) {
        let rowButton = app.buttons[row]
        for _ in 0..<6 where !(rowButton.exists && rowButton.isHittable) {
            app.swipeUp()
        }
        XCTAssertTrue(rowButton.waitForExistence(timeout: 5))
        rowButton.tap()

        // An alert action shows as a button inside a button with the same identifier.
        let confirmButton = app.alerts.buttons.matching(identifier: button).firstMatch
        XCTAssertTrue(confirmButton.waitForExistence(timeout: 5))
        confirmButton.tap()
    }
}
