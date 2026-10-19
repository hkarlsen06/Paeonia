import Foundation
import Testing
@testable import PaeoniaApp

@MainActor
struct PairingJoinViewModelTests {
    private let userID = "11111111-1111-1111-1111-111111111111"
    private let partnerCode = "02BCDE"

    // MARK: - Checking a code

    @Test func checkThenAcceptJoinsTheCheckedCodeWithoutAStartDate() async throws {
        let preview = makePreview()
        let service = JoinFlowPairingService(preview: preview)
        let viewModel = makeViewModel(service: service)

        #expect(await viewModel.checkCode(" 02-bcde ", currentUserID: userID))
        #expect(viewModel.preview(for: partnerCode) == preview)
        #expect(viewModel.checkedCode == partnerCode)
        #expect(viewModel.lastError == nil)

        #expect(await viewModel.acceptCheckedCode(partnerCode))

        let accepted = await service.acceptedJoins
        #expect(accepted.count == 1)
        #expect(accepted.first?.code == partnerCode)
        #expect(accepted.first?.startedOn == nil)
        // The screen keeps showing who was joined while the app moves on.
        #expect(viewModel.preview(for: partnerCode) == preview)
    }

    @Test func theUsersOwnCodeIsRejected() async throws {
        let ownPreview = makePreview(inviterUserID: userID)
        let viewModel = makeViewModel(service: JoinFlowPairingService(preview: ownPreview))

        #expect(!(await viewModel.checkCode(partnerCode, currentUserID: userID)))

        #expect(viewModel.lastError == .ownCode)
        #expect(viewModel.preview(for: partnerCode) == nil)
    }

    @Test func aSecondCheckWhileOneIsPendingIsIgnored() async throws {
        let gate = JoinFlowGate()
        let service = JoinFlowPairingService(preview: makePreview(), previewGate: gate)
        let viewModel = makeViewModel(service: service)

        let first = Task { await viewModel.checkCode(partnerCode, currentUserID: userID) }
        await gate.waitUntilWaiting()
        #expect(viewModel.isBusy)

        let second = await viewModel.checkCode("03CDEF", currentUserID: userID)
        let accepted = await viewModel.acceptCheckedCode(partnerCode)
        await gate.open()

        #expect(!second)
        #expect(!accepted)
        #expect(await first.value)
        #expect(await service.previewedCodes == [partnerCode])
        #expect(await service.acceptedJoins.isEmpty)
    }

    // MARK: - Joining

    @Test func acceptJoinsOnlyTheCodeThatWasChecked() async throws {
        let service = JoinFlowPairingService(preview: makePreview())
        let viewModel = makeViewModel(service: service)
        _ = await viewModel.checkCode(partnerCode, currentUserID: userID)

        // A newer link brought another code that has not been checked yet.
        #expect(!(await viewModel.acceptCheckedCode("03CDEF")))

        #expect(await service.acceptedJoins.isEmpty)
    }

    /// The first accept reached the server and paired the couple, but its answer
    /// was lost. Retrying used to preview again (the used invite now looks gone)
    /// and send a new operation (the couple now exists), so it always failed.
    @Test func retryAfterLostAcceptAnswerReplaysTheSameOperation() async throws {
        let pairing = LostAnswerPairing()
        let viewModel = PairingJoinViewModel(pairingService: pairing, operationProvider: CountingOperationProvider())

        #expect(await viewModel.checkCode(partnerCode, currentUserID: userID))
        #expect(!(await viewModel.acceptCheckedCode(partnerCode)))
        #expect(viewModel.lastError == .joinFailed(.offline))

        // Going back and entering the same code again still replays the join.
        viewModel.clearCheckedCode()
        #expect(await viewModel.checkCode(partnerCode, currentUserID: userID))
        #expect(await viewModel.acceptCheckedCode(partnerCode))

        #expect(await pairing.previewCount == 1)
        let operations = await pairing.acceptOperations
        #expect(operations.count == 2)
        #expect(operations.first == operations.last)
    }

    @Test func serverRejectionStartsTheNextAcceptFresh() async throws {
        let pairing = LostAnswerPairing(firstFailure: .server(code: "53300", message: "too many invite attempts"))
        let viewModel = PairingJoinViewModel(pairingService: pairing, operationProvider: CountingOperationProvider())

        _ = await viewModel.checkCode(partnerCode, currentUserID: userID)
        _ = await viewModel.acceptCheckedCode(partnerCode)
        _ = await viewModel.acceptCheckedCode(partnerCode)

        let operations = await pairing.acceptOperations
        #expect(operations.count == 2)
        #expect(operations.first != operations.last)
    }

    @Test func anUnconfirmedJoinIsNotReplayedForAnotherUser() async throws {
        let pairing = LostAnswerPairing()
        let viewModel = PairingJoinViewModel(pairingService: pairing, operationProvider: CountingOperationProvider())
        _ = await viewModel.checkCode(partnerCode, currentUserID: userID)
        _ = await viewModel.acceptCheckedCode(partnerCode)

        viewModel.clearCheckedCode()
        _ = await viewModel.checkCode(partnerCode, currentUserID: "33333333-3333-3333-3333-333333333333")

        #expect(await pairing.previewCount == 2)
    }

    // MARK: - Helpers

    private func makePreview(inviterUserID: String = "22222222-2222-2222-2222-222222222222") -> PairingInvitePreview {
        PairingInvitePreview(
            inviteID: UUID(),
            inviterUserID: UUID(uuidString: inviterUserID) ?? UUID(),
            inviterDisplayName: "Robin",
            expiresAt: Date(timeIntervalSince1970: 1_000_000),
            hasSafetyWarning: false,
            inviterPhotoURL: URL(string: "https://actions.paeonia.no/media?token=abc")
        )
    }

