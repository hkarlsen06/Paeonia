import Foundation

/// What the inviter has made for their partner while waiting for them to join, as
/// `firstDay:start_first_day_draft` and `firstDay:get_first_day_draft` return it. When the
/// partner joins, the server turns it into the couple's first day.
nonisolated struct FirstDayDraft: Decodable, Equatable, Sendable {
    let startedOn: String?
    var questions: [FirstDayQuestion]
    let drawing: FirstDayDrawingReference?

    var answeredCount: Int {
        questions.count { $0.answerText != nil }
    }

    var hasAnsweredAll: Bool {
        !questions.isEmpty && answeredCount == questions.count
    }

    enum CodingKeys: String, CodingKey {
        case startedOn = "started_on"
        case questions
        case drawing
    }
}

/// One of the inviter's two first daily questions, with their saved answer.
nonisolated struct FirstDayQuestion: Decodable, Equatable, Identifiable, Sendable {
    let slotNumber: Int
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
        case slotNumber = "slot_number"
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
