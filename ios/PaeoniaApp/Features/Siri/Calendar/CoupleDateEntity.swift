import AppIntents
import CoreSpotlight
import Foundation
import GeoToolbox

/// Which of the couple's own dates an entity is. Milestones come from the start date and are
/// not entities, because nobody can edit or delete one on its own.
nonisolated enum CoupleDateID: Hashable, Sendable, EntityIdentifierConvertible {
    case countdown(UUID)
    /// A partner's birthday, by their user id.
    case birthday(userID: UUID)

    var entityIdentifierString: String {
        switch self {
        case let .countdown(id): "countdown:\(id.uuidString)"
        case let .birthday(userID): "birthday:\(userID.uuidString)"
        }
    }

    static func entityIdentifier(for entityIdentifierString: String) -> CoupleDateID? {
        let parts = entityIdentifierString.split(separator: ":", maxSplits: 1).map(String.init)
        guard parts.count == 2, let id = UUID(uuidString: parts[1]) else { return nil }
        switch parts[0] {
        case "countdown": return .countdown(id)
        case "birthday": return .birthday(userID: id)
        default: return nil
        }
    }
}

extension CoupleDateEvent {
    /// The entity for a countdown or a birthday. Nil for a milestone.
    var coupleDateID: CoupleDateID? {
        switch kind {
        case let .countdown(countdown): .countdown(countdown.id)
        case let .birthday(userID): .birthday(userID: userID)
        case .milestone: nil
        }
    }
}

/// A countdown the couple added, or a partner's birthday, as a calendar event. Dates are
/// whole days on this phone's calendar, like the timeline. A yearly date starts on the day it
/// was set for and repeats every year, with 29 February falling on 28 February in other years.
@AppEntity(schema: .calendar.event)
struct CoupleDateEntity: IndexedEntity, OwnershipProvidingEntity {
    @available(iOS 27.3, *)
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresLocalDeviceAuthentication
    static let defaultQuery = CoupleDateQuery()

    let id: CoupleDateID
    var calendar: CoupleCalendarEntity
    var title: String
    var startDate: Date
    var endDate: Date
    var isAllDay: Bool
    var recurrence: Calendar.RecurrenceRule?
    var note: AttributedString?
    var travelTime: Duration?
    var location: CoupleDateLocation?
    var virtualLocation: URL?
    var status: CoupleDateStatus?
    var alarms: [CoupleDateAlarm]
    var organizers: [IntentPerson]
    var attendees: [CoupleDateAttendee]
    /// The next time it comes around, today included, as the timeline shows it.
    let nextDate: Date

    var ownership: EntityOwnership { .shared }

    var displayRepresentation: DisplayRepresentation {
        let symbol = switch id {
        case .countdown: "calendar"
        case .birthday: "gift"
        }
        return DisplayRepresentation(
            title: "\(title)",
            subtitle: "\(nextDate.formatted(date: .long, time: .omitted))",
            image: .init(systemName: symbol)
        )
    }

    init(id: CoupleDateID, title: String, day: Date, nextDate: Date, repeatsYearly: Bool, calendar: Calendar) {
        self.id = id
        self.nextDate = nextDate
        self.calendar = .shared
        self.title = title
        startDate = day
        endDate = calendar.date(byAdding: .day, value: 1, to: day) ?? day
        isAllDay = true
        recurrence = repeatsYearly ? Self.yearly(in: calendar) : nil
        note = nil
        travelTime = nil
        location = nil
        virtualLocation = nil
        status = .confirmed
        alarms = []
        organizers = []
        attendees = []
    }

    /// Every year on the same day. A 29 February date falls on the 28th in other years, the
    /// rule `LockScreenCalendarDate.nextYearlyOccurrence` uses everywhere else.
    static func yearly(in calendar: Calendar) -> Calendar.RecurrenceRule {
        Calendar.RecurrenceRule(
            calendar: calendar,
            frequency: .yearly,
            matchingPolicy: .previousTimePreservingSmallerComponents
        )
    }

