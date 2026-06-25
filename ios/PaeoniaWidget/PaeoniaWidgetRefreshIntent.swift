import AppIntents
import WidgetKit

/// Backs the widget's refresh button. Reloads the widget from the latest local
/// App Group payload.
///
/// Today the payload only changes when the app saves a drawing, so this re-reads
/// local state. Once partner sync exists, trigger that sync here before
/// reloading so the button pulls a partner's newest drawing on demand.
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

    // `perform()` is async by AppIntent protocol; reloading the timeline is synchronous.
    // swiftlint:disable:next async_without_await
    func perform() async throws -> some IntentResult {
        WidgetCenter.shared.reloadTimelines(ofKind: "PaeoniaWidget")
        return .result()
    }
}
