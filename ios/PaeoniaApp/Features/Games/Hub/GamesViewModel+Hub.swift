import Foundation

/// The hub's order rules.
extension GamesViewModel {
    /// The games the partner has open, in the server's order.
    nonisolated static func partnerGames(in overview: RemoteGamesOverview?) -> [GameKind] {
        (overview?.presence ?? []).filter(\.partnerPresent).map(\.kind)
    }

    /// When either partner last had each game open, for the games ever opened.
    nonisolated static func lastPlayed(in overview: RemoteGamesOverview?) -> [GameKind: Date] {
        var lastPlayed: [GameKind: Date] = [:]
        for entry in overview?.presence ?? [] {
            lastPlayed[entry.kind] = entry.lastPlayedAt
        }
        return lastPlayed
    }

    /// The game the partner just opened. Both lists are freshest first. Leaving
    /// one of two open games opens nothing.
    nonisolated static func openedPartnerGame(from old: [GameKind], to new: [GameKind]) -> GameKind? {
        new.first { !old.contains($0) }
    }

    /// The games the partner is in, then the games waiting for this person, played
    /// most recently first.
    nonisolated static func featuredOrder(
        _ kinds: [GameKind],
        partnerGames: [GameKind],
        yourTurn: Set<GameKind>,
        lastPlayed: [GameKind: Date]
    ) -> [GameKind] {
        let catalog = GameKind.allCases.filter(kinds.contains)
        let rest = catalog.filter { !partnerGames.contains($0) }
        let waiting = recentFirst(rest.filter(yourTurn.contains), lastPlayed: lastPlayed)
        return partnerGames.filter(catalog.contains) + waiting
    }

    /// The game for "Today's pick", the same on both phones on a couple day, because it
    /// reads only the server's `today` and play times. It takes turns, by day, through the
    /// games neither partner opened since the start (UTC) of the day a week before
    /// `today`, in catalog order. When every game was opened in that time, it is the one
    /// played longest ago.
    nonisolated static func todaysPick(
        _ kinds: [GameKind],
        lastPlayed: [GameKind: Date],
        today: LockScreenCalendarDate
    ) -> GameKind? {
        let catalog = GameKind.allCases.filter(kinds.contains)
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = .gmt
        let cutoff = today.startOfDay(in: utc).map { $0.addingTimeInterval(-7 * 86_400) } ?? .distantPast
        let rested = catalog.filter { lastPlayed[$0].map { $0 < cutoff } ?? true }
        guard rested.isEmpty else {
            let day = today.dayNumber
            return rested[((day % rested.count) + rested.count) % rested.count]
        }
        return catalog.min { lastPlayed[$0, default: .distantPast] < lastPlayed[$1, default: .distantPast] }
    }

    /// The games played most recently first, then the games neither partner ever
    /// opened in catalog order.
    nonisolated static func recentFirst(_ kinds: [GameKind], lastPlayed: [GameKind: Date]) -> [GameKind] {
        let catalog = GameKind.allCases.filter(kinds.contains)
        let played = catalog.filter { lastPlayed[$0] != nil }
            .sorted { lastPlayed[$0, default: .distantPast] > lastPlayed[$1, default: .distantPast] }
        return played + catalog.filter { lastPlayed[$0] == nil }
    }
}
