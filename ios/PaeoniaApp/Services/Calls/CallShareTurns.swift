import Foundation

/// Whose screen share runs when both partners start one. One share runs at a time, and the newest
/// share takes over, as in FaceTime. Arrival order cannot say which share is newest, because two
/// shares that start inside the relay's delay each arrive after the other phone's own. So each
/// share takes a turn one higher than any turn this call has used on either phone, and the phone
/// with the lower turn stops its share. Equal turns mean both started before either heard the
/// other, and then the caller's share stays.
nonisolated struct CallShareTurns: Equatable, Sendable {
    /// The turn of this phone's running share, nil while it shares nothing.
    private(set) var own: Int?
    /// The turn of the partner's running share, nil while they share nothing.
    private(set) var partners: Int?
    /// The highest turn either phone has used in this call.
    private var latest = 0

    mutating func startOwn() {
        latest += 1
        own = latest
    }

    mutating func stopOwn() {
        own = nil
    }

    mutating func partnerChanged(to turn: Int?) {
        partners = turn
        latest = max(latest, turn ?? 0)
    }

    /// True when both share and the partner's share should run instead of this phone's.
    func ownGivesWay(isCaller: Bool) -> Bool {
        guard let own, let partners else { return false }
        return partners > own || (partners == own && !isCaller)
    }
}
