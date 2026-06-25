import Foundation
import CryptoKit
import Supabase

nonisolated struct SupabaseRemoteSession: Equatable, Sendable {
    let userID: String
    let provider: AuthProvider
    let displayName: String?
}

nonisolated struct SupabaseProfile: Codable, Equatable, Sendable {
    let userID: String
    let displayName: String?
    let timeZoneID: String?
    let timeZoneUpdatedAt: Date?
    let onboardingCompletedAt: Date?
    let profilePhotoAssetID: UUID?

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case displayName = "display_name"
        case timeZoneID = "time_zone_id"
        case timeZoneUpdatedAt = "time_zone_updated_at"
        case onboardingCompletedAt = "onboarding_completed_at"
        case profilePhotoAssetID = "profile_photo_asset_id"
    }
}

protocol SupabaseAuthGateway: Actor {
    func restoreSession() async throws -> SupabaseRemoteSession?
    func signInWithApple(idToken: String, nonce: String) async throws -> SupabaseRemoteSession
    func signInWithGoogle(idToken: String, accessToken: String?) async throws -> SupabaseRemoteSession
    func loadProfile(userID: String) async throws -> SupabaseProfile
    func updateAuthDisplayName(_ displayName: String) async throws
    func uploadProfilePhoto(
        userID: String,
        compressedImage: ImageCompressor.CompressedImage
    ) async throws -> UUID
    func completeProfileOnboarding(
        userID: String,
        timeZoneID: String,
        profilePhotoAssetID: UUID?
    ) async throws -> SupabaseProfile
    func requestAccountDeletion() async throws
    func signOut() async throws
}

actor LiveSupabaseAuthGateway: SupabaseAuthGateway {
    private let client: SupabaseClient
    private let defaults: UserDefaults
    private var fallbackClientSequence: Int64 = 0
    private let profileColumns = """
        user_id,
        display_name,
        time_zone_id,
        time_zone_updated_at,
        onboarding_completed_at,
        profile_photo_asset_id
        """

    init(client: SupabaseClient, defaults: UserDefaults = .standard) {
        self.client = client
        self.defaults = defaults
    }

    func restoreSession() async throws -> SupabaseRemoteSession? {
        do {
            let session = try await client.auth.session
            return Self.remoteSession(from: session)
        } catch AuthError.sessionMissing {
            return nil
        }
    }

    func signInWithApple(idToken: String, nonce: String) async throws -> SupabaseRemoteSession {
        let session = try await client.auth.signInWithIdToken(
            credentials: OpenIDConnectCredentials(
                provider: .apple,
                idToken: idToken,
                nonce: nonce
            )
        )

        return Self.remoteSession(from: session, fallbackProvider: .apple)
    }

    func signInWithGoogle(
        idToken: String,
        accessToken: String?
    ) async throws -> SupabaseRemoteSession {
        let session = try await client.auth.signInWithIdToken(
            credentials: OpenIDConnectCredentials(
                provider: .google,
                idToken: idToken,
                accessToken: accessToken
            )
        )
        return Self.remoteSession(from: session, fallbackProvider: .google)
    }

    func loadProfile(userID: String) async throws -> SupabaseProfile {
        try await client
            .from("profiles")
            .select(profileColumns)
            .eq("user_id", value: userID)
            .single()
            .execute()
            .value
    }

    func updateAuthDisplayName(_ displayName: String) async throws {
        try await client.auth.update(
            user: UserAttributes(
                data: [
                    "name": .string(displayName),
                    "full_name": .string(displayName),
                    "display_name": .string(displayName),
                ]
            )
        )
    }

    func completeProfileOnboarding(
        userID: String,
        timeZoneID: String,
        profilePhotoAssetID: UUID?
    ) async throws -> SupabaseProfile {
        try await client
            .from("profiles")
            .update(
                CompleteProfileOnboardingRequest(
                    timeZoneID: timeZoneID,
                    timeZoneUpdatedAt: Date(),
                    onboardingCompletedAt: Date(),
                    profilePhotoAssetID: profilePhotoAssetID
                )
            )
            .eq("user_id", value: userID)
            .select(profileColumns)
            .single()
            .execute()
            .value
    }

    // swiftlint:disable:next function_body_length
    func uploadProfilePhoto(
        userID: String,
        compressedImage: ImageCompressor.CompressedImage
    ) async throws -> UUID {
        let reservedParentID = try UUID(uuidString: userID).orThrow()
        let reserveOperation = makeClientOperation()
        let reservation: [PendingMediaUploadResponse] = try await client
            .rpc(
                "create_pending_media_upload",
                params: CreatePendingProfilePhotoUploadRequest(
                    operation: reserveOperation,
                    reservedParentID: reservedParentID,
                    fileExtension: compressedImage.fileExtension
                )
            )
            .execute()
            .value
        guard let reservation = reservation.first else {
            throw AuthServiceError.invalidProfilePhoto
        }

        try await client.storage
            .from(reservation.bucket)
            .upload(
                reservation.storagePath,
                data: compressedImage.data,
                options: FileOptions(contentType: compressedImage.mediaType)
            )

        let finalizeOperation = makeClientOperation()
        let finalized: [FinalizedMediaUploadResponse] = try await client
            .rpc(
                "finalize_media_upload",
                params: FinalizeProfilePhotoUploadRequest(
                    reservation: reservation,
                    reservedByClientOperationID: reserveOperation.id,
                    operation: finalizeOperation,
                    reservedParentID: reservedParentID,
                    image: compressedImage
                )
            )
            .execute()
            .value
        guard let finalized = finalized.first,
              finalized.uploadStatus == "finalized" else {
            throw AuthServiceError.invalidProfilePhoto
        }

        return finalized.mediaAssetID
    }

    func requestAccountDeletion() async throws {
        try await client
            .rpc("request_account_deletion")
            .execute()
    }

    func signOut() async throws {
        try await client.auth.signOut()
    }

    private static func remoteSession(
        from session: Session,
        fallbackProvider: AuthProvider = .unknown
    ) -> SupabaseRemoteSession {
        SupabaseRemoteSession(
            userID: session.user.id.uuidString,
            provider: provider(from: session.user) ?? fallbackProvider,
            displayName: displayName(from: session.user)
        )
    }

    private static func provider(from user: User) -> AuthProvider? {
        switch user.appMetadata["provider"]?.stringValue {
        case "apple":
            .apple
        case "google":
            .google
        case .some:
            .unknown
        case .none:
            nil
        }
    }

    private static func displayName(from user: User) -> String? {
        let candidates = [
            user.userMetadata["full_name"]?.stringValue,
            user.userMetadata["name"]?.stringValue,
            user.userMetadata["display_name"]?.stringValue,
        ]

        return candidates.compactMap { $0?.trimmedNonEmpty }.first
    }
}

