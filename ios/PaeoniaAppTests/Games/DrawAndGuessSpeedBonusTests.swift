import Foundation
import Testing
@testable import PaeoniaApp

@MainActor
struct DrawAndGuessSpeedBonusTests {
    private let now = GameFixture.now

    private func round(drawing: Bool, submittedAgo: TimeInterval = 5) -> DrawAndGuessRoundView {
        var remote = GameFixture.round(
            state: drawing ? .guessing : .drawing,
            drawer: GameFixture.partner,
            hasDrawing: drawing
        )
        if drawing {
            remote = RemoteDrawAndGuessRound(
                id: remote.id, roundNumber: remote.roundNumber, drawerUserID: remote.drawerUserID,
                guesserUserID: remote.guesserUserID, state: remote.state, difficulty: remote.difficulty,
                word: remote.word, points: remote.points, drawingMediaAssetID: remote.drawingMediaAssetID,
                drawingSubmittedAt: now.addingTimeInterval(-submittedAgo), startedAt: remote.startedAt,
                guesserFirstSeenAt: nil, endedAt: nil, solveMs: nil, speedBonus: 0, firstTryBonus: 0,
                hintsUsed: 0, personalBest: false, drawerResultSeenAt: nil,
                guesserResultSeenAt: nil, attempts: []
            )
        }
        return DrawAndGuessRoundView(remote)
    }

    private func bonus(
        _ style: GamePlayStyle?,
        _ round: DrawAndGuessRoundView?,
        seenAgo: TimeInterval? = nil
    ) -> DrawAndGuessSpeedBonus {
        DrawAndGuessSpeedBonus.make(
            playStyle: style,
            round: round,
            userID: GameFixture.me,
            firstSeenAt: seenAgo.map { now.addingTimeInterval(-$0) }
        )
    }

    @Test func playingTogetherNeverShowsABonus() {
        #expect(bonus(.together, round(drawing: true), seenAgo: 1) == .hidden)
        #expect(bonus(nil, round(drawing: true), seenAgo: 1) == .hidden)
    }

    @Test func theDrawersOwnRoundHasNoBonus() {
        let mine = DrawAndGuessRoundView(GameFixture.round(state: .guessing, drawer: GameFixture.me, hasDrawing: true))

        #expect(bonus(.against, mine, seenAgo: 1) == .hidden)
    }

    @Test func theBonusHasTwoTiersAndThenNothing() {
        func tier(seenAgo: TimeInterval?) -> Int {
            bonus(.against, round(drawing: true), seenAgo: seenAgo).tier(at: now)
        }

        #expect(tier(seenAgo: nil) == 2)
        #expect(tier(seenAgo: 0) == 2)
        #expect(tier(seenAgo: 15) == 2)
        #expect(tier(seenAgo: 15.5) == 1)
        #expect(tier(seenAgo: 30) == 1)
        #expect(tier(seenAgo: 30.5) == 0)
        #expect(DrawAndGuessSpeedBonus.hidden.tier(at: now) == 0)
    }

    @Test func whileThePartnerStillDrawsTheThirtySecondsCountFromTheFirstLook() {
        let live = bonus(.against, round(drawing: false), seenAgo: 10)

        #expect(live == .counting(startedAt: now.addingTimeInterval(-10)))
        #expect(live.remaining(at: now) == 20)
        #expect(!bonus(.against, round(drawing: false), seenAgo: 40).isAvailable(at: now))
    }

    @Test func sendingTheDrawingDoesNotRestartTheThirtySeconds() {
        // Watched live from 20 s ago, sent 5 s ago: the clock started 20 s ago.
        let afterSubmit = bonus(.against, round(drawing: true, submittedAgo: 5), seenAgo: 20)
        #expect(afterSubmit.remaining(at: now) == 10)

        // Sent 50 s ago but first seen 10 s ago: the clock started 10 s ago.
        let afterSeen = bonus(.against, round(drawing: true, submittedAgo: 50), seenAgo: 10)
        #expect(afterSeen.remaining(at: now) == 20)
    }
}
