import SwiftUI

/// The cards a letter starts from. The server knows only the key
/// (`LETTER_TEMPLATE_KEYS` in `backend/convex/lib/letters.ts`).
struct LetterTemplate: Identifiable {
    nonisolated enum Key: String, Codable, CaseIterable, Sendable {
        case blank
        case goodMorning = "good_morning"
        case goodNight = "good_night"
        case birthday
        case anniversary
        case missYou = "miss_you"
        case goodLuck = "good_luck"
        case thankYou = "thank_you"
    }

    let key: Key
    let name: LocalizedStringResource
    /// What the note starts with. The author can change it. Empty for the blank card.
    let firstLine: LocalizedStringResource?
    let art: ImageResource

    var id: Key { key }

    static let all: [LetterTemplate] = Key.allCases.map { LetterTemplate($0) }

    init(_ key: Key) {
        self.key = key
        switch key {
        case .blank:
            name = .mailTemplateBlankName
            firstLine = nil
            art = .mailTemplateBlank
        case .goodMorning:
            name = .mailTemplateGoodMorningName
            firstLine = .mailTemplateGoodMorningFirstLine
            art = .mailTemplateGoodMorning
        case .goodNight:
            name = .mailTemplateGoodNightName
            firstLine = .mailTemplateGoodNightFirstLine
            art = .mailTemplateGoodNight
        case .birthday:
            name = .mailTemplateBirthdayName
            firstLine = .mailTemplateBirthdayFirstLine
            art = .mailTemplateBirthday
        case .anniversary:
            name = .mailTemplateAnniversaryName
            firstLine = .mailTemplateAnniversaryFirstLine
            art = .mailTemplateAnniversary
        case .missYou:
            name = .mailTemplateMissYouName
            firstLine = .mailTemplateMissYouFirstLine
            art = .mailTemplateMissYou
        case .goodLuck:
            name = .mailTemplateGoodLuckName
            firstLine = .mailTemplateGoodLuckFirstLine
            art = .mailTemplateGoodLuck
        case .thankYou:
            name = .mailTemplateThankYouName
            firstLine = .mailTemplateThankYouFirstLine
            art = .mailTemplateThankYou
        }
    }

    /// The note a new letter on this card starts with.
    var startingBody: String {
        firstLine.map { String(localized: $0) } ?? ""
    }
}
