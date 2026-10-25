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

    /// The person who starts the couple picks the date and makes the first drawing
    /// before there is an account, then signs in, sets up the profile, sees that the
    /// drawing is ready on the paywall, and reaches the invite screen.
    @MainActor
    func testInteractiveLocalFlowStartsACoupleFromWelcomeIntoPairing() throws {
        let app = XCUIApplication()
        app.launchEnvironment["PAEONIA_SCENARIO"] = "local-flow-fresh"
        // English, so the headlines can be checked.
        app.launchArguments += ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()

        pickTheDateAndDrawBeforeSignIn(app)

        let signInTitle = app.staticTexts["welcome.signIn.title"]
        XCTAssertTrue(signInTitle.waitForExistence(timeout: 5))
        XCTAssertEqual(signInTitle.label, "Keep your drawing for them")
        XCTAssertTrue(app.buttons["welcome.signIn.back"].exists)

        let appleSignInButton = app.buttons["auth.signIn.apple"]
        XCTAssertTrue(appleSignInButton.waitForExistence(timeout: 5))
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

        let purchaseButton = app.buttons["paywall.primaryAction"]
        XCTAssertTrue(purchaseButton.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Your drawing is ready"].exists)
        purchaseButton.tap()

        XCTAssertTrue(app.buttons["pairing.share"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["inviter.questions"].waitForExistence(timeout: 5))
    }

    /// Welcome, Start our space, the date with its days count, then a drawing that lands
    /// on a picture of a Home Screen.
    @MainActor
    private func pickTheDateAndDrawBeforeSignIn(_ app: XCUIApplication) {
        let startButton = app.buttons["welcome.start"]
        XCTAssertTrue(startButton.waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["welcome.invited"].exists)
        XCTAssertTrue(app.buttons["welcome.returning"].exists)
        startButton.tap()

        // Continue saves the date and plays the days count, which moves on by itself.
        let continueDate = app.buttons["welcome.startDate.continue"]
        XCTAssertTrue(continueDate.waitForExistence(timeout: 5))
        continueDate.tap()

        let canvas = app.otherElements["widgetDrawing.canvas"].firstMatch
        XCTAssertTrue(canvas.waitForExistence(timeout: 10))
        canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.3))
            .press(forDuration: 0.05, thenDragTo: canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.7, dy: 0.6)))
        let send = app.buttons["widgetDrawing.send"]
        XCTAssertTrue(send.waitForExistence(timeout: 5))
        send.tap()

        let landedContinue = app.buttons["Continue"].firstMatch
        XCTAssertTrue(landedContinue.waitForExistence(timeout: 5))
        landedContinue.tap()
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
