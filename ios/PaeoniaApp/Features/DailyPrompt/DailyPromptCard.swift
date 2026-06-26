import SwiftUI

/// Today's shared questions on the Us tab, with the couple's streak. This is the
/// core daily ritual surface and has no tab of its own, so it sits at the top of
/// Home.
///
/// Each person answers three questions a day; this card shows the first one and a
/// three-step indicator for the rest. The question text and streak are placeholder
/// values for now, and the Answer button is inert. They get wired to the daily
/// challenge data later.
struct DailyPromptCard: View {
    var onAnswer: () -> Void = {}

    // Placeholders until the daily questions and streak are wired up.
    private static let questionCount = 3
    private static let currentQuestion = 1
    private static let placeholderQuestion =
        "What's one small thing I did this week that made you feel loved?"
    private static let placeholderStreak = 12

    var body: some View {
        PaeoniaCard {
            VStack(alignment: .leading, spacing: PaeoniaSpacing.space16) {
                HStack(alignment: .center) {
                    PaeoniaCardEyebrow(.homeDailyPromptEyebrow)
                    Spacer(minLength: PaeoniaSpacing.space12)
                    StreakPill(count: Self.placeholderStreak)
                }

                QuestionProgress(total: Self.questionCount, current: Self.currentQuestion)

                Text(verbatim: Self.placeholderQuestion)
                    .font(PaeoniaTypography.title)
                    .foregroundStyle(.paeoniaTextPrimary)
                    .fixedSize(horizontal: false, vertical: true)

                Button(action: onAnswer) {
                    Text(.homeDailyPromptAnswer)
                }
                .buttonStyle(PaeoniaPrimaryButtonStyle())
            }
        }
    }
}

/// A three-step bar showing how far through today's questions the couple is. The
/// first segment is the active question; the rest are still to come.
private struct QuestionProgress: View {
    let total: Int
    let current: Int

    var body: some View {
        HStack(spacing: PaeoniaSpacing.space4) {
            ForEach(0..<total, id: \.self) { index in
                Capsule()
                    .fill(index < current ? Color.paeoniaAccentPrimary : Color.paeoniaSurfaceSecondary)
                    .frame(height: 4)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(.homeDailyPromptProgress))
    }
}

/// A compact flame pill showing how many days the couple has kept their streak.
private struct StreakPill: View {
    let count: Int

    var body: some View {
        HStack(spacing: PaeoniaSpacing.space4) {
            Image(systemName: "flame.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.paeoniaAccentSecondary)

            Text(count, format: .number)
                .font(PaeoniaTypography.bodyEmphasis)
                .foregroundStyle(.paeoniaTextPrimary)

            Text(.homeStreakLabel)
                .font(PaeoniaTypography.caption)
                .foregroundStyle(.paeoniaTextSecondary)
        }
        .padding(.horizontal, PaeoniaSpacing.space12)
        .padding(.vertical, PaeoniaSpacing.space8)
        .background(Capsule().fill(.paeoniaSurfaceSecondary))
        .accessibilityElement(children: .combine)
    }
}

#if DEBUG
#Preview {
    DailyPromptCard()
        .padding(PaeoniaSpacing.screenHorizontalPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(.paeoniaBackgroundPrimary)
        .preferredColorScheme(.dark)
}
#endif
