import XCTest

/// The release checklist's touch target, invite paste and location text checks, run on the
/// scenarios that show those controls. Each sweep fails on a control under 44 points in
/// the accessibility tree and on Apple's hit region audit, and attaches the tree, a
/// screenshot and every other audit finding, so a finding can be read with its frames.
final class AccessibilityReleaseChecksUITests: XCTestCase {
    private static let minimumTarget: CGFloat = 44

    override func setUp() {
        // An audit of a long screen, or five launches, takes more than the default 2 minutes.
        executionTimeAllowance = 300
    }

    @MainActor func testWelcomeTargets() throws { try sweep("welcome") }
    @MainActor func testSignInTargets() throws { try sweep("sign-in") }
    @MainActor func testCodeEntryTargets() throws { try sweep("pairing-join") }
    @MainActor func testInviteTargets() throws { try sweep("pairing-invite-ready") }
    @MainActor func testPaywallTargets() throws { try sweep("paywall-trial") }
    @MainActor func testHomeTargets() throws { try sweep("paired-home") }
    @MainActor func testQuestionsTargets() throws { try sweep("questions") }
    @MainActor func testAnswerTargets() throws { try sweep("question-answer-flow") }
    @MainActor func testDrawingTargets() throws { try sweep("widget-drawing") }
    @MainActor func testDrawingTargetsWithExtraControls() throws { try sweep("widget-drawing", extraControls: true) }
    @MainActor func testMemoryEditorTargets() throws { try sweep("memory-editor") }
    @MainActor func testSettingsTargets() throws { try sweep("settings") }
    @MainActor func testGamesHubTargets() throws { try sweep("games-hub-your-turn") }
    @MainActor func testLocationTargets() throws { try sweep("location-live") }

