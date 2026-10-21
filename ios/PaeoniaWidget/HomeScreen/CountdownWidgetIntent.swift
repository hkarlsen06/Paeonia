#if WIDGET_EXTENSION
import AppIntents
import Foundation
import WidgetKit

// The explicit keys below are on purpose. App Intents metadata is built from
// the source text, like `PaeoniaWidgetRefreshIntent.title`.

/// What the person sets up when they edit the Home Screen countdown widget:
/// one countdown or birthday, or "Next one", which always shows the soonest.
struct CountdownWidgetIntent: WidgetConfigurationIntent {
    static let title = LocalizedStringResource(
        "widget.home.countdown.intent.title",
        table: "Localizable",
        comment: "Title of the settings of the Home Screen countdown widget."
    )
    static let description = IntentDescription(
        LocalizedStringResource(
            "widget.home.countdown.intent.description",
            table: "Localizable",
            comment: "Explains the settings of the Home Screen countdown widget: pick a countdown or a birthday."
        )
    )

    @Parameter(
        title: LocalizedStringResource(
            "widget.home.countdown.intent.date",
            table: "Localizable",
            comment: "Name of the setting where the person picks which countdown or birthday the widget shows."
        )
    )
    var date: CountdownChoice?
}

/// One thing the countdown widget can show, as the settings list it. The widget
/// keeps only the `id`, so a renamed countdown still shows under its new name.
struct CountdownChoice: AppEntity, Identifiable {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(
        name: LocalizedStringResource(
            "widget.home.countdown.choice.type",
            table: "Localizable",
            comment: "Name for one countdown or birthday in the countdown widget's settings."
        )
    )
    static let defaultQuery = CountdownChoiceQuery()

    let id: String
    let title: String
    /// The day it falls on, as text. Nil for "Next one".
    let subtitle: String?
    let symbol: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: "\(title)",
            subtitle: subtitle.map { "\($0)" },
            image: .init(systemName: symbol)
        )
    }

    /// The choice that always shows the soonest date.
    static let next = CountdownChoice(
        id: LockScreenDates.nextID,
        title: String(
            localized: LocalizedStringResource(
                "widget.home.countdown.choice.next",
                table: "Localizable",
                comment: "The choice in the countdown widget's settings that always shows the soonest date."
            )
        ),
        subtitle: nil,
        symbol: "sparkles"
    )

    /// "Next one", then every date in the saved snapshot, soonest first. Empty
    /// but for "Next one" when the app has not saved anything yet.
    static func all(now: Date = .now, calendar: Calendar = .current) -> [CountdownChoice] {
        guard let snapshot = LockScreenStateService.loadCache()?.snapshot else { return [next] }
        let today = LockScreenCalendarDate(containing: now, in: calendar)
        let partnerName = snapshot.partnerFirstName
        let items = LockScreenDates.items(in: snapshot.dates, today: today).map { item in
            CountdownChoice(
                id: item.id,
                title: item.title(partnerName: partnerName),
                subtitle: item.date.startOfDay(in: calendar)?.formatted(.dateTime.day().month(.abbreviated).year()),
                symbol: item.symbol
            )
        }
        return [next] + items
    }
}

// `EntityQuery` requires async methods, and reading the saved snapshot is synchronous.
struct CountdownChoiceQuery: EntityQuery {
    // swiftlint:disable:next async_without_await
    func entities(for identifiers: [String]) async throws -> [CountdownChoice] {
        CountdownChoice.all().filter { identifiers.contains($0.id) }
    }

    // swiftlint:disable:next async_without_await
    func suggestedEntities() async throws -> [CountdownChoice] {
        CountdownChoice.all()
    }

    // swiftlint:disable:next async_without_await
    func defaultResult() async -> CountdownChoice? {
        .next
    }
}
#endif
