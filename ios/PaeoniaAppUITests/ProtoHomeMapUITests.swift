import XCTest

/// PROTOTYPE. Drives the Home map layout's gestures and saves screenshots for review.
final class ProtoHomeMapUITests: XCTestCase {
    @MainActor
    func testGestures() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-paeonia-scenario", "paired-home", "-paeonia-scenario-hide-controls", "YES",
                               "-proto.home.fakePartner", "real"]
        app.launch()
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 15))
        sleep(4)
        shot(app, "ui1-rest")

        let window = app.windows.firstMatch
        func point(_ x: Double, _ y: Double) -> XCUICoordinate {
            window.coordinate(withNormalizedOffset: CGVector(dx: x, dy: y))
        }
        for _ in 0..<4 {
            point(0.5, 0.85).press(forDuration: 0.05, thenDragTo: point(0.5, 0.15), withVelocity: .fast, thenHoldForDuration: 0)
        }
        sleep(2)
        shot(app, "ui2-scrolled-max")

        // One long drag back up that runs past the top. It started away from the top, so
        // the map must stay closed.
        point(0.5, 0.15).press(forDuration: 0.05, thenDragTo: point(0.5, 0.95), withVelocity: .slow, thenHoldForDuration: 0.2)
        sleep(2)
        shot(app, "ui3-back-top")

        point(0.5, 0.45).press(forDuration: 0.1, thenDragTo: point(0.5, 0.9), withVelocity: .default, thenHoldForDuration: 0.1)
        sleep(2)
        shot(app, "ui4-map-open")
        sleep(3)
        shot(app, "ui4b-map-open-later")

        app.maps.firstMatch.pinch(withScale: 0.15, velocity: -2)
        sleep(2)
        shot(app, "ui5-zoomed-out")

        app.buttons["Close"].tap()
        sleep(2)
        shot(app, "ui6-closed")

        point(0.5, 0.2).tap()
        sleep(2)
        shot(app, "ui7-tap-opened")
    }

    @MainActor
    private func shot(_ app: XCUIApplication, _ name: String) {
        let data = XCUIScreen.main.screenshot().pngRepresentation
        try? data.write(to: URL(fileURLWithPath: "/tmp/home-mock/\(name).png"))
    }
}
