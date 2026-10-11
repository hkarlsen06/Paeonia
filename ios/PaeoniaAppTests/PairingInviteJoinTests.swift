import Foundation
import Testing
@testable import PaeoniaApp

@MainActor
struct PairingInviteJoinTests {
    private let userID = "11111111-1111-1111-1111-111111111111"
    private let partnerCode = "02BCDE"

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

    @Test func createInviteIsIgnoredWhileANewCodeIsBeingMade() async throws {
        let gate = JoinTestGate()
        let service = JoinTestPairingService(rotateGate: gate)
        let viewModel = makeViewModel(service: service, store: JoinTestInviteStore(initialInvite: makeInvite()))
        await viewModel.loadInviteIfNeeded()

        let rotation = Task { await viewModel.revokeAndCreateNewInvite() }
        await gate.waitUntilWaiting()
        await viewModel.createInvite()
        await gate.open()
        _ = await rotation.value

        #expect(await service.createCallCount == 0)
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

    // MARK: - Joining a partner's code

    @Test func previewThenAcceptJoinsThePreviewedCodeWithoutAStartDate() async throws {
        let preview = makePreview()
        let service = JoinTestPairingService(preview: preview)
        let viewModel = await makeLoadedViewModel(service: service)

        let didPreview = await viewModel.previewJoin(codeInput: " 02-bcde ")

        #expect(didPreview)
        #expect(viewModel.joinPreview == preview)
        #expect(viewModel.error == nil)
        #expect(await service.previewedCodes == [partnerCode])

        let didJoin = await viewModel.acceptPreviewedJoin()

        #expect(didJoin)
        #expect(viewModel.joinPreview == nil)
        #expect(!viewModel.isJoining)
        let accepted = await service.acceptedJoins
        #expect(accepted.count == 1)
        #expect(accepted.first?.code == partnerCode)
        #expect(accepted.first?.startedOn == nil)
    }

    @Test func acceptWithoutAPreviewDoesNothing() async throws {
        let service = JoinTestPairingService(preview: makePreview())
        let viewModel = await makeLoadedViewModel(service: service)

        let didJoin = await viewModel.acceptPreviewedJoin()

        #expect(!didJoin)
        #expect(viewModel.error == nil)
        #expect(await service.acceptedJoins.isEmpty)
    }

    @Test func aSecondPreviewWhileOneIsPendingIsIgnored() async throws {
        let gate = JoinTestGate()
        let service = JoinTestPairingService(preview: makePreview(), previewGate: gate)
        let viewModel = await makeLoadedViewModel(service: service)

        let first = Task { await viewModel.previewJoin(codeInput: partnerCode) }
        await gate.waitUntilWaiting()
        #expect(viewModel.isJoining)

        let secondPreview = await viewModel.previewJoin(codeInput: "03CDEF")
        let accepted = await viewModel.acceptPreviewedJoin()
        await gate.open()
        let firstResult = await first.value

        #expect(!secondPreview)
        #expect(!accepted)
        #expect(firstResult)
        #expect(await service.previewedCodes == [partnerCode])
        #expect(await service.acceptedJoins.isEmpty)
    }

    @Test func previewDoesNothingUntilTheOwnCodeIsShowing() async throws {
        let service = JoinTestPairingService(preview: makePreview())
        let viewModel = makeViewModel(service: service, store: JoinTestInviteStore())

        let didPreview = await viewModel.previewJoin(codeInput: partnerCode)

        #expect(!didPreview)
        #expect(viewModel.error == nil)
        #expect(await service.previewedCodes.isEmpty)
    }

    @Test func aCodeThatIsNotFoundSetsTheNotFoundError() async throws {
        let service = JoinTestPairingService(preview: nil)
        let viewModel = await makeLoadedViewModel(service: service)

        let didPreview = await viewModel.previewJoin(codeInput: partnerCode)

        #expect(!didPreview)
        #expect(viewModel.error == .joinNotFound)
        #expect(viewModel.lastJoinError == .joinNotFound)
        #expect(viewModel.lastJoinError?.isFinalJoinFailure == true)
        #expect(viewModel.joinPreview == nil)
        #expect(viewModel.invite != nil)
    }

    @Test func aMalformedCodeSetsTheInvalidErrorWithoutCallingTheService() async throws {
        let service = JoinTestPairingService(preview: makePreview())
        let viewModel = await makeLoadedViewModel(service: service)

        let didPreview = await viewModel.previewJoin(codeInput: "abc")

        #expect(!didPreview)
        #expect(viewModel.error == .joinInvalid)
        #expect(viewModel.lastJoinError?.isFinalJoinFailure == true)
        #expect(await service.previewedCodes.isEmpty)
    }

    @Test func theUsersOwnCodeIsRejectedBeforeAskingTheServer() async throws {
        let service = JoinTestPairingService(preview: makePreview())
        let viewModel = await makeLoadedViewModel(service: service)

        let didPreview = await viewModel.previewJoin(codeInput: makeInvite().code.lowercased())

        #expect(!didPreview)
        #expect(viewModel.error == .joinOwnCode)
        #expect(await service.previewedCodes.isEmpty)
    }

    @Test func aConnectionProblemDuringPreviewKeepsTheCodeWorthRetrying() async throws {
        let service = JoinTestPairingService(previewError: URLError(.notConnectedToInternet))
        let viewModel = await makeLoadedViewModel(service: service)

        let didPreview = await viewModel.previewJoin(codeInput: partnerCode)

        #expect(!didPreview)
        #expect(viewModel.error == .joinCheckFailed)
        #expect(viewModel.lastJoinError?.isFinalJoinFailure == false)
    }

    @Test func aFailedJoinClearsThePreviewAndReportsTheError() async throws {
        let service = JoinTestPairingService(preview: makePreview(), acceptError: URLError(.timedOut))
        let viewModel = await makeLoadedViewModel(service: service)
        _ = await viewModel.previewJoin(codeInput: partnerCode)

        let didJoin = await viewModel.acceptPreviewedJoin()

        #expect(!didJoin)
        #expect(viewModel.error == .joinFailed)
        #expect(viewModel.joinPreview == nil)
        #expect(!viewModel.isJoining)
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

    private func makePreview() -> PairingInvitePreview {
        PairingInvitePreview(
            inviteID: UUID(),
            inviterUserID: UUID(),
            inviterDisplayName: "Robin",
            expiresAt: Self.now.addingTimeInterval(86_400),
            hasSafetyWarning: false
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

    private func makeLoadedViewModel(service: JoinTestPairingService) async -> PairingInviteViewModel {
        let viewModel = makeViewModel(service: service, store: JoinTestInviteStore())
        await viewModel.createInvite()
        return viewModel
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

private struct JoinTestAcceptedJoin: Equatable {
    let code: String
    let startedOn: PairingStartDate?
}

// swiftlint:disable async_without_await
private actor JoinTestPairingService: PairingServicing {
    private let createdInvite: PairingInvite
    private let rotatedInvite: PairingInvite
    private let validationError: (any Error)?
    private let preview: PairingInvitePreview?
    private let previewError: (any Error)?
    private let rotateError: (any Error)?
    private let acceptError: (any Error)?
    private let createGate: JoinTestGate?
    private let rotateGate: JoinTestGate?
    private let previewGate: JoinTestGate?

    private(set) var createCallCount = 0
    private(set) var rotateCallCount = 0
    private(set) var previewedCodes = [String]()
    private(set) var acceptedJoins = [JoinTestAcceptedJoin]()

    init(
        createdInvite: PairingInvite = JoinTestPairingService.defaultInvite,
        rotatedInvite: PairingInvite = JoinTestPairingService.defaultInvite,
        validationError: (any Error)? = nil,
        preview: PairingInvitePreview? = nil,
        previewError: (any Error)? = nil,
        rotateError: (any Error)? = nil,
        acceptError: (any Error)? = nil,
        createGate: JoinTestGate? = nil,
        rotateGate: JoinTestGate? = nil,
        previewGate: JoinTestGate? = nil
    ) {
        self.createdInvite = createdInvite
        self.rotatedInvite = rotatedInvite
        self.validationError = validationError
        self.preview = preview
        self.previewError = previewError
        self.rotateError = rotateError
        self.acceptError = acceptError
        self.createGate = createGate
        self.rotateGate = rotateGate
        self.previewGate = previewGate
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
        previewedCodes.append(codeInput)
        await previewGate?.wait()
        if let previewError {
            throw previewError
        }

        return preview
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
        acceptedJoins.append(JoinTestAcceptedJoin(code: codeInput, startedOn: startedOn))
        if let acceptError {
            throw acceptError
        }

        return PairingAcceptedRelationship(coupleID: UUID())
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
