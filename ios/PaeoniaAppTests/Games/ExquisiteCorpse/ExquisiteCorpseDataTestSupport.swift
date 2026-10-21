import Foundation
import Testing
@testable import PaeoniaApp

extension ExquisiteCorpseFixture {
    /// What the scripted transfer returns for the full part and for its strip.
    static let drawingAssetID = UUID(uuidString: "AAAAAAAA-0000-4000-8000-000000000001") ?? UUID()
    static let stripAssetID = UUID(uuidString: "AAAAAAAA-0000-4000-8000-000000000002") ?? UUID()

    /// The error the Convex client throws when a function refuses a call.
    static func refusal(_ code: String, _ message: String) -> PaeoniaConvexError {
        .server(code: code, message: message)
    }

    /// A part of `me` with a drawing and a strip that differ, so a test can tell the uploads apart.
    /// The drawing is `Data([1, 1, 1])` and the strip is `Data([2, 2])`. The legs have no strip.
    static func distinctPart(
        figure: Int = 2,
        partIndex: Int = 0,
        idea: RemoteExquisiteCorpseIdea? = nil,
        renewedAt: Date? = nil
    ) -> ExquisiteCorpseSubmitPartPayload {
        func upload(_ data: Data, sequence: Int64) -> ExquisiteCorpseQueuedUpload {
            ExquisiteCorpseQueuedUpload(
                data: data,
                reserveOperation: SyncClientOperation(clientID: UUID(), clientSequence: sequence),
                finalizeOperation: SyncClientOperation(clientID: UUID(), clientSequence: sequence + 1)
            )
        }
        return ExquisiteCorpseSubmitPartPayload(
            gameID: gameID,
            figureID: figureID(figure),
            partID: ExquisiteCorpseIDs.part(gameID: gameID, figureNumber: figure, partIndex: partIndex, drawerID: me),
            partIndex: partIndex,
            coupleID: couple,
            drawing: upload(Data([1, 1, 1]), sequence: 10),
            strip: partIndex < 2 ? upload(Data([2, 2]), sequence: 20) : nil,
            idea: idea,
            createdAt: now,
            renewedAt: renewedAt
        )
    }

    /// A state of figure 2 (started by `me`, the body is next and the partner draws it) at a game
    /// version. A higher version is a later state.
    static func state(
        version: Int,
        current: RemoteExquisiteCorpseFigure? = nil,
        recent: [RemoteExquisiteCorpseFigure] = [],
        ideas: [RemoteExquisiteCorpseIdea] = []
    ) -> RemoteExquisiteCorpseState {
        let base = game(figure: 2, partIndex: 1, turn: partner)
        let versioned = RemoteExquisiteCorpseGame(
            id: base.id,
            turnUserID: base.turnUserID,
            turnStartedAt: base.turnStartedAt,
            figureID: base.figureID,
            figureNumber: base.figureNumber,
            partIndex: base.partIndex,
            figuresFinished: base.figuresFinished,
            version: version,
            createdAt: base.createdAt,
            updatedAt: base.updatedAt
        )
        return state(game: versioned, current: current, recent: recent, ideas: ideas)
    }

    /// The same state as `state`, read by another person.
    static func state(_ state: RemoteExquisiteCorpseState, readBy userID: UUID) -> RemoteExquisiteCorpseState {
        RemoteExquisiteCorpseState(
            userID: userID,
            partnerUserID: state.partnerUserID,
            coupleID: state.coupleID,
            dataEpoch: "",
            game: state.game,
            currentFigure: state.currentFigure,
            recentFigures: state.recentFigures,
            ideas: state.ideas
        )
    }
}

/// The error a piece of work throws, or nil when it finishes.
func corpseThrownError<Value>(_ work: () async throws -> Value) async -> (any Error)? {
    do {
        _ = try await work()
        return nil
    } catch {
        return error
    }
}

/// Records an issue unless the write stopped for good.
func expectCorpseTerminalFailure(_ result: PendingSyncOperationSendResult) {
    guard case .terminalFailure = result else {
        Issue.record("Expected a terminal failure, got \(result)")
        return
    }
}

// The protocols are async, and the scripted stand-ins do not always await.
// swiftlint:disable async_without_await

