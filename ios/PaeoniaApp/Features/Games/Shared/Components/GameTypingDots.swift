import SwiftUI

/// Decorative dots. The adjacent localized text names the actual writing signal.
struct GameTypingDots: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .caption) private var dotSize: CGFloat = 5

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: reduceMotion)) { context in
            HStack(spacing: dotSize * 0.6) {
                ForEach(0..<3, id: \.self) { index in
                    Circle()
                        .frame(width: dotSize, height: dotSize)
                        .opacity(opacity(at: context.date, index: index))
                }
            }
        }
        .foregroundStyle(.paeoniaTextSecondary)
        .accessibilityHidden(true)
    }

    private func opacity(at date: Date, index: Int) -> Double {
        guard !reduceMotion else { return 1 }
        let phase = date.timeIntervalSinceReferenceDate * 5 - Double(index) * 0.9
        return 0.65 + 0.35 * sin(phase)
    }
}
