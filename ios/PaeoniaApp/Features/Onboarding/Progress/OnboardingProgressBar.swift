import SwiftUI

/// The thin bar at the top of the onboarding screens. VoiceOver reads it as
/// "Getting set up" with the percent done.
struct OnboardingProgressBar: View {
    let fraction: Double

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ProgressView(value: clampedFraction)
            .progressViewStyle(OnboardingProgressBarStyle(
                animation: reduceMotion ? nil : PaeoniaMotion.meaningfulMoment
            ))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(.onboardingProgressLabel))
            .accessibilityValue(Text(clampedFraction, format: .percent.precision(.fractionLength(0))))
    }

    private var clampedFraction: Double {
        min(max(fraction, 0), 1)
    }
}

/// Draws the bar without its label. Only the fill's scale animates, so the bar's
/// first layout never animates with it.
private struct OnboardingProgressBarStyle: ProgressViewStyle {
    let animation: Animation?

    func makeBody(configuration: Configuration) -> some View {
        Rectangle()
            .fill(.paeoniaAccentPrimary)
            .animation(animation) { fill in
                fill.scaleEffect(x: configuration.fractionCompleted ?? 0, anchor: .leading)
            }
            .background(Color.paeoniaTextPrimary.opacity(0.18))
            .clipShape(.capsule)
            .frame(height: PaeoniaSpacing.space4)
    }
}

#if DEBUG
#Preview {
    @Previewable @State var fraction = 3.0 / 8
    VStack(spacing: PaeoniaSpacing.space24) {
        OnboardingProgressBar(fraction: fraction)
        Button {
            fraction = min(fraction + 1.0 / 8, 1)
        } label: {
            Text(verbatim: "Next")
        }
    }
    .padding()
    .background(PaeoniaGlowBackground())
    .preferredColorScheme(.dark)
}
#endif
