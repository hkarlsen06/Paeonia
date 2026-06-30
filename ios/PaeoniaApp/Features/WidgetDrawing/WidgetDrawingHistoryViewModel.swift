import CoreGraphics
import Foundation

/// One drawing in the history timeline.
nonisolated struct WidgetDrawingHistoryItem: Identifiable, Sendable, Equatable {
    /// The revision id.
    let id: UUID
    let authorName: String?
    /// True when the signed-in person drew this. Drives which side of the
    /// timeline the drawing sits on (mine trailing, partner's leading).
    let isMine: Bool
    let createdAt: Date
    let mediaAssetID: UUID
    let canvasSide: CGFloat
}

/// Loads the couple's past drawings newest-first, one page at a time, for the
/// history timeline. Paging, cursoring, and dedupe live here so the view stays
/// declarative and the logic stays testable.
@MainActor
@Observable
final class WidgetDrawingHistoryViewModel {
    enum Phase: Equatable {
        case loading
        case loaded
        case failed
    }

    /// The state of one drawing's "save to your photos" button.
    enum SaveButtonState: Equatable {
        case idle
        case saving
        case saved
    }

    /// A blocking notice shown when a save can't go through on its own. Only the
    /// permission case needs the person to act (in Settings); ordinary failures
    /// just reset the button so they can try again.
    enum SaveAlert: Equatable {
        case permissionDenied
    }

    private(set) var items: [WidgetDrawingHistoryItem] = []
    private(set) var phase: Phase = .loading
    private(set) var isLoadingMore = false
    private(set) var hasMore = true

    /// Per-drawing save button state, keyed by revision id. Survives reloads so a
    /// drawing already saved keeps its checkmark.
    private(set) var saveStates: [UUID: SaveButtonState] = [:]
    private(set) var saveAlert: SaveAlert?

    /// True once the first load finished and there is nothing to show.
    var isEmpty: Bool { phase == .loaded && items.isEmpty }

    /// The partner's display name for copy that names them (e.g. the empty state),
    /// falling back to a neutral "Partner" before the nickname is known.
    var partnerName: String {
        identity.partnerDisplayName?.trimmedNonEmpty ?? String(localized: .pairingCelebrationPartnerName)
    }

    private let gateway: any WidgetCanvasGateway
    private let identity: WidgetSyncIdentity
    private let pageSize: Int
    private let exporter: any WidgetRevisionThumbnailLoading
    private let photoSaver: any PhotoLibrarySaving

    private var canvasID: UUID?
    private var cursor: Cursor?
    private var seenRevisionIDs: Set<UUID> = []
    private var didStartInitialLoad = false

    private struct Cursor: Equatable {
        let createdBefore: Date
        let revisionID: UUID
    }

    init(
        gateway: any WidgetCanvasGateway,
        identity: WidgetSyncIdentity,
        pageSize: Int = 30,
        exporter: any WidgetRevisionThumbnailLoading = NoOpWidgetRevisionThumbnailLoader(),
        photoSaver: any PhotoLibrarySaving = PhotoLibrarySaver()
    ) {
        self.gateway = gateway
        self.identity = identity
        self.pageSize = pageSize
        self.exporter = exporter
        self.photoSaver = photoSaver
    }

    func loadInitialIfNeeded() async {
        guard !didStartInitialLoad else {
            return
        }
        didStartInitialLoad = true
        await loadFirstPage()
    }

    func retry() async {
        await loadFirstPage()
    }

    /// The save button state for a drawing, defaulting to idle.
    func saveState(for id: UUID) -> SaveButtonState {
        saveStates[id] ?? .idle
    }

    func dismissSaveAlert() {
        saveAlert = nil
    }

