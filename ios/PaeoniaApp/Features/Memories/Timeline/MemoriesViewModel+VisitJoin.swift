import Foundation

extension MemoriesViewModel {
    func joinedVisitMemories(
        leaving previous: [MemoryRecord],
        for records: [MemoryRecord],
        ownerUserID: UUID
    ) async -> [UUID: UUID] {
        let shown = Set(records.map(\.snapshot.memoryID))
        var joins: [UUID: UUID] = [:]
        for left in previous where !shown.contains(left.snapshot.memoryID) {
            guard let visitID = left.snapshot.visitID,
                  let joined = records.filter({ $0.snapshot.visitID == visitID })
                      .min(by: { $0.snapshot.createdAt < $1.snapshot.createdAt }),
                  await isNotStored(left.snapshot.memoryID, ownerUserID: ownerUserID)
            else { continue }
            joins[left.snapshot.memoryID] = joined.snapshot.memoryID
        }
        return joins
    }

    private func isNotStored(_ memoryID: UUID, ownerUserID: UUID) async -> Bool {
        do {
            return try await memoryService.loadCachedMemory(ownerUserID: ownerUserID, memoryID: memoryID) == nil
        } catch {
            return false
        }
    }

    /// Says the memory was deleted only when it did not join another memory for its visit. When
    /// it joined, `joinedNotice` says what happened instead, if the screen does not already.
    func noticeRemovalUnlessJoined(_ memoryID: UUID, joinedNotice: MemoriesNotice? = nil) async {
        await load()
        if record(for: memoryID) == nil {
            notice = .memoryRemoved
        } else if let joinedNotice {
            notice = joinedNotice
        }
    }

    /// The person confirmed deleting `waiting`, which had joined `joined` meanwhile. Their photos
    /// from it and their note leave the joined memory. Nothing of the partner's is touched.
    func takeTheirPart(of waiting: MemoryRecord, off joined: MemoryRecord) async {
        guard let currentUserID else { return }
        let theirs = Set(waiting.snapshot.media.filter { $0.ownerUserID == currentUserID }.map(\.memoryMediaID))
        do {
            for media in joined.snapshot.media
            where media.isVisible && media.ownerUserID == currentUserID && theirs.contains(media.memoryMediaID) {
                _ = try await memoryService.removeMemoryMedia(
                    ownerUserID: currentUserID, memoryID: joined.snapshot.memoryID,
                    memoryMediaID: media.memoryMediaID, operation: operationProvider.makeOperation()
                )
            }
            _ = try await memoryService.deleteOwnNote(
                ownerUserID: currentUserID, memoryID: joined.snapshot.memoryID,
                operation: operationProvider.makeOperation()
            )
        } catch {
            report("Taking their part off a joined memory failed", error, notice: .deleteFailed)
            await load()
            return
        }
        PaeoniaHaptics.destructiveActionConfirmed()
        notice = .ownPartRemovedAfterJoin
        await load()
        syncInBackground()
    }
}
