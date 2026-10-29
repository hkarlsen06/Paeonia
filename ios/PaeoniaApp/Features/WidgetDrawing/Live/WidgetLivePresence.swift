import Foundation

/// Who else is in the couple's room on the relay, and what they are doing.
/// The relay announces sockets with `welcome`, `joined`, and `left`. Each app
/// then says what it is doing with a `hello`.
nonisolated struct WidgetLivePresence {
    /// The cases are in the order the partner's activity picks from when several
    /// sockets are in the widget canvas's room. The widget canvas sends only
    /// `drawing` and `watching`. The last three are for Draw & Guess.
    enum Role: String, Codable, Sendable, CaseIterable {
        /// On the drawing canvas.
        case drawing
        /// Looking at the widget on the Home tab, or at a drawing as it is made.
        case watching
        /// Game only: on the screen where a word is picked.
        case choosing
        /// Game only: looking at the result of a round.
        case result
        /// Game only: in the game on any other screen.
        case present
    }

    enum PartnerActivity: Equatable {
        case away
        case watching
        case drawing
        case choosing
        case result
        case present

        init(_ role: Role) {
            switch role {
            case .drawing: self = .drawing
            case .watching: self = .watching
            case .choosing: self = .choosing
            case .result: self = .result
            case .present: self = .present
            }
        }
    }

    /// Draw & Guess: a phone has one socket in the game's room, so another
    /// socket of the partner's is an old one the relay has not closed yet, such
    /// as after their phone locked or lost signal. It keeps the role it had, so
    /// only the socket that said hello last counts.
    let countsLatestHelloOnly: Bool
    private(set) var ownID: String?
    /// The partner's sockets in the room, including ones that have not said hello yet.
    private(set) var peerCount = 0
    private var roles: [String: Role] = [:]
    private var renewedAt: [String: Date] = [:]

    init(countsLatestHelloOnly: Bool = false) {
        self.countsLatestHelloOnly = countsLatestHelloOnly
    }

    var partnerActivity: PartnerActivity {
        guard peerCount > 0, !roles.isEmpty else {
            return .away
        }
        let present = Set(roles.values)
        return Role.allCases.first(where: present.contains).map(PartnerActivity.init) ?? .away
    }

    mutating func welcome(id: String?, peers: Int) {
        ownID = id
        peerCount = max(0, peers)
        roles = [:]
        renewedAt = [:]
    }

    mutating func joined() {
        peerCount += 1
    }

    mutating func hello(from id: String, role: Role, now: Date = Date()) {
        if countsLatestHelloOnly {
            roles = [:]
            renewedAt = [:]
        }
        roles[id] = role
        renewedAt[id] = now
    }

    /// Each connected surface repeats hello every 5 seconds. Dropped sockets lose their role after 15.
    mutating func expire(now: Date = Date()) {
        for id in roles.keys where now.timeIntervalSince(renewedAt[id] ?? .distantPast) >= 15 {
            roles[id] = nil
            renewedAt[id] = nil
        }
    }

    mutating func left(id: String?) {
        peerCount = max(0, peerCount - 1)
        if let id {
            roles[id] = nil
            renewedAt[id] = nil
        }
        if peerCount == 0 {
            roles = [:]
        }
    }

    mutating func reset() {
        self = WidgetLivePresence(countsLatestHelloOnly: countsLatestHelloOnly)
    }
}
