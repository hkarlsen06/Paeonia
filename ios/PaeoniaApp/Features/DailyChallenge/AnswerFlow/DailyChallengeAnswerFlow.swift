import SwiftUI

/// Answers one daily question, then opens its conversation in the same cover.
struct DailyChallengeAnswerFlow: View {
    let viewModel: DailyChallengeViewModel
    var questionID: UUID?
    var onClose: () -> Void = {}
    var privacySafetyService: (any PrivacySafetyServicing)?
    var privacyOperationProvider: (any SyncClientOperationProviding)?
    var onReportedAndLeft: () -> Void = {}

    @Environment(PaeoniaBannerCenter.self) var bannerCenter
    @State var committedAnswerHold: DailyAnswerStepVisualHold?
    @State var heldQuestion: DailyChallengeQuestion?
    @State var chat: ThreadChatViewModel?
    @State var sentQuestionID: UUID?
    @State var submittedAnswer: DailySendingPreview?
    @FocusState var isComposerFocused: Bool

    enum Phase {
        case loading
        case answering
        case unavailable
    }

    var currentQuestion: DailyChallengeQuestion? {
        if let questionID { return viewModel.knownQuestion(questionID) }
        return viewModel.snapshot.todayQuestion
    }

    var phase: Phase {
        if heldQuestion != nil || currentQuestion != nil { return .answering }
        if viewModel.isStarting || viewModel.isLoading { return .loading }
        return .unavailable
    }

    var body: some View {
        Group {
            if let chat {
                DailyAnswerFlowChat(
                    chat: chat,
                    viewModel: viewModel,
                    submittedAnswer: submittedAnswer,
                    privacySafetyService: privacySafetyService,
                    privacyOperationProvider: privacyOperationProvider,
                    onReportedAndLeft: onReportedAndLeft,
                    onClose: dismiss
                )
                .transition(.opacity)
            } else {
                phaseContent
                    .paeoniaReadableWidth()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background { PaeoniaGlowBackground() }
            }
        }
        .task(id: currentQuestion?.id) {
            guard let question = currentQuestion,
                  question.hasOwnAnswer || viewModel.isSending(question.id)
            else { return }
            await openChat(for: question)
        }
        .onChange(of: wasAnswerReturned) { _, returned in
            guard returned else { return }
            withAnimation(PaeoniaMotion.stateChange) {
                chat = nil
                heldQuestion = nil
                committedAnswerHold = nil
            }
        }
        .onChange(of: viewModel.notice) { _, notice in showBanner(for: notice) }
    }
}

#if DEBUG
#Preview {
    DailyChallengeAnswerFlowPreviewHost()
}

private struct DailyChallengeAnswerFlowPreviewHost: View {
    @State var viewModel = DailyChallengeViewModel(service: PreviewDailyChallengeService())

    var body: some View {
        DailyChallengeAnswerFlow(viewModel: viewModel)
            .environment(PaeoniaBannerCenter())
            .preferredColorScheme(.dark)
            .task {
                await viewModel.configure(currentUserID: PreviewDailyChallengeService.userID)
            }
    }
}
#endif