    private func makeViewModel(service: JoinFlowPairingService) -> PairingJoinViewModel {
        PairingJoinViewModel(pairingService: service, operationProvider: CountingOperationProvider())
    }
}

// MARK: - Test doubles

private actor JoinFlowGate {
    private var waiter: CheckedContinuation<Void, Never>?
    private var startWatcher: CheckedContinuation<Void, Never>?

    func wait() async {
        await withCheckedContinuation { continuation in
            waiter = continuation
            startWatcher?.resume()
            startWatcher = nil
        }
    }

    func waitUntilWaiting() async {
        if waiter != nil {
            return
        }

        await withCheckedContinuation { continuation in
            startWatcher = continuation
        }
    }

    func open() {
        waiter?.resume()
        waiter = nil
    }
}

private struct JoinFlowAcceptedJoin: Equatable {
    let code: String
    let startedOn: PairingStartDate?
}

// Fakes implement only what joining uses, so unused requirements trap and sync
// bodies need no await.
// swiftlint:disable async_without_await unavailable_function
private actor JoinFlowPairingService: PairingServicing {
    private let preview: PairingInvitePreview?
    private let previewGate: JoinFlowGate?

    private(set) var previewedCodes = [String]()
    private(set) var acceptedJoins = [JoinFlowAcceptedJoin]()

    init(
        preview: PairingInvitePreview? = nil,
        previewGate: JoinFlowGate? = nil
    ) {
        self.preview = preview
        self.previewGate = previewGate
    }

    func previewInvite(codeInput: String) async throws -> PairingInvitePreview? {
        previewedCodes.append(codeInput)
        await previewGate?.wait()
        return preview
    }

    func acceptInvite(
        codeInput: String,
        operation: PairingClientOperation,
        startedOn: PairingStartDate?
    ) async throws -> PairingAcceptedRelationship {
        acceptedJoins.append(JoinFlowAcceptedJoin(code: codeInput, startedOn: startedOn))
        return PairingAcceptedRelationship(coupleID: UUID())
    }

    func createInvite(operation: PairingClientOperation, expiresAt: Date) async throws -> PairingInvite {
        fatalError("unused")
    }

    func validateInvite(_ invite: PairingInvite) async throws -> PairingInviteValidation {
        fatalError("unused")
    }

    func rotateInvite(
        currentInvite: PairingInvite,
        operation: PairingClientOperation,
        expiresAt: Date
    ) async throws -> PairingInvite {
        fatalError("unused")
    }

    func revokeInvite(id: UUID) async throws -> Bool {
        fatalError("unused")
    }

    func leaveRelationship(operation: PairingClientOperation) async throws -> Bool {
        fatalError("unused")
    }
}

/// Pairs on the first accept but loses the answer (or rejects it, when
/// `firstFailure` is a server error). Like the server, a replay of the first
/// operation returns the stored result, and any other operation fails.
private actor LostAnswerPairing: PairingServicing {
    private let firstFailure: PaeoniaConvexError?
    private var pairedOperation: PairingClientOperation?
    private(set) var previewCount = 0
    private(set) var acceptOperations = [PairingClientOperation]()

    init(firstFailure: PaeoniaConvexError? = nil) {
        self.firstFailure = firstFailure
    }

    func previewInvite(codeInput: String) async throws -> PairingInvitePreview? {
        previewCount += 1
        guard pairedOperation == nil else {
            return nil
        }
        return PairingInvitePreview(
            inviteID: UUID(),
            inviterUserID: UUID(),
            inviterDisplayName: "Robin",
            expiresAt: Date().addingTimeInterval(3_600),
            hasSafetyWarning: false
        )
    }

    func acceptInvite(
        codeInput: String,
        operation: PairingClientOperation,
        startedOn: PairingStartDate?
    ) async throws -> PairingAcceptedRelationship {
        acceptOperations.append(operation)
        if let pairedOperation {
            guard pairedOperation == operation else {
                throw PaeoniaConvexError.server(code: "22023", message: "pairing invite is not pending")
            }
            return PairingAcceptedRelationship(coupleID: UUID())
        }
        if let firstFailure, acceptOperations.count == 1 {
            throw firstFailure
        }
        pairedOperation = operation
        throw URLError(.networkConnectionLost)
    }

    func createInvite(operation: PairingClientOperation, expiresAt: Date) async throws -> PairingInvite {
        fatalError("unused")
    }

    func validateInvite(_ invite: PairingInvite) async throws -> PairingInviteValidation {
        fatalError("unused")
    }

    func rotateInvite(
        currentInvite: PairingInvite,
        operation: PairingClientOperation,
        expiresAt: Date
    ) async throws -> PairingInvite {
        fatalError("unused")
    }

    func revokeInvite(id: UUID) async throws -> Bool {
        fatalError("unused")
    }

    func leaveRelationship(operation: PairingClientOperation) async throws -> Bool {
        fatalError("unused")
    }
}

/// Hands out a new operation every time, so a reused one is easy to spot.
@MainActor
private final class CountingOperationProvider: PairingClientOperationProviding {
    private var sequence: Int64 = 0

    func makeOperation() -> PairingClientOperation {
        sequence += 1
        return SyncClientOperation(clientID: UUID(), clientSequence: sequence)
    }
}
// swiftlint:enable async_without_await unavailable_function
