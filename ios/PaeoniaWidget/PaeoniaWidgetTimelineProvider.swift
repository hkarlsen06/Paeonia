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
    /// Fallback poll only. Pushes and app reloads do the real work.
    private static let fallbackPollInterval: TimeInterval = 60 * 60

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
            let entry = PaeoniaWidgetEntry(
                date: .now,
                content: PaeoniaWidgetStore.loadContent(for: family)
            )
            let nextRefresh = entry.date.addingTimeInterval(Self.fallbackPollInterval)
            completion(Timeline(entries: [entry], policy: .after(nextRefresh)))
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
