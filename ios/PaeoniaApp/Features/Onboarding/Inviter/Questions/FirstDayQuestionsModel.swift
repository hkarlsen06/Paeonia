import Foundation
import Observation

/// The inviter's two first questions, one page each, then the question time step and
/// a small finish.
///
/// Typed text is kept on this phone until the server has it, in the first day answer
/// draft store, so it survives closing the flow or the app, and after pairing the daily
/// answer screen picks it up. Each answer is saved as the
/// person moves on. A failed save keeps them on the page with their text, and
/// `saveFailure` tells the view to show the banner. Answers can be changed by opening
/// the flow again, until the partner joins.
@MainActor
@Observable
final class FirstDayQuestionsModel: Identifiable {
    enum Step: Equatable {
        case question(Int)
        case questionTime
        case finished
    }

    private(set) var questions: [FirstDayQuestion]
    private(set) var step: Step
    private(set) var isSaving = false
    /// Set when the last save failed. The view shows it and then clears it.
    private(set) var saveFailure: PaeoniaFailure?
    /// False once the question reminder turned out to be on already.
    private(set) var asksQuestionTime = true
    private var texts: [UUID: String] = [:]
    /// Drives the question time step, with the same preferences this model reads.
    @ObservationIgnored let questionTimeModel: QuestionTimeModel

    @ObservationIgnored private let ownerUserID: UUID
    @ObservationIgnored private let gateway: any FirstDayGateway
    @ObservationIgnored private let operationProvider: any SyncClientOperationProviding
    @ObservationIgnored private let draftStore: any FirstDayAnswerDraftStoring
    @ObservationIgnored private let preferences: (any NotificationPreferencesProviding)?

    init(
        questions: [FirstDayQuestion],
        ownerUserID: UUID,
        gateway: any FirstDayGateway,
        operationProvider: (any SyncClientOperationProviding)? = nil,
        draftStore: (any FirstDayAnswerDraftStoring)? = nil,
        preferences: (any NotificationPreferencesProviding)? = NotificationPreferencesServiceFactory.makeDefault()
    ) {
        self.questions = questions
        self.ownerUserID = ownerUserID
        self.gateway = gateway
        self.operationProvider = operationProvider ?? SyncClientOperationFactory.shared
        self.draftStore = draftStore ?? UserDefaultsFirstDayAnswerDraftStore.shared
        self.preferences = preferences
        questionTimeModel = QuestionTimeModel(preferences: preferences)
        // Opens on the first unanswered question, or on the first one to change answers.
        step = .question(questions.firstIndex { $0.answerText == nil } ?? 0)

        let drafts = self.draftStore.texts(for: ownerUserID)
        for question in questions {
            texts[question.id] = drafts[question.questionVersionID] ?? question.answerText ?? ""
        }
    }

    /// Checks whether the question reminder is on already, so the flow can skip asking.
    /// A failed check asks anyway.
    func loadQuestionTimeState() async {
        guard let preferences,
              let current = try? await preferences.loadNotificationPreferences()
        else {
            return
        }
        asksQuestionTime = !current.questionTime.isEnabled
    }

    // MARK: Current question

    var currentIndex: Int? {
        guard case let .question(index) = step, questions.indices.contains(index) else {
            return nil
        }
        return index
    }

    var currentQuestion: FirstDayQuestion? {
        currentIndex.map { questions[$0] }
    }

    var isLastQuestion: Bool {
        currentIndex == questions.count - 1
    }

    var text: String {
        get { currentQuestion.flatMap { texts[$0.id] } ?? "" }
        set {
            guard let question = currentQuestion else { return }
            texts[question.id] = newValue
            draftStore.setText(newValue, for: question.questionVersionID, userID: ownerUserID)
        }
    }

    /// The text typed for `question`, so a page sliding out keeps showing its own answer.
    func text(for question: FirstDayQuestion) -> String {
        texts[question.id] ?? ""
    }

    /// Something is typed, and it fits the server's limit.
    var canContinue: Bool {
        let length = DailyAnswerDraft.measuredLength(of: text)
        return length > 0 && length <= DailyAnswerDraft.maxTextLength && !isSaving
    }

    var answeredCount: Int {
        questions.count { $0.answerText != nil }
    }

    // MARK: Actions

    /// Saves the answer when it is new or changed, then moves on. Returns true when it
    /// moved on, for the view's haptic.
    @discardableResult
    func continueFromQuestion() async -> Bool {
        guard canContinue, let index = currentIndex else {
            return false
        }
        let question = questions[index]
        let answer = text.trimmingCharacters(in: .whitespacesAndNewlines)

        if answer != question.answerText {
            isSaving = true
            saveFailure = nil
            defer { isSaving = false }
            do {
                try await gateway.saveAnswer(
                    questionVersionID: question.questionVersionID,
                    text: answer,
                    operation: operationProvider.makeOperation()
                )
            } catch {
                saveFailure = PaeoniaFailure(error)
                return false
            }
            questions[index].answerText = answer
            draftStore.clearText(for: question.questionVersionID, userID: ownerUserID)
        }

        advance(after: index)
        return true
    }

    func finishQuestionTime() {
        step = .finished
    }

    func clearSaveFailure() {
        saveFailure = nil
    }

    private func advance(after index: Int) {
        if index + 1 < questions.count {
            step = .question(index + 1)
        } else {
            step = asksQuestionTime ? .questionTime : .finished
        }
    }
}
