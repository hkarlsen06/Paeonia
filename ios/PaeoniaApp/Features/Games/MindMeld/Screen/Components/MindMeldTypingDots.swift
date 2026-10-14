import SwiftUI

/// Three dots that rise in turn, next to "[Name] is typing". Under Reduce Motion
/// they stand still. The line beside them carries the meaning, so VoiceOver skips them.
struct MindMeldTypingDots: View {
    private static let dotCount = 3
    private static let rise: CGFloat = 3
    private static let stagger: TimeInterval = 0.12

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .caption) private var dotSize: CGFloat = 5
    @State private var isRaised = false

    var body: some View {
        HStack(spacing: dotSize * 0.6) {
            ForEach(0..<Self.dotCount, id: \.self) { index in
                Circle()
                    .frame(width: dotSize, height: dotSize)
                    .offset(y: isRaised ? -Self.rise : 0)
                    .animation(reduceMotion ? nil : bounce(for: index), value: isRaised)
            }
        }
        .foregroundStyle(.paeoniaTextSecondary)
        .onAppear { isRaised = !reduceMotion }
        .accessibilityHidden(true)
    }

    /// Each dot repeats the same rise and fall, started a little after the one before.
    private func bounce(for index: Int) -> Animation {
        PaeoniaMotion.standardCurve(duration: PaeoniaMotion.motionDefault)
            .repeatForever(autoreverses: true)
            .delay(Double(index) * Self.stagger)
    }
}

#if DEBUG
#Preview {
    HStack(spacing: PaeoniaSpacing.space8) {
        MindMeldTypingDots()
        Text(verbatim: "Robin is typing")
            .font(PaeoniaTypography.caption)
            .foregroundStyle(.paeoniaTextSecondary)
    }
    .padding()
    .background(.paeoniaBackgroundSecondary)
}
#endif
