import Foundation
import Testing
@testable import PaeoniaApp

// The test doubles mirror async protocols, so some bodies do not await.
// swiftlint:disable async_without_await

/// First-page, newest-page, and older-page loads that fail or overlap in time.
@MainActor
struct WidgetDrawingHistoryLoadingTests {
    // MARK: - Newest page

    @Test func refreshNewestReloadsWhenAFullPageOfNewDrawingsArrives() async {
        let existing = makeSummary(createdAt: date(100))
        let arrivedNewer = makeSummary(createdAt: date(300))
        let arrivedOlder = makeSummary(createdAt: date(200))
        // A full page with nothing already loaded in it may hide more new drawings
        // behind it, so the refresh (call 2) is followed by a reload (call 3).
        let gateway = StubGateway(
            canvasState: makeState(),
            pages: [[existing], [arrivedNewer, arrivedOlder], [arrivedNewer, arrivedOlder]]
        )
        let viewModel = makeViewModel(gateway: gateway, pageSize: 2)
        await viewModel.loadInitialIfNeeded()

        await viewModel.refreshNewest()

        #expect(viewModel.items.map(\.id) == [arrivedNewer.revisionID, arrivedOlder.revisionID])
        #expect(viewModel.phase == .loaded)
        #expect(viewModel.hasMore)
        #expect(gateway.listCursors.count == 3)
        #expect(gateway.listCursors[2].before == nil)
    }

    // MARK: - Overlapping loads

    @Test func retryWinsOverAnEarlierFirstPageLoadThatFinishesLate() async {
        let stale = makeSummary(createdAt: date(100))
        let fresh = makeSummary(createdAt: date(200))
        let gateway = GatedListGateway(canvasState: makeState(), heldCall: 1, otherPages: [[fresh]])
        let viewModel = makeViewModel(gateway: gateway, pageSize: 10)

        let earlierLoad = Task { await viewModel.loadInitialIfNeeded() }
        await gateway.waitUntilListIsHeld()
        await viewModel.retry()
        #expect(viewModel.items.map(\.id) == [fresh.revisionID])

        await gateway.releaseHeldList(with: .success([stale]))
        await earlierLoad.value

        #expect(viewModel.items.map(\.id) == [fresh.revisionID])
        #expect(viewModel.phase == .loaded)
    }

    @Test func aFailedEarlierFirstPageLoadDoesNotOverwriteALoadedTimeline() async {
        let fresh = makeSummary(createdAt: date(200))
        let gateway = GatedListGateway(canvasState: makeState(), heldCall: 1, otherPages: [[fresh]])
        let viewModel = makeViewModel(gateway: gateway, pageSize: 10)

        let earlierLoad = Task { await viewModel.loadInitialIfNeeded() }
        await gateway.waitUntilListIsHeld()
        await viewModel.retry()

        await gateway.releaseHeldList(with: .failure(URLError(.timedOut)))
        await earlierLoad.value

        #expect(viewModel.items.map(\.id) == [fresh.revisionID])
        #expect(viewModel.phase == .loaded)
    }

    @Test func refreshNewestDropsItsPageWhenAFirstPageLoadStartedMeanwhile() async {
        let existing = makeSummary(createdAt: date(100))
        let reloaded = makeSummary(createdAt: date(150))
        let arrived = makeSummary(createdAt: date(200))
        // Call 1 is the first load, call 2 (held) is the refresh, call 3 is the retry.
        let gateway = GatedListGateway(
            canvasState: makeState(), heldCall: 2, otherPages: [[existing], [reloaded]]
        )
        let viewModel = makeViewModel(gateway: gateway, pageSize: 10)
        await viewModel.loadInitialIfNeeded()

        let refresh = Task { await viewModel.refreshNewest() }
        await gateway.waitUntilListIsHeld()
        await viewModel.retry()

        await gateway.releaseHeldList(with: .success([arrived]))
        await refresh.value

        #expect(viewModel.items.map(\.id) == [reloaded.revisionID])
    }

