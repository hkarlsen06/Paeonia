import SwiftUI

/// What a replay hands the game's own board view.
struct BoardGameReplayBoard<Board: BoardGameRules> {
    let board: Board
    let lastMove: BoardMoveEvent?
    let styles: BoardPieceStyles
    let me: BoardPlayer
    let showsOutcome: Bool
    let bloomSeed: String
    let partnerName: String
}

/// Opens one game from "Past games". The route carries only the game's number,
/// so the game comes from the list the person tapped it in.
struct BoardGameReplayHost<Board: BoardGameRules>: View {
    let history: BoardGameHistoryViewModel
    let players: BoardGameViewModel<Board>
    let gameNumber: Int
    let boardView: (BoardGameReplayBoard<Board>) -> AnyView

    var body: some View {
        if let game = history.game(numbered: gameNumber) {
            BoardGameReplayScreen(game: game, players: players, boardView: boardView)
        } else {
            ProgressView()
                .tint(.paeoniaAccentPrimary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .paeoniaScreenBackground(.paeoniaBackgroundSecondary)
                .task { await history.load() }
        }
    }
}

/// A finished game played again: the players, the board, the bet, and a play
/// button with a slider to jump to any move. It starts playing when it opens.
struct BoardGameReplayScreen<Board: BoardGameRules>: View {
    let players: BoardGameViewModel<Board>
    let boardView: (BoardGameReplayBoard<Board>) -> AnyView

    @State private var model: BoardGameReplayModel<Board>

    init(
        game: RemoteBoardGameHistoryGame,
        players: BoardGameViewModel<Board>,
        boardView: @escaping (BoardGameReplayBoard<Board>) -> AnyView
    ) {
        self.players = players
        self.boardView = boardView
        _model = State(initialValue: BoardGameReplayModel(game: game, userID: players.currentUserID))
    }

    var body: some View {
        VStack(spacing: PaeoniaSpacing.space16) {
            BoardGamePlayersRow(
                me: players.meInfo,
                partner: players.partnerInfo,
                turn: turn,
                partnerName: players.partnerName,
                partnerIsHere: false
            )
            Spacer(minLength: 0)
            boardView(replayBoard)
                .frame(maxWidth: .infinity)
            Spacer(minLength: 0)
            if let stake = model.game.stake {
                Text(.boardGamesStakePlayingFor(stake))
                    .font(PaeoniaTypography.caption.weight(.semibold))
                    .lineLimit(2)
                    .padding(.horizontal, PaeoniaSpacing.space12)
                    .padding(.vertical, PaeoniaSpacing.space4)
                    .gameCapsuleStyle()
            }
            controls
        }
        .padding(.horizontal, PaeoniaSpacing.screenHorizontalPadding)
        .padding(.vertical, PaeoniaSpacing.space16)
        .paeoniaReadableWidth()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .paeoniaScreenBackground(.paeoniaBackgroundSecondary)
        .navigationTitle(Text(.boardGamesReplayTitle(model.game.gameNumber)))
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.paeoniaBackgroundSecondary, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .preferredColorScheme(.dark)
        .onAppear { model.play() }
        .onDisappear { model.pause() }
        .accessibilityIdentifier("boardGames.replay")
        .gameConversationToolbar(
            players.participants.coupleID.flatMap {
                .board(kind: players.kind, coupleID: $0, number: model.game.gameNumber)
            }, result: .board(players.kind, model.game))
    }

    // MARK: Board

    private var replayBoard: BoardGameReplayBoard<Board> {
        BoardGameReplayBoard(
            board: model.board,
            lastMove: model.lastMove,
            styles: styles,
            me: model.me,
            showsOutcome: model.showsOutcome,
            bloomSeed: "\(players.kind.rawValue):replay:\(model.game.gameNumber)",
            partnerName: players.partnerName
        )
    }

    /// My pieces look like mine whichever player I was in that game.
    private var styles: BoardPieceStyles {
        let mine = players.meInfo.style
        let theirs = players.partnerInfo.style
        return model.me == .one ? BoardPieceStyles(one: mine, two: theirs) : BoardPieceStyles(one: theirs, two: mine)
    }

    private var turn: BoardGameTurnLabel {
        guard let outcome = model.board.outcome else {
            return model.board.next == model.me ? .yourTurn : .partnerTurn
        }
        switch outcome.winner {
        case nil: return .draw
        case .some(model.me): return .youWon
        default: return .partnerWon
        }
    }

    // MARK: Controls

    private var controls: some View {
        VStack(spacing: PaeoniaSpacing.space8) {
            HStack(spacing: PaeoniaSpacing.space16) {
                playButton
                Slider(value: stepBinding, in: 0...Double(max(model.moveCount, 1)), step: 1)
                    .tint(.paeoniaAccentPrimary)
                    .disabled(model.moveCount == 0)
                    .accessibilityLabel(Text(.boardGamesReplaySliderA11Y))
                    .accessibilityValue(Text(.boardGamesReplayProgress(model.step, model.moveCount)))
                    .accessibilityIdentifier("boardGames.replay.slider")
            }
            Text(.boardGamesReplayProgress(model.step, model.moveCount))
                .font(PaeoniaTypography.caption)
                .monospacedDigit()
                .foregroundStyle(.paeoniaTextSecondary)
                .accessibilityHidden(true)
        }
    }

    private var stepBinding: Binding<Double> {
        Binding(
            get: { Double(model.step) },
            set: { newValue in
                let step = Int(newValue.rounded())
                if step != model.step {
                    model.scrub(to: step)
                }
            }
        )
    }

    private var playButton: some View {
        Button {
            if model.isPlaying {
                model.pause()
            } else {
                model.play()
            }
        } label: {
            Image(systemName: playIcon)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.paeoniaTextPrimary)
                .contentTransition(.symbolEffect(.replace))
                .frame(width: 52, height: 52)
                .glassEffect(.regular.tint(Color.paeoniaAccentPrimary.opacity(0.35)).interactive(), in: Circle())
        }
        .buttonStyle(.plain)
        .disabled(model.moveCount == 0)
        .accessibilityLabel(Text(playLabel))
        .accessibilityIdentifier("boardGames.replay.play")
    }

    private var playIcon: String {
        if model.isPlaying { return "pause.fill" }
        return model.isAtEnd ? "arrow.counterclockwise" : "play.fill"
    }

    private var playLabel: LocalizedStringResource {
        if model.isPlaying { return .boardGamesReplayPause }
        return model.isAtEnd ? .boardGamesReplayRestart : .boardGamesReplayPlay
    }
}
