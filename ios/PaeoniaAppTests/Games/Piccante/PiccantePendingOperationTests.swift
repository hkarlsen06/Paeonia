import Foundation
import Testing
@testable import PaeoniaApp

@MainActor
struct PiccantePendingOperationTests {
    private let state = DeveloperPiccanteFixture.state(for: .piccanteBiting)
    private let pending = InMemoryPendingSyncOperationRepository()

    private func move(_ action: PiccanteAction, version: Int? = nil) throws -> PiccanteMove {
        let game = try #require(state.game)
        return PiccanteMove(action: action, gameID: game.id, gameNumber: game.gameNumber,
                            expectedVersion: version ?? game.version, tile: 6)
    }

    @Test func clockRollbackCannotSendABiteBeforeItsHide() async throws {
        let hide = try move(.hide)
        let first = SyncClientOperation(clientID: UUID(), clientSequence: 1,
                                        localCreatedAt: Date(timeIntervalSince1970: 200))
        try await pending.enqueue(PendingSyncOperationRequest(
            ownerUserID: state.userID, operation: first, operationKind: .piccanteHide,
            idempotencyScope: "hide", requestData: try JSONEncoder().encode(hide)))
        let bite = try snapshot(.piccanteBite, move(.bite), owner: state.userID,
                                operation: SyncClientOperation(clientID: first.clientID, clientSequence: 2,
                                                               localCreatedAt: Date(timeIntervalSince1970: 100)))
        let handler = PiccantePendingOperationHandler(operationKind: .piccanteBite,
            gateway: RejectingPiccanteGateway(state: state), cache: InMemoryPiccanteCache(state: state))
        #expect(try await handler.send(bite, context: syncContext(pending)) == .retry(after: nil))
    }

    @Test func reloadOverlaysMovesInSequenceDespiteClockRollback() async throws {
        var initial = state
        initial.game?.phase = .choosing
        initial.game?.myChili = nil
        initial.game?.bites = []
        let game = try #require(initial.game)
        let environment = GamesTestEnvironment(state: nil)
        var dependencies = environment.dependencies()
        dependencies.piccanteCache = InMemoryPiccanteCache(state: initial)
        let clientID = UUID()
        for (sequence, action, time) in [(Int64(1), PiccanteAction.choose, 200.0), (2, .hide, 100.0)] {
            let payload = PiccanteMove(action: action, gameID: game.id, gameNumber: game.gameNumber,
                                      expectedVersion: game.version + Int(sequence) - 1, tile: 6, size: 3)
            try await environment.pending.enqueue(PendingSyncOperationRequest(
                ownerUserID: state.userID,
                operation: SyncClientOperation(clientID: clientID, clientSequence: sequence,
                                               localCreatedAt: Date(timeIntervalSince1970: time)),
                operationKind: action.pendingKind, idempotencyScope: action.rawValue,
                requestData: try JSONEncoder().encode(payload)))
        }
        let model = PiccanteViewModel(dependencies: dependencies)
        model.configure(participants: GameParticipants(currentUserID: state.userID,
            coupleID: state.coupleID, partnerName: "Partner"))
        await model.reload()
        #expect(model.game?.myChili == 6)
        #expect(model.game?.version == game.version + 2)
    }

    @Test func losingRematchRaceMarksThePreviousResultSeenWithoutConsumingAVersion() async throws {
        let finished = DeveloperPiccanteFixture.state(for: .piccanteResult)
        let old = try #require(finished.game)
        var server = finished
        server.game?.gameNumber += 1
        server.game?.version += 1
        server.game?.phase = .choosing
        server.game?.turnUserID = nil
        let gateway = RematchRacePiccanteGateway(state: server)
        let cache = InMemoryPiccanteCache(state: finished)
        let rematch = PiccanteMove(action: .rematch, gameID: old.id, gameNumber: old.gameNumber,
                                  expectedVersion: old.version)
        let operation = try snapshot(.piccanteRematch, rematch, owner: server.userID)
        let handler = PiccantePendingOperationHandler(operationKind: .piccanteRematch, gateway: gateway, cache: cache)
        #expect(try await handler.send(operation, context: syncContext(pending)) == .succeeded)
        let saved = await cache.document(ownerUserID: server.userID).state
        #expect(saved?.unseenResult == nil)
        #expect(saved?.game?.version == server.game?.version)
        #expect(saved?.game?.gameNumber == old.gameNumber + 1)
        #expect(await gateway.seenNumbers == [old.gameNumber])
        #expect(await cache.takeRefused(ownerUserID: server.userID).isEmpty)
    }

