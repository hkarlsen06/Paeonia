import Foundation

/// What the partner is doing, as the screens say it. It comes from the role the
/// partner's phone announces in the relay room, and from their heartbeat when
/// the room says nothing.
nonisolated enum ExquisiteCorpsePartnerPresence: Equatable, Sendable {
    case away
    /// Has the game screen open, and the room does not say more.
    case here
    /// In the live room, drawing their part.
    case drawing
    /// In the live room, watching the folded paper.
    case watching
    /// Looking at the reveal.
    case result

    /// Reads the role the partner's phone announced. `isHeartbeatFresh` is the
    /// server's word for a partner whose phone is not in the room.
    init(_ activity: WidgetLivePresence.PartnerActivity, isHeartbeatFresh: Bool) {
        switch activity {
        case .drawing: self = .drawing
        case .watching: self = .watching
        case .result: self = .result
        // The game never sends `choosing`, so only `present` ends up here.
        case .present, .choosing: self = .here
        case .away: self = isHeartbeatFresh ? .here : .away
        }
    }

    var isHere: Bool {
        self != .away
    }

    /// The partner's phone told the room what it is doing.
    var isInRoom: Bool {
        self != .away && self != .here
    }

    /// The left side of the drawing screen's live row.
    func drawingLine(partnerName: String) -> LocalizedStringResource {
        switch self {
        case .watching: .exquisiteCorpseDrawWatching(partnerName)
        case .here, .drawing, .result: .exquisiteCorpseDrawHere(partnerName)
        case .away: .exquisiteCorpseDrawLater(partnerName)
        }
    }
}

nonisolated extension ExquisiteCorpsePartKind {
    /// The part drawn before this one, or nil for the head.
    var previous: ExquisiteCorpsePartKind? {
        Self(rawValue: rawValue - 1)
    }

    /// The drawer sees the bottom of the part above, as a strip over the canvas.
    var hasStripAbove: Bool {
        self != .head
    }
}
