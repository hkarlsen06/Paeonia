import Foundation

nonisolated enum ExquisiteCorpsePartKind: Int, Codable, CaseIterable, Sendable {
    case head
    case body
    case legs
    case feet

    var next: ExquisiteCorpsePartKind? {
        Self(rawValue: rawValue + 1)
    }

    var hasStrip: Bool {
        next != nil
    }

    /// The drawer is told where the next drawer's view starts.
    var showsFoldLine: Bool {
        hasStrip
    }
}

nonisolated extension RemoteExquisiteCorpseFigure {
    func startsNextFigure(_ userID: UUID?) -> Bool {
        starterUserID != userID
    }
}
