import XCTest

/// A former partner used the invite and asked to bring back what the two had. The
/// inviter answers through the real root in a local flow. Bringing it back plays the
/// reunion celebration and lands in the paired app. Starting fresh makes a new couple,
/// which gets the first pairing celebration even though this phone celebrated the
/// old couple.
final class RestoreRelationshipJourneyUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testBringingItBackCelebratesTheReunionThenOpensThePairedAppWithoutTheFirstDay() throws {
        let app = XCUIApplication()
        app.launchEnvironment["PAEONIA_SCENARIO"] = "local-flow-restore-request"
        app.launchArguments += ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()

        let bringBack = app.buttons["pairing.restore.request.bringBack"]
        XCTAssertTrue(bringBack.waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Robin wants to bring back what you had"].exists)
        XCTAssertFalse(app.buttons["pairing.share"].exists)

        bringBack.tap()

        // The couple came back: the celebration plays once more, as a reunion.
        let pickUp = app.buttons["pairingCelebration.continue"]
        XCTAssertTrue(pickUp.waitForExistence(timeout: 10))
        XCTAssertEqual(pickUp.label, "Pick up where you left off")
        XCTAssertFalse(bringBack.exists)
        // The button turns on once the intro has played.
        let enabled = XCTNSPredicateExpectation(predicate: NSPredicate(format: "isEnabled == true"), object: pickUp)
        XCTAssertEqual(XCTWaiter().wait(for: [enabled], timeout: 20), .completed)
        pickUp.tap()

        // No first day after it, only the tabs.
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 15))
        XCTAssertFalse(pickUp.exists)
    }

    @MainActor
    func testStartingFreshCelebratesTheNewCoupleAsAFirstPairing() throws {
        let app = XCUIApplication()
        app.launchEnvironment["PAEONIA_SCENARIO"] = "local-flow-restore-request"
        app.launchArguments += ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()

        let startFresh = app.buttons["pairing.restore.request.startFresh"]
        XCTAssertTrue(startFresh.waitForExistence(timeout: 10))
        startFresh.tap()

        // A new couple: the first pairing celebration, not the reunion.
        let getStarted = app.buttons["pairingCelebration.continue"]
        XCTAssertTrue(getStarted.waitForExistence(timeout: 10))
        XCTAssertNotEqual(getStarted.label, "Pick up where you left off")
        let enabled = XCTNSPredicateExpectation(predicate: NSPredicate(format: "isEnabled == true"), object: getStarted)
        XCTAssertEqual(XCTWaiter().wait(for: [enabled], timeout: 20), .completed)
        getStarted.tap()

        // The local flow's first day has nothing to show the inviter, so it ends on the tabs.
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 15))
        XCTAssertFalse(getStarted.exists)
    }
}
