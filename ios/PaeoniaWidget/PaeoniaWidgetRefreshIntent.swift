import AppIntents
import Foundation
#if DEBUG
import OSLog
#endif
import WidgetKit

/// Refreshes the shared canvas inside the widget extension. It deliberately
/// stays in the background: only tapping the canvas opens Paeonia.
struct PaeoniaWidgetRefreshIntent: AppIntent {
    static let title = LocalizedStringResource(
        "widget.refresh",
        table: "Localizable",
        comment: "Accessibility label and title for the widget refresh button."
    )
    static var supportedModes: IntentModes { .background }
    /// Only the widget button runs this intent, so keep it out of Shortcuts.
    static var isDiscoverable: Bool { false }

    static var allowedExecutionTargets: IntentExecutionTargets {
        .widgetKitExtension
    }

    func perform() -> some IntentResult {
#if DEBUG
        let bundleIdentifier = Bundle.main.bundleIdentifier ?? "unknown"
        Self.logger.debug(
            "Widget refresh intent started in bundle: \(bundleIdentifier, privacy: .public)"
        )
#endif
        // The new timeline fetches the latest drawing (`refreshWithinDeadline`), so
        // fetching here too would download it twice.
        WidgetCenter.shared.reloadTimelines(ofKind: "PaeoniaWidget")
        return .result()
    }

#if DEBUG
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "no.paeonia.app",
        category: "WidgetRefreshIntent"
    )
#endif
}
