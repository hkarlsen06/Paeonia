#if DEBUG
  import Foundation

  /// Pairing for the pairing and join scenarios, answered locally by `mode`.
  actor DeveloperScenarioPairingService: PairingServicing, RelationshipRestoreAnswering {
    enum Mode: Equatable { case ready, expired, failing, safetyWarning, restorable, restoreWaiting }
    private let mode: Mode

    init(mode: Mode) { self.mode = mode }

    func createInvite(operation _: PairingClientOperation, expiresAt: Date) throws
      -> PairingInvite
    {
      guard mode != .failing else { throw PairingInviteCreationError.inviteCodeCollision }
      guard let joinURL = URL(string: "https://paeonia.no/join/LOVE26") else {
        throw URLError(.badURL)
      }
      return PairingInvite(
        id: UUID(uuidString: "55555555-5555-5555-5555-555555555555") ?? UUID(),
        code: "LOVE26",
        joinURL: joinURL,
        expiresAt: expiresAt
      )
    }

    func validateInvite(_ invite: PairingInvite) throws -> PairingInviteValidation {
      PairingInviteValidation(
        inviteID: invite.id,
        status: mode == .expired ? .expired : .pending,
        expiresAt: invite.expiresAt
      )
    }

    func previewInvite(codeInput _: String) throws -> PairingInvitePreview? {
      guard mode != .failing else { throw URLError(.notConnectedToInternet) }
      guard mode != .expired else { return nil }
      return PairingInvitePreview(
        inviteID: UUID(uuidString: "55555555-5555-5555-5555-555555555555") ?? UUID(),
        inviterUserID: DeveloperScenarioFixture.partnerUserID,
        inviterDisplayName: "Robin",
        expiresAt: DeveloperScenarioFixture.now.addingTimeInterval(86_400),
        hasSafetyWarning: mode == .safetyWarning,
        canRestore: mode == .restorable || mode == .restoreWaiting,
        restoreRequested: mode == .restoreWaiting
      )
    }
    func rotateInvite(
      currentInvite _: PairingInvite, operation: PairingClientOperation, expiresAt: Date
    ) throws -> PairingInvite {
      try createInvite(operation: operation, expiresAt: expiresAt)
    }
    func acceptInvite(
      codeInput _: String, operation _: PairingClientOperation, startedOn _: PairingStartDate?, restore: Bool
    ) throws -> PairingJoinResult {
      restore ? .waitingForPartner : .paired(coupleID: DeveloperScenarioFixture.coupleID)
    }
    func leaveRelationship(operation _: PairingClientOperation) throws -> Bool { true }
    func answerRestore(
      inviteID _: UUID, restore: Bool, operation _: PairingClientOperation
    ) throws -> RelationshipRestoreAnswer {
      RelationshipRestoreAnswer(coupleID: DeveloperScenarioFixture.coupleID, restored: restore)
    }
  }
#endif
