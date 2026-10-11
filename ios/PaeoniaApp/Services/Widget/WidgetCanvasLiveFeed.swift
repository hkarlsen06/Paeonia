import Foundation

/// Keeps the app and widget canvas current while the app is open.
///
/// Subscribes to the couple's canvas. When the active revision differs from the
/// one this device last showed, it runs the normal sync (download, save,
/// notify, reload widget timelines). `get_or_create_widget_canvas` stays in the
/// upload path, so this feed only reads. Syncs go through the shared sync
/// service, which coalesces overlapping runs, and the feed awaits each one
/// before it reads the next canvas update.
nonisolated struct WidgetCanvasLiveFeed: LiveFeed {
    let name = "widgetCanvas"

    private let syncer: any WidgetCanvasSyncing
    private let lastSyncedRevisionID: @Sendable () -> String?
    private let storedIdentity: @Sendable () -> WidgetSyncIdentity
    private let hasPendingUpload: @Sendable () -> Bool

    init(
        syncer: any WidgetCanvasSyncing,
        lastSyncedRevisionID: @escaping @Sendable () -> String? = { WidgetCanvasSyncService.lastSyncedRevisionID() },
        storedIdentity: @escaping @Sendable () -> WidgetSyncIdentity = { WidgetSyncIdentityStore.shared.load() },
        hasPendingUpload: @escaping @Sendable () -> Bool = { WidgetPendingUploadStore.shared.hasPending }
    ) {
        self.syncer = syncer
        self.lastSyncedRevisionID = lastSyncedRevisionID
        self.storedIdentity = storedIdentity
        self.hasPendingUpload = hasPendingUpload
    }

    func run(session: SyncSession, live: LiveQueryService) async {
        guard let coupleID = session.activeCoupleID else {
            return
        }

        let updates = live.subscribe(
            "widget:get_widget_canvas",
            args: ["p_couple_id": coupleID.uuidString],
            as: [WidgetCanvasState].self
        )
        for await update in updates {
            guard !Task.isCancelled else {
                return
            }
            guard case let .value(rows) = update else {
                continue
            }
            // A new result also arrives when the connection comes back. That is
            // the moment to retry a drawing that is still waiting to be sent,
            // even when the canvas itself did not change.
            let revisionID = rows.first?.activeRevisionID
            let isNewRevision = revisionID.map { $0.uuidString != lastSyncedRevisionID() } ?? false
            guard isNewRevision || hasPendingUpload() else {
                continue
            }

            // The signed-in user is known from the session even before the
            // stored names exist, so our own revision is never pulled back.
            let stored = storedIdentity()
            await syncer.sync(
                identity: WidgetSyncIdentity(
                    currentUserID: session.userID,
                    currentDisplayName: stored.currentDisplayName,
                    partnerDisplayName: stored.partnerDisplayName
                )
            )
        }
    }
}
