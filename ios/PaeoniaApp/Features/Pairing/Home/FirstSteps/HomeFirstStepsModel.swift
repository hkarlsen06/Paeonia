import Foundation
import Observation

/// The saved state of Home's "Things to try together" card for the current pair, and
/// whether this person has saved a memory. `MainTabView` builds the card from this and
/// from the other tabs' view models (`MainTabView+FirstSteps.swift`).
///
/// The Memories tab reads its list only when it opens, so this reads the memories on the
/// phone itself, and only while the card still waits for a memory.
@MainActor
@Observable
final class HomeFirstStepsModel {
    /// Nil while there is no pair, or its first day sequence has not finished on this phone.
    private(set) var progress: HomeFirstStepsProgress?
    /// This person saved a memory that is on this phone. Nil until read.
    private(set) var hasOwnMemory: Bool?

    @ObservationIgnored private let store: any PairingCelebrationStoring
    @ObservationIgnored private let memoryService: any MemoryDataServicing
    @ObservationIgnored private var pairID: UUID?

    init(store: any PairingCelebrationStoring, memoryService: any MemoryDataServicing) {
        self.store = store
        self.memoryService = memoryService
    }

    /// Reads the pair's saved card, then follows this person's memories until one is saved.
    /// Runs until the calling task is cancelled.
    func load(pairID: UUID?, ownerUserID: UUID?) async {
        self.pairID = pairID
        progress = nil
        hasOwnMemory = nil
        guard let pairID, store.postPairingProgress(forPairID: pairID)?.isFinished == true else { return }
        let saved = store.homeFirstSteps(forPairID: pairID)
        progress = saved
        guard !saved.isClosed, !saved.doneSteps.contains(.memory), let ownerUserID else { return }

        // Subscribed before the first read, so a memory saved while it runs still arrives.
        let changes = LocalStoreChanges.changes(in: .memories)
        await readOwnMemory(ownerUserID: ownerUserID)
        for await change in changes {
            guard !Task.isCancelled, hasOwnMemory != true, progress?.isClosed == false else { return }
            guard change.ownerUserID == nil || change.ownerUserID == ownerUserID else { continue }
            await readOwnMemory(ownerUserID: ownerUserID)
        }
    }

    /// Ticks the rows seen done, for good.
    func record(_ doneSteps: Set<HomeFirstStep>) {
        guard let pairID, var progress, !doneSteps.isSubset(of: progress.doneSteps) else { return }
        progress.doneSteps.formUnion(doneSteps)
        save(progress, pairID: pairID)
    }

    func close() {
        guard let pairID, var progress else { return }
        progress.isClosed = true
        save(progress, pairID: pairID)
    }

    private func save(_ progress: HomeFirstStepsProgress, pairID: UUID) {
        self.progress = progress
        store.saveHomeFirstSteps(progress, forPairID: pairID)
    }

    private func readOwnMemory(ownerUserID: UUID) async {
        let records = (try? await memoryService.loadCachedMemories(ownerUserID: ownerUserID, includeHidden: false))
        guard !Task.isCancelled, let records else { return }
        hasOwnMemory = records.contains { $0.snapshot.createdByUserID == ownerUserID }
    }
}
