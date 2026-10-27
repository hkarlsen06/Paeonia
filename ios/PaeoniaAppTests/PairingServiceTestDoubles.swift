import Foundation
@testable import PaeoniaApp

// swiftlint:disable async_without_await
actor FakePairingGateway: PairingGateway {
    private let createdInviteID: UUID
    private var createFailuresBeforeSuccess: Int
    private let preview: PairingInvitePreview?
    private let validation: PairingInviteValidation
    private let acceptedCoupleID: UUID
    private let rotatedInviteID: UUID
    private let leaveResult: Bool
    private(set) var createdInviteCode: String?
    private(set) var createdInviteCodes: [String] = []
    private(set) var createdOperation: PairingClientOperation?
    private(set) var createdExpiresAt: Date?
    private(set) var validatedInviteID: UUID?
    private(set) var validatedInviteCode: String?
    private(set) var previewedInviteCode: String?
    private(set) var rotatedCurrentInviteID: UUID?
    private(set) var rotatedInviteCode: String?
    private(set) var rotatedInviteCodes: [String] = []
    private(set) var rotatedOperation: PairingClientOperation?
    private(set) var rotatedExpiresAt: Date?
    private(set) var acceptedInviteCode: String?
    private(set) var acceptedOperation: PairingClientOperation?
    private(set) var acceptedStartedOn: PairingStartDate?
    private(set) var leftOperation: PairingClientOperation?

    init(
        createdInviteID: UUID = UUID(),
        createFailuresBeforeSuccess: Int = 0,
        preview: PairingInvitePreview? = nil,
        validation: PairingInviteValidation = PairingInviteValidation(
            inviteID: nil,
            status: .notFound,
            expiresAt: nil
        ),
        acceptedCoupleID: UUID = UUID(),
        rotatedInviteID: UUID = UUID(),
        leaveResult: Bool = true
    ) {
        self.createdInviteID = createdInviteID
        self.createFailuresBeforeSuccess = createFailuresBeforeSuccess
        self.preview = preview
        self.validation = validation
        self.acceptedCoupleID = acceptedCoupleID
        self.rotatedInviteID = rotatedInviteID
        self.leaveResult = leaveResult
    }

    func createInvite(
        inviteCode: String,
        operation: PairingClientOperation,
        expiresAt: Date
    ) async throws -> UUID {
        createdInviteCode = inviteCode
        createdInviteCodes.append(inviteCode)
        createdOperation = operation
        createdExpiresAt = expiresAt

        if createFailuresBeforeSuccess > 0 {
            createFailuresBeforeSuccess -= 1
            throw PairingInviteCreationError.inviteCodeCollision
        }

        return createdInviteID
    }

    func validateInvite(inviteID: UUID, inviteCode: String) async throws -> PairingInviteValidation {
        validatedInviteID = inviteID
        validatedInviteCode = inviteCode
        return validation
    }

    func previewInvite(inviteCode: String) async throws -> PairingInvitePreview? {
        previewedInviteCode = inviteCode
        return preview
    }

    func rotateInvite(
        currentInviteID: UUID,
        inviteCode: String,
        operation: PairingClientOperation,
        expiresAt: Date
    ) async throws -> UUID {
        rotatedCurrentInviteID = currentInviteID
        rotatedInviteCode = inviteCode
        rotatedInviteCodes.append(inviteCode)
        rotatedOperation = operation
        rotatedExpiresAt = expiresAt

        if createFailuresBeforeSuccess > 0 {
            createFailuresBeforeSuccess -= 1
            throw PairingInviteCreationError.inviteCodeCollision
        }

        return rotatedInviteID
    }

    func acceptInvite(
        inviteCode: String,
        operation: PairingClientOperation,
        startedOn: PairingStartDate?
    ) async throws -> UUID {
        acceptedInviteCode = inviteCode
        acceptedOperation = operation
        acceptedStartedOn = startedOn
        return acceptedCoupleID
    }

    func revokeInvite(id: UUID) async throws -> Bool {
        true
    }

    func leaveRelationship(operation: PairingClientOperation) async throws -> Bool {
        leftOperation = operation
        return leaveResult
    }
}
// swiftlint:enable async_without_await

final class GeneratedInviteCodeSequence: @unchecked Sendable {
    private var codes: [String]
    private var index = 0

    init(_ codes: [String]) {
        self.codes = codes
    }

    func next() -> String {
        defer { index += 1 }
        return codes[index]
    }
}

