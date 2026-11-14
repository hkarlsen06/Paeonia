import Foundation

/// The four parts of a figure, in the order they are drawn. The raw value is
/// the part's index on the server.
nonisolated enum ExquisiteCorpsePartKind: Int, Codable, CaseIterable, Sendable {
    case head
    case body
    case legs
    case feet

    /// The part drawn after this one, or nil after the feet.
    var next: ExquisiteCorpsePartKind? {
        Self(rawValue: rawValue + 1)
    }

    /// The next drawer sees the bottom of this part, so it is clipped to a strip
    /// and the strip is uploaded on its own. Nobody draws after the feet.
    var hasStrip: Bool {
        next != nil
    }

    /// The drawer is told where the next drawer's view starts.
    var showsFoldLine: Bool {
        hasStrip
    }
}

nonisolated extension RemoteExquisiteCorpseFigure {
    /// Whether `userID` draws the next figure's head. Every part passes the turn
    /// to the partner except the feet, whose drawer keeps it and starts the next
    /// figure. So the starter draws the head and the legs, the partner draws the
    /// body and the feet, and the partner starts the next figure. The server's
    /// `progressAfter` (`backend/convex/lib/exquisiteCorpse.ts`) holds the same rule.
    func startsNextFigure(_ userID: UUID?) -> Bool {
        starterUserID != userID
    }
}
