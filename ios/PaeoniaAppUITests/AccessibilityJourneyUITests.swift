import XCTest

final class AccessibilityJourneyUITests: XCTestCase {
    @MainActor func testWelcomeAudit() throws { try audit("welcome") }

    @MainActor func testSignInAudit() throws { try audit("sign-in") }

    @MainActor func testPaywallAudit() throws { try audit("paywall-trial") }

    @MainActor func testHomeAudit() throws { try audit("paired-home") }

    @MainActor func testQuestionsAudit() throws { try audit("questions") }

    @MainActor func testMemoryAudit() throws { try audit("memory-detail") }

    @MainActor func testPrivacyAudit() throws { try audit("privacy-safety") }

    @MainActor func testHomeAtAX5InNorwegian() throws {
        try audit("paired-home", largestText: true, norwegian: true)
    }

    @MainActor func testSignInAtAX5InNorwegian() throws {
        try audit("sign-in", largestText: true, norwegian: true)
    }

    @MainActor func testDrawingAudit() throws { try audit("widget-drawing") }

    @MainActor func testWelcomeAtAX5InNorwegian() throws {
        try audit("welcome", largestText: true, norwegian: true)
    }

    @MainActor func testPaywallAtAX5InNorwegian() throws {
        try audit("paywall-trial", largestText: true, norwegian: true)
    }

    @MainActor func testAnswerAtAX5InNorwegian() throws {
        try audit("question-answer-flow", largestText: true, norwegian: true)
    }

    @MainActor func testMemoryEditorAtAX5InNorwegian() throws {
        try audit("memory-editor", largestText: true, norwegian: true)
    }

    @MainActor func testSettingsAtAX5InNorwegian() throws {
        try audit("settings", largestText: true, norwegian: true)
    }

    @MainActor
    func testStoriesCanPauseAndNavigateWithoutHoldingOrSwiping() throws {
        continueAfterFailure = false
        let app = launch("avatar-stories-new")
        let own = app.buttons["stories.own"]
        XCTAssertTrue(own.waitForExistence(timeout: 15))
        own.tap()
        let pause = app.buttons["story.viewer.pause"]
        if pause.waitForExistence(timeout: 2) { pause.tap() }
        let next = app.buttons["story.viewer.next"]
        XCTAssertTrue(next.isHittable)
        XCTAssertFalse(app.buttons["story.viewer.previous"].isEnabled)
        // The old viewer closed after six seconds. A paused story must stay available.
        let disappeared = NSPredicate(format: "exists == false")
        let expiry = XCTNSPredicateExpectation(predicate: disappeared, object: next)
        XCTAssertEqual(XCTWaiter.wait(for: [expiry], timeout: 7), .timedOut)
        capture(app, "Paused story")
        next.tap()
        XCTAssertTrue(own.waitForExistence(timeout: 5))
    }

    @MainActor
    private func audit(_ scenario: String, largestText: Bool = false, norwegian: Bool = false) throws {
        continueAfterFailure = true
        let settings = SimulatorTextSizeSettings(testCase: self)
        try settings.withSize(largestText ? .largestAccessibility : .standard) {
            try auditAtCurrentSystemSize(scenario, largestText: largestText, norwegian: norwegian)
        }
    }

    @MainActor
    private func auditAtCurrentSystemSize(_ scenario: String, largestText: Bool, norwegian: Bool) throws {
        let app = launch(scenario, norwegian: norwegian)
        defer { app.terminate() }
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10))
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 10))
        capture(app, "\(scenario)-before-audit\(largestText ? "-AX5" : "-standard")\(norwegian ? "-nb" : "-en")")
        try app.performAccessibilityAudit { issue in
            let details = """
            Type: \(issue.auditType.rawValue)
            \(issue.compactDescription)
            \(issue.detailedDescription)
            Element: \(issue.element?.debugDescription ?? "unavailable")
            """
            let attachment = XCTAttachment(string: details)
            attachment.name = "Accessibility issue"
            attachment.lifetime = .keepAlways
            self.add(attachment)
            return false
        }
        capture(app, "\(scenario)\(largestText ? "-AX5" : "")\(norwegian ? "-nb" : "-en")")
    }

    @MainActor
    private func launch(_ scenario: String, norwegian: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["PAEONIA_SCENARIO"] = scenario
        app.launchArguments = ["-paeonia-scenario-hide-controls", "YES"]
        app.launchArguments += norwegian
            ? ["-AppleLanguages", "(nb)", "-AppleLocale", "nb_NO"]
            : ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        return app
    }

    @MainActor
    private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
