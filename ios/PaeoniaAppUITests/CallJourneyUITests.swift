import XCTest

/// Calls through the real root, with a partner in place of the call service. One starts from a
/// game's toolbar, shrinks to the bubble, follows the person into "Just us", and ends from the
/// bubble with its row in the chat. Another opens "Just us" under the full call and closes it again.
/// In the last the partner calls while the app is open, and the call rings in its pill, opens to the
/// call screen and connects when the person answers.
final class CallJourneyUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testCallFromGameShrinksToBubbleAndEndsInJustUs() throws {
        let app = launch(scenario: "local-flow-call")

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

    /// Message on the call screen raises "Just us" under the call, which shrinks to the top. A
    /// message sent there shows in the chat, and a tap on the small call closes the chat and grows
    /// the call back.
    @MainActor
    func testJustUsRisesUnderTheCallAndTheCallGrowsBack() throws {
        let app = launch(scenario: "local-flow-call")

        let minimize = startCallFromGame(in: app)
        let message = app.buttons["calls.openChat"]
        XCTAssertTrue(message.waitForExistence(timeout: 5), app.debugDescription)
        message.tap()

        let field = app.descendants(matching: .any)["chat.composer.field"].firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 10), app.debugDescription)
        let smallCall = app.descendants(matching: .any)["calls.chat.preview"].firstMatch
        XCTAssertTrue(smallCall.waitForExistence(timeout: 5), app.debugDescription)
        // UI tests still list views hidden from VoiceOver, so the full call's faded controls show
        // as not hittable instead of gone.
        XCTAssertTrue(waitUntil(minimize, isHittable: false), app.debugDescription)
        field.tap()
        field.typeText("Can you hear the rain?")
        let send = app.buttons["chat.composer.send"]
        XCTAssertTrue(send.waitForExistence(timeout: 5), app.debugDescription)
        send.tap()
        XCTAssertTrue(app.staticTexts["Can you hear the rain?"].waitForExistence(timeout: 5), app.debugDescription)
        attach(app, named: "Just us under the call with the sent message")

        smallCall.tap()
        XCTAssertTrue(field.waitForNonExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(waitUntil(minimize, isHittable: true), app.debugDescription)
        XCTAssertTrue(app.buttons["calls.end"].isHittable, app.debugDescription)
        attach(app, named: "The call grown back after closing Just us")
    }

    @MainActor
    func testPartnersCallRingsInItsPillAndConnectsFromTheCallScreen() throws {
        let app = launch(scenario: "local-flow-incoming-call")

        let ring = app.descendants(matching: .any)["calls.ring"].firstMatch
        XCTAssertTrue(ring.waitForExistence(timeout: 15), app.debugDescription)
        XCTAssertTrue(app.buttons["calls.ring.answer"].exists, app.debugDescription)
        XCTAssertTrue(app.buttons["calls.ring.decline"].exists, app.debugDescription)
        attach(app, named: "The partner's call ringing in its pill over Us")

        ring.tap()
        let answer = app.buttons["calls.answer"]
        XCTAssertTrue(answer.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(ring.waitForNonExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(app.buttons["calls.decline"].exists, app.debugDescription)
        attach(app, named: "Call screen while the partner's call rings")

        answer.tap()
        waitForCallTime(in: app)
        XCTAssertFalse(answer.exists, app.debugDescription)
        app.buttons["calls.end"].tap()
        XCTAssertTrue(
            app.descendants(matching: .any)["calls.status"].firstMatch.waitForNonExistence(timeout: 10),
            app.debugDescription)
    }

    @MainActor
    private func launch(scenario: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["PAEONIA_SCENARIO"] = scenario
        app.launchArguments += [
            "-AppleLanguages", "(en)", "-AppleLocale", "en_US", "-paeonia-scenario-hide-controls", "YES",
        ]
        app.launch()
        return app
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
        waitForCallTime(in: app)
        return minimize
    }

    /// Waits on the call screen until the call time, such as "0:01", shows, once the partner has
    /// answered and the phones connected.
    @MainActor
    private func waitForCallTime(in app: XCUIApplication) {
        let status = app.descendants(matching: .any)["calls.status"].firstMatch
        XCTAssertTrue(status.waitForExistence(timeout: 5), app.debugDescription)
        let timer = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label MATCHES %@", ".*\\b[0-9]+:[0-9]{2}\\b.*"), object: status)
        XCTAssertEqual(XCTWaiter.wait(for: [timer], timeout: 10), .completed, status.debugDescription)
        attach(app, named: "Call screen with the call running")
    }

    /// Waits up to 5 seconds for `element` to become hittable or not.
    @MainActor
    private func waitUntil(_ element: XCUIElement, isHittable: Bool) -> Bool {
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "hittable == %@", NSNumber(value: isHittable)), object: element)
        return XCTWaiter.wait(for: [expectation], timeout: 5) == .completed
    }

    @MainActor
    private func attach(_ app: XCUIApplication, named name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
