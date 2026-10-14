import Foundation

/// One old piece of the couple's shared history, as `lookBack:get_look_back` returns it. The server
/// picks it, so both partners see the same item all day. A question round carries both answers, a
/// drawing carries what the history thumbnail needs, and a memory carries its title and first photo.
nonisolated struct LookBackItem: Codable, Equatable, Sendable {
    nonisolated enum Kind: String, Codable, Sendable {
        case question
        case drawing
        case memory
    }

    nonisolated struct Answer: Codable, Equatable, Sendable {
        let userID: UUID
        let text: String?
        /// The person picked on a "pick one of you" question.
        let selectedUserID: UUID?
        let hasPhoto: Bool
        let hasVoice: Bool

        enum CodingKeys: String, CodingKey {
            case userID = "user_id"
            case text
            case selectedUserID = "selected_user_id"
            case hasPhoto = "has_photo"
            case hasVoice = "has_voice"
        }
    }

    nonisolated struct Question: Codable, Equatable, Sendable {
        /// The question instance, which the question's chat is keyed on.
        let instanceID: UUID
        let shortPromptEN: String
        let shortPromptNB: String
        let ownAnswer: Answer
        let partnerAnswer: Answer

        enum CodingKeys: String, CodingKey {
            case instanceID = "instance_id"
            case shortPromptEN = "short_prompt_en"
            case shortPromptNB = "short_prompt_nb"
            case ownAnswer = "own_answer"
            case partnerAnswer = "partner_answer"
        }

        func shortPrompt(for locale: Locale) -> String {
            let code = locale.language.languageCode?.identifier
            return code == "nb" || code == "no" ? shortPromptNB : shortPromptEN
        }
    }

    nonisolated struct Drawing: Codable, Equatable, Sendable {
        let revisionID: UUID
        /// The drawing file. The thumbnail loader turns it into a picture through a signed link.
        let mediaAssetID: UUID
        let authorUserID: UUID
        let canvasSide: Double?

        enum CodingKeys: String, CodingKey {
            case revisionID = "revision_id"
            case mediaAssetID = "media_asset_id"
            case authorUserID = "author_user_id"
            case canvasSide = "canvas_side"
        }
    }

    nonisolated struct Memory: Codable, Equatable, Sendable {
        let memoryID: UUID
        let title: String
        let photoMediaAssetID: UUID?

        enum CodingKeys: String, CodingKey {
            case memoryID = "memory_id"
            case title
            case photoMediaAssetID = "photo_media_asset_id"
        }
    }

    let kind: Kind
    /// The couple-local date the content belongs to (`yyyy-MM-dd`).
    let contentDate: String
    /// True when the content is from this month and day in an earlier year.
    let onThisDay: Bool
    let question: Question?
    let drawing: Drawing?
    let memory: Memory?

    enum CodingKeys: String, CodingKey {
        case kind
        case contentDate = "content_date"
        case onThisDay = "on_this_day"
        case question
        case drawing
        case memory
    }

    /// Where a tap on the card goes.
    nonisolated enum Destination: Equatable {
        case questionChat(instanceID: UUID)
        case drawingHistory
        case memory(id: UUID)
    }

    /// Nil when the item's kind has no matching content, which the server never sends.
    var destination: Destination? {
        switch kind {
        case .question: question.map { .questionChat(instanceID: $0.instanceID) }
        case .drawing: drawing.map { _ in .drawingHistory }
        case .memory: memory.map { .memory(id: $0.memoryID) }
        }
    }

    /// The content date as a point in time, for relative wording like "3 weeks ago". Noon, so a
    /// time zone shift cannot move it to another day.
    var contentDay: Date? {
        let parts = contentDate.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return Calendar.current.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2], hour: 12))
    }

    var contentYear: Int? {
        contentDate.split(separator: "-").first.flatMap { Int($0) }
    }
}
