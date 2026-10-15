import SwiftUI

/// A segmented progress bar for the daily challenge. Each segment is one of the
/// day's questions: filled segments are answered, an optional `current` segment
/// is highlighted while the user is on it. Shared between the compact Home tab card
/// and the full answering flow so the steps read identically in both.
struct DailyChallengeStepBar: View {
    let total: Int
    /// Which segments are answered. The flow passes the real steps, because the user
    /// can jump ahead and answer the second question before the first. The Home card
    /// only knows a count, so it fills from the start.
    let completedSteps: Set<Int>
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
        self.init(
            total: total,
            completedSteps: Set(0..<max(completed, 0)),
            current: current,
            height: height,
            onSelect: onSelect
        )
    }

    init(
        total: Int,
        completedSteps: Set<Int>,
        current: Int? = nil,
        height: CGFloat = 6,
        onSelect: ((Int) -> Void)? = nil
    ) {
        self.total = total
        self.completedSteps = completedSteps
        self.current = current
        self.height = height
        self.onSelect = onSelect
    }

    private var segmentCount: Int { max(total, 1) }

    private var completedCount: Int {
        completedSteps.filter { (0..<segmentCount).contains($0) }.count
    }

    var body: some View {
        let bar = HStack(spacing: PaeoniaSpacing.space4) {
            ForEach(0..<segmentCount, id: \.self) { index in
                segment(at: index)
            }
        }
        // The answering flow (the tappable bar) always keeps room for the taller
        // current segment, so the bar doesn't jump on steps with no current segment.
        .frame(height: onSelect == nil && current == nil ? height : currentHeight)
        .animation(PaeoniaMotion.stateChange, value: completedSteps)
        .animation(PaeoniaMotion.stateChange, value: current)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(.dailyChallengeProgressAccessibilityLabel))
        .accessibilityValue(Text(.dailyChallengeProgressPillAccessibility(completedCount, segmentCount)))

        if let onSelect {
            // VoiceOver users swipe up or down to move between questions, the same
            // jump sighted users get by tapping a segment.
            bar.accessibilityAdjustableAction { direction in
                let from = current ?? 0
                switch direction {
                case .increment where from + 1 < segmentCount: onSelect(from + 1)
                case .decrement where from > 0: onSelect(from - 1)
                default: break
                }
            }
        } else {
            bar
        }
    }

    @ViewBuilder
    private func segment(at index: Int) -> some View {
        if let onSelect {
            Button { onSelect(index) } label: {
                // The bar is only a few points tall, so the tap area is padded to a
                // comfortable size without changing how the bar looks or sits.
                fill(at: index)
                    .padding(.vertical, PaeoniaSpacing.space16)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.vertical, -PaeoniaSpacing.space16)
        } else {
            fill(at: index)
        }
    }

    private func fill(at index: Int) -> some View {
        let isCompleted = completedSteps.contains(index)
        let isCurrent = index == current
        let shape = Capsule(style: .continuous)

        // The step the user is on stands taller than the rest. If it isn't answered
        // yet, a faint fill marks it without making it look complete.
        return shape
            // Unanswered segments are a faint blush, not a surface color. A dark
            // plum track disappears on the dark capsule behind the Home badge.
            .fill(isCompleted ? Color.paeoniaAccentPrimary : Color.paeoniaTextPrimary.opacity(0.25))
            .overlay {
                if isCurrent, !isCompleted {
                    shape.fill(Color.paeoniaAccentPrimary.opacity(0.3))
                }
            }
            .frame(height: isCurrent ? currentHeight : height)
    }

    private var currentHeight: CGFloat { height * 1.75 }
}

#if DEBUG
#Preview {
    VStack(spacing: PaeoniaSpacing.space24) {
        DailyChallengeStepBar(total: 2, completed: 1)
        DailyChallengeStepBar(total: 2, completed: 1, current: 1, height: 8)
        DailyChallengeStepBar(total: 2, completed: 2, height: 8)
    }
    .padding(PaeoniaSpacing.screenHorizontalPadding)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(.paeoniaBackgroundPrimary)
    .preferredColorScheme(.dark)
}
#endif