    /// Renders the drawing at full quality and adds it to the device's photo
    /// library. On success the button latches to a checkmark; if the person has
    /// blocked photo access we surface a notice pointing them to Settings, and any
    /// other failure resets the button so they can try again.
    func saveToDevice(_ item: WidgetDrawingHistoryItem) async {
        guard saveState(for: item.id) == .idle else {
            return
        }
        saveStates[item.id] = .saving

        guard let png = await exporter.exportPNG(
            revisionID: item.id,
            mediaAssetID: item.mediaAssetID,
            canvasSide: item.canvasSide
        ) else {
            saveStates[item.id] = .idle
            PaeoniaHaptics.validationError()
            return
        }

        switch await photoSaver.savePNG(png) {
        case .saved:
            saveStates[item.id] = .saved
            PaeoniaHaptics.drawingSaved()
        case .permissionDenied:
            saveStates[item.id] = .idle
            saveAlert = .permissionDenied
        case .failed:
            saveStates[item.id] = .idle
            PaeoniaHaptics.validationError()
        }
    }

    func loadMoreIfNeeded(currentItem: WidgetDrawingHistoryItem) async {
        guard phase == .loaded,
              hasMore,
              !isLoadingMore,
              cursor != nil,
              shouldLoadMore(after: currentItem)
        else {
            return
        }

        isLoadingMore = true
        defer { isLoadingMore = false }
        // Keep the list intact and leave `hasMore` true on failure so scrolling
        // retries.
        try? await fetchUntilProgressOrEnd()
    }

    private func loadFirstPage() async {
        phase = .loading
        items = []
        cursor = nil
        seenRevisionIDs = []
        hasMore = true

        do {
            guard let state = try await gateway.getCanvasState() else {
                // No canvas yet (e.g. not paired) means no drawings to show.
                canvasID = nil
                hasMore = false
                phase = .loaded
                return
            }
            canvasID = state.canvasID
            try await fetchUntilProgressOrEnd()
            phase = .loaded
        } catch {
            phase = .failed
        }
    }

    /// Fetches pages from the current cursor until at least one showable drawing
    /// is added or there are no more pages. The RPC can return a full page made
    /// entirely of hidden/deleted revisions (payload nulled), which yields no
    /// items but must still advance the cursor — otherwise the timeline would
    /// show a false empty state with no row available to trigger the next page.
    private func fetchUntilProgressOrEnd() async throws {
        guard let canvasID else {
            return
        }
        let startCount = items.count
        repeat {
            let page = try await gateway.listRevisions(
                canvasID: canvasID,
                limit: pageSize,
                createdBefore: cursor?.createdBefore,
                createdBeforeRevisionID: cursor?.revisionID
            )
            apply(page)
        } while hasMore && items.count == startCount
    }

    private func shouldLoadMore(after item: WidgetDrawingHistoryItem) -> Bool {
        guard let index = items.firstIndex(of: item) else {
            return false
        }
        // Prefetch the next page while the last few rows come into view.
        return index >= items.count - 3
    }

    /// Folds a raw RPC page into the timeline. The cursor advances by the last
    /// *raw* row — including hidden ones the RPC returns with a null payload — so
    /// an all-hidden page still moves forward instead of looping. Only showable
    /// rows become visible items.
    private func apply(_ page: [WidgetDrawingRevisionSummary]) {
        if let last = page.last {
            cursor = Cursor(createdBefore: last.createdAt, revisionID: last.revisionID)
        }
        hasMore = page.count == pageSize

        let newItems = page.compactMap { summary -> WidgetDrawingHistoryItem? in
            guard let mediaAssetID = summary.payloadMediaAssetID,
                  !seenRevisionIDs.contains(summary.revisionID)
            else {
                return nil
            }
            seenRevisionIDs.insert(summary.revisionID)
            let isMine = summary.authorUserID != nil && summary.authorUserID == identity.currentUserID
            return WidgetDrawingHistoryItem(
                id: summary.revisionID,
                authorName: WidgetCanvasSyncService.authorName(for: summary.authorUserID, identity: identity),
                isMine: isMine,
                createdAt: summary.createdAt,
                mediaAssetID: mediaAssetID,
                canvasSide: summary.bounds.map { CGFloat($0.canvasSide) } ?? WidgetDrawingViewModel.fallbackCanvasSide
            )
        }
        items.append(contentsOf: newItems)
    }
}
