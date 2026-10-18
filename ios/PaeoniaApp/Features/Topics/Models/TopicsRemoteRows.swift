import Foundation

/// `topics:get_topics_overview`: every topic the couple can see, in shelf order.
/// The adults-only topic is missing while either partner has it hidden.
nonisolated struct RemoteTopicsOverview: Codable, Equatable, Sendable {
    let topics: [RemoteTopicSummary]
    /// The viewer hid the adults-only topic, so the shelf offers to show it again.
    let adultTopicsHiddenByViewer: Bool

    enum CodingKeys: String, CodingKey {
        case topics
        case adultTopicsHiddenByViewer = "adult_topics_hidden_by_viewer"
    }
}

nonisolated struct RemoteTopicSummary: Codable, Equatable, Sendable {
    let topicKey: String
    let collectionID: UUID
    let sortOrder: Int
    let adultsOnly: Bool
    let titleEN: String
    let subtitleEN: String
    let titleNB: String
    let subtitleNB: String
    /// `open`, `locked` or `waiting_for_partner`. Always `open` for other topics.
    let adultState: String
    /// Questions the couple hasn't skipped.
    let totalCount: Int
    /// Questions both partners answered.
    let togetherCount: Int
    /// Questions the partner answered that the viewer hasn't.
    let forYouCount: Int
    /// Questions the viewer answered that the partner hasn't.
    let waitingForPartnerCount: Int

    enum CodingKeys: String, CodingKey {
        case topicKey = "topic_key"
        case collectionID = "collection_id"
        case sortOrder = "sort_order"
        case adultsOnly = "adults_only"
        case titleEN = "title_en"
        case subtitleEN = "subtitle_en"
        case titleNB = "title_nb"
        case subtitleNB = "subtitle_nb"
        case adultState = "adult_state"
        case totalCount = "total_count"
        case togetherCount = "together_count"
        case forYouCount = "for_you_count"
        case waitingForPartnerCount = "waiting_for_partner_count"
    }
}

/// `topics:get_topic`: one topic's questions with the answers the viewer may read.
nonisolated struct RemoteTopicDetail: Codable, Equatable, Sendable {
    let topic: RemoteTopicSummary
    let questions: [RemoteTopicQuestionRow]
    let answerDetails: [DailyAnswerDetailRow]

    enum CodingKeys: String, CodingKey {
        case topic
        case questions
        case answerDetails = "answer_details"
    }
}

nonisolated struct RemoteTopicQuestionRow: Codable, Equatable, Sendable {
    let questionID: UUID
    let questionKey: String
    let questionVersionID: UUID
    let sortOrder: Int
    let promptEN: String
    let shortPromptEN: String
    let promptNB: String
    let shortPromptNB: String
    let answerKinds: [DailyChallengeAnswerKind]
    let isSkipped: Bool
    /// The couple's instance of the question, in the daily row shape. Nil until
    /// someone answers it.
    let row: DailyQuestionRow?
    /// The two options of a pick-one-of-two question, in both languages.
    var optionAEN: String?
    var optionBEN: String?
    var optionANB: String?
    var optionBNB: String?

    enum CodingKeys: String, CodingKey {
        case questionID = "question_id"
        case questionKey = "question_key"
        case questionVersionID = "question_version_id"
        case sortOrder = "sort_order"
        case promptEN = "prompt_en"
        case shortPromptEN = "short_prompt_en"
        case promptNB = "prompt_nb"
        case shortPromptNB = "short_prompt_nb"
        case answerKinds = "answer_kinds"
        case isSkipped = "is_skipped"
        case row
        case optionAEN = "option_a_en"
        case optionBEN = "option_b_en"
        case optionANB = "option_a_nb"
        case optionBNB = "option_b_nb"
    }
}

extension Locale {
    /// Topic and question copy comes in English and Norwegian. Anything that isn't
    /// Norwegian reads the English copy.
    nonisolated var prefersNorwegianTopicCopy: Bool {
        let languageCode = language.languageCode?.identifier
        return languageCode == "nb" || languageCode == "no"
    }
}
