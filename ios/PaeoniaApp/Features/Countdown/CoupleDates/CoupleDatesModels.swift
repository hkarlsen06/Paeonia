import Foundation

/// A countdown the couple added themselves ("Trip to Bergen"), next to the milestones
/// derived from the relationship start date.
nonisolated struct CustomCountdown: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    var title: String
    /// The calendar day it counts down to, `yyyy-MM-dd`. Each phone counts in its own time zone.
    var targetDate: String

    /// The editor caps titles at this many characters.
    static let maxTitleLength = 40
    /// The server refuses more per couple, so the phone says so before queueing one.
    static let maxCount = 50

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case targetDate = "target_date"
    }
}

/// The couple's own dates as this phone knows them: the countdowns and both partners'
/// birthdays (`yyyy-MM-dd`, keyed by user id).
nonisolated struct CoupleDates: Codable, Equatable, Sendable {
    var countdowns: [CustomCountdown] = []
    var birthdays: [UUID: String] = [:]

    mutating func upsert(_ countdown: CustomCountdown) {
        if let index = countdowns.firstIndex(where: { $0.id == countdown.id }) {
            countdowns[index] = countdown
        } else {
            countdowns.append(countdown)
        }
    }

    mutating func removeCountdown(id: UUID) {
        countdowns.removeAll { $0.id == id }
    }

    mutating func setBirthday(_ birthday: String?, for userID: UUID) {
        birthdays[userID] = birthday
    }

    /// The server's dates with this phone's queued writes laid over them, oldest write
    /// first, so an edit shows at once and survives a relaunch while offline.
    func applying(_ writes: [CoupleDatesWrite]) -> CoupleDates {
        var dates = self
        for write in writes {
            switch write {
            case let .save(countdown):
                dates.upsert(countdown)
            case let .delete(id):
                dates.removeCountdown(id: id)
            case let .birthday(payload):
                dates.setBirthday(payload.birthday, for: payload.userID)
            }
        }
        return dates
    }
}

/// One queued write, decoded from its pending operation.
nonisolated enum CoupleDatesWrite: Equatable, Sendable {
    case save(CustomCountdown)
    case delete(UUID)
    case birthday(SetBirthdayPayload)

    init?(_ operation: PendingSyncOperationSnapshot) {
        guard let data = operation.requestData else { return nil }
        let decoder = JSONDecoder()
        switch operation.operationKind {
        case .saveCountdown?:
            guard let countdown = try? decoder.decode(CustomCountdown.self, from: data) else { return nil }
            self = .save(countdown)
        case .deleteCountdown?:
            guard let payload = try? decoder.decode(DeleteCountdownPayload.self, from: data) else { return nil }
            self = .delete(payload.id)
        case .setBirthday?:
            guard let payload = try? decoder.decode(SetBirthdayPayload.self, from: data) else { return nil }
            self = .birthday(payload)
        default:
            return nil
        }
    }

    static let operationKinds: [SyncPendingOperationKind] = [.saveCountdown, .deleteCountdown, .setBirthday]
}

/// `countdowns:delete_countdown`.
nonisolated struct DeleteCountdownPayload: Codable, Equatable, Sendable {
    let id: UUID
}

/// `countdowns:set_birthday`. A nil birthday removes it.
nonisolated struct SetBirthdayPayload: Codable, Equatable, Sendable {
    let userID: UUID
    let birthday: String?
}

/// The result of `countdowns:get_countdowns`.
nonisolated struct RemoteCoupleDates: Decodable, Equatable, Sendable {
    let coupleID: UUID
    let countdowns: [CustomCountdown]
    let birthdays: [RemoteBirthday]

    var dates: CoupleDates {
        CoupleDates(
            countdowns: countdowns,
            birthdays: Dictionary(birthdays.map { ($0.userID, $0.birthday) }, uniquingKeysWith: { _, last in last })
        )
    }

    enum CodingKeys: String, CodingKey {
        case coupleID = "couple_id"
        case countdowns
        case birthdays
    }
}

nonisolated struct RemoteBirthday: Decodable, Equatable, Sendable {
    let userID: UUID
    let birthday: String

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case birthday
    }
}

/// The result of `countdowns:set_birthday`.
nonisolated struct RemoteBirthdayResult: Decodable, Equatable, Sendable {
    let userID: UUID
    let birthday: String?

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case birthday
    }
}
