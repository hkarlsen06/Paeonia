import Observation
import SwiftUI

/// One board game on the Games tab: its hub card and badge, and its screen.
/// The board games share it. `game` is built once, so a notification that
/// opens the game finds it ready. A game that can play a finished game again
/// also gets "Past games".
@MainActor
@Observable
final class BoardGameHubModel<Board: BoardGameRules>: GameHubModel {
    let kind: GameKind
    let game: BoardGameViewModel<Board>
    /// "Past games". Nil for a game without a replay.
    let history: BoardGameHistoryViewModel?

    @ObservationIgnored private let name: LocalizedStringResource
    @ObservationIgnored private let subtitle: LocalizedStringResource
    @ObservationIgnored private let artwork: () -> AnyView
    @ObservationIgnored private let makeScreen: (BoardGameViewModel<Board>) -> AnyView
    @ObservationIgnored private let replayBoard: ((BoardGameReplayBoard<Board>) -> AnyView)?

    init(
        kind: GameKind,
        name: LocalizedStringResource,
        subtitle: LocalizedStringResource,
        timing: BoardGameMoveTiming,
        dependencies: GamesDependencies,
        artwork: @escaping () -> AnyView,
        screen: @escaping (BoardGameViewModel<Board>) -> AnyView,
        replayBoard: ((BoardGameReplayBoard<Board>) -> AnyView)? = nil
    ) {
        self.kind = kind
        self.name = name
        self.subtitle = subtitle
        self.artwork = artwork
        makeScreen = screen
        self.replayBoard = replayBoard
        game = BoardGameViewModel(kind: kind, timing: timing, dependencies: dependencies)
        history = replayBoard == nil
            ? nil
            : BoardGameHistoryViewModel(kind: kind, gateway: dependencies.boardGamesGateway)
    }

    var isYourTurn: Bool {
        game.summary?.isYourTurn == true
    }

    func configure(participants: GameParticipants) {
        game.configure(participants: participants)
        history?.configure(userID: participants.currentUserID)
    }

    func setLocalChangeSyncHandler(_ handler: (@MainActor @Sendable () async -> Void)?) {
        game.setLocalChangeSyncHandler(handler)
    }

    func reload() async {
        await game.reload()
    }

    func refresh() async {
        await game.refresh()
    }

    // A refused move is told on the board screen, which keeps the notice until
    // it opens. The tab shows nothing for it.

    func card(_ context: GameHubCardContext, open: @escaping (GamesDestination) -> Void) -> AnyView? {
        // Hidden until the first read, so the card never flashes "Start".
        guard let summary = game.summary else { return nil }
        let kind = kind
        return AnyView(BoardGameHubCard(
            kind: kind,
            name: name,
            subtitle: subtitle,
            summary: summary,
            context: context,
            me: game.meInfo,
            partner: game.partnerInfo,
            open: { open(.game(kind)) },
            openHistory: history != nil && context.isOnHub && summary.score?.isEmpty == false
                ? { open(.boardGameHistory(kind)) }
                : nil,
            artwork: artwork
        ))
    }

    func screen(for destination: GamesDestination) -> AnyView? {
        switch destination {
        case .game(kind):
            return makeScreen(game)
        case .boardGameHistory(kind):
            guard let history else { return nil }
            return AnyView(BoardGameHistoryScreen(viewModel: history, players: game))
        case let .boardGameReplay(replayKind, gameNumber) where replayKind == kind:
            guard let history, let replayBoard else { return nil }
            return AnyView(BoardGameReplayHost(
                history: history,
                players: game,
                gameNumber: gameNumber,
                boardView: replayBoard
            ))
        default:
            return nil
        }
    }
}

/// A board game's card on the hub and the Home tab.
struct BoardGameHubCard: View {
    let kind: GameKind
    let name: LocalizedStringResource
    /// What the game is, shown until the couple first plays it.
    let subtitle: LocalizedStringResource
    let summary: BoardGameHubSummary
    let context: GameHubCardContext
    let me: BoardGamePlayerInfo
    let partner: BoardGamePlayerInfo
    let open: () -> Void
    /// Opens "Past games". Nil where the card has no room for the link, or
    /// before the couple has finished a game.
    var openHistory: (() -> Void)?
    let artwork: () -> AnyView

    var body: some View {
        GameHubCardFrame(
            name: name,
            status: Text(status),
            actionTitle: actionTitle,
            isYourTurn: summary.isYourTurn,
            context: context,
            actionIdentifier: "games.hub.\(kind.rawValue)",
            open: open,
            artwork: artwork,
            badge: {
                if let score = summary.score, !score.isEmpty {
                    BoardGameScoreCapsule(score: score, me: me, partner: partner)
                }
            },
            extras: { historyLink }
        )
    }

    @ViewBuilder
    private var historyLink: some View {
        if let openHistory {
            Button(action: openHistory) {
                Label {
                    Text(.boardGamesHistoryTitle)
                } icon: {
                    Image(systemName: "clock.arrow.circlepath")
                }
            }
            .buttonStyle(PaeoniaQuietButtonStyle())
            .frame(maxWidth: .infinity)
            .accessibilityIdentifier("games.hub.\(kind.rawValue).history")
        }
    }

    private var status: LocalizedStringResource {
        switch summary.status {
        case .notStarted: subtitle
        case .yourTurn: .boardGamesHubStatusYourTurn
        case .partnerTurn: .boardGamesHubStatusPartnerTurn(context.partnerName)
        case .youWon: .boardGamesHubStatusYouWon
        case .partnerWon: .boardGamesHubStatusPartnerWon(context.partnerName)
        case .draw: .boardGamesHubStatusDraw
        }
    }

    private var actionTitle: LocalizedStringResource {
        switch summary.status {
        case .notStarted: .boardGamesHubActionStart
        case .yourTurn: .boardGamesHubActionPlay
        case .partnerTurn: .boardGamesHubActionLook
        case .youWon, .partnerWon, .draw: .boardGamesHubActionPlayAgain
        }
    }
}
