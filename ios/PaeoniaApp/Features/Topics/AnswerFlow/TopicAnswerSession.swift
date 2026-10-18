import SwiftUI

/// Answering a topic's questions one after another in one cover. Each question uses
/// the daily single-question flow (`DailyPartnerAnswerFlow`): the same composers,
/// drafts and send queue, then the question's page. Next moves on to the topic's next
/// question without going back to the list. Skip puts a question aside without asking
/// and moves on, or closes the cover when nothing is left.
struct TopicAnswerSession: View {
    let topics: TopicsViewModel
    let dailyChallenge: DailyChallengeViewModel
    var privacySafetyService: (any PrivacySafetyServicing)?
    var privacyOperationProvider: (any SyncClientOperationProviding)?
    var onReportedAndLeft: () -> Void = {}
    let onClose: () -> Void

    @State private var question: DailyChallengeQuestion
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(
        question: DailyChallengeQuestion,
        topics: TopicsViewModel,
        dailyChallenge: DailyChallengeViewModel,
        privacySafetyService: (any PrivacySafetyServicing)? = nil,
        privacyOperationProvider: (any SyncClientOperationProviding)? = nil,
        onReportedAndLeft: @escaping () -> Void = {},
        onClose: @escaping () -> Void
    ) {
        _question = State(initialValue: question)
        self.topics = topics
        self.dailyChallenge = dailyChallenge
        self.privacySafetyService = privacySafetyService
        self.privacyOperationProvider = privacyOperationProvider
        self.onReportedAndLeft = onReportedAndLeft
        self.onClose = onClose
    }

    var body: some View {
        DailyPartnerAnswerFlow(
            question: question,
            viewModel: dailyChallenge,
            privacySafetyService: privacySafetyService,
            privacyOperationProvider: privacyOperationProvider,
            onReportedAndLeft: onReportedAndLeft,
            onClose: onClose,
            topicTitle: question.topicKey.flatMap { topics.topic($0)?.title },
            onSkip: skip,
            onNext: next
        )
        // A fresh flow per question, so its phase and held composer start over.
        .id(question.id)
        .transition(.opacity)
        .analyticsScreen("topic_answer")
    }

    /// The topic's next question, or nil when every question is answered or skipped.
    private var nextQuestion: DailyChallengeQuestion? {
        topics.nextQuestion(after: question).map(dailyChallenge.latestQuestion)
    }

    private func next() {
        guard let nextQuestion else {
            onClose()
            return
        }
        withAnimation(reduceMotion ? nil : PaeoniaMotion.stateChange) {
            question = nextQuestion
        }
    }

    private func skip() {
        let skipped = question
        let following = nextQuestion
        Task { await topics.setSkipped(skipped, skipped: true) }
        guard let following else {
            onClose()
            return
        }
        withAnimation(reduceMotion ? nil : PaeoniaMotion.stateChange) {
            question = following
        }
    }
}
