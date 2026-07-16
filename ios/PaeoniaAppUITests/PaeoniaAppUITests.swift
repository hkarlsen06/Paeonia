import XCTest

final class PaeoniaAppUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testExample() throws {
        let app = XCUIApplication()
        app.launch()

        XCTAssertEqual(app.state, .runningForeground)
    }

    @MainActor
    func testQuestionsScenarioLaunchesWithoutAccountSetup() throws {
        let app = XCUIApplication()
        app.launchEnvironment["PAEONIA_SCENARIO"] = "questions"
        app.launch()

        XCTAssertTrue(
            app.buttons["mainTab.questions"].waitForExistence(timeout: 5)
        )
    }

    @MainActor
    func testScenarioSchemeArgumentOpensCatalog() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-paeonia-scenarios"]
        app.launch()

        XCTAssertTrue(app.navigationBars["Developer Scenarios"].waitForExistence(timeout: 5))
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
    func testCatalogKeepsItsPositionAfterReturningFromAScenario() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-paeonia-scenarios"]
        app.launch()

        let scenario = app.descendants(matching: .any)[
            "developer.scenario.deep-link-subscription"
        ]
        for _ in 0..<12 where !scenario.exists {
            app.swipeUp()
        }

        XCTAssertTrue(scenario.waitForExistence(timeout: 2))
        scenario.tap()
        app.buttons["developer.scenario.return"].tap()

        XCTAssertTrue(scenario.waitForExistence(timeout: 2))
    }

    @MainActor
    func testInteractiveLocalFlowContinuesFromSignInIntoPairing() throws {
        let app = XCUIApplication()
        app.launchEnvironment["PAEONIA_SCENARIO"] = "local-flow-fresh"
        app.launch()

        let skipWelcomeButton = app.buttons["auth.welcome.skip"]
        XCTAssertTrue(skipWelcomeButton.waitForExistence(timeout: 8))
        skipWelcomeButton.tap()

        let appleSignInButton = app.buttons["auth.signIn.apple"]
        XCTAssertTrue(appleSignInButton.waitForExistence(timeout: 5))
        appleSignInButton.tap()

        let nameField = app.textFields["auth.onboarding.displayName"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 5))
        nameField.tap()
        nameField.typeText("Alex")
        app.buttons["auth.onboarding.complete"].tap()

        let purchaseButton = app.buttons["paywall.primaryAction"]
        XCTAssertTrue(purchaseButton.waitForExistence(timeout: 5))
        purchaseButton.tap()

        XCTAssertTrue(app.buttons["pairing.checkAccess"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testLaunchPerformance() throws {
        // This measures how long it takes to launch your application.
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            XCUIApplication().launch()
        }
    }

    @MainActor
    func testReviewQABootstrap() throws {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let openButton = springboard.buttons["Åpne"]
        if openButton.waitForExistence(timeout: 5) {
            openButton.tap()
        }

        let app = XCUIApplication()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10))
        sleep(3)
        print("QA_APP_TREE_BEGIN\n\(app.debugDescription)\nQA_APP_TREE_END")

        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Review QA bootstrap"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }
}