nonisolated private struct CompleteProfileOnboardingRequest: Encodable {
    let timeZoneID: String
    let timeZoneUpdatedAt: Date
    let onboardingCompletedAt: Date
    let profilePhotoAssetID: UUID?

    enum CodingKeys: String, CodingKey {
        case timeZoneID = "time_zone_id"
        case timeZoneUpdatedAt = "time_zone_updated_at"
        case onboardingCompletedAt = "onboarding_completed_at"
        case profilePhotoAssetID = "profile_photo_asset_id"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(timeZoneID, forKey: .timeZoneID)
        try container.encode(timeZoneUpdatedAt, forKey: .timeZoneUpdatedAt)
        try container.encode(onboardingCompletedAt, forKey: .onboardingCompletedAt)
        try container.encodeIfPresent(profilePhotoAssetID, forKey: .profilePhotoAssetID)
    }
}

nonisolated private struct AuthClientOperation: Sendable {
    let id: UUID
    let clientID: UUID
    let clientSequence: Int64
    let localCreatedAt: Date
}

nonisolated private struct PendingMediaUploadResponse: Decodable, Sendable {
    let mediaAssetID: UUID
    let bucket: String
    let storagePath: String

    enum CodingKeys: String, CodingKey {
        case mediaAssetID = "media_asset_id"
        case bucket
        case storagePath = "storage_path"
    }
}

nonisolated private struct FinalizedMediaUploadResponse: Decodable, Sendable {
    let mediaAssetID: UUID
    let uploadStatus: String

    enum CodingKeys: String, CodingKey {
        case mediaAssetID = "media_asset_id"
        case uploadStatus = "upload_status"
    }
}

