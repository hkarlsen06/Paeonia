#if DEBUG
  import Foundation

  actor DeveloperLocalFlowStore {
    private var session: AuthSession?
    private var isEntitled: Bool
    private var isPaired: Bool

    init(seed: DeveloperLocalFlowSeed) {
      switch seed {
      case .fresh:
        session = nil
        isEntitled = false
        isPaired = false
      case .onboarding:
        session = Self.session(provider: .apple, complete: false)
        isEntitled = false
        isPaired = false
      case .paywall:
        session = Self.session(provider: .apple, complete: true)
        isEntitled = false
        isPaired = false
      case .pairing:
        session = Self.session(provider: .apple, complete: true)
        isEntitled = true
        isPaired = false
      case .paired:
        session = Self.session(provider: .apple, complete: true)
        isEntitled = true
        isPaired = true
      }
    }

    func restoredSession() -> AuthSession? { session }

    func signIn(provider: AuthProvider) -> AuthSession {
      let newSession = Self.session(provider: provider, complete: false)
      session = newSession
      return newSession
    }

    func completeOnboarding(displayName: String, timeZoneID: String) throws -> AuthSession {
      guard let session else { throw AuthServiceError.noActiveSession }
      guard let displayName = AuthDisplayNamePolicy.validatedSingleName(from: displayName) else {
        throw AuthServiceError.invalidDisplayName
      }
      let completed = session.completingOnboarding(
        displayName: displayName,
        timeZoneID: timeZoneID
      )
      self.session = completed
      return completed
    }

    func updateProfile(displayName: String) throws -> AuthSession {
      guard let session else { throw AuthServiceError.noActiveSession }
      guard let displayName = AuthDisplayNamePolicy.validatedSingleName(from: displayName) else {
        throw AuthServiceError.invalidDisplayName
      }
      let updated = AuthSession(
        id: session.id,
        provider: session.provider,
        displayName: displayName,
        timeZoneID: session.timeZoneID,
        profilePhotoAssetID: session.profilePhotoAssetID,
        profileStatus: session.profileStatus,
        customProfilePhotoAssetID: session.customProfilePhotoAssetID,
        providerProfilePhotoAssetID: session.providerProfilePhotoAssetID
      )
      self.session = updated
      return updated
    }

    func signOut() { session = nil }

    func deleteAccount() {
      session = nil
      isEntitled = false
      isPaired = false
    }

    func grantEntitlement() { isEntitled = true }

    func acceptInvite() {
      isEntitled = true
      isPaired = true
    }

    func leaveRelationship() { isPaired = false }

    func resolveAccess(hasPendingInvite: Bool) -> AccessRouteResolution {
      if hasPendingInvite, isEntitled, !isPaired {
        isPaired = true
      }

      let snapshot = AccessRouteSnapshot(
        userEntitlement: userEntitlement,
        coupleEntitlement: coupleEntitlement,
        relationshipState: relationship,
        hasPendingInvite: hasPendingInvite
      )
      return AccessRouteResolution(
        route: AccessRouteResolver().route(for: snapshot),
        snapshot: snapshot
      )
    }

    private var userEntitlement: SupabaseUserEntitlement? {
      guard isEntitled else { return nil }
      return SupabaseUserEntitlement(
        userID: DeveloperScenarioFixture.currentUserID,
        isEntitled: true,
        source: "developer_local_flow",
        status: "active",
        productID: nil,
        currentPeriodEnd: DeveloperScenarioFixture.now.addingTimeInterval(30 * 86_400),
        updatedAt: DeveloperScenarioFixture.now
      )
    }

    private var coupleEntitlement: SupabaseCoupleEntitlement? {
      guard isPaired, isEntitled else { return nil }
      return SupabaseCoupleEntitlement(
        coupleID: DeveloperScenarioFixture.coupleID,
        isEntitled: true,
        coveringUserID: DeveloperScenarioFixture.currentUserID,
        source: "developer_local_flow",
        status: "active",
        productID: nil,
        currentPeriodEnd: DeveloperScenarioFixture.now.addingTimeInterval(30 * 86_400),
        updatedAt: DeveloperScenarioFixture.now
      )
    }

    private var relationship: SupabaseRelationshipState? {
      guard isPaired else { return nil }
      return SupabaseRelationshipState(
        coupleID: DeveloperScenarioFixture.coupleID,
        pairID: DeveloperLocalFlowIDs.pairID,
        relationshipStatus: .active,
        memberStatus: .active,
        partnerUserID: DeveloperScenarioFixture.partnerUserID,
        partnerDisplayName: "Robin",
        partnerProfilePhotoAssetID: nil,
        startedOn: "2025-09-14",
        endedAt: nil,
        deleteAfter: nil,
        endedNoticeSeenAt: nil
      )
    }

    private nonisolated static func session(
      provider: AuthProvider,
      complete: Bool
    ) -> AuthSession {
      AuthSession(
        id: DeveloperScenarioFixture.currentUserID.uuidString,
        provider: provider,
        displayName: complete ? "Alex" : nil,
        timeZoneID: complete ? "Europe/Oslo" : nil,
        profilePhotoAssetID: nil,
        profileStatus: complete ? .complete : .needsOnboarding
      )
    }
  }

  private nonisolated enum DeveloperLocalFlowIDs {
    static let pairID = UUID(uuidString: "66666666-6666-6666-6666-666666666666") ?? UUID()
  }

  // Protocol doubles intentionally keep async requirements even when a local
  // implementation can answer immediately.
  // swiftlint:disable async_without_await

  actor DeveloperLocalFlowAuthService: AuthServicing {
    let store: DeveloperLocalFlowStore

    init(store: DeveloperLocalFlowStore) { self.store = store }

    func restoreSession() async throws -> AuthSession? { await store.restoredSession() }
    func signInWithApple(_: AppleSignInCredential) async throws -> AuthSession {
      await store.signIn(provider: .apple)
    }
    func signInWithGoogle(_: GoogleSignInCredential) async throws -> AuthSession {
      await store.signIn(provider: .google)
    }
    func signInForDevelopment() async throws -> AuthSession {
      await store.signIn(provider: .development)
    }
    func completeOnboarding(
      displayName: String,
      timeZoneID: String,
      profilePhotoData _: Data?
    ) async throws -> AuthSession {
      try await store.completeOnboarding(displayName: displayName, timeZoneID: timeZoneID)
    }
    func updateProfile(
      displayName: String,
      profilePhotoUpdate _: AuthProfilePhotoUpdate
    ) async throws -> AuthSession {
      try await store.updateProfile(displayName: displayName)
    }
    func signOut() async throws { await store.signOut() }
    func requestAccountDeletion(appleAuthorizationCode _: String?) async throws
      -> AccountDeletionOutcome
    {
      await store.deleteAccount()
      return .completed
    }
  }

  actor DeveloperLocalFlowAccessService: AccessRouteServicing {
    let store: DeveloperLocalFlowStore
    init(store: DeveloperLocalFlowStore) { self.store = store }
    func resolveAccess(hasPendingInvite: Bool) async throws -> AccessRouteResolution {
      await store.resolveAccess(hasPendingInvite: hasPendingInvite)
    }
    func markRelationshipEndedNoticeSeen(coupleID _: UUID) async throws {}
  }

  actor DeveloperLocalFlowPairingService: PairingServicing {
    let store: DeveloperLocalFlowStore
    init(store: DeveloperLocalFlowStore) { self.store = store }

    func createInvite(operation _: PairingClientOperation, expiresAt: Date) async throws
      -> PairingInvite
    {
      guard let joinURL = URL(string: "https://paeonia.no/join/LOVE26") else {
        throw URLError(.badURL)
      }
      return PairingInvite(
        id: DeveloperLocalFlowIDs.pairID,
        code: "LOVE26",
        joinURL: joinURL,
        expiresAt: expiresAt
      )
    }
    func validateInvite(_ invite: PairingInvite) async throws -> PairingInviteValidation {
      PairingInviteValidation(inviteID: invite.id, status: .pending, expiresAt: invite.expiresAt)
    }
    func previewInvite(codeInput _: String) async throws -> PairingInvitePreview? {
      PairingInvitePreview(
        inviteID: DeveloperLocalFlowIDs.pairID,
        inviterUserID: DeveloperScenarioFixture.partnerUserID,
        inviterDisplayName: "Robin",
        expiresAt: DeveloperScenarioFixture.now.addingTimeInterval(86_400),
        hasSafetyWarning: false
      )
    }
    func rotateInvite(
      currentInvite _: PairingInvite,
      operation: PairingClientOperation,
      expiresAt: Date
    ) async throws -> PairingInvite {
      try await createInvite(operation: operation, expiresAt: expiresAt)
    }
    func acceptInvite(
      codeInput _: String,
      operation _: PairingClientOperation,
      startedOn _: PairingStartDate?
    ) async throws -> PairingAcceptedRelationship {
      await store.acceptInvite()
      return PairingAcceptedRelationship(coupleID: DeveloperScenarioFixture.coupleID)
    }
    func revokeInvite(id _: UUID) async throws -> Bool { true }
    func leaveRelationship(operation _: PairingClientOperation) async throws -> Bool {
      await store.leaveRelationship()
      return true
    }
  }

  actor DeveloperLocalFlowSyncService: PaeoniaSyncing {
    func configure(session _: SyncSession?) {}
    func start() {}
    func requestSync(reason _: SyncRequestReason) {}
    func runOnce(reason _: SyncRequestReason) async -> SyncRunResult {
      SyncRunResult(
        status: .succeeded,
        attemptedStreamCount: 0,
        completedStreamCount: 0,
        failedStreamKey: nil,
        errorDescription: nil
      )
    }
    func stop() {}
    func resetForUserChange() async {}
    func purgeRelationshipAccess(ownerUserID _: UUID, permanently _: Bool) async
      -> LocalPrivacyPurgeResult
    { .completed }
    func retryPendingPrivacyPurges() async -> LocalPrivacyPurgeRetryResult { .completed }
  }

  @MainActor
  final class DeveloperLocalFlowAppleSignInProvider: AppleSignInProviding {
    func signIn() async throws -> AppleSignInCredential {
      AppleSignInCredential(
        idToken: "developer-apple-token",
        nonce: "developer-nonce",
        fullName: "Alex"
      )
    }
  }

  @MainActor
  final class DeveloperLocalFlowGoogleSignInProvider: GoogleSignInProviding {
    func signIn() async throws -> GoogleSignInCredential {
      GoogleSignInCredential(
        idToken: "developer-google-token",
        accessToken: "developer-access-token"
      )
    }
    func signOut() {}
  }

  @MainActor
  final class DeveloperLocalFlowCelebrationStore: PairingCelebrationStoring {
    private var seenPairIDs = Set<UUID>()
    func hasSeenCelebration(forPairID pairID: UUID) -> Bool { seenPairIDs.contains(pairID) }
    func markCelebrationSeen(forPairID pairID: UUID) { seenPairIDs.insert(pairID) }
  }

  nonisolated struct DeveloperLocalFlowPrimerStore: PushPermissionPrimerPersisting {
    func hasResponded() -> Bool { true }
    func markResponded() {}
  }

  nonisolated struct DeveloperLocalFlowLocationPrimerStore: LocationSharingPrimerPersisting {
    func hasResponded(ownerUserID _: UUID, coupleID _: UUID) -> Bool { true }
    func markResponded(ownerUserID _: UUID, coupleID _: UUID) {}
  }

  actor DeveloperLocalFlowPartnerAvatarSharing: PartnerAvatarSharing {
    func cachePartnerAvatar(assetID _: UUID?) async {}
    func clear() async {}
  }

  @MainActor
  final class DeveloperLocalFlowLocationCapture: ForegroundLocationCapturing {
    func captureCurrentLocation() async throws -> LocationPoint {
      throw ForegroundLocationCaptureError.unavailable
    }
  }

  @MainActor
  final class DeveloperLocalFlowDailyDraftStore: DailyChallengeDraftStoring {
    private var storage: [UUID: [UUID: DailyAnswerDraft]] = [:]
    func drafts(for userID: UUID) -> [UUID: DailyAnswerDraft] { storage[userID] ?? [:] }
    func setDraft(_ draft: DailyAnswerDraft, for instanceID: UUID, userID: UUID) {
      storage[userID, default: [:]][instanceID] = draft.hasContent ? draft : nil
    }
    func clearDraft(for instanceID: UUID, userID: UUID) {
      storage[userID]?[instanceID] = nil
    }
  }

  nonisolated final class DeveloperLocalFlowMediaDraftStore:
    DailyAnswerMediaDraftStoring,
    @unchecked Sendable
  {
    private let lock = NSLock()
    private var storage: [UUID: Data] = [:]
    func writeStagedMedia(_ data: Data, instanceID: UUID) throws {
      lock.withLock { storage[instanceID] = data }
    }
    func stagedMediaData(instanceID: UUID) -> Data? { lock.withLock { storage[instanceID] } }
    func removeStagedMedia(instanceID: UUID) { lock.withLock { storage[instanceID] = nil } }
    func clearAll() { lock.withLock { storage.removeAll() } }
  }

  nonisolated struct DeveloperLocalFlowSnapshotCache: DailyChallengeSnapshotCaching {
    func load(ownerUserID _: UUID) -> DailyChallengeRemoteSnapshotRow? { nil }
    func save(_: DailyChallengeRemoteSnapshotRow, ownerUserID _: UUID) {}
    func clearAll() {}
  }

  // swiftlint:enable async_without_await
#endif
