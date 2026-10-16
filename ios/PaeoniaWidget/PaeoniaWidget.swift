import SwiftUI
import UIKit
import WidgetKit

struct PaeoniaWidget: Widget {
    let kind: String = "PaeoniaWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: PaeoniaWidgetTimelineProvider()) { entry in
            PaeoniaWidgetEntryView(entry: entry)
                .containerBackground(.paeoniaWidgetBackground, for: .widget)
        }
        .configurationDisplayName(String(localized: .widgetTitle))
        .description(String(localized: .widgetDescription))
        .pushHandler(PaeoniaWidgetPushHandler.self)
        // The drawing stays on the Home Screen. The Lock Screen widgets live in
        // `LockScreen/` and show numbers and short status lines only.
        .supportedFamilies([.systemSmall, .systemLarge])
    }
}

private extension PaeoniaWidgetEntry {
    static var previewDrawing: PaeoniaWidgetEntry {
        let image = UIImage(systemName: "scribble")?
            .withTintColor(.white, renderingMode: .alwaysOriginal) ?? UIImage()

        return PaeoniaWidgetEntry(
            date: .now,
            content: .drawing(
                PaeoniaWidgetDrawingContent(
                    image: image,
                    authorName: "Hjalmar",
                    savedAt: .now
                )
            )
        )
    }
}

#Preview(as: .systemSmall) {
    PaeoniaWidget()
} timeline: {
    PaeoniaWidgetEntry(date: .now, content: .placeholder)
    PaeoniaWidgetEntry.previewDrawing
}

#Preview(as: .systemLarge) {
    PaeoniaWidget()
} timeline: {
    PaeoniaWidgetEntry(date: .now, content: .placeholder)
    PaeoniaWidgetEntry.previewDrawing
}
