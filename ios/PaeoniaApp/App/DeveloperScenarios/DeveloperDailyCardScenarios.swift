#if DEBUG
  import SwiftUI

  /// The daily question card's envelope on its own. The envelope holds Robin's answer,
  /// so it opens once it can be read. Answer first and it stays sealed until Robin
  /// answers. Let Robin answer first and it opens as the card shrinks.
  nonisolated extension DeveloperScenario {
    static let dailyCard: [DeveloperScenario] = [dailyCardSealMoment]

    static let dailyCardSealMoment = DeveloperScenario(
      "daily-card-seal-moment", "Questions · seal moment",
      "Answer today's question and let Robin answer, in either order", .questions
    ) { _ in DeveloperDailyCardSealScenarioView() }
  }

  private struct DeveloperDailyCardSealScenarioView: View {
    @State private var isFinished = false
    @State private var robinAnswered = false

    private var state: DailyChallengeCardState {
      DailyChallengeCardState(
        kind: isFinished
          ? .complete
          : .active(prompt: "What is one small thing your partner did recently that stayed with you?"),
        hasPartnerAnsweredToday: robinAnswered
      )
    }

    var body: some View {
      ScrollView {
        VStack(spacing: PaeoniaSpacing.space12) {
          DailyPromptCard(state: state, partnerName: "Robin")
            .padding(.bottom, PaeoniaSpacing.space12)

          if !isFinished {
            button("Answer today's question") { isFinished = true }
          }
          if !robinAnswered {
            button("Robin answers") { robinAnswered = true }
          }
          button("Start over") {
            isFinished = false
            robinAnswered = false
          }
        }
        .padding(PaeoniaSpacing.screenHorizontalPadding)
      }
      .background(.paeoniaBackgroundPrimary)
      .preferredColorScheme(.dark)
    }

    private func button(_ title: String, action: @escaping () -> Void) -> some View {
      Button(action: action) {
        Text(verbatim: title)
      }
      .buttonStyle(PaeoniaSecondaryButtonStyle())
    }
  }
#endif
