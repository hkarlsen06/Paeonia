import Foundation

/// Who else is in the couple's room on the relay, and what they are doing.
/// The relay announces sockets with `welcome`, `joined`, and `left`. Each app
/// then says whether it is drawing or watching with a `hello`.
nonisolated struct WidgetLivePresence {
    enum Role: String, Codable, Sendable {
        /// On the drawing canvas.
        case drawing
        /// Looking at the widget on the Home tab.
        case watching
    }

    enum PartnerActivity: Equatable {
        case away
        case watching
        case drawing
    }

    private(set) var ownID: String?
    /// The partner's sockets in the room, including ones that have not said hello yet.
    private(set) var peerCount = 0
    private var roles: [String: Role] = [:]

    var partnerActivity: PartnerActivity {
        guard peerCount > 0, !roles.isEmpty else {
            return .away
        }
        return roles.values.contains(.drawing) ? .drawing : .watching
    }

    mutating func welcome(id: String?, peers: Int) {
        ownID = id
        peerCount = max(0, peers)
        roles = [:]
    }

    mutating func joined() {
        peerCount += 1
    }

    mutating func hello(from id: String, role: Role) {
        roles[id] = role
    }

    mutating func left(id: String?) {
        peerCount = max(0, peerCount - 1)
        if let id {
            roles[id] = nil
        }
        if peerCount == 0 {
            roles = [:]
        }
    }

    mutating func reset() {
        self = WidgetLivePresence()
    }
}
