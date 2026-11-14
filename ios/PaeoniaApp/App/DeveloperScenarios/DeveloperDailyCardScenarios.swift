#if DEBUG
  import SwiftUI

  /// The daily question card's envelope on its own. The envelope holds Robin's answer,
  /// so it opens once it can be read. Answer first and it stays sealed until Robin
  /// answers. Let Robin answer first and it opens as the card shrinks.
  nonisolated extension DeveloperScenario {
    static let dailyCard: [DeveloperScenario] = [dailyCardSealMoment, dailyCardEnvelopeStages]

    static let dailyCardSealMoment = DeveloperScenario(
      "daily-card-seal-moment", "Questions · seal moment",
      "Answer today's question and let Robin answer, in either order", .questions
    ) { _ in DeveloperDailyCardSealScenarioView() }

    static let dailyCardEnvelopeStages = DeveloperScenario(
      "daily-card-envelope-stages", "Questions · envelope stages",
      "The envelope closed, opening and open, at the sizes the app shows it", .questions
    ) { _ in DeveloperEnvelopeStagesScenarioView() }
  }

  /// A row of the three stages at the short row's size and at Home's, then one large open
  /// envelope to look at closely.
  private struct DeveloperEnvelopeStagesScenarioView: View {
    private let widths: [CGFloat] = [68, 112]

    var body: some View {
      ScrollView {
        VStack(spacing: PaeoniaSpacing.space40) {
          ForEach(widths, id: \.self) { width in
            HStack(alignment: .bottom, spacing: PaeoniaSpacing.space16) {
              ForEach([DailyPromptEnvelopeOpening.closed, .flapOpening, .letterOut], id: \.self) { opening in
                DailyPromptEnvelope(width: width, opening: opening)
                  .padding(.top, width * 0.4)
              }
            }
          }
          DailyPromptEnvelope(width: 300, opening: .letterOut)
            .padding(.top, 220)
        }
        .padding(PaeoniaSpacing.screenHorizontalPadding)
        .frame(maxWidth: .infinity)
      }
      .background(.paeoniaBackgroundPrimary)
      .preferredColorScheme(.dark)
    }
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
