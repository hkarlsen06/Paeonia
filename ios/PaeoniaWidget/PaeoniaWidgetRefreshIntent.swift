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

    #if compiler(>=6.4)
    @available(iOS 27.0, *)
    static var allowedExecutionTargets: IntentExecutionTargets {
        .widgetKitExtension
    }
    #endif

    func perform() async -> some IntentResult {
#if DEBUG
        let bundleIdentifier = Bundle.main.bundleIdentifier ?? "unknown"
        Self.logger.debug(
            "Widget refresh intent started in bundle: \(bundleIdentifier, privacy: .public)"
        )
#endif
#if WIDGET_EXTENSION
        // WidgetKit runs a plain AppIntent in the extension process. Keep the
        // network implementation extension-only while exposing this intent
        // type from both targets, as required for interactive widgets.
        try? await PaeoniaWidgetRefreshService.refresh()
#endif
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
