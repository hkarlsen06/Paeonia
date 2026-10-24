import SwiftUI

/// The invite screen's first question: one card that shows whether it is answered and
/// opens the answer flow as a full-screen cover. It pops with hearts when the question
/// is answered. The pop is silent, since the answer flow already played its own sound
/// and haptics. It also loads the first day draft and sends a waiting first drawing,
/// since it stays on screen while the code is out.
struct InviterQuestionsRow: View {
    let model: InviterFirstDayModel

    @State private var questionsModel: FirstDayQuestionsModel?
    /// The question the flow closed with, applied once the cover is gone so the
    /// completion beat plays on this screen.
    @State private var closedQuestion: FirstDayQuestion?
    @State private var isOpeningQuestions = false
    @Environment(PaeoniaBannerCenter.self) private var bannerCenter
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.inviterTaskOpenChanged) private var taskOpenChanged

    var body: some View {
        InviterFirstDayRow(
            title: .inviterQuestionsRowTitle,
            subtitle: model.hasAnsweredQuestion ? .inviterQuestionsRowDone : .inviterQuestionsRowSubtitle,
            isDone: model.hasAnsweredQuestion,
            completion: model.completion,
            action: openQuestions
        ) {
            InviterFirstDayRowIcon(systemImage: "text.bubble.fill")
        } trailing: {
            InviterFirstDayCheck(isDone: model.hasAnsweredQuestion, isLoading: isOpeningQuestions)
        }
        .accessibilityIdentifier("inviter.questions")
        .screenEntrance(order: 1, isReady: model.hasLoaded)
        .task {
            await model.load()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task { await model.refreshOnForeground() }
            }
        }
        .onChange(of: model.loadFailure) { _, failure in
            guard let failure else {
                return
            }
            bannerCenter.show(.error(
                title: String(localized: .inviterQuestionsLoadFailedTitle),
                message: String(
                    localized: failure == .offline
                        ? .inviterQuestionsLoadFailedOfflineMessage
                        : .commonActionFailedMessage
                )
            ))
            model.clearLoadFailure()
        }
        .fullScreenCover(item: $questionsModel, onDismiss: questionsClosed) { questionsModel in
            FirstDayQuestionsFlow(model: questionsModel) { question in
                closedQuestion = question
                self.questionsModel = nil
            }
            .environment(bannerCenter)
            .paeoniaTopBanner(bannerCenter)
        }
    }

    private func openQuestions() {
        guard !isOpeningQuestions else {
            return
        }
        isOpeningQuestions = true
        Task {
            questionsModel = await model.makeQuestionsModel()
            isOpeningQuestions = false
            if questionsModel != nil {
                taskOpenChanged(true)
            }
        }
    }

    private func questionsClosed() {
        taskOpenChanged(false)
        guard let closedQuestion else {
            return
        }
        self.closedQuestion = nil
        model.questionsFlowClosed(with: closedQuestion)
        Task { await model.refreshNotificationPermission() }
    }
}
