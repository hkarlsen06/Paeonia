import Foundation
import Testing
@testable import PaeoniaApp

/// A Ludo screen for the roll model: the moves on the board, what the phone
/// kept, and every move the model plays.
@MainActor
private final class RollHarness {
    let gameID = UUID()
    let me: BoardPlayer
    var moves: [Int]
    var canPlayOverride: Bool?
    var holdsAutomaticMoves = false
    var dice: [Int]
    private(set) var kept: LudoSavedRoll?
    private(set) var savedRolls: [LudoSavedRoll] = []
    private(set) var played: [Int] = []
    private(set) var sleeps: [Duration] = []
    private(set) var model: LudoRollModel!

    init(moves: [Int], me: BoardPlayer = .one, dice: [Int] = []) {
        self.moves = moves
        self.me = me
        self.dice = dice
        model = LudoRollModel(
            context: { [unowned self] in self.context },
            store: LudoRollStore(
                load: { [unowned self] in self.kept },
                save: { [unowned self] roll in
                    self.kept = roll
                    self.savedRolls.append(roll)
                }
            ),
            play: { [unowned self] move in
                self.played.append(move)
                self.moves.append(move)
            },
            rollDie: { [unowned self] in self.dice.removeFirst() },
            tumbleDuration: .milliseconds(800),
            sleep: { [unowned self] duration in await self.recordSleep(duration) }
        )
    }

    /// Records the wait. While `holdsAutomaticMoves` is set, the waits before a
    /// move that plays by itself last until it is cleared, so a test can look at
    /// the screen in between.
    func recordSleep(_ duration: Duration) async {
        sleeps.append(duration)
        let isAutomatic = duration == LudoRollDecision.autoMoveDelay || duration == LudoRollDecision.autoPassDelay
        while holdsAutomaticMoves, isAutomatic, !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(5))
        }
    }

    var board: LudoBoard {
        LudoBoard.replay(moves) ?? .initial
    }

    /// The throw of a tap at the position on screen.
    var tapToss: LudoToss {
        .tap(seed: position.tossSeed)
    }

    var position: LudoPosition {
        LudoPosition(gameID: gameID, gameNumber: 1, moveCount: moves.count)
    }

    var context: LudoRollContext {
        LudoRollContext(
            position: position,
            board: board,
            moves: moves,
            me: me,
            canPlay: canPlayOverride ?? (board.outcome == nil && board.next == me),
            prefersReducedMotion: false
        )
    }

    func setKept(_ roll: LudoSavedRoll?) {
        kept = roll
    }

    func position(movesCount: Int) -> LudoPosition {
        LudoPosition(gameID: gameID, gameNumber: 1, moveCount: movesCount)
    }
}

@MainActor
struct LudoRollModelTests {
    /// Player one has pawns on progress 5 and 1, and a 3 moves either one.
    /// Robin missed a 6 three times.
    private static let twoPawns = [15, 16, 9, 8, 8, 14]
    /// Player one has one pawn out on progress 1, so a 3 has one option.
    private static let onePawn = [15]

    @Test func theDieWaitsOnMyTrayAndSaysTapToRoll() async {
        let harness = RollHarness(moves: [])
        #expect(harness.model.die == .idle(side: .one))
        await harness.model.restore()
        #expect(harness.model.die == .ready)
        #expect(harness.model.hint == .tapToRoll)
        #expect(harness.model.movableChoices.isEmpty)
    }

    @Test func aTapSavesTheRollThenTumblesAndShowsTheFace() async {
        let harness = RollHarness(moves: Self.twoPawns, dice: [3])
        await harness.model.restore()
        harness.model.roll()
        // The die tumbles at once.
        #expect(harness.model.die == .rolling(die: 3, side: .one, token: 1, toss: harness.tapToss))
        #expect(harness.model.hint == nil)

        let landed = await waitUntil { harness.model.die == .showing(die: 3, side: .one) }
        #expect(landed)
        // The roll was saved before the die landed, with the position it belongs to.
        #expect(harness.savedRolls == [LudoSavedRoll(position: harness.position, die: 3)])
        #expect(harness.sleeps.first == .milliseconds(800))
        #expect(harness.model.movableChoices == [.first, .second])
        // Two options wait for a tap.
        #expect(harness.played.isEmpty)
    }

