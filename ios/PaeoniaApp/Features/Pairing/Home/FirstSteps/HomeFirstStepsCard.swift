import SwiftUI

/// The Home card after the first day with a few things to try together. Each row opens
/// its feature and ticks itself off once the thing is done. Home hides the card when
/// every row is done or the person closes it.
struct HomeFirstStepsCard: View {
    let steps: HomeFirstSteps
    let partnerName: String
    var onOpen: (HomeFirstStep) -> Void = { _ in }
    var onClose: () -> Void = {}

    var body: some View {
        PaeoniaCard {
            VStack(alignment: .leading, spacing: PaeoniaSpacing.space12) {
                header
                VStack(alignment: .leading, spacing: PaeoniaSpacing.space4) {
                    ForEach(HomeFirstStep.allCases, id: \.self) { step in
                        Button {
                            onOpen(step)
                        } label: {
                            row(step)
                        }
                        .buttonStyle(.paeoniaPressableRow)
                        .accessibilityValue(Text(steps.isDone(step) ? .homeFirstStepsDone : .homeFirstStepsNotDone))
                        .accessibilityIdentifier("home.firstSteps.\(step.rawValue)")
                    }
                }
            }
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: PaeoniaSpacing.space12) {
            VStack(alignment: .leading, spacing: PaeoniaSpacing.space2) {
                Text(.homeFirstStepsTitle)
                    .font(PaeoniaTypography.sectionTitle)
                    .foregroundStyle(.paeoniaTextPrimary)
                Text(.homeFirstStepsProgress(steps.doneCount, steps.totalCount))
                    .font(PaeoniaTypography.caption)
                    .foregroundStyle(.paeoniaTextSecondary)
                    .contentTransition(.numericText())
            }
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)

            Spacer(minLength: 0)

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(PaeoniaTypography.caption.weight(.semibold))
                    .foregroundStyle(.paeoniaTextSecondary)
                    .frame(width: PaeoniaSpacing.compactButtonHeight, height: PaeoniaSpacing.compactButtonHeight)
                    .background(.paeoniaSurfaceSecondary, in: Circle())
                    .contentShape(Circle())
            }
            .buttonStyle(.paeoniaPressableCard)
            .accessibilityLabel(Text(.homeFirstStepsClose))
            .accessibilityIdentifier("home.firstSteps.close")
        }
    }

    private func row(_ step: HomeFirstStep) -> some View {
        let isDone = steps.isDone(step)
        return HStack(spacing: PaeoniaSpacing.space12) {
            Image(systemName: isDone ? "checkmark.circle.fill" : "circle")
                .font(PaeoniaTypography.sectionTitle)
                .foregroundStyle(isDone ? .paeoniaAccentPrimary : .paeoniaTextTertiary)
                .contentTransition(.symbolEffect(.replace))
                .accessibilityHidden(true)

            Text(title(for: step))
                .font(PaeoniaTypography.body)
                .foregroundStyle(isDone ? .paeoniaTextSecondary : .paeoniaTextPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)

            Image(systemName: "chevron.right")
                .font(PaeoniaTypography.caption.weight(.semibold))
                .foregroundStyle(.paeoniaTextTertiary)
                .accessibilityHidden(true)
        }
        .padding(.vertical, PaeoniaSpacing.space8)
        .contentShape(Rectangle())
    }

    private func title(for step: HomeFirstStep) -> LocalizedStringResource {
        switch step {
        case .game: .homeFirstStepsGame(partnerName)
        case .memory: .homeFirstStepsMemory
        case .countdown: .homeFirstStepsCountdown
        case .story: .homeFirstStepsStory
        case .topic: .homeFirstStepsTopic
        }
    }
}

#if DEBUG
#Preview {
    HomeFirstStepsCard(
        steps: HomeFirstSteps(doneSteps: [.game, .countdown]),
        partnerName: "Robin"
    )
    .padding()
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(.paeoniaBackgroundPrimary)
    .preferredColorScheme(.dark)
}
#endif
