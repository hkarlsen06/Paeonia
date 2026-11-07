import Foundation

/// The heartbeat that tells the server this game screen is open. The server
/// counts the screen as closed 60 seconds after the last one, and says so in the
/// overview's `partnerPresent`.
nonisolated enum GamePresence {
    /// How often the open screen refreshes its own heartbeat.
    static let heartbeatInterval: Duration = .seconds(30)
}

/// The "Tell [Name] you want to play" button.
nonisolated enum GameInviteState: Equatable, Sendable {
    /// The partner has the game open, so there is nobody to invite.
    case hidden
    case available
    /// An invite went out. The button reads "Sent" until `until`.
    case sent(until: Date)

    /// Each person can send one invite every 15 minutes.
    static let interval: TimeInterval = 15 * 60

    /// - Parameters:
    ///   - lastInviteAt: The server's record of this person's last invite.
    ///   - localSentAt: An invite sent from this phone that the live result has not caught up with yet.
    static func make(
        lastInviteAt: Date?,
        localSentAt: Date? = nil,
        partnerIsHere: Bool,
        now: Date
    ) -> GameInviteState {
        guard !partnerIsHere else {
            return .hidden
        }
        let latest = [lastInviteAt, localSentAt].compactMap { $0 }.max()
        if let latest {
            let until = latest.addingTimeInterval(interval)
            if until > now {
                return .sent(until: until)
            }
        }
        return .available
    }
}

/// How sending an invite ended. The server takes one invite every 15 minutes and
/// answers a second one with `53300`, which means the earlier invite still stands.
nonisolated enum GameInviteDelivery: Equatable, Sendable {
    case sent(at: Date)
    case alreadySent
    case failed(PaeoniaFailure)

    static func send(_ kind: GameKind, through gateway: any GamesGateway) async -> GameInviteDelivery {
        do {
            return .sent(at: try await gateway.sendInvite(kind).sentAt)
        } catch PaeoniaConvexError.server(code: "53300", message: _) {
            return .alreadySent
        } catch {
            return .failed(PaeoniaFailure(error))
        }
    }

    /// When this phone last sent an invite, given `optimistic`, the time the button
    /// was tapped.
    func localSentAt(optimistic: Date?) -> Date? {
        switch self {
        case let .sent(at): at
        case .alreadySent: optimistic
        case .failed: nil
        }
    }

    var failure: PaeoniaFailure? {
        if case let .failed(failure) = self { failure } else { nil }
    }
}