@MainActor
final class StaticPairingOperationProvider: PairingClientOperationProviding {
    private let operation: PairingClientOperation
    private(set) var makeOperationCallCount = 0

    init(
        operation: PairingClientOperation = PairingClientOperation(
            clientID: UUID(),
            clientSequence: 1
        )
    ) {
        self.operation = operation
    }

    func makeOperation() -> PairingClientOperation {
        makeOperationCallCount += 1
        return operation
    }
}

@MainActor
final class PairingInviteStoreSpy: PairingInviteStoring {
    private let initialInvite: PairingInvite?
    private(set) var savedInvite: PairingInvite?
    private(set) var didClearInvite = false

    init(initialInvite: PairingInvite?) {
        self.initialInvite = initialInvite
    }

    func loadInvite(for userID: String) -> PairingInvite? {
        return initialInvite
    }

    func saveInvite(_ invite: PairingInvite, for userID: String) {
        savedInvite = invite
    }

    func clearInvite(for userID: String) {
        didClearInvite = true
    }
}

// swiftlint:disable unavailable_function
actor CachedInviteRecoveryPairingService: PairingServicing {
    private let validation: PairingInviteValidation
    private let createdInvite: PairingInvite
    private(set) var validatedInvite: PairingInvite?

    init(validation: PairingInviteValidation, createdInvite: PairingInvite) {
        self.validation = validation
        self.createdInvite = createdInvite
    }

    func createInvite(
        operation: PairingClientOperation,
        expiresAt: Date
    ) throws -> PairingInvite {
        createdInvite
    }

    func validateInvite(_ invite: PairingInvite) throws -> PairingInviteValidation {
        validatedInvite = invite
        return validation
    }

    func previewInvite(codeInput: String) throws -> PairingInvitePreview? {
        fatalError("unused")
    }

    func rotateInvite(
        currentInvite: PairingInvite,
        operation: PairingClientOperation,
        expiresAt: Date
    ) throws -> PairingInvite {
        fatalError("unused")
    }

    func acceptInvite(
        codeInput: String,
        operation: PairingClientOperation,
        startedOn: PairingStartDate?
    ) throws -> PairingAcceptedRelationship {
        fatalError("unused")
    }

    func revokeInvite(id: UUID) throws -> Bool {
        fatalError("unused")
    }

    func leaveRelationship(operation: PairingClientOperation) throws -> Bool {
        fatalError("unused")
    }
}
// swiftlint:enable unavailable_function

actor PendingCreatePairingService: PairingServicing {
    private let invite: PairingInvite
    private var createContinuation: CheckedContinuation<PairingInvite, any Error>?
    private var createStartedContinuation: CheckedContinuation<Void, Never>?

    init(invite: PairingInvite) {
        self.invite = invite
    }

    func createInvite(
        operation: PairingClientOperation,
        expiresAt: Date
    ) async throws -> PairingInvite {
        return try await withCheckedThrowingContinuation { continuation in
            createContinuation = continuation
            createStartedContinuation?.resume()
            createStartedContinuation = nil
        }
    }

    func validateInvite(_ invite: PairingInvite) throws -> PairingInviteValidation {
        PairingInviteValidation(
            inviteID: invite.id,
            status: .pending,
            expiresAt: invite.expiresAt
        )
    }

    func waitForCreateToStart() async {
        if createContinuation != nil {
            return
        }

        await withCheckedContinuation { continuation in
            createStartedContinuation = continuation
        }
    }

    func finishCreate() {
        createContinuation?.resume(returning: invite)
        createContinuation = nil
    }

    func previewInvite(codeInput: String) async throws -> PairingInvitePreview? {
        await Task.yield()
        return nil
    }

    func rotateInvite(
        currentInvite: PairingInvite,
        operation: PairingClientOperation,
        expiresAt: Date
    ) async throws -> PairingInvite {
        return try await withCheckedThrowingContinuation { continuation in
            createContinuation = continuation
            createStartedContinuation?.resume()
            createStartedContinuation = nil
        }
    }

    func acceptInvite(
        codeInput: String,
        operation: PairingClientOperation,
        startedOn: PairingStartDate?
    ) async throws -> PairingAcceptedRelationship {
        await Task.yield()
        return PairingAcceptedRelationship(coupleID: UUID())
    }

    func revokeInvite(id: UUID) async throws -> Bool {
        await Task.yield()
        return true
    }

    func leaveRelationship(operation: PairingClientOperation) async throws -> Bool {
        await Task.yield()
        return true
    }
}