    /// A text field takes taps only on its text, so the box around it focuses it too.
    @MainActor
    func testTappingAFieldsPaddingFocusesIt() throws {
        let app = launch("memory-editor")
        defer { app.terminate() }
        let title = app.textFields.firstMatch
        XCTAssertTrue(title.waitForExistence(timeout: 15))
        XCTAssertFalse(hasFocus(title))
        // 8 points above the text, inside the box's 12-point padding.
        title.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0))
            .withOffset(CGVector(dx: 0, dy: -8))
            .tap()
        XCTAssertTrue(waitForFocus(title))
    }

    /// The keyboard leaves the field and Send in view, and Return does what its key says.
    @MainActor
    func testKeyboardLeavesTheFieldAndSendInView() throws {
        let app = launch("question-answer-flow")
        let field = app.descendants(matching: .any)["daily.answer.text"]
        XCTAssertTrue(field.waitForExistence(timeout: 15))
        field.tap()
        XCTAssertTrue(waitForFocus(field))
        let keyboard = app.keyboards.firstMatch
        field.typeText("Rain on the roof")
        let send = app.buttons["daily.flow.primary"]
        XCTAssertTrue(send.isEnabled)
        XCTAssertTrue(send.isHittable)
        assertAbove(keyboard, field, send)
        capture(app, "Answer with the keyboard up")
        app.terminate()

        let editor = launch("memory-editor")
        let title = editor.textFields.firstMatch
        XCTAssertTrue(title.waitForExistence(timeout: 15))
        title.tap()
        XCTAssertTrue(waitForFocus(title))
        assertAbove(editor.keyboards.firstMatch, title)
        // The title's Return key says Next and moves to the note, without a line break.
        let typed = title.value as? String ?? ""
        title.typeText("\n")
        let note = editor.textFields.element(boundBy: 1)
        XCTAssertTrue(waitForFocus(note))
        XCTAssertEqual(title.value as? String, typed)
        assertAbove(editor.keyboards.firstMatch, note)
        capture(editor, "Memory note after Next")
        editor.terminate()
    }

    @MainActor func testPhotoComposerTargets() throws { try sweep("question-answer-flow", answerFormat: "photo-text") }
    @MainActor func testVoiceComposerTargets() throws { try sweep("question-answer-flow", answerFormat: "voice-text") }

    /// Record asks for the microphone with the system prompt. After a refusal the composer
    /// says how to allow it.
    @MainActor
    func testRecordAsksForTheMicrophoneAndExplainsARefusal() throws {
        let app = XCUIApplication()
        app.resetAuthorizationStatus(for: .microphone)
        app.launchEnvironment["PAEONIA_SCENARIO"] = "question-answer-flow"
        app.launchArguments = [
            "-paeonia-answer-format", "voice-text", "-paeonia-scenario-hide-controls", "YES",
            "-AppleLanguages", "(en)", "-AppleLocale", "en_US"
        ]
        app.launch()
        defer { app.terminate() }
        let record = app.buttons["daily.answer.voice.record"]
        XCTAssertTrue(record.waitForExistence(timeout: 15))
        XCTAssertFalse(record.label.isEmpty)
        record.tap()
        let prompt = XCUIApplication(bundleIdentifier: "com.apple.springboard").alerts.firstMatch
        XCTAssertTrue(prompt.waitForExistence(timeout: 10), "Record did not ask for the microphone")
        attach("Microphone prompt", prompt.debugDescription)
        capture(XCUIApplication(bundleIdentifier: "com.apple.springboard"), "Microphone prompt")
        // The first button is Don't Allow.
        prompt.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.buttons["daily.answer.voice.openSettings"].waitForExistence(timeout: 5))
        capture(app, "After refusing the microphone")
    }

    /// Pasting a bare code, a code with spaces and a shared message with a join link
    /// fills the six cells, and VoiceOver reads the field's name, the code and a hint.
    @MainActor
    func testInviteCodePasteFillsTheFieldForVoiceOver() throws {
        continueAfterFailure = false
        let pastes = [
            "7K3QXP": "7K3QXP",
            "7k3 qxp": "7K3QXP",
            "Join me in Paeonia: https://paeonia.no/join/7k3-qxp": "7K3QXP"
        ]
        // Welcome shows its paste button while the clipboard holds a link, so leave it empty.
        defer { UIPasteboard.general.items = [] }
        for (pasted, expected) in pastes {
            let app = launch("pairing-join")
            let field = app.descendants(matching: .any)["pairing.codeEntry.field"]
            XCTAssertTrue(field.waitForExistence(timeout: 15))
            XCTAssertFalse(field.label.isEmpty, "The code field has no VoiceOver name")
            UIPasteboard.general.string = pasted
            let paste = app.buttons["pairing.codeEntry.paste"]
            XCTAssertTrue(paste.waitForExistence(timeout: 5))
            paste.tap()
            let filled = NSPredicate(format: "value == %@", expected)
            let expectation = XCTNSPredicateExpectation(predicate: filled, object: field)
            XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 5), .completed,
                           "Pasting \(pasted) left \(field.value ?? "nothing")")
            XCTAssertTrue(app.buttons["pairing.codeEntry.submit"].isEnabled)
            attach("Code field after pasting \(pasted)", "label: \(field.label)\nvalue: \(field.value ?? "")")
            capture(app, "Pasted \(pasted)")
            app.terminate()
        }
    }

    /// The map is never the only place the distance shows. The Home distance line and the
    /// iPad map card each read the distance, or that the two are together, and how old the
    /// partner's place is. The other states say in text why there is no distance.
    @MainActor
    func testLocationStateIsReadAsText() throws {
        let spoken = [
            "paired-home": "home.map.distance", "location-live": "location.map", "location-stale": "location.map"
        ]
        let quiet = ["location-not-sharing", "location-current-missing"]
        for scenario in ["paired-home", "location-live", "location-stale"] + quiet {
            let app = launch(scenario)
            XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 15))
            if let identifier = spoken[scenario] {
                let element = app.descendants(matching: .any)[identifier]
                XCTAssertTrue(element.waitForExistence(timeout: 10), "\(scenario) has no \(identifier)")
                XCTAssertFalse(element.label.isEmpty)
                let value = element.value as? String ?? ""
                XCTAssertFalse(value.isEmpty, "\(scenario) does not say how old the place is")
            }
            let lines = try app.snapshot().flattened()
                .filter { !$0.label.isEmpty || !($0.value as? String ?? "").isEmpty }
                .map { "\($0.elementType.rawValue) \($0.identifier) | \($0.label) | \($0.value as? String ?? "")" }
            attach("\(scenario) spoken text", lines.joined(separator: "\n"))
            capture(app, scenario)
            app.terminate()
        }
    }

    /// With a hardware keyboard connected, as on the shared simulators, iOS shows no
    /// on-screen keyboard and its element has no frame, so there is nothing to cover.
    @MainActor
    private func assertAbove(_ keyboard: XCUIElement, _ elements: XCUIElement...) {
        guard keyboard.keys.firstMatch.exists else {
            attach("Keyboard", "No on-screen keyboard: a hardware keyboard is connected")
            return
        }
        for element in elements {
            XCTAssertLessThanOrEqual(element.frame.maxY, keyboard.frame.minY, "\(element) is under the keyboard")
        }
    }

    @MainActor
    private func hasFocus(_ element: XCUIElement) -> Bool {
        element.value(forKey: "hasKeyboardFocus") as? Bool == true
    }

    @MainActor
    private func waitForFocus(_ element: XCUIElement) -> Bool {
        let focused = NSPredicate { _, _ in MainActor.assumeIsolated { self.hasFocus(element) } }
        let expectation = XCTNSPredicateExpectation(predicate: focused, object: nil)
        return XCTWaiter.wait(for: [expectation], timeout: 5) == .completed
    }

    @MainActor
    private func sweep(_ scenario: String, extraControls: Bool = false, answerFormat: String? = nil) throws {
        continueAfterFailure = true
        let app = launch(scenario, extraControls: extraControls, answerFormat: answerFormat)
        defer { app.terminate() }
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 15))
        sleep(3)
        let root = try app.snapshot()
        let window = app.windows.firstMatch.frame
        attach("\(scenario) accessibility tree", app.debugDescription)
        capture(app, scenario)
        let small = root.flattened(skipping: Self.systemSizedContainers).filter { element in
            Self.interactiveTypes.contains(element.elementType)
                && !Self.exempt(element, scenario: scenario, extraControls: extraControls)
                && window.contains(element.frame)
                && (element.frame.width < Self.minimumTarget - 0.5 || element.frame.height < Self.minimumTarget - 0.5)
        }
        for element in small {
            let size = "\(Int(element.frame.width.rounded()))x\(Int(element.frame.height.rounded()))"
            record(XCTIssue(
                type: .assertionFailure,
                compactDescription: "\(scenario): \(size) pt target '\(element.identifier)' '\(element.label)' "
                    + "at \(element.frame.origin)"
            ))
        }
        // Every finding is attached. Only a hit region fails this test. The contrast audit
        // reports text that measures over 5:1 in the screenshot, so contrast is measured
        // from the pixels instead (docs/accessibility-report.md).
        try app.performAccessibilityAudit { issue in
            self.attach(
                "Audit issue",
                "\(issue.auditType.rawValue) \(issue.compactDescription)\n"
                    + (issue.element?.debugDescription ?? "unavailable")
            )
            return issue.auditType != .hitRegion
        }
    }

    /// System bars, keyboards and pickers size their own controls, and UIKit gives a bar
    /// button a larger hit area than its frame.
    private static let systemSizedContainers: Set<XCUIElement.ElementType> = [.keyboard, .navigationBar, .datePicker]

    /// Targets under 44 points that are not a defect, with the reason.
    @MainActor
    private static func exempt(_ element: XCUIElementSnapshot, scenario: String, extraControls: Bool) -> Bool {
        switch element.elementType {
        // A slider's frame is its track. UISlider takes touches in a larger area around the thumb.
        case .slider: return true
        // A text field's frame is its lines of text. Its box focuses it on a tap, which
        // testTappingAFieldsPaddingFocusesIt proves.
        case .textField, .textView: return true
        default: break
        }
        // The system paste button keeps its own 34-point height. controlSize and frame
        // leave it unchanged.
        if ["pairing.codeEntry.paste", "welcome.paste"].contains(element.identifier) { return true }
        // Links inside the agreement sentence (WCAG 2.5.8 inline exception).
        if scenario == "sign-in", ["terms", "privacy"].contains(element.identifier) { return true }
        // By design the colors stay on one row, at about 38 points each on a 6.3-inch
        // phone. Extra controls (More > Accessibility, or any assistive technology) wrap
        // them into 44-point cells, which testDrawingTargetsWithExtraControls checks.
        return scenario == "widget-drawing" && !extraControls && drawingColors.contains(element.label)
    }

    private static let drawingColors: Set<String> = [
        "Blush", "Petal pink", "Pink", "Warm pink", "Green", "Gold", "Blue", "Lavender", "Custom color"
    ]

    private static let interactiveTypes: Set<XCUIElement.ElementType> = [
        .button, .link, .textField, .secureTextField, .textView, .switch, .toggle, .slider,
        .stepper, .segmentedControl, .menuButton, .popUpButton, .colorWell, .incrementArrow, .decrementArrow
    ]

    @MainActor
    private func launch(
        _ scenario: String, extraControls: Bool = false, answerFormat: String? = nil
    ) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["PAEONIA_SCENARIO"] = scenario
        app.launchArguments = [
            "-paeonia-scenario-hide-controls", "YES", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"
        ]
        if let answerFormat { app.launchArguments += ["-paeonia-answer-format", answerFormat] }
        if extraControls {
            app.launchWithExtraAccessibilityTools()
        } else {
            app.launch()
        }
        return app
    }

    private func attach(_ name: String, _ text: String) {
        let attachment = XCTAttachment(string: text)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor
    private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

private extension XCUIElementSnapshot {
    func flattened(skipping containers: Set<XCUIElement.ElementType> = []) -> [XCUIElementSnapshot] {
        if containers.contains(elementType) { return [] }
        return [self] + children.flatMap { $0.flattened(skipping: containers) }
    }
}
