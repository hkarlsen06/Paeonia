#if DEBUG
  import SwiftUI

  /// The daily question card's seal moment on its own. The button finishes today's
  /// questions, so the seal breaks, the envelope opens and the card shrinks, and it can
  /// start over.
  nonisolated extension DeveloperScenario {
    static let dailyCard: [DeveloperScenario] = [dailyCardSealMoment]

    static let dailyCardSealMoment = DeveloperScenario(
      "daily-card-seal-moment", "Questions · seal moment",
      "Finish today's questions to break the seal and open the envelope", .questions
    ) { _ in DeveloperDailyCardSealScenarioView() }
  }

  private struct DeveloperDailyCardSealScenarioView: View {
    private static let active = DailyChallengeCardState(
      kind: .active(prompt: "What is a small thing I do that always makes your day better?"),
      answeredCount: 1,
      totalCount: 2
    )
    private static let complete = DailyChallengeCardState(kind: .complete, answeredCount: 2, totalCount: 2)

    @State private var state = Self.active

    var body: some View {
      ScrollView {
        VStack(spacing: PaeoniaSpacing.space24) {
          DailyPromptCard(state: state, partnerName: "Robin")

          Button {
            state = state == Self.active ? Self.complete : Self.active
          } label: {
            Text(verbatim: state == Self.active ? "Finish today's questions" : "Start over")
          }
          .buttonStyle(PaeoniaSecondaryButtonStyle())
        }
        .padding(PaeoniaSpacing.screenHorizontalPadding)
      }
      .background(.paeoniaBackgroundPrimary)
      .preferredColorScheme(.dark)
    }
  }
#endif
