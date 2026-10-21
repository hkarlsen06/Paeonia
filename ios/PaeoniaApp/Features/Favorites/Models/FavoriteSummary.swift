import Foundation

/// What the favorites list shows for one saved item, from `favorites:get_favorite_summaries`.
/// One shape for every kind. A field a kind does not have is nil.
nonisolated struct FavoriteSummary: Decodable, Equatable, Sendable {
    let target: FavoriteTarget
    let savedAt: Date
    /// Daily question and answer: the question whose page opens.
    let questionID: UUID?
    /// The question's wording in each language. The screen picks the one it shows.
    let promptEnglish: String?
    let promptNorwegian: String?
    /// Daily answer and widget drawing: who made it.
    let authorUserID: UUID?
    /// Daily answer: the written text.
    let answerText: String?
    /// Daily answer: the label of the picked option, in each language.
    let optionEnglish: String?
    let optionNorwegian: String?
    /// Daily answer: `photo` or `voice` when it has media.
    let mediaKind: String?
    /// Daily answer: the partner who was picked.
    let selectedUserID: UUID?
    /// Widget drawing: the stored drawing and its bounds, which give the canvas size.
    let mediaAssetID: UUID?
    let bounds: WidgetDrawingBounds?
    /// Game items: the round, creature or story number, and the word or title.
    let number: Int?
    let title: String?
    /// When the saved thing was made.
    let occurredAt: Date

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        target = FavoriteTarget(
            kind: try container.decode(FavoriteKind.self, forKey: .kind),
            id: try container.decode(UUID.self, forKey: .targetID)
        )
        savedAt = try container.decode(Date.self, forKey: .createdAt)
        let summary = try container.nestedContainer(keyedBy: SummaryKeys.self, forKey: .summary)
        questionID = try summary.decodeIfPresent(UUID.self, forKey: .questionID)
        promptEnglish = try summary.decodeIfPresent(String.self, forKey: .promptEnglish)
        promptNorwegian = try summary.decodeIfPresent(String.self, forKey: .promptNorwegian)
        authorUserID = try summary.decodeIfPresent(UUID.self, forKey: .authorUserID)
        answerText = try summary.decodeIfPresent(String.self, forKey: .answerText)
        optionEnglish = try summary.decodeIfPresent(String.self, forKey: .optionEnglish)
        optionNorwegian = try summary.decodeIfPresent(String.self, forKey: .optionNorwegian)
        mediaKind = try summary.decodeIfPresent(String.self, forKey: .mediaKind)
        selectedUserID = try summary.decodeIfPresent(UUID.self, forKey: .selectedUserID)
        mediaAssetID = try summary.decodeIfPresent(UUID.self, forKey: .mediaAssetID)
        // A drawing without readable bounds still shows, at the fallback size.
        bounds = try? summary.decodeIfPresent(WidgetDrawingBounds.self, forKey: .bounds)
        number = try summary.decodeIfPresent(Int.self, forKey: .number)
        title = try summary.decodeIfPresent(String.self, forKey: .title)
        occurredAt = try summary.decode(Date.self, forKey: .occurredAt)
    }

    private enum CodingKeys: String, CodingKey {
        case kind
        case targetID = "target_id"
        case createdAt = "created_at"
        case summary
    }

    private enum SummaryKeys: String, CodingKey {
        case questionID = "question_id"
        case promptEnglish = "prompt_en"
        case promptNorwegian = "prompt_nb"
        case authorUserID = "author_user_id"
        case answerText = "answer_text"
        case optionEnglish = "option_en"
        case optionNorwegian = "option_nb"
        case mediaKind = "media_kind"
        case selectedUserID = "selected_user_id"
        case mediaAssetID = "media_asset_id"
        case bounds
        case number
        case title
        case occurredAt = "occurred_at"
    }
}

nonisolated extension FavoriteSummary {
    /// The question's wording in the language of `locale`.
    func prompt(for locale: Locale = .current) -> String? {
        Self.isNorwegian(locale) ? promptNorwegian : promptEnglish
    }

    /// The label of the option the answer picked, in the language of `locale`.
    func option(for locale: Locale = .current) -> String? {
        Self.isNorwegian(locale) ? optionNorwegian : optionEnglish
    }

    private static func isNorwegian(_ locale: Locale) -> Bool {
        let code = locale.language.languageCode?.identifier
        return code == "nb" || code == "no"
    }
}

extension FavoriteSummary: Identifiable {
    var id: FavoriteTarget { target }
}
