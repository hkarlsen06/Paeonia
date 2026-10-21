import Foundation

nonisolated enum LocationSharingSource: String, Codable, CaseIterable, Sendable {
    case foregroundOpen = "foreground_open"
    case manualRefresh = "manual_refresh"
    case settingsToggle = "settings_toggle"
    /// Sent while Paeonia was closed, after the phone moved a good distance.
    case background = "background"
}

nonisolated enum PartnerLocationVisibilityState: Codable, Equatable, Sendable {
    case disabled
    case notSharing
    case visible
    case relationshipEnded
    /// You paused sharing. The partner's location is hidden from you meanwhile too.
    case viewerPaused
    /// The partner paused sharing. The server sends no position and no end time.
    case partnerPaused
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
        case "viewer_paused":
            self = .viewerPaused
        case "partner_paused":
            self = .partnerPaused
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
        case .viewerPaused:
            "viewer_paused"
        case .partnerPaused:
            "partner_paused"
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

/// Display-only age classification for a last-known location. Old locations
/// remain available; after 24 hours the UI dims the marker and plainly labels
/// the timestamp instead of treating the location as missing.
nonisolated enum LocationDisplayRecency: Equatable, Sendable {
    case recent
    case stale

    static let staleAfter: TimeInterval = 24 * 60 * 60

    static func resolve(
        capturedAt: Date,
        now: Date = Date(),
        wasStaleAtLastRefresh: Bool = false
    ) -> Self {
        if wasStaleAtLastRefresh {
            return .stale
        }

        return now.timeIntervalSince(capturedAt) >= staleAfter ? .stale : .recent
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
    /// When your own pause ends. The server never sends the partner's.
    var viewerPausedUntil: Date?

    /// Your pause end if it is still ahead of `now`. A pause the clock has passed is over,
    /// even before the server clears it.
    func pausedUntil(at now: Date) -> Date? {
        viewerPausedUntil.flatMap { $0 > now ? $0 : nil }
    }
}

/// What the person chose for their own sharing: on or off, and for how long it is paused.
/// A bare `true` or `false` means a choice without a pause.
nonisolated struct ViewerSharingChoice: Equatable, Sendable, ExpressibleByBooleanLiteral {
    let isEnabled: Bool
    let pausedUntil: Date?

    init(isEnabled: Bool, pausedUntil: Date? = nil) {
        self.isEnabled = isEnabled
        self.pausedUntil = isEnabled ? pausedUntil : nil
    }

    init(booleanLiteral value: Bool) {
        self.init(isEnabled: value)
    }

    /// Pause ends compare to the second, because the server keeps milliseconds
    /// and the phone's clock has finer time.
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.isEnabled == rhs.isEnabled
            && lhs.pausedUntil.map { Int($0.timeIntervalSince1970.rounded()) }
            == rhs.pausedUntil.map { Int($0.timeIntervalSince1970.rounded()) }
    }
}

/// The server's answer to a sharing operation: the choice the operation sent, and the choice the
/// server kept. They differ when the server dropped a pause whose end had passed while the phone was offline.
nonisolated struct ViewerSharingConfirmation: Equatable, Sendable {
    let submitted: ViewerSharingChoice
    let confirmed: ViewerSharingChoice

    /// The server kept the choice as it was sent.
    init(_ choice: ViewerSharingChoice) {
        submitted = choice
        confirmed = choice
    }

    init(submitted: ViewerSharingChoice, confirmed: ViewerSharingChoice) {
        self.submitted = submitted
        self.confirmed = confirmed
    }
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
    /// You are not sharing your location.
    case currentUnknown
    /// You asked to share and the phone is looking up where you are.
    case locatingCurrent
    /// You share, but no location has been found yet. The card offers a retry.
    case currentLocationMissing
    /// You paused sharing until this time. Nothing is sent and the partner's
    /// location is hidden meanwhile.
    case sharingPaused(until: Date)
    /// iOS location access for Paeonia is off, so nothing can be shared.
    case locationAccessOff
    /// Your partner does not share, the relationship ended, or the map cannot
    /// be shown right now (`.unknown`).
    case partnerUnknown(PartnerLocationVisibilityState)
    /// Your partner turned sharing on but has not sent a location yet.
    case waitingForPartnerLocation
    case ready(current: LocationPoint, partner: LocationPoint, partnerWasStaleAtLastRefresh: Bool)
}

nonisolated struct LocationIdentity: Equatable, Hashable, Sendable {
    let currentUserID: UUID?
    let coupleID: UUID?
}
