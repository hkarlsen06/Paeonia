import Foundation
@testable import PaeoniaApp

/// Builders for the resolver tests. A test struct supplies `me` and `partner`.
protocol MindMeldResolverFixtures {
    var me: UUID { get }
    var partner: UUID { get }
}

extension MindMeldResolverFixtures {
    /// One couple for every state, so the states can be ordered (`isOlder`).
    static var coupleID: UUID {
        UUID(uuid: (0x33, 0x33, 0x33, 0x33, 0x33, 0x33, 0x33, 0x33, 0x33, 0x33, 0x33, 0x33, 0x33, 0x33, 0x33, 0x33))
    }

    var at: Date { Date(timeIntervalSince1970: 1_800_000_000) }

    var resolver: MindMeldResolver { MindMeldResolver(userID: me) }

    func revealed(
        _ number: Int,
        _ mine: String = "ocean",
        _ theirs: String = "sushi",
        outcome: MindMeldOutcome = .miss,
        seen: Bool = true,
        countedBy: UUID? = nil
    ) -> RemoteMindMeldRound {
        RemoteMindMeldRound(
            id: UUID(),
            roundNumber: number,
            state: .revealed,
            outcome: outcome,
            countedByUserID: countedBy,
            myWord: mine,
            myLockedAt: at,
            partnerLocked: true,
            partnerLockedAt: at,
            partnerWord: theirs,
            revealedAt: at,
            myRevealSeenAt: seen ? at : nil
        )
    }

    func open(_ number: Int, mine: String? = nil, partnerLocked: Bool = false) -> RemoteMindMeldRound {
        RemoteMindMeldRound(
            id: UUID(),
            roundNumber: number,
            state: .open,
            outcome: nil,
            countedByUserID: nil,
            myWord: mine,
            myLockedAt: mine == nil ? nil : at,
            partnerLocked: partnerLocked,
            partnerLockedAt: partnerLocked ? at : nil,
            partnerWord: nil,
            revealedAt: nil,
            myRevealSeenAt: nil
        )
    }

    func game(
        _ state: MindMeldGameState = .playing,
        number: Int = 1,
        rounds: [RemoteMindMeldRound],
        reason: MindMeldEndReason? = nil,
        endedBy: UUID? = nil,
        endSeen: Bool = false
    ) -> RemoteMindMeldGame {
        RemoteMindMeldGame(
            id: UUID(),
            gameNumber: number,
            state: state,
            endReason: reason,
            endedByUserID: endedBy,
            endedAt: state == .playing ? nil : at,
            maxRounds: 10,
            myEndSeenAt: endSeen ? at : nil,
            meldNumber: state == .melded ? 1 : nil,
            isRecord: false,
            createdByUserID: me,
            createdAt: at,
            updatedAt: at,
            version: 1,
            rounds: rounds
        )
    }

    func state(current: RemoteMindMeldGame?, previous: RemoteMindMeldGame? = nil) -> RemoteMindMeldState {
        RemoteMindMeldState(
            userID: me,
            partnerUserID: partner,
            coupleID: Self.coupleID,
            dataEpoch: "",
            current: current,
            previous: previous,
            stats: RemoteMindMeldStats(melds: 0, fewestRounds: nil, games: 1)
        )
    }

    func resolve(
        _ state: RemoteMindMeldState?,
        pending: MindMeldPendingWork = .none,
        hasLoaded: Bool = true
    ) -> MindMeldResolution {
        resolver.resolve(state: state, hasLoaded: hasLoaded, pending: pending)
    }

    func resolve(_ game: RemoteMindMeldGame, pending: MindMeldPendingWork = .none) -> MindMeldResolution {
        resolve(state(current: game), pending: pending)
    }
}
