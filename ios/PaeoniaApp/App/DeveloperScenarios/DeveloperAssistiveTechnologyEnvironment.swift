#if DEBUG
import Foundation
import OSLog
import SwiftUI

/// Model the input to Paeonia's optional UI without changing SwiftUI's native accessibility state.
/// Overriding the global accessibilityEnabled value removes the tree XCTest needs to drive the app.
struct DeveloperAssistiveTechnologyEnvironment: ViewModifier {
    @Environment(\.accessibilityEnabled) private var systemEnabled

    private var simulatedEnabled: Bool? {
        switch UserDefaults.standard.string(forKey: "paeonia-scenario-assistive-technology") {
        case "none": false
        case "active": true
        default: nil
        }
    }

    func body(content: Content) -> some View {
        content
            .environment(\.scenarioAssistiveTechnologyEnabled, simulatedEnabled)
            .onChange(of: systemEnabled, initial: true) { _, systemEnabled in
                guard let simulatedEnabled else { return }
                Logger(subsystem: "no.paeonia.app", category: "DeveloperScenarios")
                    .info("Accessibility fixture: system=\(systemEnabled), simulated=\(simulatedEnabled)")
            }
    }
}
#endif
