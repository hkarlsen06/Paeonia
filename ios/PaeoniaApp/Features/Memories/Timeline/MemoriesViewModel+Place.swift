import Foundation

extension MemoriesViewModel {
    /// Sets or clears one memory's place, from the map's list of memories without one.
    /// The place is saved on this phone and sent later, and the service trims it to what
    /// the server accepts, so it can only fail here: when the memory is gone, or the
    /// phone couldn't write it. Returns whether it was saved.
    @discardableResult
    func setPlace(_ place: MemoryPlace?, forMemory memoryID: UUID) async -> Bool {
        guard let currentUserID else { return false }
        let saved = await perform("Saving a memory place failed", notice: .editFailed) {
            _ = try await self.memoryService.setMemoryPlace(
                ownerUserID: currentUserID,
                memoryID: memoryID,
                place: place,
                operation: self.operationProvider.makeOperation()
            )
        }
        guard saved else {
            await load()
            return false
        }
        PaeoniaHaptics.memorySaved()
        await load()
        syncInBackground()
        return true
    }

    /// Sends the place only when the person changed it in the form, so a place the
    /// partner set while the form was open stays.
    func savePlace(_ edit: MemoryEdit, _ latest: MemoryRecord, _ userID: UUID) async -> StepResult {
        guard edit.place != edit.base.snapshot.place, edit.place != latest.snapshot.place else {
            return .unchanged
        }
        let saved = await perform("Saving a memory place failed", notice: .editFailed) {
            _ = try await self.memoryService.setMemoryPlace(
                ownerUserID: userID,
                memoryID: latest.snapshot.memoryID,
                place: edit.place,
                operation: self.operationProvider.makeOperation()
            )
        }
        return saved ? .saved : .failed
    }
}
