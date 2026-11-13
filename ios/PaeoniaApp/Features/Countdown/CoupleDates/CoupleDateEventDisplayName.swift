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
        case let .visit(visit):
            visit.timelineTitle
        }
    }

    /// The name on the Us tab calendar tile: a milestone's short name, otherwise the title.
    func tileTitle(names: CoupleDateNames) -> String {
        if case let .milestone(kind) = kind {
            String(localized: kind.shortName)
        } else {
            title(names: names)
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
