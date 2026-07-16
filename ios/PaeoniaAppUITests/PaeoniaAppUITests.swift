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
    func testLocalFlowOnboardingMenuEntryNavigates() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-paeonia-scenarios"]
        app.launch()

        let row = app.descendants(matching: .any)[
            "developer.scenario.local-flow-onboarding"
        ]
        for _ in 0..<8 where !row.exists {
            app.swipeUp()
        }

        XCTAssertTrue(row.waitForExistence(timeout: 2))
        row.tap()
        XCTAssertTrue(app.buttons["developer.scenario.return"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testQuestionAnswerFlowMenuEntryReturnsToCatalog() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-paeonia-scenarios"]
        app.launch()

        let row = app.descendants(matching: .any)[
            "developer.scenario.question-answer-flow"
        ]
        for _ in 0..<12 where !row.exists {
            app.swipeUp()
        }

        XCTAssertTrue(row.waitForExistence(timeout: 2))
        row.tap()

        let returnButton = app.buttons["developer.scenario.return"]
        XCTAssertTrue(returnButton.waitForExistence(timeout: 5))
        returnButton.tap()
        XCTAssertTrue(app.navigationBars["Developer Scenarios"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testEveryDeveloperScenarioMenuEntryNavigatesAndReturns() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-paeonia-scenarios"]
        app.launch()

        XCTAssertTrue(app.navigationBars["Developer Scenarios"].waitForExistence(timeout: 5))

        for scenarioID in Self.developerScenarioIDs {
            let row = app.descendants(matching: .any)["developer.scenario.\(scenarioID)"]
            for _ in 0..<12 where !row.exists {
                app.swipeUp()
            }

            XCTAssertTrue(row.waitForExistence(timeout: 2), "Missing menu row: \(scenarioID)")
            row.tap()

            let returnButton = app.buttons["developer.scenario.return"]
            XCTAssertTrue(
                returnButton.waitForExistence(timeout: 5),
                "Did not open scenario: \(scenarioID)"
            )
            returnButton.tap()

            XCTAssertTrue(
                app.navigationBars["Developer Scenarios"].waitForExistence(timeout: 5),
                "Did not return from scenario: \(scenarioID)"
            )
        }
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

        let hierarchy = XCTAttachment(string: app.debugDescription)
        hierarchy.name = "Review QA app hierarchy"
        hierarchy.lifetime = .keepAlways
        add(hierarchy)

        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Review QA bootstrap"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    private static let developerScenarioIDs = [
        "launch-loading",
        "welcome",
        "sign-in",
        "sign-in-invite",
        "onboarding-empty",
        "onboarding-prefilled",
        "local-flow-fresh",
        "local-flow-onboarding",
        "local-flow-paywall",
        "local-flow-pairing",
        "local-flow-paired",
        "pairing-invite-ready",
        "pairing-join",
        "pairing-invite-expired",
        "pairing-safety-warning",
        "pairing-invite-error",
        "pairing-celebration",
        "pairing-celebration-settled",
        "paywall-trial",
        "paywall-standard",
        "paywall-paired",
        "paywall-loading",
        "paired-home",
        "questions",
        "questions-partial",
        "questions-revealed",
        "questions-empty",
        "questions-loading",
        "questions-error",
        "questions-history",
        "questions-offline-queued",
        "question-answer-flow",
        "streak-healthy",
        "streak-broken",
        "streak-restored",
        "memories-empty",
        "memories-populated",
        "memory-editor",
        "memory-detail",
        "countdown-missing",
        "countdown-upcoming",
        "countdown-today",
        "location-not-sharing",
        "location-current-missing",
        "location-live",
        "location-stale",
        "widget-drawing",
        "widget-history-empty",
        "widget-history-populated",
        "notification-primer",
        "settings",
        "settings-notifications-denied",
        "privacy-safety",
        "report-and-leave",
        "deep-link-daily-today",
        "deep-link-daily-reveal",
        "deep-link-widget",
        "deep-link-streak",
        "deep-link-subscription",
    ]
}
