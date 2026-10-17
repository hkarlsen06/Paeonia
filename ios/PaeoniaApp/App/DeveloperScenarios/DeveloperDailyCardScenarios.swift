#if DEBUG
  import SwiftUI

  /// The daily question card's envelope on its own. The envelope holds Robin's answers,
  /// so it opens once they can be read. Finish first and it stays sealed until Robin
  /// answers. Let Robin answer first and it opens as the card shrinks.
  nonisolated extension DeveloperScenario {
    static let dailyCard: [DeveloperScenario] = [dailyCardSealMoment]

    static let dailyCardSealMoment = DeveloperScenario(
      "daily-card-seal-moment", "Questions · seal moment",
      "Finish today's questions and let Robin answer, in either order", .questions
    ) { _ in DeveloperDailyCardSealScenarioView() }
  }

  private struct DeveloperDailyCardSealScenarioView: View {
    @State private var isFinished = false
    @State private var robinAnswered = false

    private var state: DailyChallengeCardState {
      DailyChallengeCardState(
        kind: isFinished
          ? .complete
          : .active(prompt: "What is a small thing I do that always makes your day better?"),
        answeredCount: isFinished ? 2 : 1,
        totalCount: 2,
        hasPartnerAnswersForToday: robinAnswered
      )
    }

    var body: some View {
      ScrollView {
        VStack(spacing: PaeoniaSpacing.space12) {
          DailyPromptCard(state: state, partnerName: "Robin")
            .padding(.bottom, PaeoniaSpacing.space12)

          if !isFinished {
            button("Finish today's questions") { isFinished = true }
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
