import SwiftUI

/// One "while you wait" item: a tool the inviter opens, so it is a pressable card. When
/// it turns done the card pops and hearts rise from its trailing mark.
struct InviterFirstDayRow<Leading: View, Trailing: View>: View {
    let title: LocalizedStringResource
    let subtitle: LocalizedStringResource
    let isDone: Bool
    /// Set for the completion beat. A new id plays it again.
    let completion: InviterFirstDayModel.Completion?
    let action: () -> Void
    @ViewBuilder let leading: Leading
    @ViewBuilder let trailing: Trailing

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .body) private var burstSize: CGFloat = 56

    var body: some View {
        // Read here, since the keyframe closure can't read view state.
        let pops = !reduceMotion

        Button(action: action) {
            label(showsBurst: pops)
        }
        .buttonStyle(.paeoniaPressableCard)
        .modifier(InviterFirstDayRowPop(trigger: completion?.id, pops: pops))
        .animation(PaeoniaMotion.stateChange, value: isDone)
        .accessibilityElement(children: .combine)
    }

    private func label(showsBurst: Bool) -> some View {
        let shape = RoundedRectangle(cornerRadius: PaeoniaRadius.radius16, style: .continuous)

        return HStack(spacing: PaeoniaSpacing.space12) {
            leading

            VStack(alignment: .leading, spacing: PaeoniaSpacing.space2) {
                Text(title)
                    .font(PaeoniaTypography.bodyEmphasis)
                    .foregroundStyle(.paeoniaTextPrimary)

                Text(subtitle)
                    .font(PaeoniaTypography.caption)
                    .foregroundStyle(.paeoniaTextSecondary)
                    .contentTransition(.opacity)
            }
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)

            trailing
                .background {
                    if let completion, showsBurst {
                        MilestoneHeartBurst(unit: burstSize)
                            .id(completion.id)
                    }
                }
        }
        .padding(PaeoniaSpacing.cardContentPadding)
        .background(.paeoniaSurfaceSecondary, in: shape)
        .overlay {
            shape.strokeBorder(
                isDone ? Color.paeoniaAccentPrimary.opacity(0.35) : .clear,
                lineWidth: PaeoniaRadius.strokeDefault
            )
        }
        .contentShape(shape)
    }
}

/// The card's pop when it turns done. A non-generic modifier, so the keyframe
/// closure doesn't capture the row's view types.
private struct InviterFirstDayRowPop: ViewModifier {
    let trigger: UUID?
    let pops: Bool

    func body(content: Content) -> some View {
        content.keyframeAnimator(initialValue: CGFloat(1), trigger: trigger) { content, scale in
            content.scaleEffect(pops ? scale : 1)
        } keyframes: { _ in
            SpringKeyframe(1.04, duration: 0.18, spring: .snappy)
            SpringKeyframe(1, duration: 0.5, spring: .bouncy)
        }
    }
}

/// The plum tile at the start of a row.
struct InviterFirstDayRowIcon: View {
    let systemImage: String

    @ScaledMetric(relativeTo: .body) private var size: CGFloat = 44

    var body: some View {
        Image(systemName: systemImage)
            .font(.title3.weight(.semibold))
            .foregroundStyle(.paeoniaAccentPrimary)
            .frame(width: size, height: size)
            .background(
                .paeoniaAccentPrimary.opacity(0.16),
                in: RoundedRectangle(cornerRadius: PaeoniaRadius.radius12, style: .continuous)
            )
            .accessibilityHidden(true)
    }
}

/// The drawing, small, where the icon was.
struct InviterDrawingThumbnail: View {
    let image: UIImage

    @ScaledMetric(relativeTo: .body) private var size: CGFloat = 44

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: PaeoniaRadius.radius12, style: .continuous)

        Image(uiImage: image)
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .background(.paeoniaBackgroundPrimary, in: shape)
            .clipShape(shape)
            .overlay {
                shape.strokeBorder(.paeoniaSurfacePressed, lineWidth: PaeoniaRadius.strokeHairline)
            }
            .transition(.scale(scale: 0.6).combined(with: .opacity))
            .accessibilityHidden(true)
    }
}

/// A check once the item is done, and a chevron before.
struct InviterFirstDayCheck: View {
    let isDone: Bool

    var body: some View {
        Image(systemName: isDone ? "checkmark.circle.fill" : "chevron.right")
            .font(isDone ? .title2.weight(.semibold) : .body.weight(.semibold))
            .foregroundStyle(isDone ? .paeoniaAccentPrimary : .paeoniaTextTertiary)
            .contentTransition(.symbolEffect(.replace))
            .symbolEffect(.bounce, value: isDone)
            .accessibilityHidden(true)
    }
}

/// How many of the first questions are answered, as a ring that fills, then a check.
/// The While you wait button counts its two things with it too.
struct InviterQuestionsProgress: View {
    let answered: Int
    let total: Int
    /// The questions are loading because the row was tapped.
    var isLoading = false
    /// What VoiceOver reads for the count.
    var label: (Int, Int) -> LocalizedStringResource = { .inviterQuestionsRowProgress($0, $1) }

    @ScaledMetric(relativeTo: .body) private var size: CGFloat = 34

    var body: some View {
        Group {
            if isLoading {
                ProgressView()
                    .tint(.paeoniaAccentPrimary)
            } else if total > 0, answered < total {
                ring
            } else {
                InviterFirstDayCheck(isDone: total > 0)
            }
        }
        .frame(minWidth: size, minHeight: size)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(total > 0 ? Text(label(answered, total)) : Text(verbatim: ""))
    }

    private var ring: some View {
        ZStack {
            Circle()
                .stroke(.paeoniaSurfacePressed, lineWidth: 3)

            Circle()
                .trim(from: 0, to: CGFloat(answered) / CGFloat(total))
                .stroke(.paeoniaAccentPrimary, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(-90))

            Text(verbatim: "\(answered)/\(total)")
                .font(.caption2.weight(.bold))
                .monospacedDigit()
                .foregroundStyle(.paeoniaTextPrimary)
                .contentTransition(.numericText())
        }
        .frame(width: size, height: size)
        .animation(PaeoniaMotion.cardReveal, value: answered)
    }
}
