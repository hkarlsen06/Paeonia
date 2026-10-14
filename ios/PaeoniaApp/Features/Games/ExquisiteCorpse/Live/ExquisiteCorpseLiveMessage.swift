import Foundation

/// Exquisite corpse's own message on its relay room. Every message names the
/// part it is about, and the partner ignores a message about any other part.
/// Nothing in it is saved. The part itself still goes through Convex.
///
/// The hidden part of a drawing never travels here. The pen messages carry a
/// coarse position only, and the strip carries only ink at or below the fold.
nonisolated enum ExquisiteCorpseLiveMessage: GameLiveMessage, Equatable {
    static let game = "exquisite_corpse"

    /// Where the pen is on the part's square, as fractions from 0 to 1. Both are
    /// nil when the pen lifts.
    case pen(partID: UUID, x: Double?, y: Double?)
    /// The whole strip so far, as a `PKDrawing` in base64 at the canonical side.
    /// It is the whole state, so a lost message never leaves strokes missing.
    case strip(partID: UUID, drawing: String)
    /// The drawer tapped Done.
    case done(partID: UUID)

    var partID: UUID {
        switch self {
        case let .pen(partID, _, _), let .strip(partID, _), let .done(partID):
            partID
        }
    }

    // On the wire this is one flat object with a `type` field, as in
    // `{"type":"pen","part":"...","x":0.25,"y":0.5}`.
    private enum CodingKeys: String, CodingKey {
        case type
        case part
        case x
        case y
        case drawing
    }

    private enum Kind: String, Codable {
        case pen
        case strip
        case done
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let partID = try container.decode(UUID.self, forKey: .part)
        switch try container.decode(Kind.self, forKey: .type) {
        case .pen:
            self = .pen(
                partID: partID,
                x: try container.decodeIfPresent(Double.self, forKey: .x),
                y: try container.decodeIfPresent(Double.self, forKey: .y)
            )
        case .strip:
            self = .strip(partID: partID, drawing: try container.decode(String.self, forKey: .drawing))
        case .done:
            self = .done(partID: partID)
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(partID, forKey: .part)
        switch self {
        case let .pen(_, x, y):
            try container.encode(Kind.pen, forKey: .type)
            try container.encodeIfPresent(x, forKey: .x)
            try container.encodeIfPresent(y, forKey: .y)
        case let .strip(_, drawing):
            try container.encode(Kind.strip, forKey: .type)
            try container.encode(drawing, forKey: .drawing)
        case .done:
            try container.encode(Kind.done, forKey: .type)
        }
    }
}

/// Turns the drawer's pen into the coarse positions the partner sees as a glow
/// behind the folded paper. A position is the center of a cell of a 20 by 20
/// grid. At most 8 go out each second, none repeats the cell before it, and the
/// lift always goes out. The caller passes the time, so tests need no clock.
nonisolated struct ExquisiteCorpsePenSampler: Sendable {
    /// What goes out: a position, or the lift when both are nil.
    struct Sample: Equatable, Sendable {
        let x: Double?
        let y: Double?

        static let lift = Sample(x: nil, y: nil)
    }

    static let gridSize = 20
    static let maxPerSecond = 8

    private var lastCell: Int?
    private var lastSentAt: TimeInterval?

    /// The pen moved to `x` and `y`, as fractions of the square from 0 to 1.
    /// Returns what to send, or nil to send nothing now.
    mutating func move(x: Double, y: Double, at time: TimeInterval) -> Sample? {
        let column = Self.cell(of: x)
        let row = Self.cell(of: y)
        let cell = row * Self.gridSize + column
        guard cell != lastCell else {
            return nil
        }
        if let lastSentAt, time - lastSentAt < 1 / Double(Self.maxPerSecond) {
            return nil
        }
        lastCell = cell
        lastSentAt = time
        let size = Double(Self.gridSize)
        return Sample(x: (Double(column) + 0.5) / size, y: (Double(row) + 0.5) / size)
    }

    /// The pen lifted. A lift always goes out, and the next position goes out
    /// even when it is in the same cell as the one before the lift.
    mutating func lift() -> Sample {
        lastCell = nil
        return .lift
    }

    private static func cell(of fraction: Double) -> Int {
        let cell = (fraction * Double(gridSize)).rounded(.down)
        guard cell.isFinite else {
            return 0
        }
        return Int(min(max(cell, 0), Double(gridSize - 1)))
    }
}
