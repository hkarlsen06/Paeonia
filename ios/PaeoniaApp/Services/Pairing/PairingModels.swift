import Foundation

enum PairingStartDateError: Error, Equatable {
    case invalidFormat
}

typealias PairingClientOperation = SyncClientOperation

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

nonisolated enum PairingInviteValidationStatus: Codable, Equatable, Sendable {
    case pending
    case accepted
    case revoked
    case expired
    case notFound
    case unknown(String)

    init(from decoder: Decoder) throws {
        let rawValue = try decoder.singleValueContainer().decode(String.self)
        self = Self(rawValue: rawValue)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    init(rawValue: String) {
        switch rawValue {
        case "pending":
            self = .pending
        case "accepted":
            self = .accepted
        case "revoked":
            self = .revoked
        case "expired":
            self = .expired
        case "not_found":
            self = .notFound
        default:
            self = .unknown(rawValue)
        }
    }

    var rawValue: String {
        switch self {
        case .pending:
            "pending"
        case .accepted:
            "accepted"
        case .revoked:
            "revoked"
        case .expired:
            "expired"
        case .notFound:
            "not_found"
        case let .unknown(rawValue):
            rawValue
        }
    }
}

nonisolated struct PairingInviteValidation: Decodable, Equatable, Sendable {
    let inviteID: UUID?
    let status: PairingInviteValidationStatus
    let expiresAt: Date?

    enum CodingKeys: String, CodingKey {
        case inviteID = "invite_id"
        case status
        case expiresAt = "expires_at"
    }
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
