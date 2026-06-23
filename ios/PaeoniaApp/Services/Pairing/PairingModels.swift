import Foundation

enum PairingStartDateError: Error, Equatable {
    case invalidFormat
}

nonisolated struct PairingClientOperation: Equatable, Sendable {
    let id: UUID
    let clientID: UUID
    let clientSequence: Int64
    let localCreatedAt: Date

    init(
        id: UUID = UUID(),
        clientID: UUID,
        clientSequence: Int64,
        localCreatedAt: Date = Date()
    ) {
        self.id = id
        self.clientID = clientID
        self.clientSequence = clientSequence
        self.localCreatedAt = localCreatedAt
    }
}

nonisolated struct PairingStartDate: Equatable, Sendable {
    let rawValue: String

    init(rawValue: String) throws {
        let parts = rawValue.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3,
              parts[0].count == 4,
              parts[1].count == 2,
              parts[2].count == 2,
              let year = Int(parts[0]),
              let month = Int(parts[1]),
              let day = Int(parts[2]),
              (1...12).contains(month),
              (1...31).contains(day)
        else {
            throw PairingStartDateError.invalidFormat
        }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? calendar.timeZone

        var components = DateComponents()
        components.calendar = calendar
        components.timeZone = calendar.timeZone
        components.year = year
        components.month = month
        components.day = day

        guard let date = calendar.date(from: components) else {
            throw PairingStartDateError.invalidFormat
        }

        let resolvedComponents = calendar.dateComponents([.year, .month, .day], from: date)
        guard resolvedComponents.year == year,
              resolvedComponents.month == month,
              resolvedComponents.day == day
        else {
            throw PairingStartDateError.invalidFormat
        }

        self.rawValue = rawValue
    }

    init(date: Date, calendar: Calendar = .current) {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        self.rawValue = String(
            format: "%04d-%02d-%02d",
            components.year ?? 1,
            components.month ?? 1,
            components.day ?? 1
        )
    }
}

nonisolated struct PairingInvite: Equatable, Sendable {
    let id: UUID
    let code: String
    let joinURL: URL
    let expiresAt: Date
}

nonisolated struct PairingInvitePreview: Decodable, Equatable, Sendable {
    let inviteID: UUID
    let inviterUserID: UUID
    let inviterDisplayName: String?
    let expiresAt: Date
    let hasSafetyWarning: Bool

    enum CodingKeys: String, CodingKey {
        case inviteID = "invite_id"
        case inviterUserID = "inviter_user_id"
        case inviterDisplayName = "inviter_display_name"
        case expiresAt = "expires_at"
        case hasSafetyWarning = "has_safety_warning"
    }
}

nonisolated struct PairingAcceptedRelationship: Equatable, Sendable {
    let coupleID: UUID
}
