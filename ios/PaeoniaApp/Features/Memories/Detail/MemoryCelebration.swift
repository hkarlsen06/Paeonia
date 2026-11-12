import SwiftUI

/// The moment a memory saved from the Us tab's visit photo card arrives on its screen: a haptic and
/// petals fired from both bottom corners that fill the screen and fall for about three seconds. It
/// plays once, when `MemoriesViewModel.celebrationRequestedMemoryID` names this screen's memory, and
/// clears it. Under Reduce Motion the petals don't draw and only the haptic plays. The petals take
/// no taps and VoiceOver doesn't see them.
struct MemoryCelebration: ViewModifier {
    let memoryID: UUID
    let viewModel: MemoriesViewModel

    @State private var start: Date?

    /// Seconds for the screen to slide in first.
    private static let delay: TimeInterval = 0.35
    private static let length = MemoryPetalShower.duration

    func body(content: Content) -> some View {
        content
            .overlay {
                if let start {
                    MemoryPetalShower(start: start, seed: "memory.\(memoryID)")
                        .ignoresSafeArea()
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
            .onChange(of: viewModel.celebrationRequestedMemoryID, initial: true) { _, requested in
                guard requested == memoryID else { return }
                viewModel.celebrationRequestedMemoryID = nil
                Task { await celebrate() }
            }
    }

    private func celebrate() async {
        start = Date().addingTimeInterval(Self.delay)
        try? await Task.sleep(for: .seconds(Self.delay))
        PaeoniaHaptics.memoryCelebrated()
        try? await Task.sleep(for: .seconds(Self.length))
        start = nil
    }
}
