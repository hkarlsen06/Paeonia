import AppIntents
import Foundation
import GeoToolbox

/// "Add a countdown to our trip on 12 June in Paeonia." Creates a countdown through the
/// same queued write as the countdown editor.
@AppIntent(schema: .calendar.createEvent)
struct CreateCoupleDateIntent {
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresLocalDeviceAuthentication
    static let supportedModes: IntentModes = [.background, .foreground(.dynamic)]

    var title: String
    var startDate: Date
    var endDate: Date?
    var location: CoupleDateLocation?
    var calendar: CoupleCalendarEntity
    var isAllDay: Bool
    var recurrence: Calendar.RecurrenceRule?
    var attendees: [CoupleDateAttendee]
    var note: AttributedString?

    @MainActor
    func perform() async throws -> some ReturnsValue<CoupleDateEntity> {
        let couple = try await coupleToActFor()
        let writes = await CoupleDateWrites(couple: couple)
        let id = UUID()
        try await writes.saveCountdown(
            id: nil,
            title: title,
            day: startDate,
            repeatsYearly: CoupleDateWrites.repeatsYearly(recurrence),
            newID: id
        )
        return .result(value: try writes.entity(.countdown(id)))
    }
}

/// Renames or moves a countdown, or moves a birthday. A birthday keeps its name.
@AppIntent(schema: .calendar.updateEvent)
struct UpdateCoupleDateIntent {
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresLocalDeviceAuthentication
    static let supportedModes: IntentModes = [.background, .foreground(.dynamic)]

    var event: CoupleDateEntity
    var title: String?
    var attendees: [CoupleDateAttendee]?
    var startDate: Date?
    var endDate: Date?
    var isAllDay: Bool?
    var calendar: CoupleCalendarEntity?
    var recurrence: Calendar.RecurrenceRule?
    var note: String?
    var location: CoupleDateLocation?
    var span: CoupleDateSpan?

    @MainActor
    func perform() async throws -> some ReturnsValue<CoupleDateEntity> {
        let couple = try await coupleToActFor()
        let writes = await CoupleDateWrites(couple: couple)
        switch event.id {
        case let .countdown(id):
            guard let current = writes.countdown(id) else { throw SiriFailure(.siriDatesGone) }
            let repeatsYearly = switch $recurrence.valueState {
            case .set(let rule): try CoupleDateWrites.repeatsYearly(rule)
            default: current.repeatsYearly
            }
            try await writes.saveCountdown(
                id: id,
                title: title ?? current.title,
                day: startDate ?? writes.day(of: current) ?? event.startDate,
                repeatsYearly: repeatsYearly
            )
        case let .birthday(userID):
            if let title, title != event.title {
                throw SiriFailure(.siriDatesBirthdayKeepsName)
            }
            if let startDate {
                try await writes.setBirthday(startDate, for: userID)
            }
        }
        return .result(value: try writes.entity(event.id))
    }
}

/// Deletes a countdown, or removes a birthday.
@AppIntent(schema: .calendar.deleteEvent)
struct DeleteCoupleDateIntent {
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresLocalDeviceAuthentication
    static let supportedModes: IntentModes = [.background, .foreground(.dynamic)]

    var entity: CoupleDateEntity
    var span: CoupleDateSpan?

    @MainActor
    func perform() async throws -> some IntentResult {
        let couple = try await coupleToActFor()
        let writes = await CoupleDateWrites(couple: couple)
        switch entity.id {
        case let .countdown(id):
            try await writes.deleteCountdown(id)
        case let .birthday(userID):
            try await writes.setBirthday(nil, for: userID)
        }
        return .result()
    }
}

/// Opens the dates timeline, where the date sits between the milestones.
@AppIntent(schema: .system.open)
struct OpenCoupleDateIntent {
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresLocalDeviceAuthentication

    var target: CoupleDateEntity

    @MainActor
    func perform() async throws -> some IntentResult {
        if await coupleToOpenFor() != nil {
            SiriAppContext.shared.open(.dates)
        }
        return .result()
    }
}

/// The couple's dates as the timeline shows them, written through `CoupleDatesViewModel`, the
/// editors' local-first path: each write is queued and sent the way an editor's save is.
@MainActor
struct CoupleDateWrites {
    private let couple: SiriCouple
    private let model = CoupleDatesViewModel()

    init(couple: SiriCouple) async {
        self.couple = couple
        model.setSyncAfterLocalChange { await SiriAppContext.shared.syncAfterLocalChange() }
        await model.configure(ownerUserID: couple.ownerUserID)
    }

    /// Paeonia dates repeat every year or not at all.
    static func repeatsYearly(_ rule: Calendar.RecurrenceRule?) throws -> Bool {
        guard let rule else { return false }
        guard rule.frequency == .yearly, rule.interval == 1 else {
            throw SiriFailure(.siriDatesRepeatUnsupported)
        }
        return true
    }

    func countdown(_ id: UUID) -> CustomCountdown? {
        model.dates.countdowns.first { $0.id == id }
    }

    func day(of countdown: CustomCountdown) -> Date? {
        LockScreenCalendarDate(countdown.targetDate)?.startOfDay(in: .current)
    }

    func entity(_ id: CoupleDateID) throws -> CoupleDateEntity {
        guard let entity = CoupleDateEntity.all(in: model.dates, names: couple.dateNames).first(where: { $0.id == id })
        else { throw SiriFailure(.siriDatesGone) }
        return entity
    }

    func saveCountdown(id: UUID?, title: String, day: Date, repeatsYearly: Bool, newID: UUID = UUID()) async throws {
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw SiriFailure(.siriDatesTitleMissing)
        }
        let saved = await model.saveCountdown(
            id: id,
            title: title,
            on: day,
            repeatsYearly: repeatsYearly,
            newID: newID
        )
        try check(saved)
    }

    func deleteCountdown(_ id: UUID) async throws {
        guard countdown(id) != nil else { throw SiriFailure(.siriDatesGone) }
        try check(await model.deleteCountdown(id: id))
    }

    func setBirthday(_ day: Date?, for userID: UUID) async throws {
        guard userID == couple.ownerUserID || userID == couple.partnerUserID else {
            throw SiriFailure(.siriDatesGone)
        }
        try check(await model.setBirthday(day, for: userID))
    }

    private func check(_ saved: Bool) throws {
        guard !saved else { return }
        throw SiriFailure(model.error?.resource ?? .homeMilestoneErrorSaveFailed)
    }
}
