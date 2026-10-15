import Foundation
import UIKit
@testable import PaeoniaApp

// swiftlint:disable async_without_await
actor FakeAuthGateway: AuthGateway {
    private var remoteSession: RemoteAuthSession?
    /// Ends the Clerk session while `loadProfile` is in flight, like a sign-out tapped meanwhile.
    private var endsSessionDuringProfileLoad = false
    private var profile: RemoteProfile
    private let profilePhotoAssetID: UUID
    private(set) var appleIDToken: String?
    private(set) var googleSignInCallCount = 0
    private(set) var updatedProfileDisplayName: String?
    private(set) var updatedTimeZoneID: String?
    private(set) var uploadedProfilePhotoUserID: String?
    private(set) var completedProfilePhotoAssetID: UUID?
    private(set) var markedForDeletionAssetID: UUID?
    private(set) var markedForDeletionAssetIDs: [UUID] = []
    private(set) var updatedProfilePhotoAssetID: UUID?
    private(set) var providerLinkedAssetID: UUID?
    private(set) var profileEvents: [String] = []
    private(set) var requestAccountDeletionCallCount = 0
    private(set) var accountDeletionAppleCode: String?
    private(set) var signOutCallCount = 0
    private let uploadShouldFail: Bool
    private let loadProfileError: (any Error)?
    /// Makes `loadProfile` hang like a stalled connection, until cancelled.
    private let loadProfileDelay: Duration?
    private let completeProfileShouldFail: Bool
    private let updateProfileShouldFail: Bool
    private let profileUpdateFailsAfterCommit: Bool
    private let markMediaForDeletionShouldFail: Bool
    private let accountDeletionOutcome: AccountDeletionOutcome

    init(
        remoteSession: RemoteAuthSession?,
        profile: RemoteProfile,
        profilePhotoAssetID: UUID? = nil,
        uploadShouldFail: Bool = false,
        loadProfileError: (any Error)? = nil,
        loadProfileDelay: Duration? = nil,
        completeProfileShouldFail: Bool = false,
        updateProfileShouldFail: Bool = false,
        profileUpdateFailsAfterCommit: Bool = false,
        markMediaForDeletionShouldFail: Bool = false,
        accountDeletionOutcome: AccountDeletionOutcome = .completed
    ) {
        self.remoteSession = remoteSession
        self.profile = profile
        self.profilePhotoAssetID = profilePhotoAssetID
            ?? UUID(uuidString: "A6B39D76-11D0-4A4D-8B77-5AF09A9E85E1")
            ?? UUID()
        self.uploadShouldFail = uploadShouldFail
        self.loadProfileError = loadProfileError
        self.loadProfileDelay = loadProfileDelay
        self.completeProfileShouldFail = completeProfileShouldFail
        self.updateProfileShouldFail = updateProfileShouldFail
        self.profileUpdateFailsAfterCommit = profileUpdateFailsAfterCommit
        self.markMediaForDeletionShouldFail = markMediaForDeletionShouldFail
        self.accountDeletionOutcome = accountDeletionOutcome
    }

    func restoreSession() async throws -> RemoteAuthSession? {
        remoteSession
    }

    func signInWithApple(idToken: String) async throws -> RemoteAuthSession {
        appleIDToken = idToken
        return remoteSession ?? .test(provider: .apple)
    }

    func signInWithGoogle() async throws -> RemoteAuthSession {
        googleSignInCallCount += 1
        return remoteSession ?? .test(provider: .google)
    }

    func loadProfile() async throws -> RemoteProfile {
        if let loadProfileDelay {
            try await Task.sleep(for: loadProfileDelay)
        }
        if let loadProfileError {
            throw loadProfileError
        }
        if endsSessionDuringProfileLoad {
            remoteSession = nil
        }
        return profile
    }

    func endSessionDuringProfileLoad() {
        endsSessionDuringProfileLoad = true
    }

    func uploadProfilePhoto(
        userID: String,
        compressedImage: ImageCompressor.CompressedImage
    ) async throws -> UUID {
        if uploadShouldFail {
            throw AuthServiceError.invalidProfilePhoto
        }
        uploadedProfilePhotoUserID = userID
        profileEvents.append("uploaded:\(profilePhotoAssetID.uuidString)")
        return profilePhotoAssetID
    }

    func markMediaForDeletion(_ mediaAssetID: UUID) async throws {
        markedForDeletionAssetID = mediaAssetID
        markedForDeletionAssetIDs.append(mediaAssetID)
        profileEvents.append("delete:\(mediaAssetID.uuidString)")
        if markMediaForDeletionShouldFail {
            throw AuthServiceError.invalidProfilePhoto
        }
    }

    func completeProfileOnboarding(
        timeZoneID: String,
        profilePhotoAssetID: UUID?
    ) async throws -> RemoteProfile {
        completedProfilePhotoAssetID = profilePhotoAssetID
        if completeProfileShouldFail {
            throw AuthServiceError.noActiveSession
        }
        updatedTimeZoneID = timeZoneID
        profile = RemoteProfile(
            userID: profile.userID,
            displayName: profile.displayName,
            timeZoneID: timeZoneID,
            timeZoneUpdatedAt: Date(),
            onboardingCompletedAt: Date(),
            profilePhotoAssetID: profilePhotoAssetID,
            providerProfilePhotoAssetID: profile.providerProfilePhotoAssetID,
            providerProfilePhotoSource: profile.providerProfilePhotoSource
        )
        return profile
    }

    func updateProfile(
        displayName: String,
        profilePhotoAssetID: UUID?
    ) async throws -> RemoteProfile {
        updatedProfileDisplayName = displayName
        updatedProfilePhotoAssetID = profilePhotoAssetID
        profileEvents.append("linked:\(profilePhotoAssetID?.uuidString ?? "nil")")
        if updateProfileShouldFail {
            throw AuthServiceError.noActiveSession
        }
        profile = RemoteProfile(
            userID: profile.userID,
            displayName: displayName,
            timeZoneID: profile.timeZoneID,
            timeZoneUpdatedAt: profile.timeZoneUpdatedAt,
            onboardingCompletedAt: profile.onboardingCompletedAt,
            profilePhotoAssetID: profilePhotoAssetID,
            providerProfilePhotoAssetID: profile.providerProfilePhotoAssetID,
            providerProfilePhotoSource: profile.providerProfilePhotoSource
        )
        if profileUpdateFailsAfterCommit {
            throw URLError(.networkConnectionLost)
        }
        return profile
    }

    func updateProviderProfilePhoto(
        profilePhotoAssetID: UUID,
        source: String
    ) async throws -> RemoteProfile {
        providerLinkedAssetID = profilePhotoAssetID
        profileEvents.append("provider-linked:\(profilePhotoAssetID.uuidString)")
        if updateProfileShouldFail {
            throw AuthServiceError.noActiveSession
        }
        profile = RemoteProfile(
            userID: profile.userID,
            displayName: profile.displayName,
            timeZoneID: profile.timeZoneID,
            timeZoneUpdatedAt: profile.timeZoneUpdatedAt,
            onboardingCompletedAt: profile.onboardingCompletedAt,
            profilePhotoAssetID: profile.profilePhotoAssetID,
            providerProfilePhotoAssetID: profilePhotoAssetID,
            providerProfilePhotoSource: source
        )
        return profile
    }

    func requestAccountDeletion(
        appleAuthorizationCode: String?
    ) async throws -> AccountDeletionOutcome {
        requestAccountDeletionCallCount += 1
        accountDeletionAppleCode = appleAuthorizationCode
        return accountDeletionOutcome
    }

    func signOut() async throws {
        signOutCallCount += 1
    }
}
// swiftlint:enable async_without_await