    @Test func loadMoreDropsItsPageWhenAFirstPageLoadStartedMeanwhile() async {
        let newer = makeSummary(createdAt: date(500))
        let shared = makeSummary(createdAt: date(400))
        let reloaded = makeSummary(createdAt: date(450))
        let older = makeSummary(createdAt: date(300))
        // Call 1 is the first load, call 2 (held) is the older page, call 3 is the retry.
        let gateway = GatedListGateway(
            canvasState: makeState(), heldCall: 2, otherPages: [[newer, shared], [reloaded]]
        )
        let viewModel = makeViewModel(gateway: gateway, pageSize: 2)
        await viewModel.loadInitialIfNeeded()
        let lastItem = viewModel.items[1]

        let loadMore = Task { await viewModel.loadMoreIfNeeded(currentItem: lastItem) }
        await gateway.waitUntilListIsHeld()
        await viewModel.retry()

        await gateway.releaseHeldList(with: .success([older]))
        await loadMore.value

        #expect(viewModel.items.map(\.id) == [reloaded.revisionID])
        #expect(viewModel.isLoadingMore == false)
        #expect(viewModel.loadMoreFailed == false)
    }

    // MARK: - Helpers

    private func makeViewModel(
        gateway: any WidgetCanvasGateway,
        pageSize: Int = 30
    ) -> WidgetDrawingHistoryViewModel {
        WidgetDrawingHistoryViewModel(
            gateway: gateway,
            identity: WidgetSyncIdentity(currentUserID: nil, currentDisplayName: nil, partnerDisplayName: nil),
            pageSize: pageSize
        )
    }

    private func makeSummary(createdAt: Date) -> WidgetDrawingRevisionSummary {
        WidgetDrawingRevisionSummary(
            revisionID: UUID(),
            authorUserID: UUID(),
            payloadMediaAssetID: UUID(),
            bounds: WidgetDrawingBounds(x: 0, y: 0, width: 10, height: 10, canvasSide: 320),
            createdAt: createdAt
        )
    }

    private func makeState() -> WidgetCanvasState {
        WidgetCanvasState(
            canvasID: UUID(),
            activeRevisionID: nil,
            activeRevisionAuthorUserID: nil,
            payloadMediaAssetID: nil,
            bounds: nil,
            revisionCreatedAt: nil
        )
    }

    private func date(_ offset: TimeInterval) -> Date {
        Date(timeIntervalSinceReferenceDate: offset)
    }
}

/// Records the cursors it was asked for and replays canned pages in order.
private nonisolated final class StubGateway: WidgetCanvasGateway, @unchecked Sendable {
    var canvasState: WidgetCanvasState?
    var stateError: (any Error)?
    var listError: (any Error)?
    private let pages: [[WidgetDrawingRevisionSummary]]
    private var index = 0
    private(set) var listCursors: [(before: Date?, revisionID: UUID?)] = []

    init(canvasState: WidgetCanvasState?, pages: [[WidgetDrawingRevisionSummary]]) {
        self.canvasState = canvasState
        self.pages = pages
    }

    func getCanvasState() throws -> WidgetCanvasState? {
        if let stateError { throw stateError }
        return canvasState
    }

    func listRevisions(
        canvasID: UUID,
        limit: Int,
        createdBefore: Date?,
        createdBeforeRevisionID: UUID?
    ) throws -> [WidgetDrawingRevisionSummary] {
        if let listError { throw listError }
        listCursors.append((createdBefore, createdBeforeRevisionID))
        defer { index += 1 }
        return index < pages.count ? pages[index] : []
    }

    // Unused by the history timeline.
    func getOrCreateCanvas() throws -> WidgetCanvasReference {
        throw WidgetCanvasGatewayError.emptyResponse
    }
    func reserveDrawingUpload(
        coupleID: UUID, canvasID: UUID, revisionID: UUID, operation: WidgetCanvasClientOperation
    ) throws -> MediaUploadReservation {
        throw WidgetCanvasGatewayError.emptyResponse
    }
    func uploadPayload(reservation: MediaUploadReservation, data: Data) throws -> String {
        throw WidgetCanvasGatewayError.emptyResponse
    }
    func finalizeDrawingUpload(
        _ input: WidgetDrawingFinalizeInput, operation: WidgetCanvasClientOperation
    ) throws -> FinalizedMediaUploadResponse {
        throw WidgetCanvasGatewayError.emptyResponse
    }
    func submitRevision(
        _ submission: WidgetDrawingRevisionSubmission, operation: WidgetCanvasClientOperation
    ) throws -> WidgetDrawingRevisionResult {
        throw WidgetCanvasGatewayError.emptyResponse
    }
    func signedPayloadURL(mediaAssetID: UUID) -> URL? { nil }
}

