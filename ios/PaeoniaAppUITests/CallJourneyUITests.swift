import XCTest

/// A call through the real root, with a partner who answers in place of the call service: it
/// starts from a game's toolbar, shrinks to the bubble, follows the person into "Just us", and
/// ends from the bubble with its row in the chat.
final class CallJourneyUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testCallFromGameShrinksToBubbleAndEndsInJustUs() throws {
        let app = XCUIApplication()
        app.launchEnvironment["PAEONIA_SCENARIO"] = "local-flow-call"
        app.launchArguments += [
            "-AppleLanguages", "(en)", "-AppleLocale", "en_US", "-paeonia-scenario-hide-controls", "YES",
        ]
        app.launch()

        let minimize = startCallFromGame(in: app)
        minimize.tap()
        let bubble = app.descendants(matching: .any)["calls.bubble"].firstMatch
        XCTAssertTrue(bubble.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(minimize.waitForNonExistence(timeout: 5))

        // Leave the game for "Just us" while the call goes on in its bubble.
        app.navigationBars.buttons.element(boundBy: 0).tap()
        let tabs = app.tabBars.firstMatch
        XCTAssertTrue(tabs.waitForExistence(timeout: 5), app.debugDescription)
        tabs.buttons.element(boundBy: 1).tap()
        let justUs = app.buttons["chats.coupleChat"]
        XCTAssertTrue(justUs.waitForExistence(timeout: 10), app.debugDescription)
        justUs.tap()
        XCTAssertTrue(
            app.descendants(matching: .any)["chat.composer.field"].firstMatch.waitForExistence(timeout: 10),
            app.debugDescription)
        XCTAssertTrue(bubble.exists, app.debugDescription)
        let callRow = app.descendants(matching: .any)["chat.callRow"].firstMatch
        XCTAssertFalse(callRow.exists)
        attach(app, named: "Just us with the call in its bubble")

        let end = app.buttons["calls.bubble.end"]
        XCTAssertTrue(end.isHittable, app.debugDescription)
        end.tap()
        XCTAssertTrue(callRow.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(bubble.waitForNonExistence(timeout: 10), app.debugDescription)
        attach(app, named: "Just us with the finished call's row")
    }

    /// Calls from the game's toolbar and waits on the call screen until the call time runs.
    /// Returns the call screen's minimize button.
    @MainActor
    private func startCallFromGame(in app: XCUIApplication) -> XCUIElement {
        let tutorial = app.buttons["games.tutorial.next"]
        for _ in 0..<3 where tutorial.waitForExistence(timeout: 1) { tutorial.tap() }
        let callButton = app.buttons["calls.start"].firstMatch
        XCTAssertTrue(callButton.waitForExistence(timeout: 10), app.debugDescription)
        callButton.tap()

        let minimize = app.buttons["calls.minimize"]
        XCTAssertTrue(minimize.waitForExistence(timeout: 5), app.debugDescription)
        let status = app.descendants(matching: .any)["calls.status"].firstMatch
        XCTAssertTrue(status.waitForExistence(timeout: 5), app.debugDescription)
        // The call time, such as "0:01", shows once the partner has answered and the phones connected.
        let timer = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label MATCHES %@", ".*\\b[0-9]+:[0-9]{2}\\b.*"), object: status)
        XCTAssertEqual(XCTWaiter.wait(for: [timer], timeout: 10), .completed, status.debugDescription)
        attach(app, named: "Call screen with the call running")
        return minimize
    }

    @MainActor
    private func attach(_ app: XCUIApplication, named name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
