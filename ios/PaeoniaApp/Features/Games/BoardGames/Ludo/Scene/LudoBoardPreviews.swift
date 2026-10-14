import SwiftUI

/// A game you can play in Xcode previews. You are player one. Tap the die to roll
/// and tap a glowing pawn to move it. The partner rolls and moves by itself, with
/// the die tumbling at the same moment their move arrives, as on the real screen.
/// `forcedRoll` makes every roll the same number.
private struct LudoPlayablePreview: View {
    @State private var board: LudoBoard
    @State private var lastMove: BoardMoveEvent?
    @State private var die: LudoDieState
    @State private var movable: [LudoChoice] = []
    @State private var showsOutcome = false
    @State private var moveCount = 0
    @State private var tumbleCount = 0
    @State private var rolled = 1
    @State private var isRolling = false
    let forcedRoll: Int?

    init(board: LudoBoard = .initial, forcedRoll: Int? = nil) {
        _board = State(initialValue: board)
        _die = State(initialValue: .ready)
        self.forcedRoll = forcedRoll
    }

    var body: some View {
        VStack(spacing: PaeoniaSpacing.space24) {
            LudoBoardView(
                board: board,
                lastMove: lastMove,
                styles: LudoPreviewStyles.styles(for: .standard),
                me: .one,
                die: die,
                movableChoices: movable,
                showsOutcome: showsOutcome,
                bloomSeed: "preview",
                partnerName: "Maja",
                onRoll: { Task { await roll() } },
                onChoose: { choice in Task { await choose(choice) } }
            )
            Button {
                board = .initial
                lastMove = nil
                die = .ready
                movable = []
                showsOutcome = false
                moveCount = 0
            } label: {
                Text(verbatim: "New game")
            }
            .buttonStyle(.bordered)
        }
        .padding(PaeoniaSpacing.screenHorizontalPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.paeoniaBackgroundSecondary)
    }

    // MARK: My turn

    private func roll() async {
        guard board.next == .one, board.outcome == nil, die == .ready, !isRolling else { return }
        isRolling = true
        defer { isRolling = false }
        rolled = forcedRoll ?? Int.random(in: 1...LudoBoard.dieFaces)
        tumbleCount += 1
        die = .rolling(die: rolled, side: .one, token: tumbleCount)
        try? await Task.sleep(for: LudoBoardView.tumbleDuration)
        die = .showing(die: rolled, side: .one)
        let choices = board.legalChoices(die: rolled)
        if choices == [.pass] {
            try? await Task.sleep(for: .seconds(1.2))
            await choose(.pass)
        } else {
            movable = choices
        }
    }

    private func choose(_ choice: LudoChoice) async {
        guard movable.contains(choice) || choice == .pass else { return }
        movable = []
        play(die: rolled, choice: choice, isMine: true)
        try? await Task.sleep(for: .seconds(1.4))
        await afterMove()
    }

    // MARK: Partner's turn

    private func partnerTurn() async {
        let value = forcedRoll ?? Int.random(in: 1...LudoBoard.dieFaces)
        let choice = board.legalChoices(die: value).randomElement() ?? .pass
        tumbleCount += 1
        die = .rolling(die: value, side: .two, token: tumbleCount)
        play(die: value, choice: choice, isMine: false)
        try? await Task.sleep(for: LudoBoardView.tumbleDuration)
        die = .showing(die: value, side: .two)
        try? await Task.sleep(for: .seconds(1.6))
        await afterMove()
    }

    // MARK: Shared

    private func play(die value: Int, choice: LudoChoice, isMine: Bool) {
        let move = LudoBoard.move(die: value, choice: choice)
        guard let next = board.applying(move) else { return }
        moveCount += 1
        lastMove = BoardMoveEvent(number: moveCount, move: move, player: board.next, isMine: isMine)
        board = next
    }

    private func afterMove() async {
        if board.outcome != nil {
            try? await Task.sleep(for: .seconds(0.2))
            showsOutcome = true
        } else if board.next == .one {
            die = .ready
        } else {
            die = .idle(side: .two)
            try? await Task.sleep(for: .seconds(0.9))
            await partnerTurn()
        }
    }
}

/// A board that is already there, as when you open a game.
private struct LudoStaticPreview: View {
    let board: LudoBoard
    var die: LudoDieState = .idle(side: .two)
    var movable: [LudoChoice] = []
    var showsOutcome = false
    var colors = LudoColorPair.standard

    var body: some View {
        LudoBoardView(
            board: board,
            lastMove: nil,
            styles: LudoPreviewStyles.styles(for: colors),
            colors: colors,
            me: .one,
            die: die,
            movableChoices: movable,
            showsOutcome: showsOutcome,
            bloomSeed: "preview",
            partnerName: "Maja",
            onRoll: {},
            onChoose: { _ in }
        )
        .padding(PaeoniaSpacing.screenHorizontalPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.paeoniaBackgroundSecondary)
    }
}

private enum LudoPreviewStyles {
    /// Player one has a drawn mark (a heart). Player two has no mark yet, so their initial shows.
    static func styles(for colors: LudoColorPair) -> BoardPieceStyles {
        BoardPieceStyles(
            one: BoardPieceStyle(color: colors.mine.color, mark: UIImage(systemName: "heart.fill"), initial: "H"),
            two: BoardPieceStyle(color: colors.partner.color, mark: nil, initial: "M")
        )
    }
}

#Preview("Playable") {
    LudoPlayablePreview()
}

#Preview("Roll a 1 to win") {
    LudoPlayablePreview(
        board: LudoBoard(progress: [57, 56, 5, 9], next: .one, outcome: nil),
        forcedRoll: 1
    )
}

#Preview("Mid game, both pawns can move") {
    LudoStaticPreview(
        board: LudoBoard(progress: [14, 52, 9, 33], next: .one, outcome: nil),
        die: .showing(die: 3, side: .one),
        movable: [.first, .second]
    )
}

#Preview("Won") {
    LudoStaticPreview(
        board: LudoBoard(
            progress: [57, 57, 12, 40],
            next: .one,
            outcome: BoardOutcome(winner: .one, line: [])
        ),
        showsOutcome: true
    )
}

#Preview("Gold and sky blue") {
    LudoStaticPreview(
        board: LudoBoard(progress: [14, 52, 9, 33], next: .one, outcome: nil),
        die: .showing(die: 3, side: .one),
        movable: [.first, .second],
        colors: LudoColorPair(mine: .gold, partner: .sky)
    )
}
