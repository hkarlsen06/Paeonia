import Foundation

/// Who the couple is, so birthday rows read "Your birthday" and "Oda's birthday".
nonisolated struct CoupleDateNames: Equatable, Sendable {
    var currentUserID: UUID?
    var partnerUserID: UUID?
    var partnerName: String = ""
}

extension CoupleDateEvent {
    /// The row's user-facing name, shared by the Home tile and the timeline.
    func title(names: CoupleDateNames) -> String {
        switch kind {
        case let .milestone(kind):
            String(localized: kind.displayName)
        case let .countdown(countdown):
            countdown.title
        case let .birthday(userID):
            CoupleDateNames.birthdayTitle(for: userID, names: names)
        }
    }
}

extension CoupleDateNames {
    static func birthdayTitle(for userID: UUID, names: CoupleDateNames) -> String {
        userID == names.currentUserID
            ? String(localized: .homeMilestoneBirthdayYours)
            : String(localized: .homeMilestoneBirthdayPartner(names.partnerName))
    }
}
