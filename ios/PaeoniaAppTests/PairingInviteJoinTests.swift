import Foundation
import Testing
@testable import PaeoniaApp

@MainActor
struct PairingInviteJoinTests {
    private let userID = "11111111-1111-1111-1111-111111111111"

    // MARK: - Creating the invite

    @Test func createInviteIsNotReenteredWhileTheFirstCallIsPending() async throws {
        let gate = JoinTestGate()
        let service = JoinTestPairingService(createGate: gate)
        let viewModel = makeViewModel(service: service, store: JoinTestInviteStore())

        let first = Task { await viewModel.createInvite() }
        await gate.waitUntilWaiting()
        #expect(viewModel.isLoading)

        await viewModel.createInvite()
        await gate.open()
        await first.value

        #expect(await service.createCallCount == 1)
        #expect(viewModel.invite == makeInvite())
    }

    // MARK: - Offline launch

    @Test func cachedInviteThatHasNotExpiredStaysVisibleWhenTheCheckFailsOffline() async throws {
        let cached = makeInvite(expiresAt: Self.now.addingTimeInterval(3_600))
        let service = JoinTestPairingService(validationError: URLError(.notConnectedToInternet))
        let viewModel = makeViewModel(service: service, store: JoinTestInviteStore(initialInvite: cached))

        await viewModel.loadInviteIfNeeded()

        #expect(viewModel.invite == cached)
        #expect(viewModel.error == nil)
        #expect(viewModel.isPresentationReady)
        #expect(await service.createCallCount == 0)
    }

    @Test func expiredCachedInviteShowsTheErrorWhenTheCheckFailsOffline() async throws {
        let cached = makeInvite(expiresAt: Self.now.addingTimeInterval(-60))
        let service = JoinTestPairingService(validationError: URLError(.notConnectedToInternet))
        let viewModel = makeViewModel(service: service, store: JoinTestInviteStore(initialInvite: cached))

        await viewModel.loadInviteIfNeeded()

        #expect(viewModel.invite == nil)
        #expect(viewModel.error == .createFailed)
        #expect(viewModel.isPresentationReady)
    }

    // MARK: - Making a new code

    @Test func failedRotationReportsAnErrorAndKeepsTheCurrentInvite() async throws {
        let current = makeInvite()
        let service = JoinTestPairingService(rotateError: URLError(.timedOut))
        let store = JoinTestInviteStore(initialInvite: current)
        let viewModel = makeViewModel(service: service, store: store)
        await viewModel.loadInviteIfNeeded()

        let didReplace = await viewModel.revokeAndCreateNewInvite()

        #expect(!didReplace)
        #expect(viewModel.invite == current)
        #expect(viewModel.error == .replaceFailed)
        #expect(viewModel.isPresentationReady)
        #expect(!store.didClearInvite)

        viewModel.clearError()
        #expect(viewModel.error == nil)
        #expect(viewModel.invite == current)
    }

    @Test func expiredInviteIsReplacedWithoutAskingAndAFreshOneIsLeftAlone() async throws {
        let expired = makeInvite(expiresAt: Self.now.addingTimeInterval(-60))
        let replacement = makeInvite(
            id: "33333333-3333-3333-3333-333333333333",
            code: "02BCDE",
            expiresAt: Self.now.addingTimeInterval(86_400)
        )
        let service = JoinTestPairingService(rotatedInvite: replacement)
        let viewModel = makeViewModel(service: service, store: JoinTestInviteStore(initialInvite: expired))
        await viewModel.loadInviteIfNeeded()
        #expect(viewModel.invite == expired)

        #expect(await viewModel.replaceInviteIfExpired())
        #expect(viewModel.invite == replacement)

        #expect(await viewModel.replaceInviteIfExpired())
        #expect(await service.rotateCallCount == 1)
    }

    // MARK: - Helpers

    private nonisolated static let now = Date(timeIntervalSince1970: 1_000_000)

    private func makeInvite(
        id: String = "22222222-2222-2222-2222-222222222222",
        code: String = "01ABCD",
        expiresAt: Date = PairingInviteJoinTests.now.addingTimeInterval(86_400)
    ) -> PairingInvite {
        PairingInvite(
            id: UUID(uuidString: id) ?? UUID(),
            code: code,
            joinURL: URL(string: "https://paeonia.no/join/\(code)") ?? URL(fileURLWithPath: "/"),
            expiresAt: expiresAt
        )
    }

