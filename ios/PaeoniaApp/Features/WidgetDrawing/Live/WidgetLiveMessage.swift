import Foundation

/// One message on the live drawing relay (`relay/` at the repository root). The
/// relay forwards the app's messages unchanged and sends `welcome`, `joined`,
/// and `left` itself.
nonisolated struct WidgetLiveMessage: Codable, Equatable, Sendable {
    enum Kind: String, Codable, Sendable {
        /// New points of a stroke the partner is drawing right now.
        case live
        /// The partner lifted their finger. The finished stroke follows in `ops`.
        case liveEnd
        /// Finished strokes that were added or changed, and strokes that were removed.
        case ops
        /// Says whether this phone is drawing or watching, after connecting and
        /// whenever someone joins.
        case hello
        /// From the relay, right after connecting. `id` is this socket, and
        /// `peers` is how many of the partner's sockets are in the room.
        case welcome
        /// From the relay: the partner opened the canvas or the Home tab.
        case joined
        /// From the relay: the partner closed it.
        case left
    }

    var type: Kind
    /// The live stroke a `live` or `liveEnd` message belongs to, or the socket
    /// in `welcome`, `joined`, and `left`.
    var id: String?
    /// `PKInk.InkType` raw value.
    var ink: String?
    /// RGBA components in `0...1`.
    var color: [Double]?
    /// The side of the sender's square canvas, so the receiver can scale to its own.
    var side: Double?
    /// `[x, y, timeOffset, azimuth]` per point, in the sender's canvas points.
    var points: [[Double]]?
    /// Base64 `PKDrawing` with the strokes that were added or changed.
    var upserts: String?
    /// Keys (`WidgetLiveStrokeSync.key`) of strokes that were removed.
    var removals: [String]?
    /// Live strokes that the finished strokes in this message replace.
    var ended: [String]?
    /// An `ops` message with every stroke on the sender's canvas, sent to someone
    /// who just joined.
    var snapshot: Bool?
    var peers: Int?
    /// In `hello`: asks the partner's canvas for a snapshot.
    var needsCanvas: Bool?
    /// In `hello`: the sender's socket id.
    var from: String?
    /// In `hello`: `WidgetLivePresence.Role` raw value.
    var role: String?
    /// In `live`: how every point looks, learned from real strokes on the
    /// sender's phone. Sizes are in the sender's canvas points.
    var pointStyle: WidgetLiveInkCalibration.Style?
}
