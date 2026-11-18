#if DEBUG
import Foundation
import PencilKit

/// Delays independent Home reads while keeping the production root and local stores.
struct DeveloperHomeLaunchTiming {
    let location: Duration
    let question: Duration
    let calendar: Duration
    /// The partner has sharing on, but their first place arrives this long after `location`,
    /// as when a couple comes back and the partner's phone sends where it is. Nil sends
    /// both places at `location`.
    var partnerLocationLater: Duration?
    /// When the partner's drawing reaches the Home tile. Nil leaves the tile on the
    /// simulator's own widget files.
    var drawing: Duration?

    static let duringReveal = Self(
        location: .milliseconds(40), question: .milliseconds(80), calendar: .milliseconds(120)
    )
    static let locationFirst = Self(location: .seconds(0.7), question: .seconds(1.6), calendar: .seconds(2.3))
    static let calendarFirst = Self(location: .seconds(2.3), question: .seconds(1.6), calendar: .seconds(0.7))
    static let overlapping = Self(location: .seconds(2.7), question: .seconds(1.6), calendar: .seconds(2.0))
    /// Right after the couple comes back, as recorded on a phone: the server says the partner
    /// shares before their phone has sent a place, and the streak and drawing follow.
    static let afterRestore = Self(
        location: .milliseconds(300), question: .milliseconds(500), calendar: .milliseconds(200),
        partnerLocationLater: .milliseconds(1_100), drawing: .seconds(1)
    )

    func seedMap(
        visibility: InMemoryLocationVisibilityRepository,
        ownLocation: InMemoryOwnLocationSnapshotRepository,
        partnerLocated: Bool = true
    ) async throws {
        let owner = DeveloperScenarioFixture.currentUserID
        let couple = DeveloperScenarioFixture.coupleID
        let now = Date()
        try await ownLocation.save(OwnLocationSnapshot(
            ownerUserID: owner, coupleID: couple,
            location: LocationPoint(latitude: 59.9139, longitude: 10.7522, capturedAt: now),
            source: .foregroundOpen, pendingOperationID: nil, updatedAt: now
        ))
        try await visibility.save(LocationVisibilitySnapshot(
            ownerUserID: owner, coupleID: couple, viewerUserID: owner,
            partnerUserID: DeveloperScenarioFixture.partnerUserID,
            visibilityState: partnerLocated ? .visible : .notSharing,
            viewerSharingEnabled: true, partnerSharingEnabled: true,
            partnerLocation: partnerLocated ? LocationPoint(latitude: 59.94, longitude: 10.79, capturedAt: now) : nil,
            partnerLocationIsStale: false, updatedAt: now, refreshedAt: now
        ))
    }
}

/// The Home tile's drawing in a folder of the scenario's own, so the simulator's widget is untouched.
struct DeveloperHomeDrawing {
    let directory: URL
    private let canvas: WidgetCanvasService

    init() {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("DeveloperHomeDrawing-\(UUID().uuidString)", isDirectory: true)
        canvas = WidgetCanvasService(
            appGroupContainerURL: directory,
            canonicalDrawingURL: directory.appendingPathComponent("current.pkdrawing"),
            reloader: NoWidgetReload(),
            sharedDefaults: nil
        )
    }

    var loader: HomeWidgetPreviewLoader { HomeWidgetPreviewLoader(containerURL: directory) }

    /// Saves the partner's heart, which tells the open tile to read it again.
    func partnerDrew() async throws {
        let side = WidgetDrawingViewModel.fallbackCanvasSide
        try await canvas.saveDescribedDrawing(
            DeveloperPostPairingFixture.heart().dataRepresentation(),
            canvasSize: CGSize(width: side, height: side), authorName: "Robin",
            createdAt: Date(), revisionID: UUID(), accessibilityText: nil, publicationID: nil
        )
    }

    private struct NoWidgetReload: WidgetTimelineReloading {
        // swiftlint:disable:next async_without_await
        func reloadWidget() async {}
    }
}

actor DeveloperDelayedStartedOnService {
    let base: any RelationshipStartedOnDataServicing
    let delay: Duration

    init(base: any RelationshipStartedOnDataServicing, delay: Duration) {
        self.base = base
        self.delay = delay
    }
}

extension DeveloperDelayedStartedOnService: RelationshipStartedOnDataServicing {
    func loadStartedOn(ownerUserID: UUID) async throws -> RelationshipStartedOnLocalState {
        try await Task.sleep(for: delay)
        return try await base.loadStartedOn(ownerUserID: ownerUserID)
    }

    func setStartedOn(_ startedOn: PairingStartDate, ownerUserID: UUID, operation: SyncClientOperation) async throws {
        try await base.setStartedOn(startedOn, ownerUserID: ownerUserID, operation: operation)
    }
}
#endif
