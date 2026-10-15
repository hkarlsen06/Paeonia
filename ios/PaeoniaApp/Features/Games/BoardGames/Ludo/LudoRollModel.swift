import Observation
import SwiftUI

/// What the roll needs to know about the screen, read each time it updates.
struct LudoRollContext: Equatable {
    /// Nil while there is no game to play.
    let position: LudoPosition?
    let board: LudoBoard
    /// The moves on the board.
    let moves: [Int]
    let me: BoardPlayer
    /// It is this person's turn and the board is ready for a move.
    let canPlay: Bool
    let prefersReducedMotion: Bool
}

/// Where the saved roll lives. The screen binds it to the board games cache.
@MainActor
struct LudoRollStore {
    var load: () async -> LudoSavedRoll?
    var save: (LudoSavedRoll) async -> Void

    static func cache(for viewModel: BoardGameViewModel<LudoBoard>) -> LudoRollStore {
        LudoRollStore(
            load: {
                guard let userID = viewModel.currentUserID else { return nil }
                return await viewModel.dependencies.boardGamesCache.document(ownerUserID: userID).ludoRoll
            },
            save: { roll in
                guard let userID = viewModel.currentUserID else { return }
                await viewModel.dependencies.boardGamesCache.saveLudoRoll(roll, ownerUserID: userID)
            }
        )
    }
}

/// The die and the pawn choice of one Ludo screen. The phone rolls, so the roll
/// is part of the move: a throw rolls, the die tumbles, and the choice plays
/// `LudoBoard.move(die:choice:)` through the board game view model.
///
/// The model keeps the person's roll on this phone before the tumble starts, so
/// reopening the screen shows the same roll. The rules of what happens next
/// are in `LudoRollDecision`.
///
/// Rolls also travel live (see `LudoLiveLink`). `announce` sends mine as the
/// tumble starts. A partner's roll that arrives through `receivePartnerRoll`
/// tumbles their die on this phone at the same time, before their move exists here.
@MainActor
@Observable
final class LudoRollModel {
    private(set) var die: LudoDieState = .idle(side: .one)
    /// The pawns the person can move with the rolled die, or `[.pass]`.
    private(set) var movableChoices: [LudoChoice] = []
    private(set) var hint: LudoHint?

    private enum Phase: Equatable {
        case ready
        case rolling(Int)
        case showing(Int)
        case playing(Int)
    }

    /// The person's turn at one position.
    private struct Turn {
        let position: LudoPosition
        var phase: Phase
    }

    @ObservationIgnored private let context: @MainActor () -> LudoRollContext
    @ObservationIgnored private let store: LudoRollStore
    @ObservationIgnored private let play: @MainActor (Int) async -> Void
    @ObservationIgnored private let rollDie: @MainActor () -> Int
    @ObservationIgnored private let tumbleDuration: Duration
    @ObservationIgnored private let sleep: @Sendable (Duration) async throws -> Void

    @ObservationIgnored private var saved: LudoSavedRoll?
    @ObservationIgnored private var isLoaded = false
    @ObservationIgnored private var turn: Turn?
    @ObservationIgnored private var tumbleCount = 0
    @ObservationIgnored private var task: Task<Void, Never>?
    /// The newest roll my partner sent live. It can arrive before the move that
    /// leads to its position, so it waits until the board gets there.
    @ObservationIgnored private var partnerRoll: LudoSavedRoll?
    /// The position whose partner roll is tumbling or showing.
    @ObservationIgnored private var shownPartnerRoll: LudoPosition?

    /// Sends my roll to my partner's phone as the die starts to tumble, with the
    /// throw when the person threw the die by hand.
    @ObservationIgnored var announce: (@MainActor (LudoSavedRoll, LudoToss?) -> Void)?
    /// How my partner threw the die for `partnerRoll`, when they threw it by hand.
    @ObservationIgnored private var partnerToss: LudoToss?

    init(
        context: @escaping @MainActor () -> LudoRollContext,
        store: LudoRollStore,
        play: @escaping @MainActor (Int) async -> Void,
        // The system random generator.
        rollDie: @escaping @MainActor () -> Int = { Int.random(in: LudoRollDecision.faces) },
        tumbleDuration: Duration = LudoBoardView.tumbleDuration,
        sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
    ) {
        self.context = context
        self.store = store
        self.play = play
        self.rollDie = rollDie
        self.tumbleDuration = tumbleDuration
        self.sleep = sleep
    }

    // MARK: - Lifecycle

    /// Reads the saved roll, then shows the die. Until it ran the die stays idle,
    /// so a kept roll never flashes as a new one. The screen calls it again when
    /// the signed-in person changes, so the turn starts over from their roll.
    func restore() async {
        saved = await store.load()
        isLoaded = true
        turn = nil
        // A partner roll can arrive while this reads. It names its game and
        // position, so it is kept and only shown where it belongs.
        shownPartnerRoll = nil
        cancelTask()
        update()
    }

    /// Works out the die from the screen. Called when the screen changes.
    func update() {
        guard isLoaded else { return }
        let context = context()
        guard context.canPlay, let position = context.position else {
            showTheirTurn(context)
            return
        }
        guard turn?.position != position else { return }
        beginTurn(at: position, context: context)
    }

    func stop() {
        task?.cancel()
        task = nil
    }

    // MARK: - My turn

    private func beginTurn(at position: LudoPosition, context: LudoRollContext) {
        cancelTask()
        turn = Turn(position: position, phase: .ready)
        if let kept = LudoRollDecision.restoredDie(from: saved, at: position) {
            // My partner may have arrived before this roll was back on screen.
            announce?(LudoSavedRoll(position: position, die: kept), nil)
            land(kept, context: context, schedulesAutomaticPass: true)
        } else {
            die = .ready
            movableChoices = []
            hint = LudoRollDecision.hintBeforeRoll(board: context.board, moves: context.moves, me: context.me)
        }
    }

