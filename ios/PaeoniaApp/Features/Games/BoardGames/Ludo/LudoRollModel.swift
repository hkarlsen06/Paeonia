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
/// is part of the move: a tap rolls, the die tumbles, and the choice plays
/// `LudoBoard.move(die:choice:)` through the board game view model.
///
/// The model keeps the person's roll on this phone before the tumble starts, so
/// reopening the screen shows the same roll. The rules of what happens next
/// are in `LudoRollDecision`.
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
            land(kept, context: context, schedulesAutomaticMove: true)
        } else {
            die = .ready
            movableChoices = []
            hint = LudoRollDecision.hintBeforeRoll(board: context.board, moves: context.moves, me: context.me)
        }
    }

    /// The person taps the die.
    func roll() {
        let context = context()
        guard context.canPlay, let position = context.position, var turn, turn.position == position,
              turn.phase == .ready
        else { return }
        let value = rollDie()
        let roll = LudoSavedRoll(position: position, die: value)
        saved = roll
        turn.phase = .rolling(value)
        self.turn = turn
        movableChoices = []
        hint = nil
        let tumbles = !context.prefersReducedMotion
        if tumbles {
            tumbleCount += 1
            die = .rolling(die: value, side: context.me, token: tumbleCount)
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
        land(value, context: context, schedulesAutomaticMove: true)
    }

    /// The die shows its face and the person's options appear. A single option
    /// plays by itself after a moment.
    private func land(_ value: Int, context: LudoRollContext, schedulesAutomaticMove: Bool) {
        guard var turn else { return }
        turn.phase = .showing(value)
        self.turn = turn
        die = .showing(die: value, side: context.me)
        movableChoices = context.board.legalChoices(die: value)
        hint = LudoRollDecision.hintAfterRoll(board: context.board, die: value)
        guard schedulesAutomaticMove,
              let automatic = LudoRollDecision.automaticMove(board: context.board, die: value)
        else { return }
        let choice: LudoChoice
        let delay: Duration
        switch automatic {
        case let .move(only, after): (choice, delay) = (only, after)
        case let .pass(after): (choice, delay) = (.pass, after)
        }
        task?.cancel()
        let sleep = sleep
        task = Task { [weak self] in
            try? await sleep(delay)
            guard !Task.isCancelled else { return }
            await self?.chooseAutomatically(choice)
        }
    }

    /// Plays the only option. The waiting task is done, so `choose` must not cancel it.
    private func chooseAutomatically(_ choice: LudoChoice) async {
        task = nil
        await choose(choice)
    }

    /// The person taps a pawn, or the only option moves by itself.
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
            land(value, context: context(), schedulesAutomaticMove: false)
        }
    }

    // MARK: - Their turn

    /// While it is not the person's turn the die rests on the tray of whoever
    /// moves next. The board tumbles the partner's roll itself, before their pawn hops.
    private func showTheirTurn(_ context: LudoRollContext) {
        movableChoices = []
        hint = nil
        turn = nil
        cancelTask()
        die = .idle(side: context.board.next)
    }

    private func cancelTask() {
        task?.cancel()
        task = nil
    }
}
