import PencilKit
import SwiftUI

/// How a drawing travels between phones.
enum GameCanvas {
    /// Every drawing is stored and sent on a square canvas of this many points.
    /// Phones draw on canvases of different sizes, so the drawer scales to this
    /// size before sending and the guesser scales to their own canvas. It is the
    /// size the live room already uses.
    nonisolated static let canonicalSide: CGFloat = WidgetLiveRoom.side

    /// Scales a drawing made on a canvas of `side` points to the canonical size.
    nonisolated static func canonical(_ drawing: PKDrawing, fromSide side: CGFloat) -> PKDrawing {
        drawing.scaled(fromSide: side, toSide: canonicalSide)
    }

    /// Scales a canonical drawing to a canvas of `side` points.
    nonisolated static func fitted(_ drawing: PKDrawing, toSide side: CGFloat) -> PKDrawing {
        drawing.scaled(fromSide: canonicalSide, toSide: side)
    }
}