    @Test func tappingAPawnPlaysTheRollAndTheChoice() async {
        let harness = RollHarness(moves: Self.twoPawns, dice: [3])
        await harness.model.restore()
        harness.model.roll()
        _ = await waitUntil { harness.model.movableChoices == [.first, .second] }
        await harness.model.choose(.second)
        #expect(harness.played == [LudoBoard.move(die: 3, choice: .second)])
        // The turn went to Robin, so the die moves to Robin's tray.
        #expect(harness.model.die == .idle(side: .two))
    }

    @Test func theOnlyOptionMovesByItselfAfterHalfASecond() async {
        let harness = RollHarness(moves: Self.onePawn, dice: [3])
        await harness.model.restore()
        harness.model.roll()
        let moved = await waitUntil { !harness.played.isEmpty }
        #expect(moved)
        #expect(harness.played == [LudoBoard.move(die: 3, choice: .first)])
        #expect(harness.sleeps.contains(.milliseconds(500)))
    }

    @Test func aMissedSixPassesByItselfAndLeavesTwoTries() async {
        let harness = RollHarness(moves: [], dice: [3])
        harness.holdsAutomaticMoves = true
        await harness.model.restore()
        harness.model.roll()
        let hinted = await waitUntil { harness.model.hint == .noMove(die: 3) }
        #expect(hinted)
        #expect(harness.model.movableChoices == [.pass])
        #expect(harness.played.isEmpty)

        harness.holdsAutomaticMoves = false
        let passed = await waitUntil { !harness.played.isEmpty }
        #expect(passed)
        #expect(harness.played == [LudoBoard.move(die: 3, choice: .pass)])
        #expect(harness.sleeps.contains(.milliseconds(1_200)))
        // No pawn is out, so I roll again with two tries left.
        #expect(harness.model.die == .ready)
        #expect(harness.model.hint == .triesLeft(2))
    }

    @Test func theThirdMissedSixPassesTheTurn() async {
        let misses = [LudoBoard.move(die: 3, choice: .pass), LudoBoard.move(die: 5, choice: .pass)]
        let harness = RollHarness(moves: misses, dice: [1])
        await harness.model.restore()
        #expect(harness.model.hint == .triesLeft(1))
        harness.model.roll()
        let passed = await waitUntil { !harness.played.isEmpty }
        #expect(passed)
        #expect(harness.board.next == .two)
        #expect(harness.model.die == .idle(side: .two))
    }

    @Test func aSixGivesAnotherRollWithRollAgain() async {
        let harness = RollHarness(moves: Self.twoPawns, dice: [6])
        await harness.model.restore()
        harness.model.roll()
        _ = await waitUntil { harness.model.movableChoices == [.first, .second] }
        await harness.model.choose(.first)
        // Still my turn on a new position: the die is back on my tray.
        #expect(harness.model.die == .ready)
        #expect(harness.model.hint == .rollAgain)
    }

    @Test func aKeptRollShowsAgainWithoutTumbling() async {
        let harness = RollHarness(moves: Self.twoPawns)
        harness.setKept(LudoSavedRoll(position: harness.position, die: 4))
        await harness.model.restore()
        #expect(harness.model.die == .showing(die: 4, side: .one))
        #expect(harness.model.movableChoices == harness.board.legalChoices(die: 4))
        #expect(harness.savedRolls.isEmpty)
    }

    @Test func aRollFromAnEarlierPositionIsDiscarded() async {
        let harness = RollHarness(moves: Self.twoPawns)
        harness.setKept(LudoSavedRoll(position: harness.position(movesCount: 3), die: 4))
        await harness.model.restore()
        #expect(harness.model.die == .ready)
        #expect(harness.model.movableChoices.isEmpty)
    }

    @Test func itIsRobinsTurnSoTheDieSitsOnRobinsTray() async {
        let harness = RollHarness(moves: [15, 9])
        await harness.model.restore()
        #expect(harness.board.next == .two)
        #expect(harness.model.die == .idle(side: .two))
        #expect(harness.model.hint == nil)
    }

