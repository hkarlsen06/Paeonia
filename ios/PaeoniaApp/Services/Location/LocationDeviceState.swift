import CoreLocation
import Foundation

/// What this phone tells the server about sending moves while Paeonia is
/// closed. The server keeps the choice so a new sign-in can restore it, and
/// keeps the iOS access so it is clear whether the moves can arrive.
nonisolated struct LocationDeviceState: Equatable, Sendable {
    let userID: UUID
    let coupleID: UUID
    /// `nil` asks for the choice stored on the server without changing it.
    let updatesWhileClosed: Bool?
    let permission: LocationPermission
}

/// The iOS location access Paeonia has, as the server names it.
nonisolated enum LocationPermission: String, Sendable {
    case always
    case whenInUse = "when_in_use"
    case denied
    case restricted
    case notDetermined = "not_determined"

    init?(_ status: CLAuthorizationStatus) {
        switch status {
        case .authorizedAlways: self = .always
        case .authorizedWhenInUse: self = .whenInUse
        case .denied: self = .denied
        case .restricted: self = .restricted
        case .notDetermined: self = .notDetermined
        @unknown default: return nil
        }
    }
}

nonisolated struct ReportLocationDeviceStateRequest: Encodable {
    let state: LocationDeviceState
    let reportedAt: Date

    enum CodingKeys: String, CodingKey {
        case coupleID = "p_couple_id"
        case updatesWhileClosed = "p_updates_while_closed"
        case permission = "p_permission"
        case reportedAt = "p_reported_at"
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(state.coupleID, forKey: .coupleID)
        if let updatesWhileClosed = state.updatesWhileClosed {
            try container.encode(updatesWhileClosed, forKey: .updatesWhileClosed)
        } else {
            try container.encodeNil(forKey: .updatesWhileClosed)
        }
        try container.encode(state.permission.rawValue, forKey: .permission)
        try container.encode(reportedAt, forKey: .reportedAt)
    }
}

nonisolated struct ReportLocationDeviceStateResponse: Decodable, Sendable {
    let updatesWhileClosed: Bool

    enum CodingKeys: String, CodingKey {
        case updatesWhileClosed = "updates_while_closed"
    }
}
