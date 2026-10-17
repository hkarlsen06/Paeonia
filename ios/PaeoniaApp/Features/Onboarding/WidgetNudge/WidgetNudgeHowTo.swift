import SwiftUI

/// The numbered steps for adding the widget. `activeStep` lights up one step in step
/// with the Home Screen picture. Nil shows every step the same, for Reduce Motion.
struct WidgetNudgeHowTo: View {
    static let stepCount = steps.count

    private static let steps: [LocalizedStringResource] = [
        .onboardingWidgetNudgeStepHold,
        .onboardingWidgetNudgeStepEdit,
        .onboardingWidgetNudgeStepAdd,
        .onboardingWidgetNudgeStepSearch,
        .onboardingWidgetNudgeStepSize,
    ]

    var activeStep: Int?

    @ScaledMetric(relativeTo: .body) private var badgeSize: CGFloat = 28

    var body: some View {
        VStack(alignment: .leading, spacing: PaeoniaSpacing.space12) {
            Text(.onboardingWidgetNudgeHowToTitle)
                .font(PaeoniaTypography.sectionTitle)
                .foregroundStyle(.paeoniaTextPrimary)
                .accessibilityAddTraits(.isHeader)

            ForEach(Self.steps.indices, id: \.self) { index in
                row(index: index)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func row(index: Int) -> some View {
        let isActive = activeStep == nil || activeStep == index

        return HStack(alignment: .firstTextBaseline, spacing: PaeoniaSpacing.space12) {
            Text(index + 1, format: .number)
                .font(PaeoniaTypography.caption.weight(.bold))
                .foregroundStyle(activeStep == index ? .paeoniaTextInverse : .paeoniaTextPrimary)
                .frame(width: badgeSize, height: badgeSize)
                .background(
                    activeStep == index ? Color.paeoniaAccentPrimary : Color.paeoniaSurfaceSecondary,
                    in: Circle()
                )
                .scaleEffect(activeStep == index ? 1.08 : 1)

            Text(Self.steps[index])
                .font(PaeoniaTypography.body)
                .foregroundStyle(isActive ? .paeoniaTextPrimary : .paeoniaTextSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .animation(PaeoniaMotion.stateChange, value: activeStep)
        .accessibilityElement(children: .combine)
    }
}

#if DEBUG
#Preview {
    WidgetNudgeHowTo(activeStep: 1)
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.paeoniaBackgroundPrimary)
        .preferredColorScheme(.dark)
}
#endif
