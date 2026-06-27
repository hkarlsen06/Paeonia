import Foundation
import Supabase

protocol SupabaseLocationGateway: Actor {
    func loadPartnerLocationVisibility(
        ownerUserID: UUID,
        coupleID: UUID
    ) async throws -> LocationVisibilitySnapshot?
    func updateLocationSharingPreference(
        payload: LocationSharingPreferenceOperationPayload,
        operation: SyncClientOperation
    ) async throws -> LocationSharingPreferenceUpdateResponse?
    func updateLatestPartnerLocation(
        payload: LatestPartnerLocationOperationPayload,
        operation: SyncClientOperation
    ) async throws -> LatestPartnerLocationUpdateResponse?
}

actor LiveSupabaseLocationGateway: SupabaseLocationGateway {
    private let client: SupabaseClient

    init(client: SupabaseClient) {
        self.client = client
    }

    func loadPartnerLocationVisibility(
        ownerUserID: UUID,
        coupleID: UUID
    ) async throws -> LocationVisibilitySnapshot? {
        let rows: [SupabasePartnerLocationVisibility] = try await client
            .rpc(
                "get_partner_location_visibility",
                params: PartnerLocationVisibilityRequest(coupleID: coupleID)
            )
            .execute()
            .value

        return rows.first?.snapshot(ownerUserID: ownerUserID, refreshedAt: Date())
    }

    func updateLocationSharingPreference(
        payload: LocationSharingPreferenceOperationPayload,
        operation: SyncClientOperation
    ) async throws -> LocationSharingPreferenceUpdateResponse? {
        let rows: [LocationSharingPreferenceUpdateResponse] = try await client
            .rpc(
                "update_location_sharing_preference",
                params: UpdateLocationSharingPreferenceRequest(payload: payload, operation: operation)
            )
            .execute()
            .value

        return rows.first
    }

    func updateLatestPartnerLocation(
        payload: LatestPartnerLocationOperationPayload,
        operation: SyncClientOperation
    ) async throws -> LatestPartnerLocationUpdateResponse? {
        let rows: [LatestPartnerLocationUpdateResponse] = try await client
            .rpc(
                "update_latest_partner_location",
                params: UpdateLatestPartnerLocationRequest(payload: payload, operation: operation)
            )
            .execute()
            .value

        return rows.first
    }
}

nonisolated struct LocationSharingPreferenceOperationPayload: Codable, Equatable, Sendable {
    let coupleID: UUID
    let isEnabled: Bool
    let consentVersion: String?
    let source: LocationSharingSource

    init(
        coupleID: UUID,
        isEnabled: Bool,
        consentVersion: String?,
        source: LocationSharingSource
    ) {
        self.coupleID = coupleID
        self.isEnabled = isEnabled
        self.consentVersion = consentVersion
        self.source = source
    }
}

nonisolated struct LatestPartnerLocationOperationPayload: Codable, Equatable, Sendable {
    let coupleID: UUID
    let latitude: Double
    let longitude: Double
    let accuracyMeters: Double?
    let capturedAt: Date
    let source: LocationSharingSource

    init(
        coupleID: UUID,
        location: LocationPoint,
        source: LocationSharingSource
    ) {
        self.coupleID = coupleID
        latitude = location.latitude
        longitude = location.longitude
        accuracyMeters = location.accuracyMeters
        capturedAt = location.capturedAt
        self.source = source
    }
}

nonisolated struct LocationSharingPreferenceUpdateResponse: Decodable, Equatable, Sendable {
    let coupleID: UUID
    let userID: UUID
    let isEnabled: Bool
    let enabledAt: Date?
    let disabledAt: Date?
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case coupleID = "couple_id"
        case userID = "user_id"
        case isEnabled = "is_enabled"
        case enabledAt = "enabled_at"
        case disabledAt = "disabled_at"
        case updatedAt = "updated_at"
    }
}

nonisolated struct LatestPartnerLocationUpdateResponse: Decodable, Equatable, Sendable {
    let coupleID: UUID
    let userID: UUID
    let latitude: Double
    let longitude: Double
    let accuracyMeters: Double?
    let capturedAt: Date
    let receivedAt: Date
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case coupleID = "couple_id"
        case userID = "user_id"
        case latitude
        case longitude
        case accuracyMeters = "accuracy_m"
        case capturedAt = "captured_at"
        case receivedAt = "received_at"
        case updatedAt = "updated_at"
    }
}

nonisolated private struct PartnerLocationVisibilityRequest: Encodable {
    let coupleID: UUID

    enum CodingKeys: String, CodingKey {
        case coupleID = "p_couple_id"
    }
}