/// Suspends one chosen `listRevisions` call until the test releases it and serves
/// every other call from canned pages in order. Lets a test start a second load
/// while the first is still waiting on the network.
private actor GatedListGateway: WidgetCanvasGateway {
    private let canvasState: WidgetCanvasState?
    private let heldCall: Int
    private var otherPages: [[WidgetDrawingRevisionSummary]]
    private var listCallCount = 0
    private var heldList: CheckedContinuation<[WidgetDrawingRevisionSummary], any Error>?
    private var heldListWaiter: CheckedContinuation<Void, Never>?

    /// `heldCall` is the 1-based number of the `listRevisions` call to hold.
    init(canvasState: WidgetCanvasState?, heldCall: Int, otherPages: [[WidgetDrawingRevisionSummary]]) {
        self.canvasState = canvasState
        self.heldCall = heldCall
        self.otherPages = otherPages
    }

    /// Returns once the held call is suspended.
    func waitUntilListIsHeld() async {
        guard heldList == nil else { return }
        await withCheckedContinuation { continuation in
            heldListWaiter = continuation
        }
    }

    func releaseHeldList(with result: Result<[WidgetDrawingRevisionSummary], any Error>) {
        heldList?.resume(with: result)
        heldList = nil
    }

    func getCanvasState() async throws -> WidgetCanvasState? {
        canvasState
    }

    func listRevisions(
        canvasID: UUID,
        limit: Int,
        createdBefore: Date?,
        createdBeforeRevisionID: UUID?
    ) async throws -> [WidgetDrawingRevisionSummary] {
        listCallCount += 1
        guard listCallCount == heldCall else {
            return otherPages.isEmpty ? [] : otherPages.removeFirst()
        }
        return try await withCheckedThrowingContinuation { continuation in
            heldList = continuation
            heldListWaiter?.resume()
            heldListWaiter = nil
        }
    }

    // Unused by the history timeline.
    func getOrCreateCanvas() async throws -> WidgetCanvasReference {
        throw WidgetCanvasGatewayError.emptyResponse
    }
    func reserveDrawingUpload(
        coupleID: UUID, canvasID: UUID, revisionID: UUID, operation: WidgetCanvasClientOperation
    ) async throws -> MediaUploadReservation {
        throw WidgetCanvasGatewayError.emptyResponse
    }
    func uploadPayload(reservation: MediaUploadReservation, data: Data) async throws -> String {
        throw WidgetCanvasGatewayError.emptyResponse
    }
    func finalizeDrawingUpload(
        _ input: WidgetDrawingFinalizeInput, operation: WidgetCanvasClientOperation
    ) async throws -> FinalizedMediaUploadResponse {
        throw WidgetCanvasGatewayError.emptyResponse
    }
    func submitRevision(
        _ submission: WidgetDrawingRevisionSubmission, operation: WidgetCanvasClientOperation
    ) async throws -> WidgetDrawingRevisionResult {
        throw WidgetCanvasGatewayError.emptyResponse
    }
    func signedPayloadURL(mediaAssetID: UUID) async throws -> URL? { nil }
}

// swiftlint:enable async_without_await
