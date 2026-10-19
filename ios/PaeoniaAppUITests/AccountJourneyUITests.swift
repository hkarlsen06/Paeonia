import XCTest

/// The account actions on the profile screen, run through the real root in the
/// paired local flow. Each one ends the paired app and lands on the screen the
/// person should see next.
final class AccountJourneyUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testLoggingOutReturnsToSignIn() throws {
        let app = openProfileInPairedApp()

        confirm(app, row: "settings.account.logout", button: "settings.account.logout.confirm")

        XCTAssertTrue(app.buttons["auth.signIn.apple"].waitForExistence(timeout: 10))
    }

    @MainActor
    func testLeavingTheRelationshipReturnsToPairing() throws {
        let app = openProfileInPairedApp()

        confirm(app, row: "settings.account.leave", button: "settings.account.leave.confirm")

        XCTAssertTrue(app.buttons["pairing.share"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["mainTab.us"].exists)
    }

    @MainActor
    func testDeletingTheAccountReturnsToSignIn() throws {
        let app = openProfileInPairedApp()

        confirm(app, row: "settings.account.delete", button: "settings.account.delete.confirm")

        XCTAssertTrue(app.buttons["auth.signIn.apple"].waitForExistence(timeout: 10))
    }

    @MainActor
    private func openProfileInPairedApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["PAEONIA_SCENARIO"] = "local-flow-paired"
        app.launch()

        let usTab = app.buttons["mainTab.us"]
        XCTAssertTrue(usTab.waitForExistence(timeout: 10))
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

        let confirmButton = app.alerts.buttons[button]
        XCTAssertTrue(confirmButton.waitForExistence(timeout: 5))
        confirmButton.tap()
    }
}