nonisolated private struct CreatePendingProfilePhotoUploadRequest: Encodable {
    let clientOperationID: UUID
    let clientID: UUID
    let clientSequence: Int64
    let localCreatedAt: Date
    let reservedParentKind = "profile_photo"
    let reservedParentID: UUID
    let uploadPurpose = "profile_photo"
    let mediaType = "image"
    let fileExtension: String

    init(
        operation: AuthClientOperation,
        reservedParentID: UUID,
        fileExtension: String
    ) {
        self.clientOperationID = operation.id
        self.clientID = operation.clientID
        self.clientSequence = operation.clientSequence
        self.localCreatedAt = operation.localCreatedAt
        self.reservedParentID = reservedParentID
        self.fileExtension = fileExtension
    }

    enum CodingKeys: String, CodingKey {
        case clientOperationID = "p_client_operation_id"
        case clientID = "p_client_id"
        case clientSequence = "p_client_sequence"
        case localCreatedAt = "p_local_created_at"
        case reservedParentKind = "p_reserved_parent_kind"
        case reservedParentID = "p_reserved_parent_id"
        case uploadPurpose = "p_upload_purpose"
        case mediaType = "p_media_type"
        case fileExtension = "p_file_extension"
    }
}

nonisolated private struct FinalizeProfilePhotoUploadRequest: Encodable {
    let mediaAssetID: UUID
    let reservedByClientOperationID: UUID
    let clientOperationID: UUID
    let clientID: UUID
    let clientSequence: Int64
    let localCreatedAt: Date
    let bucket: String
    let storagePath: String
    let reservedParentKind = "profile_photo"
    let reservedParentID: UUID
    let uploadPurpose = "profile_photo"
    let mediaType = "image"
    let mimeType: String
    let byteSize: Int64
    let sha256Hex: String
    let width: Int
    let height: Int

    init(
        reservation: PendingMediaUploadResponse,
        reservedByClientOperationID: UUID,
        operation: AuthClientOperation,
        reservedParentID: UUID,
        image: ImageCompressor.CompressedImage
    ) {
        self.mediaAssetID = reservation.mediaAssetID
        self.reservedByClientOperationID = reservedByClientOperationID
        self.clientOperationID = operation.id
        self.clientID = operation.clientID
        self.clientSequence = operation.clientSequence
        self.localCreatedAt = operation.localCreatedAt
        self.bucket = reservation.bucket
        self.storagePath = reservation.storagePath
        self.reservedParentID = reservedParentID
        self.mimeType = image.mediaType
        self.byteSize = Int64(image.data.count)
        self.sha256Hex = SHA256.hash(data: image.data).map { String(format: "%02x", $0) }.joined()
        self.width = image.width
        self.height = image.height
    }

    enum CodingKeys: String, CodingKey {
        case mediaAssetID = "p_media_asset_id"
        case reservedByClientOperationID = "p_reserved_by_client_operation_id"
        case clientOperationID = "p_client_operation_id"
        case clientID = "p_client_id"
        case clientSequence = "p_client_sequence"
        case localCreatedAt = "p_local_created_at"
        case bucket = "p_bucket"
        case storagePath = "p_storage_path"
        case reservedParentKind = "p_reserved_parent_kind"
        case reservedParentID = "p_reserved_parent_id"
        case uploadPurpose = "p_upload_purpose"
        case mediaType = "p_media_type"
        case mimeType = "p_mime_type"
        case byteSize = "p_byte_size"
        case sha256Hex = "p_sha256_hex"
        case width = "p_width"
        case height = "p_height"
    }
}

private extension LiveSupabaseAuthGateway {
    enum DefaultsKey {
        static let clientID = "paeonia.auth.clientID"
        static let clientSequence = "paeonia.auth.clientSequence"
    }

    func makeClientOperation() -> AuthClientOperation {
        let clientID = resolvedClientID()
        let clientSequence = nextClientSequence()

        return AuthClientOperation(
            id: UUID(),
            clientID: clientID,
            clientSequence: clientSequence,
            localCreatedAt: Date()
        )
    }

    func resolvedClientID() -> UUID {
        if let storedValue = defaults.string(forKey: DefaultsKey.clientID),
           let storedID = UUID(uuidString: storedValue) {
            return storedID
        }

        let clientID = UUID()
        defaults.set(clientID.uuidString, forKey: DefaultsKey.clientID)
        return clientID
    }

    func nextClientSequence() -> Int64 {
        let currentValue = max(
            Int64(defaults.integer(forKey: DefaultsKey.clientSequence)),
            fallbackClientSequence
        )
        let nextValue = currentValue + 1
        defaults.set(nextValue, forKey: DefaultsKey.clientSequence)
        fallbackClientSequence = nextValue
        return nextValue
    }
}

private extension Optional where Wrapped == UUID {
    nonisolated func orThrow() throws -> UUID {
        guard let self else {
            throw AuthServiceError.invalidProfilePhoto
        }

        return self
    }
}

extension String {
    nonisolated var trimmedNonEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
} // swiftlint:disable:this file_length