actor FakeProfilePhotoImageCache: ProfilePhotoImageCaching {
    private var storedData: [UUID: Data] = [:]
    private(set) var storedMediaAssetIDs: [UUID] = []
    private(set) var removeAllCallCount = 0

    func profilePhotoData(for mediaAssetID: UUID) -> Data? {
        storedData[mediaAssetID]
    }

    func storeProfilePhotoData(_ data: Data, for mediaAssetID: UUID) throws {
        storedData[mediaAssetID] = data
        storedMediaAssetIDs.append(mediaAssetID)
    }

    func removeProfilePhotoData(for mediaAssetID: UUID) throws {
        storedData[mediaAssetID] = nil
    }

    func removeAllProfilePhotoData() throws {
        removeAllCallCount += 1
        storedData.removeAll()
    }
}

actor FakeAuthSessionCache: AuthSessionCaching {
    private(set) var currentSession: AuthSession?
    private var accountID: String?

    init(session: AuthSession? = nil, accountID: String? = nil) {
        currentSession = session
        self.accountID = accountID
    }

    func load(accountID: String) -> AuthSession? {
        guard self.accountID == accountID else {
            return nil
        }
        return currentSession
    }

    func save(_ session: AuthSession, accountID: String) {
        currentSession = session
        self.accountID = accountID
    }

    func clear() {
        currentSession = nil
        accountID = nil
    }
}

actor FakeProviderAvatarImageLoader: ProviderAvatarImageLoading {
    private let data: Data?
    private(set) var requestedURLs: [URL] = []

    init(data: Data?) {
        self.data = data
    }

    func imageData(from url: URL) -> Data? {
        requestedURLs.append(url)
        return data
    }
}

actor FakeProfilePhotoImageInvalidator: ProfilePhotoImageInvalidating {
    private(set) var invalidatedMediaAssetIDs: [UUID] = []

    func invalidate(mediaAssetID: UUID) {
        invalidatedMediaAssetIDs.append(mediaAssetID)
    }
}

extension RemoteAuthSession {
    static func test(
        provider: AuthProvider,
        accountID: String = "clerk-user",
        displayName: String? = "Alex",
        providerAvatarURL: URL? = nil
    ) -> RemoteAuthSession {
        RemoteAuthSession(
            accountID: accountID,
            provider: provider,
            displayName: displayName,
            providerAvatarURL: providerAvatarURL
        )
    }
}

extension RemoteProfile {
    static func test(
        userID: String = "user-id",
        displayName: String? = "Alex",
        timeZoneID: String? = "Europe/Oslo",
        timeZoneUpdatedAt: Date? = Date(),
        onboardingCompletedAt: Date?,
        profilePhotoAssetID: UUID? = nil,
        providerProfilePhotoAssetID: UUID? = nil,
        providerProfilePhotoSource: String? = nil
    ) -> RemoteProfile {
        RemoteProfile(
            userID: userID,
            displayName: displayName,
            timeZoneID: timeZoneID,
            timeZoneUpdatedAt: timeZoneUpdatedAt,
            onboardingCompletedAt: onboardingCompletedAt,
            profilePhotoAssetID: profilePhotoAssetID,
            providerProfilePhotoAssetID: providerProfilePhotoAssetID,
            providerProfilePhotoSource: providerProfilePhotoSource
        )
    }
}

extension ClerkAuthServiceTests {
    static let avatarURL = URL(string: "https://lh3.googleusercontent.com/avatar")

    static func makeJPEGData() -> Data {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 24, height: 24))
        let image = renderer.image { context in
            UIColor.systemPink.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 24, height: 24))
        }

        return image.jpegData(compressionQuality: 1) ?? Data()
    }
}
