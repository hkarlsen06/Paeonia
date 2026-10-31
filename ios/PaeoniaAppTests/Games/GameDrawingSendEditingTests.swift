import Foundation
import PencilKit
import Testing
import UIKit
@testable import PaeoniaApp

@MainActor
struct GameDrawingSendEditingTests {
    @Test(arguments: [false, true])
    func drawAndGuessFreezesEditsUntilTheDrawingIsQueued(failsFirstSave: Bool) async throws {
        let state = GameFixture.state(
            settings: GameFixture.settings(),
            game: GameFixture.game(state: .drawing, turn: GameFixture.partner),
            round: GameFixture.round(state: .drawing, drawer: GameFixture.me)
        )
        let environment = GamesTestEnvironment(state: state)
        let pending = HeldDrawingEnqueueStore(kept: environment.pending, failsFirstSave: failsFirstSave)
        var dependencies = environment.dependencies()
        dependencies.pendingOperationStore = pending
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        dependencies.drawingStore = FileGameDrawingStore(directoryURL: directory)
        let viewModel = DrawAndGuessViewModel(dependencies: dependencies, participants: GameFixture.participants)
        await viewModel.reload()
        viewModel.drawingDescription.update("A red circle above a short blue line.")
        let original = try prepare(viewModel.board)
        let attempted = PKDrawing(strokes: original.strokes + GameFixture.umbrella().strokes)
        let send = Task { await viewModel.finishDrawing() }
        try #require(await waitForEnqueue(pending))
        let reopened = FileGameDrawingStore(directoryURL: directory)
        let retained = try #require(reopened.draft(ownerUserID: GameFixture.me, roundID: GameFixture.roundID))
        #expect(try PKDrawing(data: retained).paeoniaContentSignature == original.paeoniaContentSignature)
        #expect(try reopened.draftDescription(ownerUserID: GameFixture.me,
            coupleID: DeveloperScenarioFixture.coupleID, roundID: GameFixture.roundID)
            == "A red circle above a short blue line.")
        attemptEdits(on: viewModel.board, drawing: attempted)
        viewModel.drawingDescription.update("An edit attempted while sending.")
        #expect(viewModel.drawingDescription.text == "A red circle above a short blue line.")
        #expect(viewModel.board.drawing.paeoniaContentSignature == original.paeoniaContentSignature)
        #expect(!viewModel.canFinishDrawing)
        await pending.release()
        await send.value
        #expect(!viewModel.board.isFinishing)
        if failsFirstSave {
            #expect(viewModel.canFinishDrawing)
            viewModel.board.applyEdit(attempted)
            await viewModel.finishDrawing()
        }
        let queued = try #require(await environment.queued(.submitGameDrawing).first?.requestData)
        let payload = try JSONDecoder().decode(GameSubmitDrawingPayload.self, from: queued)
        #expect(payload.drawingAccessibilityText == "A red circle above a short blue line.")
        let sent = try PKDrawing(data: payload.drawingData)
        let expected = failsFirstSave ? attempted : original
        #expect(sent.paeoniaContentSignature == expected.paeoniaContentSignature)
    }

    @Test(arguments: [false, true])
    func oddCreaturesFreezesEditsUntilThePartIsQueued(failsFirstSave: Bool) async throws {
        let environment = ExquisiteCorpseTestEnvironment(state: ExquisiteCorpseFixture.myBodyTurn())
        let pending = HeldDrawingEnqueueStore(kept: environment.pending, failsFirstSave: failsFirstSave)
        var dependencies = environment.dependencies(withRoom: false)
        dependencies.pendingOperationStore = pending
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        dependencies.drawingStore = FileGameDrawingStore(directoryURL: directory)
        let viewModel = ExquisiteCorpseViewModel(
            dependencies: dependencies, participants: ExquisiteCorpseTestEnvironment.participants
        )
        await viewModel.reload()
        viewModel.drawingDescription.update("A red circle above a short blue line.")
        let original = try prepare(viewModel.board)
        let attempted = PKDrawing(strokes: original.strokes + CorpseDrawings.crossingFold.strokes)
        let send = Task { await viewModel.finishDrawing() }
        try #require(await waitForEnqueue(pending))
        let partID = try #require(viewModel.boardPartID)
        let reopened = FileGameDrawingStore(directoryURL: directory)
        let retained = try #require(reopened.draft(
            ownerUserID: ExquisiteCorpseFixture.me, roundID: partID))
        #expect(try PKDrawing(data: retained).paeoniaContentSignature == original.paeoniaContentSignature)
        #expect(try reopened.draftDescription(
            ownerUserID: ExquisiteCorpseFixture.me,
            coupleID: ExquisiteCorpseFixture.couple,
            roundID: partID) == "A red circle above a short blue line.")
        attemptEdits(on: viewModel.board, drawing: attempted)
        viewModel.drawingDescription.update("An edit attempted while sending.")
        #expect(viewModel.drawingDescription.text == "A red circle above a short blue line.")
        #expect(viewModel.board.drawing.paeoniaContentSignature == original.paeoniaContentSignature)
        #expect(!viewModel.canFinishDrawing)
        await pending.release()
        await send.value
        #expect(!viewModel.board.isFinishing)
        if failsFirstSave {
            #expect(viewModel.canFinishDrawing)
            viewModel.board.applyEdit(attempted)
            await viewModel.finishDrawing()
        }
        let payload = try #require(await environment.queuedParts().first)
        #expect(payload.drawing.accessibilityText == "A red circle above a short blue line.")
        #expect(payload.strip?.accessibilityText == nil)
        let renewed = payload.withNewUploads(renewedAt: Date())
        #expect(renewed.drawing.accessibilityText == payload.drawing.accessibilityText)
        let sent = try PKDrawing(data: payload.drawing.data)
        let expected = failsFirstSave ? attempted : original
        #expect(sent.paeoniaContentSignature == expected.paeoniaContentSignature)
    }

    @Test
    func refusalWhileEnqueueIsHeldRestoresDrawingAndDescriptionAcrossRelaunch() async throws {
        let state = GameFixture.state(settings: GameFixture.settings(),
            game: GameFixture.game(state: .drawing, turn: GameFixture.partner),
            round: GameFixture.round(state: .drawing, drawer: GameFixture.me))
        let environment = GamesTestEnvironment(state: state)
        environment.gateway.setSubmitError(.server(code: "42501", message: "only the drawer can send the drawing"))
        let pending = HeldDrawingEnqueueStore(kept: environment.pending, failsFirstSave: false) { _ in
            let operation = try #require(try await environment.pending.inFlightOperations(
                ownerUserID: GameFixture.me, kind: .submitGameDrawing).first)
            let handler = SubmitGameDrawingPendingOperationHandler(gateway: environment.gateway,
                transfer: environment.transfer, cache: environment.cache, drawingStore: environment.drawingStore)
            let result = try await handler.send(operation, context: syncContext(environment.pending))
            guard case let .terminalFailure(reason) = result else {
                Issue.record("The real handler must restore a refused drawing before enqueue returns")
                return
            }
            try await environment.pending.markTerminalFailure(clientOperationID: operation.operation.id,
                                                               errorDescription: reason, at: Date())
        }
        var dependencies = environment.dependencies()
        dependencies.pendingOperationStore = pending
        let model = DrawAndGuessViewModel(dependencies: dependencies, participants: GameFixture.participants)
        await model.reload()
        let drawing = try prepare(model.board)
        model.drawingDescription.update("A circle above a short blue line.")
        let send = Task { await model.finishDrawing() }
        try #require(await waitForEnqueue(pending))
        await pending.release()
        await send.value
        let reopened = DrawAndGuessViewModel(dependencies: dependencies, participants: GameFixture.participants)
        await reopened.reload()
        #expect(reopened.board.canonicalDrawing.paeoniaContentSignature == drawing.paeoniaContentSignature)
        #expect(reopened.drawingDescription.text == "A circle above a short blue line.")
    }

    private func prepare(_ board: GameDrawingBoard) throws -> PKDrawing {
        board.canvasDidLayout(side: GameCanvas.canonicalSide)
        let first = try #require(DrawingComposition.stroke(
            shape: .circle, x: 50, y: 50, size: 30, side: GameCanvas.canonicalSide, color: .red
        ))
        let second = try #require(DrawingComposition.stroke(
            shape: .verticalLine, x: 50, y: 80, size: 20, side: GameCanvas.canonicalSide, color: .blue
        ))
        let original = PKDrawing(strokes: [first])
        board.applyEdit(original)
        board.applyEdit(PKDrawing(strokes: [first, second]))
        board.undoDrawing()
        return original
    }

    private func attemptEdits(on board: GameDrawingBoard, drawing: PKDrawing) {
        board.applyEdit(drawing)
        board.undoDrawing()
        board.redoDrawing()
        board.clear()
        board.fill(at: CGPoint(x: 50, y: 50))
        #expect(!board.canUndoDrawing)
        #expect(!board.canRedoDrawing)
    }

    private func waitForEnqueue(_ pending: HeldDrawingEnqueueStore) async -> Bool {
        let deadline = ContinuousClock.now + .seconds(3)
        while ContinuousClock.now < deadline {
            if await pending.isHeld { return true }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return false
    }
}

