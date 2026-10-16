import Foundation
import WidgetKit

struct PaeoniaWidgetEntry: TimelineEntry, Sendable {
    let date: Date
    let content: PaeoniaWidgetContent
}

struct PaeoniaWidgetTimelineProvider: TimelineProvider {
    /// How long a timeline reload waits for the refresh before it shows what is
    /// already on disk.
    private static let refreshDeadline: Duration = .seconds(15)

    func placeholder(in context: Context) -> PaeoniaWidgetEntry {
        PaeoniaWidgetEntry(date: .now, content: .placeholder)
    }

    func getSnapshot(
        in context: Context,
        completion: @escaping (PaeoniaWidgetEntry) -> Void
    ) {
        completion(
            PaeoniaWidgetEntry(
                date: .now,
                content: context.isPreview
                    ? .placeholder
                    : PaeoniaWidgetStore.loadContent(for: context.family)
            )
        )
    }

    func getTimeline(
        in context: Context,
        completion: @escaping @Sendable (Timeline<PaeoniaWidgetEntry>) -> Void
    ) {
        let family = context.family
        Task {
            await Self.refreshWithinDeadline()
            let content = PaeoniaWidgetStore.loadContent(for: family)
            let now = Date.now
            // A second entry at midnight turns today's "9:41" into a date
            // without spending a reload from the budget.
            let calendar = Calendar.current
            let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now))
                ?? now.addingTimeInterval(24 * 60 * 60)
            completion(
                Timeline(
                    entries: [
                        PaeoniaWidgetEntry(date: now, content: content),
                        PaeoniaWidgetEntry(date: tomorrow, content: content),
                    ],
                    // No polling. A new drawing sends a widget push, and every
                    // reload spends the same daily budget those pushes need.
                    policy: .atEnd
                )
            )
        }
    }

    /// Fetches the partner's latest drawing before the timeline is built, so a
    /// widget push shows it even when the app is not running. A timeout or an
    /// error leaves the files on disk as they are.
    private static func refreshWithinDeadline() async {
        let deadline = refreshDeadline
        await withTaskGroup(of: Void.self) { group in
            group.addTask { try? await PaeoniaWidgetRefreshService.refresh() }
            group.addTask { try? await Task.sleep(for: deadline) }
            // The first child to finish wins. Cancelling the other one stops the
            // sleep, or stops the refresh through its cancellation handler.
            _ = await group.next()
            group.cancelAll()
        }
    }
}
