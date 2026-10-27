import SwiftUI

/// The question's chat inside an answer flow's cover, once the user has sent their
/// answer: the question, both answers with the partner's lit up, and the composer. It
/// has its own navigation stack, a close button and the report screen. The daily flow
/// (`DailyChallengeAnswerFlow`) and the topic flow (`DailyPartnerAnswerFlow`) both end
/// here, so closing returns the user to the screen that opened the flow.
///
/// Until the reply unlocks, the chat's waiting page shows the user's answer. After the
/// couple's day ends, today's snapshot can drop the exchange, so the chat keeps its own
/// copy of the question instead of going back to the unanswered one.
struct DailyAnswerFlowChat: View {
    let chat: ThreadChatViewModel
    let viewModel: DailyChallengeViewModel
    var submittedAnswer: DailySendingPreview?
    var privacySafetyService: (any PrivacySafetyServicing)?
    var privacyOperationProvider: (any SyncClientOperationProviding)?
    var onReportedAndLeft: () -> Void = {}
    let onClose: () -> Void
    /// Moves on to the topic's next question. Nil for a daily question.
    var onNext: (() -> Void)?

    @State private var reportTarget: PrivacyReportTarget?

    /// The live copy of the chat's question, carrying the partner's reply once it unlocks.
    private var question: DailyChallengeQuestion? {
        chat.question.map { viewModel.latestQuestion($0) }
    }

    var body: some View {
        NavigationStack {
            ThreadChatView(
                viewModel: chat,
                question: question,
                participants: viewModel.participants,
                onReport: { reportTarget = $0 },
                sendingAnswer: question.flatMap { viewModel.sendingPreview(for: $0) } ?? submittedAnswer,
                onClose: onClose
            )
            .analyticsScreen("daily_chat")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(action: onClose) {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel(Text(.dailyChallengeFlowClose))
                    .accessibilityIdentifier("daily.chat.close")
                }
            }
            .modifier(TopicNextQuestionActions(onNext: onNext, isChatAvailable: chat.isChatAvailable))
            .navigationDestination(item: $reportTarget, destination: reportScreen)
        }
    }

    @ViewBuilder
    private func reportScreen(_ reportTarget: PrivacyReportTarget) -> some View {
        if let partnerUserID = viewModel.participants.partnerUserID {
            ReportAndLeaveView(
                partnerUserID: partnerUserID,
                partnerName: viewModel.participants.partnerName,
                reportTarget: reportTarget,
                service: privacySafetyService,
                operationProvider: privacyOperationProvider,
                onReportedAndLeft: onReportedAndLeft
            )
        }
    }
}

/// A topic question's page moves on to the topic's next question: a button at the
/// bottom while the waiting page shows (it has no composer), and Next in the toolbar
/// once the chat is open. Nothing for a daily question.
private struct TopicNextQuestionActions: ViewModifier {
    let onNext: (() -> Void)?
    let isChatAvailable: Bool

    func body(content: Content) -> some View {
        content
            .toolbar {
                if let onNext, isChatAvailable {
                    ToolbarItem(placement: .confirmationAction) {
                        Button(action: onNext) {
                            Text(.topicsFlowNext)
                        }
                        .accessibilityIdentifier("topics.flow.next")
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                if let onNext, !isChatAvailable {
                    Button(action: onNext) {
                        Text(.topicsFlowNextQuestion)
                    }
                    .buttonStyle(PaeoniaPrimaryButtonStyle())
                    .padding(.horizontal, PaeoniaSpacing.screenHorizontalPadding)
                    .padding(.bottom, PaeoniaSpacing.space8)
                    .paeoniaReadableWidth()
                    .accessibilityIdentifier("topics.flow.nextQuestion")
                }
            }
    }
}