nonisolated private struct UpdateLocationSharingPreferenceRequest: Encodable {
    let coupleID: UUID
    let isEnabled: Bool
    let consentVersion: String?
    let source: String
    let clientOperationID: UUID
    let clientID: UUID
    let clientSequence: Int64
    let localCreatedAt: Date

    init(payload: LocationSharingPreferenceOperationPayload, operation: SyncClientOperation) {
        coupleID = payload.coupleID
        isEnabled = payload.isEnabled
        consentVersion = payload.consentVersion
        source = payload.source.rawValue
        clientOperationID = operation.id
        clientID = operation.clientID
        clientSequence = operation.clientSequence
        localCreatedAt = operation.localCreatedAt
    }

    enum CodingKeys: String, CodingKey {
        case coupleID = "p_couple_id"
        case isEnabled = "p_is_enabled"
        case consentVersion = "p_consent_version"
        case source = "p_source"
        case clientOperationID = "p_client_operation_id"
        case clientID = "p_client_id"
        case clientSequence = "p_client_sequence"
        case localCreatedAt = "p_local_created_at"
    }
}

nonisolated private struct UpdateLatestPartnerLocationRequest: Encodable {
    let coupleID: UUID
    let latitude: Double
    let longitude: Double
    let accuracyMeters: Double?
    let capturedAt: Date
    let source: String
    let clientOperationID: UUID
    let clientID: UUID
    let clientSequence: Int64
    let localCreatedAt: Date

    init(payload: LatestPartnerLocationOperationPayload, operation: SyncClientOperation) {
        coupleID = payload.coupleID
        latitude = payload.latitude
        longitude = payload.longitude
        accuracyMeters = payload.accuracyMeters
        capturedAt = payload.capturedAt
        source = payload.source.rawValue
        clientOperationID = operation.id
        clientID = operation.clientID
        clientSequence = operation.clientSequence
        localCreatedAt = operation.localCreatedAt
    }

    enum CodingKeys: String, CodingKey {
        case coupleID = "p_couple_id"
        case latitude = "p_latitude"
        case longitude = "p_longitude"
        case accuracyMeters = "p_accuracy_m"
        case capturedAt = "p_captured_at"
        case source = "p_source"
        case clientOperationID = "p_client_operation_id"
        case clientID = "p_client_id"
        case clientSequence = "p_client_sequence"
        case localCreatedAt = "p_local_created_at"
    }
}

nonisolated private struct SupabasePartnerLocationVisibility: Decodable, Equatable, Sendable {
    let coupleID: UUID
    let viewerUserID: UUID
    let partnerUserID: UUID?
    let visibilityState: String
    let viewerSharingEnabled: Bool
    let partnerSharingEnabled: Bool
    let partnerLocationLatitude: Double?
    let partnerLocationLongitude: Double?
    let partnerLocationAccuracyMeters: Double?
    let partnerLocationCapturedAt: Date?
    let partnerLocationIsStale: Bool
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case coupleID = "couple_id"
        case viewerUserID = "viewer_user_id"
        case partnerUserID = "partner_user_id"
        case visibilityState = "visibility_state"
        case viewerSharingEnabled = "viewer_sharing_enabled"
        case partnerSharingEnabled = "partner_sharing_enabled"
        case partnerLocationLatitude = "partner_location_latitude"
        case partnerLocationLongitude = "partner_location_longitude"
        case partnerLocationAccuracyMeters = "partner_location_accuracy_m"
        case partnerLocationCapturedAt = "partner_location_captured_at"
        case partnerLocationIsStale = "partner_location_is_stale"
        case updatedAt = "updated_at"
    }

    func snapshot(ownerUserID: UUID, refreshedAt: Date) -> LocationVisibilitySnapshot {
        LocationVisibilitySnapshot(
            ownerUserID: ownerUserID,
            coupleID: coupleID,
            viewerUserID: viewerUserID,
            partnerUserID: partnerUserID,
            visibilityState: PartnerLocationVisibilityState(rawValue: visibilityState),
            viewerSharingEnabled: viewerSharingEnabled,
            partnerSharingEnabled: partnerSharingEnabled,
            partnerLocation: partnerLocation,
            partnerLocationIsStale: partnerLocationIsStale,
            updatedAt: updatedAt,
            refreshedAt: refreshedAt
        )
    }

    private var partnerLocation: LocationPoint? {
        guard let partnerLocationLatitude,
              let partnerLocationLongitude,
              let partnerLocationCapturedAt
        else {
            return nil
        }

        return LocationPoint(
            latitude: partnerLocationLatitude,
            longitude: partnerLocationLongitude,
            accuracyMeters: partnerLocationAccuracyMeters,
            capturedAt: partnerLocationCapturedAt,
            updatedAt: updatedAt
        )
    }
}
