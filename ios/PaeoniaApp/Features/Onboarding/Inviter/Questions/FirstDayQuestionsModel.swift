import Foundation
import Observation

/// The inviter's first question on one page, then the question time step and a small
/// finish.
///
/// Typed text is kept on this phone until the server has it, in the first day answer
/// draft store, so it survives closing the flow or the app, and after pairing the daily
/// answer screen picks it up. The answer is saved as the person moves on. A failed save
/// keeps them on the page with their text, and `saveFailure` tells the view to show the
/// banner. The answer can be changed by opening the flow again, until the partner joins.
@MainActor
@Observable
final class FirstDayQuestionsModel: Identifiable {
    enum Step: Equatable {
        case question
        case questionTime
        case finished
    }

    private(set) var question: FirstDayQuestion
    private(set) var step: Step = .question
    private(set) var isSaving = false
    /// Set when the last save failed. The view shows it and then clears it.
    private(set) var saveFailure: PaeoniaFailure?
    /// False once the question reminder turned out to be on already.
    private(set) var asksQuestionTime = true
    private var typedText: String
    /// Drives the question time step, with the same preferences this model reads.
    @ObservationIgnored let questionTimeModel: QuestionTimeModel

    @ObservationIgnored private let ownerUserID: UUID
    @ObservationIgnored private let gateway: any FirstDayGateway
    @ObservationIgnored private let operationProvider: any SyncClientOperationProviding
    @ObservationIgnored private let draftStore: any FirstDayAnswerDraftStoring
    @ObservationIgnored private let preferences: (any NotificationPreferencesProviding)?

    init(
        question: FirstDayQuestion,
        ownerUserID: UUID,
        gateway: any FirstDayGateway,
        operationProvider: (any SyncClientOperationProviding)? = nil,
        draftStore: (any FirstDayAnswerDraftStoring)? = nil,
        preferences: (any NotificationPreferencesProviding)? = NotificationPreferencesServiceFactory.makeDefault()
    ) {
        self.question = question
        self.ownerUserID = ownerUserID
        self.gateway = gateway
        self.operationProvider = operationProvider ?? SyncClientOperationFactory.shared
        self.draftStore = draftStore ?? UserDefaultsFirstDayAnswerDraftStore.shared
        self.preferences = preferences
        questionTimeModel = QuestionTimeModel(preferences: preferences)
        typedText = self.draftStore.texts(for: ownerUserID)[question.questionVersionID]
            ?? question.answerText
            ?? ""
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

    // MARK: Answer

    var text: String {
        get { typedText }
        set {
            typedText = newValue
            draftStore.setText(newValue, for: question.questionVersionID, userID: ownerUserID)
        }
    }

    /// Something is typed, and it fits the server's limit.
    var canContinue: Bool {
        let length = DailyAnswerDraft.measuredLength(of: text)
        return length > 0 && length <= DailyAnswerDraft.maxTextLength && !isSaving
    }

    // MARK: Actions

    /// Saves the answer when it is new or changed, then moves on. Returns true when it
    /// moved on, for the view's haptic.
    @discardableResult
    func continueFromQuestion() async -> Bool {
        guard canContinue, step == .question else {
            return false
        }
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
            question.answerText = answer
            draftStore.clearText(for: question.questionVersionID, userID: ownerUserID)
        }

        step = asksQuestionTime ? .questionTime : .finished
        return true
    }

    func finishQuestionTime() {
        step = .finished
    }

    func clearSaveFailure() {
        saveFailure = nil
    }
}
