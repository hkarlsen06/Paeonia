import SwiftUI

/// The moment a memory saved from the Us tab's visit photo card arrives on its screen: the petal
/// shower, once, when `MemoriesViewModel.celebrationRequestedMemoryID` names this screen's memory.
/// It clears the request so the shower doesn't replay.
struct MemoryCelebration: ViewModifier {
    let memoryID: UUID
    let viewModel: MemoriesViewModel

    @Environment(\.petalShower) private var petalShower

    func body(content: Content) -> some View {
        content
            .onChange(of: viewModel.celebrationRequestedMemoryID, initial: true) { _, requested in
                guard requested == memoryID else { return }
                viewModel.celebrationRequestedMemoryID = nil
                // Lets the screen slide in first.
                petalShower(seed: "memory.\(memoryID)", after: 0.35)
            }
    }
}
