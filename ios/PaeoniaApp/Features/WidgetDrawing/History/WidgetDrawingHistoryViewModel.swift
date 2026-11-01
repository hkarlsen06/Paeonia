import CoreGraphics
import Foundation
import UIKit

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
    var accessibilityText: String?
    var descriptionVersion: Int64?
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
        case failed(PaeoniaFailure)
    }

    private(set) var items: [WidgetDrawingHistoryItem] = []
    private(set) var phase: Phase = .loading
    private(set) var isLoadingMore = false
    /// True after an older page failed to load. Stays set until
    /// `retryLoadMore()` runs or the first page reloads, so the timeline can show
    /// a retry row instead of silently stopping.
    private(set) var loadMoreFailed = false
    private(set) var hasMore = true

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

    private var canvasID: UUID?
    private var loadedCoupleID: UUID?
    private var cursor: Cursor?
    private var seenRevisionIDs: Set<UUID> = []
    private var pendingDescriptionOperations: [UUID: UUID] = [:]
    private var descriptionsGeneration = 0
    private var didStartInitialLoad = false
    /// Bumped by every first-page load. A load, refresh, or older-page fetch that
    /// finds a different value after an `await` was overtaken by a newer first-page
    /// load and must stop without touching state.
    private var loadGeneration = 0

    private struct Cursor: Equatable {
        let createdBefore: Date
        let revisionID: UUID
    }

    init(
        gateway: any WidgetCanvasGateway,
        identity: WidgetSyncIdentity,
        pageSize: Int = 30,
        exporter: any WidgetRevisionThumbnailLoading = NoOpWidgetRevisionThumbnailLoader()
    ) {
        self.gateway = gateway
        self.identity = identity
        self.pageSize = pageSize
        self.exporter = exporter
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

    /// Adds drawings newer than the loaded ones, for example a partner's drawing
    /// that synced in while the timeline is open. Keeps the scroll position, the
    /// older-page cursor, and the save states. Failures are ignored because the
    /// list on screen is still correct.
    func refreshNewest() async {
        guard phase == .loaded else {
            return
        }
        guard let canvasID else {
            // The first load found no canvas, so there is nothing to merge into yet.
            await loadFirstPage()
            return
        }
        let generation = loadGeneration
        guard let page = try? await gateway.listRevisions(
            canvasID: canvasID,
            limit: pageSize,
            createdBefore: nil,
            createdBeforeRevisionID: nil
        ), generation == loadGeneration else {
            return
        }
        // A full page with nothing already loaded in it may have more new drawings
        // behind it, which would leave a gap above the older rows. Start over.
        if page.count == pageSize, !page.contains(where: { seenRevisionIDs.contains($0.revisionID) }) {
            await loadFirstPage()
            return
        }
        items.insert(contentsOf: newItems(from: page), at: 0)
    }

    /// The outbox is the durable local overlay until the server accepts the correction.
    func refreshDescriptions(service: MediaAlternativeEditingService?, context: ThreadChatContext) async {
        guard let service, let owner = context.participants.currentUserID, owner == identity.currentUserID,
              let couple = context.coupleID, couple == loadedCoupleID else { return }
        descriptionsGeneration += 1
        let generation = descriptionsGeneration
        let token = LocalPrivacyWriteGuard.shared.token(ownerUserID: owner)
        for item in items where item.isMine {
            let target = MediaAlternativeTarget.widgetDrawing(revisionID: item.id)
            let pending: PendingMediaAlternative?
            do {
                pending = try await service.pendingEdit(ownerUserID: owner, coupleID: couple, target: target)
            } catch {
                // A failed outbox read cannot establish that a correction completed.
                continue
            }
            guard generation == descriptionsGeneration, !Task.isCancelled,
                  LocalPrivacyWriteGuard.shared.isCurrent(token) else { return }
            guard items.contains(where: { $0.id == item.id }) else { continue }
            if let pending {
                pendingDescriptionOperations[item.id] = pending.operationID
                // The row's editor owns the pending overlay. Keep the server text and version together.
            } else if pendingDescriptionOperations.removeValue(forKey: item.id) != nil {
                let accepted = await MediaAlternativeCacheWrites.shared.acceptedWidgetDescription(
                    ownerUserID: owner, target: target
                )
                guard generation == descriptionsGeneration, !Task.isCancelled,
                      LocalPrivacyWriteGuard.shared.isCurrent(token),
                      let currentIndex = items.firstIndex(where: { $0.id == item.id }) else { return }
                if let accepted, items[currentIndex].descriptionVersion.map({ accepted.version >= $0 }) ?? true {
                    items[currentIndex].accessibilityText = accepted.text.trimmedNonEmpty
                    items[currentIndex].descriptionVersion = accepted.version
                }
            }
        }
    }

    func prepareShare(for item: WidgetDrawingHistoryItem, service: MediaAlternativeEditingService?,
                      context: ThreadChatContext) async throws -> PaeoniaShareable {
        guard let owner = context.participants.currentUserID, owner == identity.currentUserID,
              let couple = context.coupleID, couple == loadedCoupleID else {
            throw MediaAlternativeEditingError.privacyChanged
        }
        let token = LocalPrivacyWriteGuard.shared.token(ownerUserID: owner)
        var shared = items.first(where: { $0.id == item.id }) ?? item
        if item.isMine, let service {
            let pending = try await service.pendingEdit(ownerUserID: owner, coupleID: couple,
                                                        target: .widgetDrawing(revisionID: item.id))
            guard LocalPrivacyWriteGuard.shared.isCurrent(token), !Task.isCancelled else {
                throw MediaAlternativeEditingError.privacyChanged
            }
            if let pending { shared.accessibilityText = pending.text.trimmedNonEmpty }
        }
        guard LocalPrivacyWriteGuard.shared.isCurrent(token), !Task.isCancelled else {
            throw MediaAlternativeEditingError.privacyChanged
        }
        return shareable(for: shared)
    }

    /// What the share sheet offers for a drawing: the drawing at full quality on
    /// its plum canvas, with the date it was sent. Either partner's drawing can
    /// be shared, since it is a picture the two of them made together.
    func shareable(for item: WidgetDrawingHistoryItem) -> PaeoniaShareable {
        let exporter = exporter
        return PaeoniaShareable(title: String(localized: .shareTitleDrawing), text: item.accessibilityText) {
            guard let png = await exporter.exportPNG(
                revisionID: item.id,
                mediaAssetID: item.mediaAssetID,
                canvasSide: item.canvasSide
            ), let ink = UIImage(data: png) else {
                return nil
            }
            return PaeoniaShareCards.drawing(
                ink: ink,
                subtitle: item.createdAt.formatted(date: .long, time: .omitted)
            )
        }
    }

    func loadMoreIfNeeded(currentItem: WidgetDrawingHistoryItem) async {
        // After a failure the retry row is the only way to try again. Scrolling
        // must not keep re-sending a request that just failed.
        guard !loadMoreFailed, canLoadMore, shouldLoadMore(after: currentItem) else {
            return
        }
        await loadMore()
    }

    func retryLoadMore() async {
        guard canLoadMore else {
            return
        }
        await loadMore()
    }

    private var canLoadMore: Bool {
        phase == .loaded && hasMore && !isLoadingMore && cursor != nil
    }

    private func loadMore() async {
        let generation = loadGeneration
        isLoadingMore = true
        loadMoreFailed = false
        defer {
            if generation == loadGeneration {
                isLoadingMore = false
            }
        }
        do {
            try await fetchUntilProgressOrEnd(generation: generation)
        } catch {
            if generation == loadGeneration {
                // The list stays as it is and `hasMore` stays true for the retry.
                loadMoreFailed = true
            }
        }
    }

    private func loadFirstPage() async {
        loadGeneration += 1
        let generation = loadGeneration
        phase = .loading
        items = []
        cursor = nil
        seenRevisionIDs = []
        hasMore = true
        isLoadingMore = false
        loadMoreFailed = false

        do {
            guard let state = try await gateway.getCanvasState() else {
                guard generation == loadGeneration else {
                    return
                }
                // No canvas yet (e.g. not paired) means no drawings to show.
                canvasID = nil
                loadedCoupleID = nil
                hasMore = false
                phase = .loaded
                return
            }
            guard generation == loadGeneration else {
                return
            }
            canvasID = state.canvasID
            loadedCoupleID = state.coupleID
            try await fetchUntilProgressOrEnd(generation: generation)
            if generation == loadGeneration {
                phase = .loaded
            }
        } catch {
            if generation == loadGeneration {
                phase = .failed(PaeoniaFailure(error))
            }
        }
    }

    /// Fetches pages from the current cursor until at least one showable drawing
    /// is added or there are no more pages. The RPC can return a full page made
    /// entirely of hidden/deleted revisions (payload nulled), which yields no
    /// items but must still advance the cursor — otherwise the timeline would
    /// show a false empty state with no row available to trigger the next page.
    ///
    /// Stops early, leaving state untouched, once a newer first-page load has
    /// started (`generation` no longer matches `loadGeneration`).
    private func fetchUntilProgressOrEnd(generation: Int) async throws {
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
            guard generation == loadGeneration else {
                return
            }
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

        items.append(contentsOf: newItems(from: page))
    }

    /// The showable rows of `page` not yet in the timeline, marked as seen.
    private func newItems(from page: [WidgetDrawingRevisionSummary]) -> [WidgetDrawingHistoryItem] {
        page.compactMap { summary -> WidgetDrawingHistoryItem? in
            guard let mediaAssetID = summary.payloadMediaAssetID else { return nil }
            if let index = items.firstIndex(where: { $0.id == summary.revisionID }) {
                if items[index].descriptionVersion == nil || summary.descriptionVersion.map({ version in
                    items[index].descriptionVersion.map { version >= $0 } ?? true
                }) == true {
                    items[index].accessibilityText = summary.bounds?.accessibilityText
                    items[index].descriptionVersion = summary.descriptionVersion
                }
                return nil
            }
            guard !seenRevisionIDs.contains(summary.revisionID) else { return nil }
            seenRevisionIDs.insert(summary.revisionID)
            let isMine = summary.authorUserID != nil && summary.authorUserID == identity.currentUserID
            return WidgetDrawingHistoryItem(
                id: summary.revisionID,
                authorName: WidgetCanvasSyncService.authorName(for: summary.authorUserID, identity: identity),
                isMine: isMine,
                createdAt: summary.createdAt,
                mediaAssetID: mediaAssetID,
                canvasSide: summary.bounds.map { CGFloat($0.canvasSide) } ?? WidgetDrawingViewModel.fallbackCanvasSide,
                accessibilityText: summary.bounds?.accessibilityText, descriptionVersion: summary.descriptionVersion
            )
        }
    }
}
