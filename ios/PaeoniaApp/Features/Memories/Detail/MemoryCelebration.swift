import SwiftUI

/// The moment a memory saved from the Us tab's visit photo card arrives on its screen: a haptic and
/// two bursts of petals over the screen, about a second and a half. It plays once, when
/// `MemoriesViewModel.celebrationRequestedMemoryID` names this screen's memory, and clears it. Under
/// Reduce Motion the petals don't draw and only the haptic plays. The petals take no taps and
/// VoiceOver doesn't see them.
struct MemoryCelebration: ViewModifier {
    let memoryID: UUID
    let viewModel: MemoriesViewModel

    @State private var start: Date?

    /// Seconds for the screen to slide in first.
    private static let delay: TimeInterval = 0.35
    /// Seconds until both bursts are over.
    private static let length: TimeInterval = 1.6

    func body(content: Content) -> some View {
        content
            .overlay {
                if let start {
                    ZStack {
                        GamePetalBloom(start: start, seed: "memory.\(memoryID)", origin: UnitPoint(x: 0.5, y: 0.3))
                        GamePetalBloom(
                            start: start.addingTimeInterval(0.55),
                            seed: "memory.\(memoryID).second",
                            origin: UnitPoint(x: 0.5, y: 0.35),
                            intensity: 0.6
                        )
                    }
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