    @Test func robinsMoveLeavesTheTumbleToTheBoard() async {
        // Robin missed a 6 three times, the last with a 5 (move 14), and the board
        // is still replaying it. The board tumbles Robin's die itself, so the
        // model only names the tray.
        let harness = RollHarness(moves: [15, 9, 8, 8, 14])
        harness.canPlayOverride = false
        await harness.model.restore()
        #expect(harness.model.die == .idle(side: .one))
        #expect(harness.model.movableChoices.isEmpty)
    }

    // MARK: Live rolls

    @Test func myRollGoesLiveAsTheTumbleStarts() async {
        let harness = RollHarness(moves: Self.twoPawns, dice: [3])
        var announced: [LudoSavedRoll] = []
        harness.model.announce = { roll, _ in announced.append(roll) }
        await harness.model.restore()
        #expect(harness.model.ownRoll == nil)
        harness.model.roll()
        let roll = LudoSavedRoll(position: harness.position, die: 3)
        #expect(announced == [roll])
        // It is sent again when Robin opens the game, until the move lands.
        #expect(harness.model.ownRoll == roll)
    }

    @Test func aKeptRollGoesLiveAgainWhenItComesBack() async {
        let harness = RollHarness(moves: Self.twoPawns)
        var announced: [LudoSavedRoll] = []
        harness.model.announce = { roll, _ in announced.append(roll) }
        harness.setKept(LudoSavedRoll(position: harness.position, die: 4))
        await harness.model.restore()
        #expect(announced == [LudoSavedRoll(position: harness.position, die: 4)])
    }

    @Test func robinsLiveRollTumblesOnRobinsTray() async {
        let harness = RollHarness(moves: [15, 9])
        await harness.model.restore()
        harness.model.receivePartnerRoll(LudoSavedRoll(position: harness.position, die: 4))
        #expect(harness.model.die == .rolling(die: 4, side: .two, token: 1, toss: harness.tapToss))
        let landed = await waitUntil { harness.model.die == .showing(die: 4, side: .two) }
        #expect(landed)
        // The same roll again, as when Robin's phone resends it, does not tumble twice.
        harness.model.receivePartnerRoll(LudoSavedRoll(position: harness.position, die: 4))
        #expect(harness.model.die == .showing(die: 4, side: .two))
    }

    @Test func aLiveRollThatArrivesBeforeRobinsMoveWaitsForTheBoard() async {
        let harness = RollHarness(moves: [15, 9])
        await harness.model.restore()
        // Robin rolls a 6, moves, and rolls again before the move reaches this phone.
        harness.model.receivePartnerRoll(LudoSavedRoll(position: harness.position(movesCount: 3), die: 2))
        #expect(harness.model.die == .idle(side: .two))
        harness.moves.append(15)
        harness.model.update()
        #expect(harness.model.die == .rolling(die: 2, side: .two, token: 1, toss: harness.tapToss))
    }

    @Test func aThrownDieCarriesItsThrowToRobin() async {
        let harness = RollHarness(moves: Self.twoPawns, dice: [5])
        var announced: [LudoToss?] = []
        harness.model.announce = { _, toss in announced.append(toss) }
        await harness.model.restore()
        let toss = LudoToss.tap(seed: 7)
        harness.model.roll(toss)
        #expect(harness.model.die == .rolling(die: 5, side: .one, token: 1, toss: toss))
        #expect(announced == [toss])
    }

    @Test func robinsThrowIsPlayedHereAndKeptWhenTheRollIsResent() async {
        let harness = RollHarness(moves: [15, 9])
        await harness.model.restore()
        let toss = LudoToss.tap(seed: 11)
        let roll = LudoSavedRoll(position: harness.position, die: 4)
        harness.model.receivePartnerRoll(roll, toss: toss)
        #expect(harness.model.die == .rolling(die: 4, side: .two, token: 1, toss: toss))
        // Robin's phone resends the roll without the throw when this phone opens the game.
        harness.model.receivePartnerRoll(roll)
        #expect(harness.model.die == .rolling(die: 4, side: .two, token: 1, toss: toss))
    }

    @Test func aLiveRollForAnEarlierPositionIsIgnored() async {
        let harness = RollHarness(moves: [15, 9])
        await harness.model.restore()
        harness.model.receivePartnerRoll(LudoSavedRoll(position: harness.position(movesCount: 1), die: 5))
        #expect(harness.model.die == .idle(side: .two))
    }
}