    private func makeViewModel(
        service: JoinTestPairingService,
        store: JoinTestInviteStore
    ) -> PairingInviteViewModel {
        PairingInviteViewModel(
            userID: userID,
            pairingService: service,
            operationProvider: JoinTestOperationProvider(),
            inviteStore: store,
            now: { Self.now }
        )
    }
}

// MARK: - Test doubles

private actor JoinTestGate {
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

// swiftlint:disable async_without_await
private actor JoinTestPairingService: PairingServicing {
    private let createdInvite: PairingInvite
    private let rotatedInvite: PairingInvite
    private let validationError: (any Error)?
    private let rotateError: (any Error)?
    private let createGate: JoinTestGate?
    private let rotateGate: JoinTestGate?

    private(set) var createCallCount = 0
    private(set) var rotateCallCount = 0

    init(
        createdInvite: PairingInvite = JoinTestPairingService.defaultInvite,
        rotatedInvite: PairingInvite = JoinTestPairingService.defaultInvite,
        validationError: (any Error)? = nil,
        rotateError: (any Error)? = nil,
        createGate: JoinTestGate? = nil,
        rotateGate: JoinTestGate? = nil
    ) {
        self.createdInvite = createdInvite
        self.rotatedInvite = rotatedInvite
        self.validationError = validationError
        self.rotateError = rotateError
        self.createGate = createGate
        self.rotateGate = rotateGate
    }

    static let defaultInvite = PairingInvite(
        id: UUID(uuidString: "22222222-2222-2222-2222-222222222222") ?? UUID(),
        code: "01ABCD",
        joinURL: URL(string: "https://paeonia.no/join/01ABCD") ?? URL(fileURLWithPath: "/"),
        expiresAt: Date(timeIntervalSince1970: 1_000_000).addingTimeInterval(86_400)
    )

    func createInvite(
        operation: PairingClientOperation,
        expiresAt: Date
    ) async throws -> PairingInvite {
        createCallCount += 1
        await createGate?.wait()
        return createdInvite
    }

    func validateInvite(_ invite: PairingInvite) async throws -> PairingInviteValidation {
        if let validationError {
            throw validationError
        }

        return PairingInviteValidation(
            inviteID: invite.id,
            status: .pending,
            expiresAt: invite.expiresAt
        )
    }

    func previewInvite(codeInput: String) async throws -> PairingInvitePreview? {
        nil
    }

    func rotateInvite(
        currentInvite: PairingInvite,
        operation: PairingClientOperation,
        expiresAt: Date
    ) async throws -> PairingInvite {
        rotateCallCount += 1
        await rotateGate?.wait()
        if let rotateError {
            throw rotateError
        }

        return rotatedInvite
    }

    func acceptInvite(
        codeInput: String,
        operation: PairingClientOperation,
        startedOn: PairingStartDate?
    ) async throws -> PairingAcceptedRelationship {
        PairingAcceptedRelationship(coupleID: UUID())
    }

    func revokeInvite(id: UUID) async throws -> Bool {
        true
    }

    func leaveRelationship(operation: PairingClientOperation) async throws -> Bool {
        true
    }
}
// swiftlint:enable async_without_await

@MainActor
private final class JoinTestOperationProvider: PairingClientOperationProviding {
    func makeOperation() -> PairingClientOperation {
        PairingClientOperation(clientID: UUID(), clientSequence: 1)
    }
}

@MainActor
private final class JoinTestInviteStore: PairingInviteStoring {
    private let initialInvite: PairingInvite?
    private(set) var savedInvite: PairingInvite?
    private(set) var didClearInvite = false

    init(initialInvite: PairingInvite? = nil) {
        self.initialInvite = initialInvite
    }

    func loadInvite(for userID: String) -> PairingInvite? {
        initialInvite
    }

    func saveInvite(_ invite: PairingInvite, for userID: String) {
        savedInvite = invite
    }

    func clearInvite(for userID: String) {
        didClearInvite = true
    }
}