    /// The couple's countdowns and set birthdays, oldest day first.
    @MainActor
    static func all(
        in dates: CoupleDates,
        names: CoupleDateNames,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [CoupleDateEntity] {
        let today = LockScreenCalendarDate(containing: now, in: calendar)
        func entity(_ id: CoupleDateID, _ title: String, _ isoDate: String, yearly: Bool) -> CoupleDateEntity? {
            guard let original = LockScreenCalendarDate(isoDate),
                  let day = original.startOfDay(in: calendar),
                  let next = yearly
                      ? original.nextYearlyOccurrence(onOrAfter: today).startOfDay(in: calendar)
                      : day
            else { return nil }
            return CoupleDateEntity(
                id: id, title: title, day: day, nextDate: next, repeatsYearly: yearly, calendar: calendar
            )
        }
        let countdowns = dates.countdowns.compactMap { countdown in
            entity(.countdown(countdown.id), countdown.title, countdown.targetDate, yearly: countdown.repeatsYearly)
        }
        let birthdays = dates.birthdays.compactMap { userID, birthday in
            let title = CoupleDateNames.birthdayTitle(for: userID, names: names)
            return entity(.birthday(userID: userID), title, birthday, yearly: true)
        }
        return (countdowns + birthdays).sorted { $0.startDate < $1.startDate }
    }
}

struct CoupleDateQuery: EntityStringQuery, IndexedEntityQuery {
    func entities(for identifiers: [CoupleDateID]) async throws -> [CoupleDateEntity] {
        await SiriContent.dates().filter { identifiers.contains($0.id) }
    }

    func entities(matching string: String) async throws -> [CoupleDateEntity] {
        await SiriContent.dates().filter { $0.title.localizedStandardContains(string) }
    }

    /// The next few, soonest first.
    func suggestedEntities() async throws -> [CoupleDateEntity] {
        Array(await SiriContent.dates().sorted { $0.nextDate < $1.nextDate }.prefix(5))
    }

    func reindexEntities(for identifiers: [CoupleDateID], indexDescription: CSSearchableIndexDescription) async throws {
        await SiriEntityIndexer.shared.refresh(force: true)
    }

    func reindexAllEntities(indexDescription: CSSearchableIndexDescription) async throws {
        await SiriEntityIndexer.shared.refresh(force: true)
    }
}

@AppEnum(schema: .calendar.eventStatus)
enum CoupleDateStatus: String {
    case confirmed
    case tentative
    case cancelled

    static let caseDisplayRepresentations: [Self: DisplayRepresentation] = [
        .confirmed: DisplayRepresentation(
            title: LocalizedStringResource(
                "siri.dates.status.confirmed",
                table: "Localizable",
                comment: "Siri: a calendar event's status when it is going to happen."
            )
        ),
        .tentative: DisplayRepresentation(
            title: LocalizedStringResource(
                "siri.dates.status.tentative",
                table: "Localizable",
                comment: "Siri: a calendar event's status when it might happen."
            )
        ),
        .cancelled: DisplayRepresentation(
            title: LocalizedStringResource(
                "siri.dates.status.cancelled",
                table: "Localizable",
                comment: "Siri: a calendar event's status when it was called off."
            )
        ),
    ]
}

@AppEnum(schema: .calendar.eventSpan)
enum CoupleDateSpan: String {
    case this
    case future
    case all

    static let caseDisplayRepresentations: [Self: DisplayRepresentation] = [
        .this: DisplayRepresentation(
            title: LocalizedStringResource(
                "siri.dates.span.this",
                table: "Localizable",
                comment: "Siri: change or delete only this time of a date that repeats."
            )
        ),
        .future: DisplayRepresentation(
            title: LocalizedStringResource(
                "siri.dates.span.future",
                table: "Localizable",
                comment: "Siri: change or delete this time and every later time of a date that repeats."
            )
        ),
        .all: DisplayRepresentation(
            title: LocalizedStringResource(
                "siri.dates.span.all",
                table: "Localizable",
                comment: "Siri: change or delete every time of a date that repeats."
            )
        ),
    ]
}

@UnionValue
enum CoupleDateLocation {
    case place(PlaceDescriptor)
    case address(String)
}

@UnionValue
enum CoupleDateAlarm {
    case duration(Duration)
    case date(Date)
}
