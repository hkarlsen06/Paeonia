import Foundation
import SwiftData

@Model
final class LocalOwnLocationSnapshot {
    @Attribute(.unique) var storageKey: String
    var ownerUserID: UUID
    var coupleID: UUID
    var latitude: Double
    var longitude: Double
    var accuracyMeters: Double?
    var capturedAt: Date
    var locationUpdatedAt: Date?
    var sourceRawValue: String
    var pendingOperationID: UUID?
    var updatedAt: Date

    init(snapshot: OwnLocationSnapshot) {
        storageKey = Self.storageKey(ownerUserID: snapshot.ownerUserID, coupleID: snapshot.coupleID)
        ownerUserID = snapshot.ownerUserID
        coupleID = snapshot.coupleID
        latitude = snapshot.location.latitude
        longitude = snapshot.location.longitude
        accuracyMeters = snapshot.location.accuracyMeters
        capturedAt = snapshot.location.capturedAt
        locationUpdatedAt = snapshot.location.updatedAt
        sourceRawValue = snapshot.source.rawValue
        pendingOperationID = snapshot.pendingOperationID
        updatedAt = snapshot.updatedAt
    }

    var snapshot: OwnLocationSnapshot {
        OwnLocationSnapshot(
            ownerUserID: ownerUserID,
            coupleID: coupleID,
            location: LocationPoint(
                latitude: latitude,
                longitude: longitude,
                accuracyMeters: accuracyMeters,
                capturedAt: capturedAt,
                updatedAt: locationUpdatedAt
            ),
            source: LocationSharingSource(rawValue: sourceRawValue) ?? .foregroundOpen,
            pendingOperationID: pendingOperationID,
            updatedAt: updatedAt
        )
    }

    func update(from snapshot: OwnLocationSnapshot) {
        ownerUserID = snapshot.ownerUserID
        coupleID = snapshot.coupleID
        latitude = snapshot.location.latitude
        longitude = snapshot.location.longitude
        accuracyMeters = snapshot.location.accuracyMeters
        capturedAt = snapshot.location.capturedAt
        locationUpdatedAt = snapshot.location.updatedAt
        sourceRawValue = snapshot.source.rawValue
        pendingOperationID = snapshot.pendingOperationID
        updatedAt = snapshot.updatedAt
    }

    static func storageKey(ownerUserID: UUID, coupleID: UUID) -> String {
        "\(ownerUserID.uuidString.lowercased()):\(coupleID.uuidString.lowercased())"
    }
}
