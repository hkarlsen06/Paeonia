import SwiftUI

struct GameConversationBoard: View {
    let kind: GameKind
    let game: RemoteBoardGameHistoryGame
    let people: GameConversationPeople

    var body: some View {
        VStack(spacing: PaeoniaSpacing.space12) {
            if let winner = game.winnerUserID {
                Text(.gamesConversationWinner(people.name(for: winner)))
                    .font(PaeoniaTypography.sectionTitle)
            } else {
                Text(.boardGamesResultTitleDraw).font(PaeoniaTypography.sectionTitle)
            }
            board
            if let stake = game.stake {
                Text(.boardGamesStakePlayingFor(stake)).font(PaeoniaTypography.caption)
            }
        }
    }

    @ViewBuilder
    private var board: some View {
        switch kind {
        case .connectFour:
            GameConversationBoardReplay<ConnectFourBoard, _>(game: game, people: people) {
                BoardGameReplayBoards.connectFour($0)
            }
        case .dotsAndBoxes:
            GameConversationBoardReplay<DotsAndBoxesBoard, _>(game: game, people: people) {
                BoardGameReplayBoards.dotsAndBoxes($0)
            }
        case .ultimateTicTacToe:
            GameConversationBoardReplay<UltimateTicTacToeBoard, _>(game: game, people: people) { replay in
                UltimateTicTacToeBoardView(
                    board: replay.board, lastMove: replay.lastMove, styles: replay.styles, me: replay.me,
                    canPlay: false, pick: .constant(.none), showsOutcome: false, bloomSeed: "",
                    partnerName: people.participants.partnerName, isReplay: true
                )
            }
        case .ludo:
            GameConversationBoardReplay<LudoBoard, _>(game: game, people: people) {
                BoardGameReplayBoards.ludo($0)
            }
        default:
            EmptyView()
        }
    }
}

/// Uses the game's real rule engine and move history. It opens on the final board.
private struct GameConversationBoardReplay<Board: BoardGameRules, Content: View>: View {
    let people: GameConversationPeople
    let content: (BoardGameReplayBoard<Board>) -> Content
    @State private var model: BoardGameReplayModel<Board>

    init(
        game: RemoteBoardGameHistoryGame, people: GameConversationPeople,
        @ViewBuilder content: @escaping (BoardGameReplayBoard<Board>) -> Content
    ) {
        self.people = people
        self.content = content
        let model = BoardGameReplayModel<Board>(game: game, userID: people.participants.currentUserID)
        model.scrub(to: model.moveCount)
        _model = State(initialValue: model)
    }

    var body: some View {
        VStack(spacing: PaeoniaSpacing.space8) {
            content(replay)
            HStack {
                Button {
                    if model.isPlaying { model.pause() } else { model.play() }
                } label: {
                    Image(systemName: model.isPlaying ? "pause.fill" : "play.fill")
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel(Text(model.isPlaying ? .boardGamesReplayPause : .boardGamesReplayPlay))
                Slider(
                    value: Binding(
                        get: { Double(model.step) },
                        set: { model.scrub(to: Int($0)) }
                    ), in: 0...Double(max(model.moveCount, 1)), step: 1
                )
                .accessibilityLabel(Text(.boardGamesReplaySliderA11Y))
                .accessibilityValue(Text(.boardGamesReplayProgress(model.step, model.moveCount)))
            }
            .tint(.paeoniaAccentPrimary)
            .disabled(model.moveCount == 0)
            Text(.boardGamesReplayProgress(model.step, model.moveCount))
                .font(PaeoniaTypography.caption)
        }
        .onDisappear { model.pause() }
    }

    private var replay: BoardGameReplayBoard<Board> {
        let mine = people.style(for: people.participants.currentUserID ?? model.game.firstUserID)
        let theirs = people.style(for: people.participants.partnerUserID ?? model.game.firstUserID)
        return BoardGameReplayBoard(
            board: model.board, lastMove: model.lastMove,
            styles: model.me == .one ? .init(one: mine, two: theirs) : .init(one: theirs, two: mine),
            me: model.me, showsOutcome: false, bloomSeed: "",
            partnerName: people.participants.partnerName
        )
    }
}
