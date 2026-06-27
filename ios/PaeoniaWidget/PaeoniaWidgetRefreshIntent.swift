import AppIntents
import Foundation
#if DEBUG
import OSLog
#endif
import WidgetKit

/// Backs the widget's refresh button. In the app target it asks the app sync
/// service to pull the partner's latest drawing; in the widget target it keeps
/// compiling as an App-Group-only local reload.
struct PaeoniaWidgetRefreshIntent: AppIntent {
    // AppIntents extracts `title` at build time and only accepts a string literal
    // or a `LocalizedStringResource` initializer call — not a generated catalog
    // symbol like `.widgetRefresh`. Use the initializer form so the existing
    // `widget.refresh` catalog entry (and its en/nb translations) still backs it.
    static let title = LocalizedStringResource(
        "widget.refresh",
        table: "Localizable",
        comment: "Accessibility label and title for the widget refresh button."
    )
    static var supportedModes: IntentModes { .background }

    func perform() async throws -> some IntentResult {
        #if DEBUG
        let bundleIdentifier = Bundle.main.bundleIdentifier ?? "unknown"
        Self.logger.debug("Widget refresh intent running in bundle: \(bundleIdentifier, privacy: .public)")
        #endif

        #if !WIDGET_EXTENSION
        #if DEBUG
        Self.logger.debug("Starting widget canvas sync from refresh intent.")
        #endif
        await WidgetCanvasSyncServiceFactory.makeDefault()
            .sync(identity: WidgetSyncIdentityStore.shared.load())
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
