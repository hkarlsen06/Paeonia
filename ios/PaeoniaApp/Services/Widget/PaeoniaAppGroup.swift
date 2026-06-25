import Foundation

/// Shared App Group coordinates used by the app to hand prepared widget content
/// to the Home Screen widget. The widget target reads the same container; keep
/// the identifier and relative paths in sync with `PaeoniaWidgetStore`.
nonisolated enum PaeoniaAppGroup {
    nonisolated static let identifier = "group.no.paeonia.app"

    /// Reload key for the drawing widget timeline.
    nonisolated static let widgetKind = "PaeoniaWidget"

    /// Relative path, inside the App Group container, of the lightweight widget
    /// metadata file. Canonical drawing data never lives here.
    nonisolated static let widgetPayloadPath = "Widget/current.json"

    /// Relative directory, inside the App Group container, that holds the
    /// rendered preview images referenced by the widget payload.
    nonisolated static let widgetPreviewsDirectory = "Widget/previews"

    nonisolated static var containerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier)
    }
}