/// Records every Exquisite corpse call and fails the ones a test lists. A class with a lock,
/// so tests read its record without `await`.
final class ScriptedExquisiteCorpseGateway: ExquisiteCorpseGateway, @unchecked Sendable {
    struct Failure: Error {}

    struct SubmittedPart: Equatable {
        var partID: UUID
        var figureID: UUID
        var partIndex: Int
        var drawingAssetID: UUID
        var stripAssetID: UUID?
        var ideaID: String?
        var operationID: UUID
    }

    private struct Record {
        var calls: [String] = []
        var submitted: [SubmittedPart] = []
        var revealSeen: [UUID] = []
        var submitError: (any Error)?
        var revealSeenError: (any Error)?
        var stateToLoad: RemoteExquisiteCorpseState?
    }

    private let lock = NSLock()
    private var record = Record()

    private func read<T>(_ value: (Record) -> T) -> T {
        lock.withLock { value(record) }
    }

    private func write(_ change: (inout Record) -> Void) {
        lock.withLock { change(&record) }
    }

    var calls: [String] { read(\.calls) }
    var submitted: [SubmittedPart] { read(\.submitted) }
    var revealSeen: [UUID] { read(\.revealSeen) }

    func setSubmitError(_ error: (any Error)?) {
        write { $0.submitError = error }
    }

    func setRevealSeenError(_ error: (any Error)?) {
        write { $0.revealSeenError = error }
    }

    /// What `loadExquisiteCorpse` returns. Without one, it fails like a lost connection.
    func setStateToLoad(_ state: RemoteExquisiteCorpseState?) {
        write { $0.stateToLoad = state }
    }

    private func begin(_ name: String) {
        write { $0.calls.append(name) }
    }

    func ensureExquisiteCorpseGame() async throws -> RemoteExquisiteCorpseEnsureResult {
        begin("ensure")
        throw Failure()
    }

    func loadExquisiteCorpse() async throws -> RemoteExquisiteCorpseState {
        begin("load")
        guard let state = read(\.stateToLoad) else { throw Failure() }
        return state
    }

    func submitExquisiteCorpsePart(
        _ payload: ExquisiteCorpseSubmitPartPayload,
        drawingAssetID: UUID,
        stripAssetID: UUID?,
        operation: SyncClientOperation
    ) async throws -> RemoteExquisiteCorpseSubmitPartResult {
        begin("submit")
        if let error = read(\.submitError) { throw error }
        write {
            $0.submitted.append(
                SubmittedPart(
                    partID: payload.partID,
                    figureID: payload.figureID,
                    partIndex: payload.partIndex,
                    drawingAssetID: drawingAssetID,
                    stripAssetID: stripAssetID,
                    ideaID: payload.idea?.id,
                    operationID: operation.id
                )
            )
        }
        return RemoteExquisiteCorpseSubmitPartResult(
            figureID: payload.figureID,
            partID: payload.partID,
            partIndex: payload.partIndex,
            figureFinished: payload.partIndex == 2,
            createdAt: ExquisiteCorpseFixture.now
        )
    }

    func markExquisiteCorpseRevealSeen(figureID: UUID) async throws -> RemoteExquisiteCorpseRevealSeenResult {
        begin("revealSeen")
        if let error = read(\.revealSeenError) { throw error }
        write { $0.revealSeen.append(figureID) }
        return RemoteExquisiteCorpseRevealSeenResult(figureID: figureID, revealSeenAt: ExquisiteCorpseFixture.now)
    }

    func loadExquisiteCorpseHistory(
        starredOnly _: Bool,
        beforeFigureNumber _: Int?,
        limit _: Int
    ) async throws -> RemoteExquisiteCorpseHistoryPage {
        begin("history")
        throw Failure()
    }

    func loadExquisiteCorpseFigure(figureID _: UUID) async throws -> RemoteExquisiteCorpseFigure? {
        begin("figure")
        throw Failure()
    }
}

/// Uploads succeed. The full part gets `ExquisiteCorpseFixture.drawingAssetID` and the strip
/// gets `stripAssetID`.
final class ScriptedCorpseDrawingTransfer: GameDrawingTransferring, @unchecked Sendable {
    struct Upload: Equatable {
        var parent: GameUploadParent
        var data: Data
        var coupleID: UUID
        var reserveOperation: SyncClientOperation
        var finalizeOperation: SyncClientOperation
    }

