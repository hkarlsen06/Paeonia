import XCTest

/// More > Licences in the paired local flow. The list comes from a text file in the
/// app bundle, so an empty list means the file did not ship.
final class LicencesJourneyUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testLicencesListsThePackagesAndOpensOne() throws {
        let app = XCUIApplication()
        app.launchEnvironment["PAEONIA_SCENARIO"] = "local-flow-paired"
        app.launch()

        // With five tabs the system tab bar drops the tabs' accessibility identifiers, so
        // the More tab is found by its place, the last one.
        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 10))
        let moreTab = tabBar.buttons.element(boundBy: 4)
        XCTAssertTrue(moreTab.waitForExistence(timeout: 5))
        moreTab.tap()

        // The row is the last on the menu, and list rows off screen may not exist yet.
        let licencesRow = app.buttons["settings.licences"]
        for _ in 0..<6 where !(licencesRow.exists && licencesRow.isHittable) {
            app.swipeUp()
        }
        XCTAssertTrue(licencesRow.waitForExistence(timeout: 5))
        licencesRow.tap()

        let firstPackage = app.buttons.matching(identifier: "licences.package").firstMatch
        XCTAssertTrue(firstPackage.waitForExistence(timeout: 5))
        firstPackage.tap()

        XCTAssertTrue(app.staticTexts["licences.text"].waitForExistence(timeout: 5))
    }
}
