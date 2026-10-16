import Foundation
import PencilKit
@testable import PaeoniaApp

extension CorpseSimPhone {
    // MARK: - Sync

    /// One sync run, like `PaeoniaSyncService.performRun`: in-flight writes go
    /// back to retrying, then the drain sends everything that waits. A request
    /// during a run asks for one more run after it.
    func sync() async {
        guard isAlive else { return }
        if let syncTask {
            syncFollowUp = true
            await syncTask.value
            return
        }
        let task = Task { [weak self] in
            guard let self else { return }
            repeat {
                syncFollowUp = false
                await runSyncOnce()
            } while syncFollowUp && !Task.isCancelled && isAlive
        }
        syncTask = task
        await task.value
        if syncTask == task {
            syncTask = nil
        }
    }

    var isSyncing: Bool {
        syncTask != nil
    }

    private func runSyncOnce() async {
        guard let drain else { return }
        try? await pending.resetInFlight(ownerUserID: userID)
        let context = SyncContext(
            session: SyncSession(userID: userID),
            // A settled phone has waited out every retry delay, so the run tries all writes.
            reason: .manualRefresh,
            stateStore: InMemorySyncStateRepository(),
            pendingOperationStore: pending
        )
        try? await drain.push(context: context)
    }

    // MARK: - Live feed

    /// Delivers the server's state as the `exquisiteCorpse:get_exquisite_corpse`
    /// and `games:get_games_overview` subscriptions would.
    func feedTick() async {
        let isUp = isAlive && isForeground && network.isOnline && !isFeedOutage
        guard isUp else {
            feedWasUp = false
            return
        }
        if !feedWasUp {
            // A new subscription starts from the current value.
            feedWasUp = true
            feedQueue = []
            feedCapturedVersion = -1
        }
        if server.viewVersion != feedCapturedVersion {
            feedCapturedVersion = server.viewVersion
            feedQueue.append((server.state(for: userID), server.overview(for: userID)))
        }
        guard !feedQueue.isEmpty else { return }
        let (state, overview) = isFeedDelayed ? feedQueue.removeFirst() : feedQueue.removeLast()
        if !isFeedDelayed {
            feedQueue = []
        }
        await corpseCache.saveState(state, ownerUserID: userID)
        await overviewCache.saveOverview(overview, ownerUserID: userID)
        LocalStoreChanges.post(.games, ownerUserID: userID)
    }
}