    private let lock = NSLock()
    private var recordedUploads: [Upload] = []
    private var uploadError: (any Error)?

    var uploads: [Upload] { lock.withLock { recordedUploads } }

    func setUploadError(_ error: (any Error)?) {
        lock.withLock { uploadError = error }
    }

    func uploadDrawing(
        _ data: Data,
        parent: GameUploadParent,
        coupleID: UUID,
        reserveOperation: SyncClientOperation,
        finalizeOperation: SyncClientOperation
    ) async throws -> UUID {
        let error = lock.withLock {
            recordedUploads.append(
                Upload(
                    parent: parent,
                    data: data,
                    coupleID: coupleID,
                    reserveOperation: reserveOperation,
                    finalizeOperation: finalizeOperation
                )
            )
            return uploadError
        }
        if let error { throw error }
        return parent.purpose == "exquisite_corpse_strip"
            ? ExquisiteCorpseFixture.stripAssetID
            : ExquisiteCorpseFixture.drawingAssetID
    }

    func downloadDrawing(mediaAssetID _: UUID) async throws -> Data {
        Data()
    }
}

// swiftlint:enable async_without_await

/// Everything a handler test needs, in memory. The owner is `ExquisiteCorpseFixture.me`.
@MainActor
struct ExquisiteCorpseDataEnvironment {
    let gateway = ScriptedExquisiteCorpseGateway()
    let transfer = ScriptedCorpseDrawingTransfer()
    let cache = InMemoryExquisiteCorpseCache()
    let pending = InMemoryPendingSyncOperationRepository()
    let drawingStore = InMemoryGameDrawingStore()

    init() {
        // The server answers the read that follows each move it takes.
        gateway.setStateToLoad(ExquisiteCorpseFixture.state(version: 2))
    }

    func submitHandler() -> ExquisiteCorpseSubmitPartHandler {
        ExquisiteCorpseSubmitPartHandler(
            gateway: gateway,
            transfer: transfer,
            cache: cache,
            drawingStore: drawingStore
        )
    }

    func revealSeenHandler() -> ExquisiteCorpseRevealSeenHandler {
        ExquisiteCorpseRevealSeenHandler(gateway: gateway, cache: cache)
    }

    func context() -> SyncContext {
        SyncContext(
            session: SyncSession(userID: ExquisiteCorpseFixture.me),
            reason: .localChange,
            stateStore: InMemorySyncStateRepository(),
            pendingOperationStore: pending
        )
    }

    /// Puts a write in the queue, the way the screens do.
    func enqueue(
        _ kind: SyncPendingOperationKind,
        _ payload: some Encodable,
        operation: SyncClientOperation = SyncClientOperation(clientID: UUID(), clientSequence: 1)
    ) async throws {
        try await pending.enqueue(
            PendingSyncOperationRequest(
                ownerUserID: ExquisiteCorpseFixture.me,
                operation: operation,
                operationKind: kind,
                idempotencyScope: "exquisite-corpse",
                requestData: try JSONEncoder().encode(payload)
            )
        )
    }

    /// The operations still waiting, by kind.
    func queued(_ kind: SyncPendingOperationKind) async -> [PendingSyncOperationSnapshot] {
        (try? await pending.inFlightOperations(ownerUserID: ExquisiteCorpseFixture.me, kind: kind)) ?? []
    }
}

/// A queued write as the drain hands it to a handler.
func corpseSnapshot(
    _ kind: SyncPendingOperationKind,
    _ payload: some Encodable,
    operation: SyncClientOperation = SyncClientOperation(clientID: UUID(), clientSequence: 1)
) throws -> PendingSyncOperationSnapshot {
    PendingSyncOperationSnapshot(
        ownerUserID: ExquisiteCorpseFixture.me,
        operation: operation,
        operationKind: kind,
        idempotencyScope: "exquisite-corpse",
        requestHash: nil,
        requestData: try JSONEncoder().encode(payload),
        status: .queued,
        attemptCount: 0,
        lastAttemptAt: nil,
        nextRetryAt: nil,
        lastError: nil,
        completedAt: nil
    )
}