    @Test func refusedHideRestoresSelectionAfterResolvingAuthoritativeState() async throws {
        let state = DeveloperPiccanteFixture.state(for: .piccanteHide)
        let game = try #require(state.game)
        let cache = InMemoryPiccanteCache(state: state)
        await cache.refuse(PiccanteMove(action: .hide, gameID: game.id, gameNumber: game.gameNumber,
            expectedVersion: game.version, tile: 5, note: "A kiss"), ownerUserID: state.userID)
        var dependencies = GamesTestEnvironment(state: nil).dependencies()
        dependencies.piccanteCache = cache
        let model = PiccanteViewModel(dependencies: dependencies)
        model.configure(participants: GameParticipants(currentUserID: state.userID, coupleID: state.coupleID,
                                                       partnerName: "Robin"))
        await model.reload()
        #expect(model.selected == 5)
        #expect(model.note == "A kiss")
    }

    @Test(arguments: [PiccanteAction.bite, .rematch])
    func staleRefusalRefreshesImmediately(action: PiccanteAction) async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = PiccanteCache(directoryURL: directory)
        await cache.saveState(state, ownerUserID: state.userID)
        var server = state
        server.game?.version += 1
        server.game?.gameNumber += 1
        let handler = PiccantePendingOperationHandler(operationKind: action.pendingKind,
            gateway: RejectingPiccanteGateway(state: server), cache: cache)
        let operation = try snapshot(action.pendingKind, move(action), owner: state.userID)
        let result = try await handler.send(operation, context: syncContext(pending))
        if action == .rematch {
            #expect(result == .succeeded)
            #expect(await cache.takeRefused(ownerUserID: state.userID).isEmpty)
        } else {
            guard case .terminalFailure = result else {
                Issue.record("Expected an immediate terminal refusal")
                return
            }
            #expect(await cache.takeRefused(ownerUserID: state.userID) == [try move(action)])
        }
        #expect(await cache.document(ownerUserID: state.userID).state == server)
        #expect(await cache.document(ownerUserID: state.userID).refusals.isEmpty)
    }
}

private struct RejectingPiccanteGateway: PiccanteGateway {
    let state: RemotePiccanteState
    func loadPiccante() throws -> RemotePiccanteState { state }
    func ensurePiccante() throws -> RemotePiccanteState { state }
    func sendPiccante(_ move: PiccanteMove, operation: SyncClientOperation) throws -> RemotePiccanteState {
        if move.action == .seen { return state }
        throw PaeoniaConvexError.server(code: "40001", message: "the game has changed")
    }
    func loadPiccanteResult(number: Int) throws -> RemotePiccanteGame {
        try #require(state.game)
    }
}

private actor RematchRacePiccanteGateway {
    var state: RemotePiccanteState
    var seenNumbers: [Int] = []
    init(state: RemotePiccanteState) { self.state = state }
    func loadPiccante() -> RemotePiccanteState { state }
    func ensurePiccante() -> RemotePiccanteState { state }
    func sendPiccante(_ move: PiccanteMove, operation: SyncClientOperation) throws -> RemotePiccanteState {
        guard move.action == .seen else {
            throw PaeoniaConvexError.server(code: "40001", message: "the game has changed")
        }
        seenNumbers.append(move.gameNumber)
        if state.unseenResult?.gameNumber == move.gameNumber { state.unseenResult = nil }
        return state
    }
    func loadPiccanteResult(number: Int) throws -> RemotePiccanteGame { try #require(state.game) }
}
extension RematchRacePiccanteGateway: PiccanteGateway {}
