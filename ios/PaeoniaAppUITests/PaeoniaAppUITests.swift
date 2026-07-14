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