private actor HeldDrawingEnqueueStore: PendingSyncOperationPersisting {
    private let kept: InMemoryPendingSyncOperationRepository
    private let failsFirstSave: Bool
    private let afterEnqueue: (@MainActor @Sendable (PendingSyncOperationRequest) async throws -> Void)?
    private var holdsNext = true
    private var continuation: CheckedContinuation<Void, Never>?
    var isHeld: Bool { continuation != nil }

    init(kept: InMemoryPendingSyncOperationRepository, failsFirstSave: Bool,
         afterEnqueue: (@MainActor @Sendable (PendingSyncOperationRequest) async throws -> Void)? = nil) {
        self.kept = kept
        self.failsFirstSave = failsFirstSave
        self.afterEnqueue = afterEnqueue
    }

    func enqueue(_ request: PendingSyncOperationRequest) async throws {
        if holdsNext {
            holdsNext = false
            await withCheckedContinuation { continuation = $0 }
            if failsFirstSave { throw SaveFailure() }
        }
        try await kept.enqueue(request)
        try await afterEnqueue?(request)
    }

    func release() {
        continuation?.resume()
        continuation = nil
    }

    func readyOperations(ownerUserID: UUID, limit: Int, now: Date) async throws -> [PendingSyncOperationSnapshot] {
        try await kept.readyOperations(ownerUserID: ownerUserID, limit: limit, now: now)
    }

    func nextPendingOperationDate(ownerUserID: UUID, now: Date) async throws -> Date? {
        try await kept.nextPendingOperationDate(ownerUserID: ownerUserID, now: now)
    }

    func inFlightOperations(ownerUserID: UUID, kind: SyncPendingOperationKind) async throws
        -> [PendingSyncOperationSnapshot] {
        try await kept.inFlightOperations(ownerUserID: ownerUserID, kind: kind)
    }

    func markSending(clientOperationID: UUID, at date: Date) async throws {
        try await kept.markSending(clientOperationID: clientOperationID, at: date)
    }

    func markSucceeded(clientOperationID: UUID, at date: Date) async throws {
        try await kept.markSucceeded(clientOperationID: clientOperationID, at: date)
    }

    func markRetryableFailure(
        clientOperationID: UUID, errorDescription: String, nextRetryAt: Date?, at date: Date
    ) async throws {
        try await kept.markRetryableFailure(
            clientOperationID: clientOperationID, errorDescription: errorDescription, nextRetryAt: nextRetryAt, at: date
        )
    }

    func markTerminalFailure(clientOperationID: UUID, errorDescription: String, at date: Date) async throws {
        try await kept.markTerminalFailure(
            clientOperationID: clientOperationID, errorDescription: errorDescription, at: date
        )
    }

    func deleteCompleted(ownerUserID: UUID) async throws { try await kept.deleteCompleted(ownerUserID: ownerUserID) }
    func resetInFlight(ownerUserID: UUID) async throws { try await kept.resetInFlight(ownerUserID: ownerUserID) }
    private struct SaveFailure: Error {}
}
