import Foundation

/// The three parts of a figure, in the order they are drawn. The raw value is
/// the part's index on the server.
nonisolated enum ExquisiteCorpsePartKind: Int, Codable, CaseIterable, Sendable {
    case head
    case body
    case legs

    /// The part drawn after this one, or nil after the legs.
    var next: ExquisiteCorpsePartKind? {
        Self(rawValue: rawValue + 1)
    }

    /// The next drawer sees the bottom of this part, so it is clipped to a strip
    /// and the strip is uploaded on its own. Nobody draws after the legs.
    var hasStrip: Bool {
        self != .legs
    }

    /// The drawer is told where the next drawer's view starts.
    var showsFoldLine: Bool {
        hasStrip
    }
}
