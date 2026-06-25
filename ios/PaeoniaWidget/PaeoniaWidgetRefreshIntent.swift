import AppIntents
import WidgetKit

/// Backs the widget's refresh button. Reloads the widget from the latest local
/// App Group payload.
///
/// Today the payload only changes when the app saves a drawing, so this re-reads
/// local state. Once partner sync exists, trigger that sync here before
/// reloading so the button pulls a partner's newest drawing on demand.
struct PaeoniaWidgetRefreshIntent: AppIntent {
    static let title: LocalizedStringResource = .widgetRefresh

    // `perform()` is async by AppIntent protocol; reloading the timeline is synchronous.
    // swiftlint:disable:next async_without_await
    func perform() async throws -> some IntentResult {
        WidgetCenter.shared.reloadTimelines(ofKind: "PaeoniaWidget")
        return .result()
    }
}
