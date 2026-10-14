import SwiftUI

/// Three dots that breathe in turn while the partner writes. They keep breathing
/// under Reduce Motion, because they only change opacity and never move.
struct StoryChainTypingDots: View {
    var ink: Color = .paeoniaTextTertiary

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isBreathing = false

    private static let dotSize: CGFloat = 7
    private static let beat: TimeInterval = 0.6
    private static let stagger: TimeInterval = 0.18

    var body: some View {
        HStack(spacing: PaeoniaSpacing.space4) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(ink)
                    .frame(width: Self.dotSize, height: Self.dotSize)
                    .scaleEffect(reduceMotion || isBreathing ? 1 : 0.6)
                    .opacity(isBreathing ? 1 : 0.3)
                    .animation(
                        .easeInOut(duration: Self.beat)
                            .repeatForever(autoreverses: true)
                            .delay(Double(index) * Self.stagger),
                        value: isBreathing
                    )
            }
        }
        .padding(.vertical, PaeoniaSpacing.space4)
        .accessibilityHidden(true)
        .onAppear {
            isBreathing = true
        }
    }
}

#if DEBUG
#Preview {
    StoryChainTypingDots(ink: .paeoniaAccentPrimary)
        .padding()
        .background(.paeoniaBackgroundPrimary)
}
#endif
