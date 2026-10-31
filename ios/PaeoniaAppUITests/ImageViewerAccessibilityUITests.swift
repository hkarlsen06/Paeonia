import XCTest

final class ImageViewerAccessibilityUITests: XCTestCase {
    @MainActor
    func testMemoryPhotosCanBeBrowsedAndZoomedWithNativeControls() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        let thumbnail = openGallery(in: app)
        defer { app.terminate() }

        let zoomIn = app.buttons["imageViewer.zoomIn"]
        waitFor(zoomIn, enabled: true)
        let fit = app.buttons["imageViewer.fit"]
        let level = app.descendants(matching: .any)["imageViewer.zoomLevel"].firstMatch
        let fittedLevel = try XCTUnwrap(level.value as? String)
        XCTAssertFalse(fit.isEnabled)
        XCTAssertFalse(app.buttons["imageViewer.previous"].isEnabled)
        assertPhoto("Oslo Opera House beside the water in evening sunlight.", in: app)

        zoomIn.tap()
        waitFor(fit, enabled: true)
        XCTAssertNotEqual(level.value as? String, fittedLevel)
        app.buttons["imageViewer.move"].tap()
        let moveRight = app.buttons["imageViewer.move.right"]
        XCTAssertTrue(moveRight.waitForExistence(timeout: 5))
        moveRight.tap()
        app.buttons["imageViewer.zoomOut"].tap()
        waitFor(fit, enabled: false)
        XCTAssertEqual(level.value as? String, fittedLevel)

        app.buttons["imageViewer.next"].tap()
        assertPhoto("Three coffee cups, a camera and a sketchbook on a café table.", in: app)
        XCTAssertTrue(app.buttons["imageViewer.previous"].isEnabled)
        XCTAssertFalse(app.buttons["imageViewer.next"].isEnabled)
        waitFor(zoomIn, enabled: true)
        zoomIn.tap()
        waitFor(fit, enabled: true)
        fit.tap()
        waitFor(fit, enabled: false)
        zoomIn.tap()
        waitFor(fit, enabled: true)
        app.buttons["imageViewer.previous"].tap()
        assertPhoto("Oslo Opera House beside the water in evening sunlight.", in: app)
        waitFor(fit, enabled: false)
        XCTAssertEqual(level.value as? String, fittedLevel)
        app.buttons["imageViewer.close"].tap()
        XCTAssertTrue(thumbnail.waitForExistence(timeout: 5))
    }

    @MainActor
    func testMemoryPhotoLoadFailureKeepsDescriptionAndCanBeRetried() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-paeonia-scenario-gallery-retry", "YES"]
        _ = openGallery(in: app)
        defer { app.terminate() }
        let retry = app.buttons["imageViewer.retry"]
        XCTAssertTrue(retry.waitForExistence(timeout: 5))
        let description = app.staticTexts["imageViewer.failure.description"]
        XCTAssertEqual(description.label, "Oslo Opera House beside the water in evening sunlight.")
        let authoredDescription = description.label
        XCTAssertFalse(app.buttons["imageViewer.zoomIn"].isEnabled)
        retry.tap()
        waitFor(app.buttons["imageViewer.zoomIn"], enabled: true)
        assertPhoto(authoredDescription, in: app)
        app.buttons["imageViewer.close"].tap()
    }

    @MainActor
    private func openGallery(in app: XCUIApplication) -> XCUIElement {
        app.launchEnvironment["PAEONIA_SCENARIO"] = "memory-detail"
        app.launchArguments += [
            "-paeonia-scenario-hide-controls", "YES", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"
        ]
        app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryL"]
        app.launch()
        let thumbnail = app.buttons["memory.photo.E1000001-0000-4000-8000-000000000001"]
        XCTAssertTrue(thumbnail.waitForExistence(timeout: 15))
        thumbnail.tap()
        return thumbnail
    }

    @MainActor
    private func waitFor(_ element: XCUIElement, enabled: Bool) {
        let ready = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == true AND enabled == %@", NSNumber(value: enabled)),
            object: element
        )
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 5), .completed)
    }

    @MainActor
    private func assertPhoto(_ description: String, in app: XCUIApplication) {
        let photo = app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier == %@ AND label == %@", "imageViewer.photo", description)
        ).firstMatch
        XCTAssertTrue(photo.waitForExistence(timeout: 5))
    }
}
