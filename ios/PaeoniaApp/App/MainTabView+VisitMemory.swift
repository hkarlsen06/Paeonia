import SwiftUI

extension MainTabView {
    /// After a save from the Us tab's visit photo card: the memory's screen in the Memories tab, the
    /// way the look-back card opens a memory, where it celebrates once (`MemoryCelebration`).
    func openSavedVisitMemory(_ memoryID: UUID) {
        memoriesViewModel.celebrationRequestedMemoryID = memoryID
        selection.wrappedValue = .memories
        memoriesPath = [memoryID]
    }
}
