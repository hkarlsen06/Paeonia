import XCTest

/// These probes retain keyboard presentation and dismissal diagnostics in the
/// result bundle. Passing assertions do not establish that runtime warnings stopped.
final class NativeKeyboardDiagnosticUITests: XCTestCase {
    @MainActor
    func testPresentedNativeFormWithoutKeyboardToolbar() {
        exerciseForm(scenario: "keyboard-plain-form", hasKeyboardToolbar: false)
    }

    @MainActor
    func testPresentedNativeFormWithKeyboardToolbar() {
        exerciseForm(scenario: "keyboard-toolbar-form", hasKeyboardToolbar: true)
    }

    @MainActor
    func testPresentedNativeFormWithSingleKeyboardItem() {
        exerciseForm(scenario: "keyboard-single-item-form", hasKeyboardToolbar: true)
    }

    @MainActor
    private func exerciseForm(scenario: String, hasKeyboardToolbar: Bool) {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = [
            "-paeonia-scenario", scenario, "-paeonia-scenario-hide-controls", "YES",
            "-AppleLanguages", "(en)", "-AppleLocale", "en_US"
        ]
        app.launch()
        defer { app.terminate() }
        let open = app.buttons["keyboard.diagnostic.open"]
        XCTAssertTrue(open.waitForExistence(timeout: 10))
        open.tap()
        let field = app.descendants(matching: .any)["keyboard.diagnostic.text"].firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        attach(app, name: "Native Form before keyboard")
        field.tap()
        field.typeText("A circle above a line.")
        XCTAssertEqual(field.value as? String, "A circle above a line.")
        attach(app, name: "Native Form while editing")
        if hasKeyboardToolbar {
            app.buttons["keyboard.diagnostic.keyboard.done"].tap()
        }
        app.buttons["keyboard.diagnostic.sheet.done"].tap()
        XCTAssertTrue(open.waitForExistence(timeout: 5))
        XCTAssertTrue(open.isHittable)
        attach(app, name: "Native Form after dismissal")
    }

    @MainActor
    private func attach(_ app: XCUIApplication, name: String) {
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = name
        screenshot.lifetime = .keepAlways
        add(screenshot)
        let hierarchy = XCTAttachment(string: app.debugDescription)
        hierarchy.name = "\(name) hierarchy"
        hierarchy.lifetime = .keepAlways
        add(hierarchy)
    }
}
