import SwiftUI
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
            // MVP intentionally supports Home Screen families only. No Lock
            // Screen accessory family can render the couple's drawing.
            .supportedFamilies([.systemSmall, .systemLarge])
            .contentMarginsDisabled()
    }
}

private extension PaeoniaWidgetEntry {
    static var previewDrawing: PaeoniaWidgetEntry {
        PaeoniaWidgetEntry(
            date: .now,
            content: .drawing(
                PaeoniaWidgetDrawingContent(
                    previewURL: URL(fileURLWithPath: "/dev/null"),
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
