import Foundation
import WidgetKit

struct PaeoniaWidgetEntry: TimelineEntry {
    let date: Date
    let content: PaeoniaWidgetContent
}

struct PaeoniaWidgetTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> PaeoniaWidgetEntry {
        PaeoniaWidgetEntry(date: .now, content: .placeholder)
    }

    func getSnapshot(
        in context: Context,
        completion: @escaping (PaeoniaWidgetEntry) -> Void
    ) {
        completion(PaeoniaWidgetEntry(date: .now, content: .placeholder))
    }

    func getTimeline(
        in context: Context,
        completion: @escaping (Timeline<PaeoniaWidgetEntry>) -> Void
    ) {
        let entry = PaeoniaWidgetEntry(
            date: .now,
            content: PaeoniaWidgetStore.loadContent(for: context.family)
        )
        let nextRefresh = Calendar.current.date(
            byAdding: .minute,
            value: 30,
            to: entry.date
        ) ?? entry.date.addingTimeInterval(30 * 60)

        completion(Timeline(entries: [entry], policy: .after(nextRefresh)))
    }
}
