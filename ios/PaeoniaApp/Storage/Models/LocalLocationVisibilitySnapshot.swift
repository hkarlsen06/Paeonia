import Foundation
import SwiftData

@Model
final class LocalLocationVisibilitySnapshot {
    @Attribute(.unique) var storageKey: String
    var ownerUserID: UUID
    var coupleID: UUID
    var viewerUserID: UUID
    var partnerUserID: UUID?
    var visibilityStateRawValue: String
    var viewerSharingEnabled: Bool
    var partnerSharingEnabled: Bool
    var partnerLatitude: Double?
    var partnerLongitude: Double?
    var partnerAccuracyMeters: Double?
    var partnerCapturedAt: Date?
    var partnerLocationUpdatedAt: Date?
    var partnerLocationIsStale: Bool
    var updatedAt: Date
    var refreshedAt: Date

    init(snapshot: LocationVisibilitySnapshot) {
        storageKey = Self.storageKey(ownerUserID: snapshot.ownerUserID, coupleID: snapshot.coupleID)
        ownerUserID = snapshot.ownerUserID
        coupleID = snapshot.coupleID
        viewerUserID = snapshot.viewerUserID
        partnerUserID = snapshot.partnerUserID
        visibilityStateRawValue = snapshot.visibilityState.rawValue
        viewerSharingEnabled = snapshot.viewerSharingEnabled
        partnerSharingEnabled = snapshot.partnerSharingEnabled
        partnerLatitude = snapshot.partnerLocation?.latitude
        partnerLongitude = snapshot.partnerLocation?.longitude
        partnerAccuracyMeters = snapshot.partnerLocation?.accuracyMeters
        partnerCapturedAt = snapshot.partnerLocation?.capturedAt
        partnerLocationUpdatedAt = snapshot.partnerLocation?.updatedAt
        partnerLocationIsStale = snapshot.partnerLocationIsStale
        updatedAt = snapshot.updatedAt
        refreshedAt = snapshot.refreshedAt
    }

    var snapshot: LocationVisibilitySnapshot {
        LocationVisibilitySnapshot(
            ownerUserID: ownerUserID,
            coupleID: coupleID,
            viewerUserID: viewerUserID,
            partnerUserID: partnerUserID,
            visibilityState: PartnerLocationVisibilityState(rawValue: visibilityStateRawValue),
            viewerSharingEnabled: viewerSharingEnabled,
            partnerSharingEnabled: partnerSharingEnabled,
            partnerLocation: partnerLocation,
            partnerLocationIsStale: partnerLocationIsStale,
            updatedAt: updatedAt,
            refreshedAt: refreshedAt
        )
    }

    func update(from snapshot: LocationVisibilitySnapshot) {
        ownerUserID = snapshot.ownerUserID
        coupleID = snapshot.coupleID
        viewerUserID = snapshot.viewerUserID
        partnerUserID = snapshot.partnerUserID
        visibilityStateRawValue = snapshot.visibilityState.rawValue
        viewerSharingEnabled = snapshot.viewerSharingEnabled
        partnerSharingEnabled = snapshot.partnerSharingEnabled
        partnerLatitude = snapshot.partnerLocation?.latitude
        partnerLongitude = snapshot.partnerLocation?.longitude
        partnerAccuracyMeters = snapshot.partnerLocation?.accuracyMeters
        partnerCapturedAt = snapshot.partnerLocation?.capturedAt
        partnerLocationUpdatedAt = snapshot.partnerLocation?.updatedAt
        partnerLocationIsStale = snapshot.partnerLocationIsStale
        updatedAt = snapshot.updatedAt
        refreshedAt = snapshot.refreshedAt
    }

    static func storageKey(ownerUserID: UUID, coupleID: UUID) -> String {
        "\(ownerUserID.uuidString.lowercased()):\(coupleID.uuidString.lowercased())"
    }

    private var partnerLocation: LocationPoint? {
        guard let partnerLatitude, let partnerLongitude, let partnerCapturedAt else {
            return nil
        }

        return LocationPoint(
            latitude: partnerLatitude,
            longitude: partnerLongitude,
            accuracyMeters: partnerAccuracyMeters,
            capturedAt: partnerCapturedAt,
            updatedAt: partnerLocationUpdatedAt
        )
    }
}
