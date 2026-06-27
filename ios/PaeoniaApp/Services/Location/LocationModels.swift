import Foundation

nonisolated enum LocationSharingSource: String, Codable, CaseIterable, Sendable {
    case foregroundOpen = "foreground_open"
    case manualRefresh = "manual_refresh"
    case settingsToggle = "settings_toggle"
}

nonisolated enum PartnerLocationVisibilityState: Codable, Equatable, Sendable {
    case disabled
    case notSharing
    case visible
    case relationshipEnded
    case unknown(String)

    init(rawValue: String) {
        switch rawValue {
        case "disabled":
            self = .disabled
        case "not_sharing":
            self = .notSharing
        case "visible":
            self = .visible
        case "relationship_ended":
            self = .relationshipEnded
        default:
            self = .unknown(rawValue)
        }
    }

    var rawValue: String {
        switch self {
        case .disabled:
            "disabled"
        case .notSharing:
            "not_sharing"
        case .visible:
            "visible"
        case .relationshipEnded:
            "relationship_ended"
        case let .unknown(rawValue):
            rawValue
        }
    }

    init(from decoder: Decoder) throws {
        self.init(rawValue: try decoder.singleValueContainer().decode(String.self))
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

nonisolated struct LocationPoint: Codable, Equatable, Sendable {
    let latitude: Double
    let longitude: Double
    let accuracyMeters: Double?
    let capturedAt: Date
    let updatedAt: Date?

    init(
        latitude: Double,
        longitude: Double,
        accuracyMeters: Double? = nil,
        capturedAt: Date,
        updatedAt: Date? = nil
    ) {
        self.latitude = latitude
        self.longitude = longitude
        self.accuracyMeters = accuracyMeters
        self.capturedAt = capturedAt
        self.updatedAt = updatedAt
    }
}

nonisolated struct LocationVisibilitySnapshot: Codable, Equatable, Sendable {
    let ownerUserID: UUID
    let coupleID: UUID
    let viewerUserID: UUID
    let partnerUserID: UUID?
    let visibilityState: PartnerLocationVisibilityState
    let viewerSharingEnabled: Bool
    let partnerSharingEnabled: Bool
    let partnerLocation: LocationPoint?
    let partnerLocationIsStale: Bool
    let updatedAt: Date
    let refreshedAt: Date
}

nonisolated struct OwnLocationSnapshot: Codable, Equatable, Sendable {
    let ownerUserID: UUID
    let coupleID: UUID
    let location: LocationPoint
    let source: LocationSharingSource
    let pendingOperationID: UUID?
    let updatedAt: Date
}

nonisolated enum CoupleMapState: Equatable, Sendable {
    case loading
    case currentUnknown
    case partnerUnknown(PartnerLocationVisibilityState)
    case ready(current: LocationPoint, partner: LocationPoint)
}

nonisolated struct LocationIdentity: Equatable, Hashable, Sendable {
    let currentUserID: UUID?
    let coupleID: UUID?

    init(currentUserID: UUID?, coupleID: UUID?) {
        self.currentUserID = currentUserID
        self.coupleID = coupleID
    }
}
