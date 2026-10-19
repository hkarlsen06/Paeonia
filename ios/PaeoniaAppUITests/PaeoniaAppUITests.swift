import XCTest

final class PaeoniaAppUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testQuestionsScenarioLaunchesWithoutAccountSetup() throws {
        let app = XCUIApplication()
        app.launchEnvironment["PAEONIA_SCENARIO"] = "questions"
        app.launch()

        XCTAssertTrue(
            app.buttons["mainTab.questions"].waitForExistence(timeout: 10)
        )
    }

    @MainActor
    func testPaywallScenarioUsesTheCompleteProductionSurface() throws {
        let app = XCUIApplication()
        app.launchEnvironment["PAEONIA_SCENARIO"] = "paywall-standard"
        app.launch()

        let privacyLink = app.links["legal.privacy"]
        for _ in 0..<6 where !privacyLink.exists {
            app.swipeUp()
        }

        XCTAssertTrue(privacyLink.waitForExistence(timeout: 2))
        XCTAssertTrue(app.links["legal.terms"].exists)
    }

    @MainActor
    func testInteractiveLocalFlowContinuesFromSignInIntoPairing() throws {
        let app = XCUIApplication()
        app.launchEnvironment["PAEONIA_SCENARIO"] = "local-flow-fresh"
        app.launch()

        // Welcome and sign-in are one screen.
        let appleSignInButton = app.buttons["auth.signIn.apple"]
        XCTAssertTrue(appleSignInButton.waitForExistence(timeout: 8))
        appleSignInButton.tap()

        // Setup needs a photo. The system photo picker runs out of process, but its
        // grid still shows up in the app's element tree. Match the grid cells by their
        // identifier, because a looser query finds the app's own placeholder image
        // behind the picker while the picker is still loading.
        let photoButton = app.buttons["auth.onboarding.profilePhoto"]
        XCTAssertTrue(photoButton.waitForExistence(timeout: 5))
        photoButton.tap()
        let firstPhoto = app.images.matching(identifier: "PXGGridLayout-Info").firstMatch
        XCTAssertTrue(firstPhoto.waitForExistence(timeout: 10))
        firstPhoto.tap()
        let cropDone = app.buttons["imageCrop.done"]
        XCTAssertTrue(cropDone.waitForExistence(timeout: 5))
        cropDone.tap()

        let nameField = app.textFields["auth.onboarding.displayName"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 5))
        nameField.tap()
        // The keyboard covers the complete button. Its continue key does the same.
        nameField.typeText("Alex\n")

        let skipStartDate = app.buttons["auth.onboarding.startDate.skip"]
        XCTAssertTrue(skipStartDate.waitForExistence(timeout: 5))
        skipStartDate.tap()

        let purchaseButton = app.buttons["paywall.primaryAction"]
        XCTAssertTrue(purchaseButton.waitForExistence(timeout: 5))
        purchaseButton.tap()

        XCTAssertTrue(app.buttons["pairing.share"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testCatalogOpensAScenarioAndReturnsToTheSamePlace() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-paeonia-scenarios"]
        app.launch()

        XCTAssertTrue(app.navigationBars["Developer Scenarios"].waitForExistence(timeout: 5))

        // Searching avoids swiping, which can leave the row under the bottom search bar.
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap()
        search.typeText("question-answer-flow")

        let row = app.descendants(matching: .any)["developer.scenario.question-answer-flow"]
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.tap()

        let returnButton = app.buttons["developer.scenario.return"]
        XCTAssertTrue(returnButton.waitForExistence(timeout: 5))
        returnButton.tap()

        // The catalog stays behind the scenario, so the search and its result are still there.
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        XCTAssertEqual(search.value as? String, "question-answer-flow")
    }

    @MainActor
    func testEveryDeveloperScenarioOpens() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-paeonia-scenario-tour"]
        app.launch()

        XCTAssertTrue(app.staticTexts["developer.scenario.tour.done"].waitForExistence(timeout: 120))
    }
}
