import CoreGraphics
import Foundation
import Testing
@testable import PaeoniaApp

@MainActor
struct WidgetDrawingHistoryViewModelTests {
    @Test func firstPageShowsOnlyRenderableRowsInOrder() async {
        let visibleNewer = makeSummary(createdAt: date(300))
        let hidden = makeSummary(mediaAsset: nil, createdAt: date(200))
        let visibleOlder = makeSummary(createdAt: date(100))
        let gateway = StubGateway(canvasState: makeState(), pages: [[visibleNewer, hidden, visibleOlder]])
        let viewModel = makeViewModel(gateway: gateway, pageSize: 10)

        await viewModel.loadInitialIfNeeded()

        #expect(viewModel.phase == .loaded)
        #expect(viewModel.items.map(\.id) == [visibleNewer.revisionID, visibleOlder.revisionID])
        #expect(viewModel.hasMore == false)
        #expect(viewModel.isEmpty == false)
    }

    @Test func keepsFetchingPastAFullHiddenPageUsingRawCursor() async {
        let hidden1 = makeSummary(mediaAsset: nil, createdAt: date(400))
        let hidden2 = makeSummary(mediaAsset: nil, createdAt: date(300))
        let shown = makeSummary(createdAt: date(200))
        let gateway = StubGateway(canvasState: makeState(), pages: [[hidden1, hidden2], [shown]])
        let viewModel = makeViewModel(gateway: gateway, pageSize: 2)

        await viewModel.loadInitialIfNeeded()

        #expect(viewModel.items.map(\.id) == [shown.revisionID])
        #expect(viewModel.hasMore == false)
        // The 2nd page must be cursored by the last *raw* row of page 1 (a hidden
        // one), not by a visible item — otherwise an all-hidden page loops.
        #expect(gateway.listCursors.count == 2)
        #expect(gateway.listCursors[0].before == nil)
        #expect(gateway.listCursors[1].before == hidden2.createdAt)
        #expect(gateway.listCursors[1].revisionID == hidden2.revisionID)
    }

    @Test func loadMoreAppendsOlderPageAndDedupes() async {
        let newer = makeSummary(createdAt: date(500))
        let shared = makeSummary(createdAt: date(400))
        let older = makeSummary(createdAt: date(300))
        // Page 2 re-includes `shared` (overlap) plus a new older drawing.
        let gateway = StubGateway(canvasState: makeState(), pages: [[newer, shared], [shared, older]])
        let viewModel = makeViewModel(gateway: gateway, pageSize: 2)

        await viewModel.loadInitialIfNeeded()
        #expect(viewModel.items.map(\.id) == [newer.revisionID, shared.revisionID])
        #expect(viewModel.hasMore == true)

        await viewModel.loadMoreIfNeeded(currentItem: viewModel.items[viewModel.items.count - 1])

        #expect(viewModel.items.map(\.id) == [newer.revisionID, shared.revisionID, older.revisionID])
    }

    @Test func refreshNewestPrependsNewDrawingsAndKeepsTheOlderCursor() async {
        let existing = makeSummary(createdAt: date(100))
        let arrived = makeSummary(createdAt: date(200))
        // The refresh page re-includes `existing`, which must not duplicate.
        let gateway = StubGateway(canvasState: makeState(), pages: [[existing], [arrived, existing]])
        let viewModel = makeViewModel(gateway: gateway, pageSize: 10)
        await viewModel.loadInitialIfNeeded()

        await viewModel.refreshNewest()

        #expect(viewModel.items.map(\.id) == [arrived.revisionID, existing.revisionID])
        #expect(gateway.listCursors.count == 2)
        #expect(gateway.listCursors[1].before == nil)
        #expect(viewModel.hasMore == false)
    }

    @Test func refreshNewestKeepsTheListWhenTheReadFails() async {
        let existing = makeSummary(createdAt: date(100))
        let gateway = StubGateway(canvasState: makeState(), pages: [[existing]])
        let viewModel = makeViewModel(gateway: gateway, pageSize: 10)
        await viewModel.loadInitialIfNeeded()
        gateway.listError = URLError(.notConnectedToInternet)

        await viewModel.refreshNewest()

        #expect(viewModel.items.map(\.id) == [existing.revisionID])
        #expect(viewModel.phase == .loaded)
    }

    // MARK: - Helpers

    private func makeViewModel(
        gateway: StubGateway,
        pageSize: Int = 30
    ) -> WidgetDrawingHistoryViewModel {
        WidgetDrawingHistoryViewModel(
            gateway: gateway,
            identity: WidgetSyncIdentity(currentUserID: nil, currentDisplayName: nil, partnerDisplayName: nil),
            pageSize: pageSize
        )
    }

    private func makeSummary(
        id: UUID = UUID(),
        author: UUID? = UUID(),
        mediaAsset: UUID? = UUID(),
        createdAt: Date,
        canvasSide: Double = 320
    ) -> WidgetDrawingRevisionSummary {
        WidgetDrawingRevisionSummary(
            revisionID: id,
            authorUserID: author,
            payloadMediaAssetID: mediaAsset,
            bounds: WidgetDrawingBounds(x: 0, y: 0, width: 10, height: 10, canvasSide: canvasSide),
            createdAt: createdAt
        )
    }

    private func makeState(canvasID: UUID = UUID()) -> WidgetCanvasState {
        WidgetCanvasState(
            canvasID: canvasID,
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
