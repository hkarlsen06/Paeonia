import Foundation

/// Which of the two options a pick-one-of-two answer chose. Sent as `option_choice`.
nonisolated enum DailyAnswerOption: String, Codable, CaseIterable, Hashable, Sendable {
    case first = "a"
    case second = "b"
}

/// The two options of a pick-one-of-two question, in the phone's language. They are
/// short labels that read well in "You picked …", such as "By the sea".
nonisolated struct DailyAnswerOptions: Equatable, Hashable, Sendable {
    let first: String
    let second: String

    func label(for option: DailyAnswerOption) -> String {
        switch option {
        case .first: first
        case .second: second
        }
    }

    /// The options from a row's four labels, or nil when the question has none.
    static func make(en: (String?, String?), nb: (String?, String?), locale: Locale) -> DailyAnswerOptions? {
        let (first, second) = locale.prefersNorwegianTopicCopy ? nb : en
        guard let first, let second, !first.isEmpty, !second.isEmpty else { return nil }
        return DailyAnswerOptions(first: first, second: second)
    }
}

nonisolated extension DailyAnswerDraft {
    /// The why line under a pick-one-of-two answer stays short. The backend's limit
    /// for every answer text is `maxTextLength`.
    static let maxWhyLineLength = 280
}

nonisolated extension DailyChallengeQuestion {
    /// How long this question's text answer may be: a short why line next to a pick
    /// of two, otherwise the backend's limit for any answer.
    var maxAnswerTextLength: Int {
        answerKinds.contains(.eitherOr) ? DailyAnswerDraft.maxWhyLineLength : DailyAnswerDraft.maxTextLength
    }
}

extension DailyQuestionRow {
    nonisolated func options(for locale: Locale) -> DailyAnswerOptions? {
        DailyAnswerOptions.make(en: (optionAEN, optionBEN), nb: (optionANB, optionBNB), locale: locale)
    }
}

extension DailyQuestionAnswerDetail {
    /// The same answer with its picked option's label filled in, so the answer views
    /// and the chat can show it without the question at hand.
    nonisolated func labelingPick(with options: DailyAnswerOptions?) -> DailyQuestionAnswerDetail {
        var detail = self
        detail.selectedOptionLabel = selectedOption.flatMap { option in options?.label(for: option) }
        return detail
    }
}
