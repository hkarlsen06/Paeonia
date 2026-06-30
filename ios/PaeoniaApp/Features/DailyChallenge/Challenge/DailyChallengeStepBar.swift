import SwiftUI

/// A segmented progress bar for the daily challenge. Each segment is one of the
/// day's questions: filled segments are answered, an optional `current` segment
/// is highlighted while the user is on it. Shared between the compact Us-tab card
/// and the full answering flow so the "three steps" read identically in both.
struct DailyChallengeStepBar: View {
    let total: Int
    let completed: Int
    var current: Int?
    var height: CGFloat
    /// When set, segments become tappable so the user can jump to that step.
    var onSelect: ((Int) -> Void)?

    init(
        total: Int,
        completed: Int,
        current: Int? = nil,
        height: CGFloat = 6,
        onSelect: ((Int) -> Void)? = nil
    ) {
        self.total = total
        self.completed = completed
        self.current = current
        self.height = height
        self.onSelect = onSelect
    }

    private var segmentCount: Int { max(total, 1) }

    var body: some View {
        HStack(spacing: PaeoniaSpacing.space4) {
            ForEach(0..<segmentCount, id: \.self) { index in
                segment(at: index)
            }
        }
        .animation(PaeoniaMotion.stateChange, value: completed)
        .animation(PaeoniaMotion.stateChange, value: current)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(.dailyChallengeProgressAccessibilityLabel))
        .accessibilityValue(Text(verbatim: "\(completed)/\(segmentCount)"))
    }

    @ViewBuilder
    private func segment(at index: Int) -> some View {
        if let onSelect {
            Button { onSelect(index) } label: { fill(at: index) }
                .buttonStyle(.plain)
        } else {
            fill(at: index)
        }
    }

    private func fill(at index: Int) -> some View {
        let isCompleted = index < completed
        let isCurrent = index == current
        let shape = Capsule(style: .continuous)

        return shape
            .fill(isCompleted ? Color.paeoniaAccentPrimary : Color.paeoniaSurfaceSecondary)
            .frame(height: height)
            .overlay {
                // A faint fill marks the step the user is on but hasn't answered,
                // so the bar reads as "you are here" without looking complete.
                if isCurrent, !isCompleted {
                    shape.fill(Color.paeoniaAccentPrimary.opacity(0.3))
                }
            }
            .overlay {
                if isCurrent {
                    shape.stroke(Color.paeoniaAccentPrimary, lineWidth: PaeoniaRadius.strokeEmphasis)
                }
            }
    }
}

#if DEBUG
#Preview {
    VStack(spacing: PaeoniaSpacing.space24) {
        DailyChallengeStepBar(total: 3, completed: 1)
        DailyChallengeStepBar(total: 3, completed: 1, current: 1, height: 8)
        DailyChallengeStepBar(total: 3, completed: 3, height: 8)
    }
    .padding(PaeoniaSpacing.screenHorizontalPadding)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(.paeoniaBackgroundPrimary)
    .preferredColorScheme(.dark)
}
#endif
