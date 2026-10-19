import Foundation
@testable import PaeoniaApp

// swiftlint:disable async_without_await

// Test doubles for `RootViewModelFlowTests`.

extension AccessRouteResolution {
    static let unpairedForFlowTest = AccessRouteResolution(
        route: .unpaired,
        snapshot: AccessRouteSnapshot(
            userEntitlement: nil,
            coupleEntitlement: nil,
            relationshipState: nil,
            hasPendingInvite: false
        )
    )

    static func pairedForFlowTest(ownerUserID: UUID) -> AccessRouteResolution {
        let snapshot = AccessSyncSnapshot.testPaired(ownerUserID: ownerUserID)
        return AccessRouteResolution(
            route: .paired,
            snapshot: AccessRouteSnapshot(
                userEntitlement: snapshot.userEntitlement,
                coupleEntitlement: snapshot.coupleEntitlement,
                relationshipState: snapshot.relationshipState,
                hasPendingInvite: false
            )
        )
    }
}

/// Returns its resolutions in order (repeating the last) and can hold one call
/// open until the test releases it.
actor ScriptedAccessRouteService: AccessRouteServicing {
    private let resolutions: [AccessRouteResolution]
    private let blockedCall: Int?
    private var callCount = 0
    private var blockedCallStarted = false
    private var startWaiters: [CheckedContinuation<Void, Never>] = []
    private var releaseContinuation: CheckedContinuation<Void, Never>?

    init(_ resolutions: [AccessRouteResolution], blockedCall: Int? = nil) {
        precondition(!resolutions.isEmpty)
        self.resolutions = resolutions
        self.blockedCall = blockedCall
    }

    func resolveAccess(hasPendingInvite _: Bool) async throws -> AccessRouteResolution {
        callCount += 1
        let call = callCount
        if call == blockedCall {
            blockedCallStarted = true
            startWaiters.forEach { $0.resume() }
            startWaiters = []
            await withCheckedContinuation { releaseContinuation = $0 }
        }
        return resolutions[min(call, resolutions.count) - 1]
    }

    func waitForBlockedCall() async {
        guard !blockedCallStarted else { return }
        await withCheckedContinuation { startWaiters.append($0) }
    }

    func release() {
        releaseContinuation?.resume()
        releaseContinuation = nil
    }

    func markRelationshipEndedNoticeSeen(coupleID _: UUID) async throws {}
}

enum FlowTestError: Error {
    case unavailable
}

actor FlowAuthService: AuthServicing {
    private var session: AuthSession?
    private let signInSession: AuthSession?
    private let gatesProfileUpdate: Bool
    private var profileUpdateStarted = false
    private var profileUpdateWaiters: [CheckedContinuation<Void, Never>] = []
    private var profileUpdateRelease: CheckedContinuation<Void, Never>?
    private(set) var deletionCodes: [String?] = []

    private let failsRestoreAfterFirst: Bool
    private var restoreCount = 0

    init(
        restoredSession: AuthSession? = nil,
        signInSession: AuthSession? = nil,
        gatesProfileUpdate: Bool = false,
        failsRestoreAfterFirst: Bool = false
    ) {
        self.session = restoredSession
        self.signInSession = signInSession
        self.gatesProfileUpdate = gatesProfileUpdate
        self.failsRestoreAfterFirst = failsRestoreAfterFirst
    }

    func restoreSession() async throws -> AuthSession? {
        restoreCount += 1
        if failsRestoreAfterFirst, restoreCount > 1 {
            throw FlowTestError.unavailable
        }
        return session
    }

    func signInWithApple(_: AppleSignInCredential) async throws -> AuthSession {
        try signIn()
    }

    func signInWithGoogle() async throws -> AuthSession {
        try signIn()
    }

    func signInForDevelopment() async throws -> AuthSession {
        try signIn()
    }

    private func signIn() throws -> AuthSession {
        guard let signInSession else {
            throw FlowTestError.unavailable
        }
        session = signInSession
        return signInSession
    }

    func completeOnboarding(
        displayName: String,
        timeZoneID: String,
        profilePhotoData _: Data?
    ) async throws -> AuthSession {
        guard let session else {
            throw AuthServiceError.noActiveSession
        }
        let completed = session.completingOnboarding(displayName: displayName, timeZoneID: timeZoneID)
        self.session = completed
        return completed
    }

    func updateProfile(
        displayName: String,
        profilePhotoUpdate _: AuthProfilePhotoUpdate
    ) async throws -> AuthSession {
        if gatesProfileUpdate {
            profileUpdateStarted = true
            profileUpdateWaiters.forEach { $0.resume() }
            profileUpdateWaiters = []
            await withCheckedContinuation { profileUpdateRelease = $0 }
        }
        guard let session else {
            throw AuthServiceError.noActiveSession
        }
        let updated = AuthSession(
            id: session.id,
            provider: session.provider,
            displayName: displayName,
            timeZoneID: session.timeZoneID,
            profilePhotoAssetID: session.profilePhotoAssetID,
            profileStatus: session.profileStatus
        )
        self.session = updated
        return updated
    }

    func waitForProfileUpdate() async {
        guard !profileUpdateStarted else { return }
        await withCheckedContinuation { profileUpdateWaiters.append($0) }
    }

    func releaseProfileUpdate() {
        profileUpdateRelease?.resume()
        profileUpdateRelease = nil
    }

    func signOut() async throws {
        session = nil
    }

    func requestAccountDeletion(appleAuthorizationCode: String?) async throws -> AccountDeletionOutcome {
        deletionCodes.append(appleAuthorizationCode)
        session = nil
        return appleAuthorizationCode == nil ? .manualAppleRevocationRequired : .completed
    }
}

@MainActor
final class StubAppleSignInProvider: AppleSignInProviding {
    private let code: String?
    private let error: (any Error)?

    init(code: String? = nil, error: (any Error)? = nil) {
        self.code = code
        self.error = error
    }

    func signIn() async throws -> AppleSignInCredential {
        if let error {
            throw error
        }
        return AppleSignInCredential(idToken: "token", nonce: "nonce", givenName: nil, authorizationCode: code)
    }
}

@MainActor
final class GatedAppleSignInProvider: AppleSignInProviding {
    private(set) var signInCount = 0
    private var sheetWaiters: [CheckedContinuation<Void, Never>] = []
    private var pending: CheckedContinuation<AppleSignInCredential, any Error>?

    func signIn() async throws -> AppleSignInCredential {
        signInCount += 1
        sheetWaiters.forEach { $0.resume() }
        sheetWaiters = []
        return try await withCheckedThrowingContinuation { pending = $0 }
    }

    func waitForSheet() async {
        guard pending == nil else { return }
        await withCheckedContinuation { sheetWaiters.append($0) }
    }

    func finish(code: String) {
        pending?.resume(
            returning: AppleSignInCredential(idToken: "token", nonce: "nonce", givenName: nil, authorizationCode: code)
        )
        pending = nil
    }
}

// swiftlint:enable async_without_await
