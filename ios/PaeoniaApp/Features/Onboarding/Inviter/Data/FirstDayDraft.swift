import Foundation

/// What the inviter has made for their partner while waiting for them to join, as
/// `firstDay:start_first_day_draft` and `firstDay:get_first_day_draft` return it. When the
/// partner joins, the server turns it into the couple's first day.
nonisolated struct FirstDayDraft: Decodable, Equatable, Sendable {
    let startedOn: String?
    /// Nil until the server has picked the question.
    var question: FirstDayQuestion?
    let drawing: FirstDayDrawingReference?

    var hasAnswered: Bool {
        question?.answerText != nil
    }

    enum CodingKeys: String, CodingKey {
        case startedOn = "started_on"
        case question
        case drawing
    }
}

/// The inviter's first daily question, with their saved answer. When the partner joins,
/// it becomes the couple's question for their first day, and the partner answers it too.
nonisolated struct FirstDayQuestion: Decodable, Equatable, Identifiable, Sendable {
    let questionVersionID: UUID
    let promptEN: String
    let promptNB: String
    var answerText: String?

    var id: UUID { questionVersionID }

    /// The prompt in the app's language, picked the way the daily questions pick it.
    func prompt(for locale: Locale) -> String {
        let languageCode = locale.language.languageCode?.identifier
        return languageCode == "nb" || languageCode == "no" ? promptNB : promptEN
    }

    enum CodingKeys: String, CodingKey {
        case questionVersionID = "question_version_id"
        case promptEN = "prompt_en"
        case promptNB = "prompt_nb"
        case answerText = "answer_text"
    }
}

/// The drawing the draft holds. The owner downloads it through a signed URL.
nonisolated struct FirstDayDrawingReference: Decodable, Equatable, Sendable {
    let mediaAssetID: UUID
    let revisionID: UUID

    enum CodingKeys: String, CodingKey {
        case mediaAssetID = "media_asset_id"
        case revisionID = "revision_id"
    }
}