    /// The person throws the die with `toss`, or rolls it with VoiceOver, which has no throw.
    func roll(_ toss: LudoToss? = nil) {
        let context = context()
        guard context.canPlay, let position = context.position, var turn, turn.position == position,
              turn.phase == .ready
        else { return }
        let value = rollDie()
        let roll = LudoSavedRoll(position: position, die: value)
        saved = roll
        let toss = toss ?? .tap(seed: position.tossSeed)
        announce?(roll, toss)
        turn.phase = .rolling(value)
        self.turn = turn
        movableChoices = []
        hint = nil
        let tumbles = !context.prefersReducedMotion
        if tumbles {
            tumbleCount += 1
            die = .rolling(die: value, side: context.me, token: tumbleCount, toss: toss)
        } else {
            die = .showing(die: value, side: context.me)
        }
        task?.cancel()
        // The roll is saved before the die lands, and the tumble waits for it.
        let store = store
        let sleep = sleep
        let tumbleDuration = tumbleDuration
        task = Task { [weak self] in
            await store.save(roll)
            if tumbles {
                try? await sleep(tumbleDuration)
            }
            guard !Task.isCancelled else { return }
            self?.landIfStillMine(value, at: position)
        }
    }

    private func landIfStillMine(_ value: Int, at position: LudoPosition) {
        let context = context()
        guard context.canPlay, context.position == position, turn?.position == position else { return }
        land(value, context: context, schedulesAutomaticPass: true)
    }

    /// The die shows its face and the person's options appear. With no pawn to
    /// move, the turn passes by itself after a moment.
    private func land(_ value: Int, context: LudoRollContext, schedulesAutomaticPass: Bool) {
        guard var turn else { return }
        turn.phase = .showing(value)
        self.turn = turn
        die = .showing(die: value, side: context.me)
        movableChoices = context.board.legalChoices(die: value)
        hint = LudoRollDecision.hintAfterRoll(board: context.board, die: value)
        guard schedulesAutomaticPass, LudoRollDecision.passesByItself(board: context.board, die: value)
        else { return }
        task?.cancel()
        let sleep = sleep
        task = Task { [weak self] in
            try? await sleep(LudoRollDecision.autoPassDelay)
            guard !Task.isCancelled else { return }
            await self?.passAutomatically()
        }
    }

    /// Passes the turn. The waiting task is done, so `choose` must not cancel it.
    private func passAutomatically() async {
        task = nil
        await choose(.pass)
    }

    /// The person taps a pawn, or the turn passes by itself.
    func choose(_ choice: LudoChoice) async {
        guard let started = turn, case let .showing(value) = started.phase,
              movableChoices.contains(choice)
        else { return }
        task?.cancel()
        var playing = started
        playing.phase = .playing(value)
        turn = playing
        await play(LudoBoard.move(die: value, choice: choice))
        update()
        // The move did not land, so the same roll can be used again.
        if let turn, turn.position == started.position, turn.phase == .playing(value) {
            land(value, context: context(), schedulesAutomaticPass: false)
        }
    }

    /// My roll for the turn on screen, from the tap until the move lands. My
    /// partner's phone gets it again when they open the game in the middle of it.
    var ownRoll: LudoSavedRoll? {
        guard let turn else { return nil }
        switch turn.phase {
        case .ready: return nil
        case let .rolling(value), let .showing(value), let .playing(value):
            return LudoSavedRoll(position: turn.position, die: value)
        }
    }

    // MARK: - Their turn

    /// My partner rolled. Their die tumbles here once the board is at the roll's
    /// position, with their throw when they threw it by hand.
    func receivePartnerRoll(_ roll: LudoSavedRoll, toss: LudoToss? = nil) {
        guard LudoRollDecision.faces.contains(roll.die) else { return }
        // A resent roll has no throw. It keeps the one that came with it first.
        if roll != partnerRoll || toss != nil { partnerToss = toss }
        partnerRoll = roll
        update()
    }

    /// While it is not the person's turn the die rests in the yard of whoever
    /// moves next, or shows the roll my partner sent live. Without a live roll the
    /// board tumbles the partner's roll itself when their move arrives.
    private func showTheirTurn(_ context: LudoRollContext) {
        movableChoices = []
        hint = nil
        turn = nil
        if let partnerRoll, let position = context.position, partnerRoll.position == position,
           context.board.outcome == nil, context.board.next == context.me.other {
            // Already tumbling or showing: leave it alone.
            guard shownPartnerRoll != position else { return }
            showPartnerRoll(partnerRoll.die, at: position, context: context)
            return
        }
        shownPartnerRoll = nil
        cancelTask()
        die = .idle(side: context.board.next)
    }

    private func showPartnerRoll(_ value: Int, at position: LudoPosition, context: LudoRollContext) {
        cancelTask()
        shownPartnerRoll = position
        let side = context.me.other
        // Under Reduce Motion the stage shows the face without a tumble, and still
        // knows the die is rolled, so the partner's move does not roll it again.
        tumbleCount += 1
        let toss = partnerToss ?? .tap(seed: position.tossSeed)
        die = .rolling(die: value, side: side, token: tumbleCount, toss: toss)
        let sleep = sleep
        let tumbleDuration = tumbleDuration
        task = Task { [weak self] in
            try? await sleep(tumbleDuration)
            guard !Task.isCancelled, let self, shownPartnerRoll == position else { return }
            die = .showing(die: value, side: side)
        }
    }

    private func cancelTask() {
        task?.cancel()
        task = nil
    }
}
