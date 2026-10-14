import Foundation

extension LookBackItem.Answer {
    /// What the card shows for one answer: the words when there are any, otherwise how it was
    /// answered.
    nonisolated enum Display: Equatable {
        case text(String)
        case photo
        case voice
        /// A "pick one of you" answer, with the person picked.
        case choice(UUID)
        case none
    }

    nonisolated var display: Display {
        if let text = text?.trimmedNonEmpty { return .text(text) }
        if hasPhoto { return .photo }
        if hasVoice { return .voice }
        if let selectedUserID { return .choice(selectedUserID) }
        return .none
    }
}
