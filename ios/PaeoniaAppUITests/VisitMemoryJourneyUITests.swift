import XCTest

/// The Us tab's card after a visit, in the paired local flow: it opens the new-memory form on
/// the visit's first day and place, and once the person saved a photo from the visit it goes.
final class VisitMemoryJourneyUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testSavingAPhotoFromTheVisitCardHidesTheCard() throws {
        let app = XCUIApplication()
        app.launchEnvironment["PAEONIA_SCENARIO"] = "local-flow-paired"
        // English, so the date and the button names can be checked.
        app.launchArguments += [
            "-paeonia-scenario-visit-ended", "-AppleLanguages", "(en)", "-AppleLocale", "en_US",
        ]
        app.launch()

        let card = app.buttons["home.visitMemory.card"]
        XCTAssertTrue(card.waitForExistence(timeout: 15))
        scrollUntilHittable(card, in: app)
        card.tap()

        // The visit started five days ago, at Bryggen.
        let firstDay = Calendar.current.date(byAdding: .day, value: -5, to: Date()) ?? Date()
        let date = firstDay.formatted(.dateTime.month(.abbreviated).day().year().locale(Locale(identifier: "en_US")))
        XCTAssertTrue(element(labelled: date, in: app).waitForExistence(timeout: 5), date)
        XCTAssertTrue(element(labelled: "Bryggen", in: app).exists)

        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        app.typeText("Rainy Bergen")

        // The system photo picker runs out of process, and its grid shows in the app's tree.
        app.buttons["Add photo"].tap()
        let firstPhoto = app.images.matching(identifier: "PXGGridLayout-Info").firstMatch
        XCTAssertTrue(firstPhoto.waitForExistence(timeout: 10))
        firstPhoto.tap()
        let add = app.buttons["Add"]
        if add.waitForExistence(timeout: 3) { add.tap() }

        let save = app.buttons["memories.editor.save"].firstMatch
        XCTAssertTrue(save.waitForExistence(timeout: 5))
        let enabled = NSPredicate(format: "isEnabled == true")
        expectation(for: enabled, evaluatedWith: save)
        waitForExpectations(timeout: 10)
        save.tap()

        XCTAssertTrue(save.waitForNonExistence(timeout: 10))
        XCTAssertTrue(card.waitForNonExistence(timeout: 10))
    }

    @MainActor
    private func element(labelled text: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS %@ OR value CONTAINS %@", text, text)).firstMatch
    }

    @MainActor
    private func scrollUntilHittable(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<6 where !element.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(element.isHittable)
    }
}
