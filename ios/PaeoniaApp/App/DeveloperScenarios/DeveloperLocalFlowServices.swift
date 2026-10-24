#if DEBUG
  import Foundation

  actor DeveloperLocalFlowStore {
    private var session: AuthSession?
    private var isEntitled: Bool
    private var isPaired: Bool
    private var acceptedInvite = false

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
      guard let displayName = AuthDisplayNamePolicy.validatedName(from: displayName) else {
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
      guard let displayName = AuthDisplayNamePolicy.validatedName(from: displayName) else {
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
      acceptedInvite = false
    }

    func grantEntitlement() { isEntitled = true }

    func acceptInvite() {
      isEntitled = true
      isPaired = true
      acceptedInvite = true
    }

    func leaveRelationship() {
      isPaired = false
      acceptedInvite = false
    }

    func resolveAccess(hasPendingInvite: Bool) -> AccessRouteResolution {
      if hasPendingInvite, isEntitled, !isPaired {
        isPaired = true
        acceptedInvite = true
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

    /// The simulated purchase stands in for an App Store subscription, so the
    /// screens that depend on one (leaving, managing it) behave as they would.
    private var userEntitlement: RemoteUserEntitlement? {
      guard isEntitled else { return nil }
      return RemoteUserEntitlement(
        userID: DeveloperScenarioFixture.currentUserID,
        isEntitled: true,
        source: "storekit",
        status: "active",
        productID: nil,
        billingPeriod: "monthly",
        currentPeriodEnd: DeveloperScenarioFixture.now.addingTimeInterval(30 * 86_400),
        updatedAt: DeveloperScenarioFixture.now
      )
    }

    private var coupleEntitlement: RemoteCoupleEntitlement? {
      guard isPaired, isEntitled else { return nil }
      return RemoteCoupleEntitlement(
        coupleID: DeveloperScenarioFixture.coupleID,
        isEntitled: true,
        coveringUserID: DeveloperScenarioFixture.currentUserID,
        source: "storekit",
        status: "active",
        productID: nil,
        billingPeriod: "monthly",
        currentPeriodEnd: DeveloperScenarioFixture.now.addingTimeInterval(30 * 86_400),
        updatedAt: DeveloperScenarioFixture.now
      )
    }

    private var relationship: RemoteRelationshipState? {
      guard isPaired else { return nil }
      return RemoteRelationshipState(
        coupleID: DeveloperScenarioFixture.coupleID,
        pairID: DeveloperLocalFlowIDs.pairID,
        relationshipStatus: .active,
        memberStatus: .active,
        acceptedInvite: acceptedInvite,
        partnerUserID: DeveloperScenarioFixture.partnerUserID,
        partnerAccountName: "Robin",
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

    func restoreSession() async throws -> RestoredSession? {
      await store.restoredSession().map { RestoredSession(session: $0, access: nil) }
    }
    func signInWithApple(_: AppleSignInCredential) async throws -> AuthSession {
      await store.signIn(provider: .apple)
    }
    func signInWithGoogle() async throws -> AuthSession {
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
        givenName: "Alex"
      )
    }
  }

  @MainActor
  final class DeveloperLocalFlowCelebrationStore: PairingCelebrationStoring {
    private var seenPairIDs = Set<UUID>()

    /// The paired local flow starts in the tabs, past the celebration and the first day.
    init(startsPastFirstDay: Bool = false) {
      guard startsPastFirstDay else { return }
      seenPairIDs.insert(DeveloperLocalFlowIDs.pairID)
      progressByPairID[DeveloperLocalFlowIDs.pairID] = PostPairingProgress(isFinished: true)
    }

    func hasSeenCelebration(forPairID pairID: UUID) -> Bool { seenPairIDs.contains(pairID) }
    func markCelebrationSeen(forPairID pairID: UUID) { seenPairIDs.insert(pairID) }
    private var progressByPairID: [UUID: PostPairingProgress] = [:]
    func postPairingProgress(forPairID pairID: UUID) -> PostPairingProgress? { progressByPairID[pairID] }
    func savePostPairingProgress(_ progress: PostPairingProgress, forPairID pairID: UUID) {
      progressByPairID[pairID] = progress
    }
  }

  nonisolated struct DeveloperLocalFlowPrimerStore: PushPermissionPrimerPersisting {
    func progress() -> PushPermissionPrimerProgress { .finished }
    func markDeclinedFirstAsk(at _: Date) {}
    func markFinished() {}
  }

  nonisolated struct DeveloperLocalFlowLocationPrimerStore: LocationSharingPrimerPersisting {
    func hasResponded(ownerUserID _: UUID, coupleID _: UUID) -> Bool { true }
    func markResponded(ownerUserID _: UUID, coupleID _: UUID) {}
  }

  actor DeveloperLocalFlowPartnerAvatarSharing: PartnerAvatarSharing {
    func cachePartnerAvatar(assetID _: UUID?) async -> Bool { true }
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
