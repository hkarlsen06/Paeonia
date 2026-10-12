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
                guesserFirstSeenAt: nil, endedAt: nil, solveMs: nil, speedBonus: 0, memoryID: nil,
                savedByUserID: nil, mySaveResponse: nil, partnerSaveResponse: nil, attempts: []
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

    @Test func whileThePartnerStillDrawsTheBonusStaysOpen() {
        let live = bonus(.against, round(drawing: false), seenAgo: 40)

        #expect(live == .open)
        #expect(live.isAvailable(at: now))
        #expect(live.remaining(at: now) == nil)
    }

    @Test func theThirtySecondsCountFromTheLaterOfSeenAndSubmitted() {
        // Seen 20 s ago but submitted 5 s ago: the clock started 5 s ago.
        let afterSubmit = bonus(.against, round(drawing: true, submittedAgo: 5), seenAgo: 20)
        #expect(afterSubmit.remaining(at: now) == 25)

        // Submitted 50 s ago but first seen 10 s ago: the clock started 10 s ago.
        let afterSeen = bonus(.against, round(drawing: true, submittedAgo: 50), seenAgo: 10)
        #expect(afterSeen.remaining(at: now) == 20)
    }

    @Test func theBonusEndsAfterThirtySecondsAndStaysOver() {
        let late = bonus(.against, round(drawing: true, submittedAgo: 60), seenAgo: 45)

        #expect(late.remaining(at: now) == 0)
        #expect(!late.isAvailable(at: now))
    }

    @Test func aFinishedDrawingNotSeenYetKeepsTheBonusOpen() {
        #expect(bonus(.against, round(drawing: true), seenAgo: nil) == .open)
    }

    @Test func aFinishedRoundHasNoBonusLeft() {
        var finished = round(drawing: true)
        finished.state = .solved

        #expect(bonus(.against, finished, seenAgo: 1) == .hidden)
    }
}
