import XCTest

final class ProfileAccessibilityJourneyUITests: XCTestCase {
    @MainActor
    func testProfileOpensFromTheCoupleHeaderAndCancellingKeepsTheSavedName() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-paeonia-scenario", "settings", "-paeonia-scenario-hide-controls", "YES",
                               "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        defer { app.terminate() }
        let profile = app.buttons["settings.coupleHeader.profile"]
        XCTAssertTrue(profile.waitForExistence(timeout: 10))
        scrollTo(profile, in: app)
        profile.tap()

        let photo = app.buttons["settings.profile.photo.change"]
        scrollTo(photo, in: app)
        XCTAssertTrue(photo.isHittable)
        let field = app.textFields["settings.profile.displayName"]
        scrollTo(field, in: app)
        let savedName = field.value as? String
        field.tap()
        field.typeText("andria")
        XCTAssertTrue((field.value as? String)?.contains("andria") == true)
        let save = app.buttons["settings.profile.save"]
        scrollTo(save, in: app)
        XCTAssertTrue(save.isEnabled)
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Profile editing and reachable Save at actual system text size"
        attachment.lifetime = .keepAlways
        add(attachment)

        app.buttons["settings.profile.cancel"].tap()
        scrollTo(field, in: app, scrollsDown: false)
        XCTAssertEqual(field.value as? String, savedName)
        XCTAssertFalse(app.buttons["settings.profile.cancel"].exists)
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(profile.waitForExistence(timeout: 5))
        XCTAssertTrue(profile.isHittable)
    }

    @MainActor
    private func scrollTo(_ element: XCUIElement, in app: XCUIApplication, scrollsDown: Bool = true) {
        for _ in 0..<12 where !element.exists || !element.isHittable {
            if element.exists && element.frame.midY < app.windows.firstMatch.frame.midY {
                app.swipeDown()
            } else if element.exists || scrollsDown {
                app.swipeUp()
            } else {
                app.swipeDown()
            }
        }
        XCTAssertTrue(element.isHittable)
    }
}
