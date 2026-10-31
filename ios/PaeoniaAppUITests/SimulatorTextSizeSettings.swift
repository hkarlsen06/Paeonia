import CoreGraphics
import XCTest

/// Changes the simulator's actual preference, so accessibility audits can still exercise live size changes.
/// Keep the app free of -UIPreferredContentSizeCategoryName and dynamicTypeSize environment overrides.
@MainActor
struct SimulatorTextSizeSettings {
    enum Size: Equatable { case standard, largestAccessibility }
    struct Snapshot {
        let largerAccessibilitySizes: Bool
        let sliderPosition: Float
    }
    enum SettingsError: Error { case unavailable(String) }

    let testCase: XCTestCase
    private let settings = XCUIApplication(bundleIdentifier: "com.apple.Preferences")

    func withSize<Result>(_ size: Size, perform: () throws -> Result) throws -> Result {
        try openLargerText()
        let original = try snapshot()
        defer {
            do {
                try openLargerText()
                try apply(original)
                settings.terminate()
            } catch {
                recordFailure("Could not restore the simulator's text size: \(error)")
            }
        }
        let requested = Snapshot(largerAccessibilitySizes: size == .largestAccessibility,
                                 sliderPosition: size == .largestAccessibility ? 1 : 0.5)
        try apply(requested)
        attachState(name: size == .largestAccessibility ? "Actual Settings AX5" : "Actual Settings standard text")
        return try perform()
    }

    private func openLargerText() throws {
        settings.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        settings.launch()
        guard settings.wait(for: .runningForeground, timeout: 10) else {
            throw failure("Settings did not enter the foreground")
        }
        if isLargerTextPage { return }
        // Settings reopens its previous page. Return through native navigation before searching its root.
        for _ in 0..<8 where !settings.navigationBars["Settings"].exists {
            let back = settings.navigationBars.buttons.firstMatch
            guard back.waitForExistence(timeout: 2), back.isHittable else {
                throw failure("Could not return to the Settings root")
            }
            back.tap()
        }
        guard settings.navigationBars["Settings"].waitForExistence(timeout: 5) else {
            throw failure("Settings root was not available")
        }
        // The previous visit can leave the Settings list scrolled down.
        for _ in 0..<4 { settings.swipeDown() }
        try tapRow("Accessibility")
        try tapRow("Display & Text Size")
        try tapRow("Larger Text")
        guard isLargerTextPage else { throw failure("Larger Text controls did not appear") }
    }

    private var isLargerTextPage: Bool {
        largerSizesSwitch.exists && settings.sliders.count == 1
    }

    private var largerSizesSwitch: XCUIElement {
        // Observed iOS 27 Settings cell identifier. Its last switch is the native inner control.
        let switches = settings.cells["LARGER_DYNAMIC_TYPE_SWITCH"].switches
        return switches.element(boundBy: max(0, switches.count - 1))
    }

    private func tapRow(_ label: String) throws {
        for _ in 0..<14 {
            // iOS Settings can expose zero-sized inner buttons at AX5. Use the native row.
            let candidates = [
                settings.cells.containing(.staticText, identifier: label).firstMatch,
                settings.buttons[label].firstMatch,
                settings.staticTexts[label].firstMatch,
            ]
            let viewport = settings.windows.firstMatch.frame.insetBy(dx: 0, dy: 116)
            if let row = candidates.first(where: {
                $0.exists && $0.isHittable && $0.frame.width > 0 && $0.frame.height > 0
                    && viewport.contains(CGPoint(x: $0.frame.midX, y: $0.frame.midY))
            }) {
                row.tap()
                guard settings.navigationBars[label].waitForExistence(timeout: 5) else {
                    throw failure("Settings row did not open: \(label)")
                }
                return
            }
            if let target = candidates.first(where: { $0.exists && $0.frame.height > 0 }),
               target.frame.midY < viewport.midY {
                settings.swipeDown()
            } else {
                settings.swipeUp()
            }
        }
        throw failure("Settings row was not available: \(label)")
    }

    private func snapshot() throws -> Snapshot {
        let toggle = largerSizesSwitch
        guard let raw = toggle.value as? String, raw == "0" || raw == "1" else {
            throw failure("Could not read Larger Accessibility Sizes")
        }
        return Snapshot(largerAccessibilitySizes: raw == "1", sliderPosition: try sliderPosition())
    }

    private func sliderPosition() throws -> Float {
        guard settings.sliders.count == 1, let raw = settings.sliders.firstMatch.value as? String,
              raw.hasSuffix("%") else {
            throw failure("Could not read the Larger Text slider's percentage")
        }
        let number = raw.dropLast().trimmingCharacters(in: .whitespacesAndNewlines)
        guard let percent = Float(number), (0...100).contains(percent) else {
            throw failure("Unexpected Larger Text slider percentage: \(raw)")
        }
        return percent / 100
    }

    private func apply(_ snapshot: Snapshot) throws {
        let toggle = largerSizesSwitch
        for _ in 0..<5 where !toggle.isHittable { settings.swipeDown() }
        guard toggle.isHittable else { throw failure("Larger Accessibility Sizes switch is not operable") }
        if (toggle.value as? String == "1") != snapshot.largerAccessibilitySizes { toggle.tap() }
        let slider = settings.sliders.firstMatch
        for _ in 0..<5 where !slider.isHittable { settings.swipeUp() }
        guard slider.waitForExistence(timeout: 5), slider.isHittable else {
            throw failure("Larger Text slider is not operable")
        }
        slider.adjust(toNormalizedSliderPosition: CGFloat(snapshot.sliderPosition))
        let actual = try self.snapshot()
        guard actual.largerAccessibilitySizes == snapshot.largerAccessibilitySizes,
              abs(actual.sliderPosition - snapshot.sliderPosition) <= 0.02 else {
            throw failure("Larger Text did not reach the requested switch and slider state")
        }
    }

    private func attachState(name: String) {
        let screenshot = XCTAttachment(screenshot: settings.screenshot())
        screenshot.name = name
        screenshot.lifetime = .keepAlways
        testCase.add(screenshot)
        let state = XCTAttachment(string: settings.debugDescription)
        state.name = "\(name) hierarchy"
        state.lifetime = .keepAlways
        testCase.add(state)
    }

    private func failure(_ message: String) -> SettingsError {
        attachState(name: "Text size setup failure")
        return .unavailable(message)
    }

    private func recordFailure(_ message: String) {
        attachState(name: "Text size restoration failure")
        testCase.record(XCTIssue(type: .assertionFailure, compactDescription: message))
    }
}
