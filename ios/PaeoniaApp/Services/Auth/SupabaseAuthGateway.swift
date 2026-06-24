import Foundation
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

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case displayName = "display_name"
        case timeZoneID = "time_zone_id"
        case timeZoneUpdatedAt = "time_zone_updated_at"
        case onboardingCompletedAt = "onboarding_completed_at"
    }
}

protocol SupabaseAuthGateway: Actor {
    func restoreSession() async throws -> SupabaseRemoteSession?
    func signInWithApple(idToken: String, nonce: String) async throws -> SupabaseRemoteSession
    func signInWithGoogle(idToken: String, accessToken: String?) async throws -> SupabaseRemoteSession
    func loadProfile(userID: String) async throws -> SupabaseProfile
    func updateAuthDisplayName(_ displayName: String) async throws
    func completeProfileOnboarding(userID: String, timeZoneID: String) async throws -> SupabaseProfile
    func requestAccountDeletion() async throws
    func signOut() async throws
}

actor LiveSupabaseAuthGateway: SupabaseAuthGateway {
    private let client: SupabaseClient
    private let profileColumns = """
        user_id,
        display_name,
        time_zone_id,
        time_zone_updated_at,
        onboarding_completed_at
        """

    init(client: SupabaseClient) {
        self.client = client
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
        timeZoneID: String
    ) async throws -> SupabaseProfile {
        try await client
            .from("profiles")
            .update(
                CompleteProfileOnboardingRequest(
                    timeZoneID: timeZoneID,
                    timeZoneUpdatedAt: Date(),
                    onboardingCompletedAt: Date()
                )
            )
            .eq("user_id", value: userID)
            .select(profileColumns)
            .single()
            .execute()
            .value
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

    enum CodingKeys: String, CodingKey {
        case timeZoneID = "time_zone_id"
        case timeZoneUpdatedAt = "time_zone_updated_at"
        case onboardingCompletedAt = "onboarding_completed_at"
    }
}

extension String {
    nonisolated var trimmedNonEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
