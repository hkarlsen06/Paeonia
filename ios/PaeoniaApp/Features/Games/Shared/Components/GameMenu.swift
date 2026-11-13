import SwiftUI

/// A game's list of finished games, such as "Past games" or "Our melds". The
/// game's menu and its card's long-press menu open it.
struct GameHistoryLink {
    let destination: GamesDestination
    /// The title the history screen shows.
    let title: LocalizedStringResource

    static let drawAndGuess = Self(destination: .drawAndGuessHistory, title: .gamesDrawAndGuessHistoryTitle)
    static let storyChain = Self(destination: .storyChainHistory, title: .storyChainHistoryTitle)
    static let mindMeld = Self(destination: .mindMeldHistory, title: .mindMeldHistoryTitle)
    static let consensio = Self(destination: .consensioHistory, title: .consensioHistoryTitle)
    static let guessMySpot = Self(destination: .guessMySpotHistory, title: .guessMySpotHistoryTitle)
    static let exquisiteCorpse = Self(destination: .exquisiteCorpseHistory, title: .exquisiteCorpseHistoryTitle)

    static func boardGame(_ kind: GameKind) -> Self {
        Self(destination: .boardGameHistory(kind), title: .boardGamesHistoryTitle)
    }
}

/// The "•••" menu in a game's toolbar. The invite to play comes first while
/// there is one (`gameMenuInvite`). A game puts its own items, such as Mind
/// Meld's "Start over", in `extra`, under the shared ones.
struct GameMenu<Extra: View>: View {
    let history: GameHistoryLink?
    /// Opens the history instead of pushing `history.destination`, for a game
    /// that keeps playing under its history.
    var openHistory: (() -> Void)?
    var editMark: (() -> Void)?
    var showTutorial: (() -> Void)?
    @ViewBuilder var extra: () -> Extra

    @Environment(\.gameMenuInviteItem) private var invite

    var body: some View {
        Menu {
            if let invite {
                Button(action: invite.tap) {
                    Label {
                        Text(invite.sentUntil == nil ? .gamesInviteButton(invite.partnerName) : .gamesInviteSent)
                    } icon: {
                        Image(systemName: invite.sentUntil == nil ? "bell" : "bell.fill")
                    }
                }
                .accessibilityIdentifier(invite.sentUntil == nil ? invite.identifier : "\(invite.identifier).sent")
            }
            GameMenuItems(history: history, openHistory: openHistory, editMark: editMark, showTutorial: showTutorial)
            extra()
        } label: {
            Image(systemName: "ellipsis")
                .accessibilityLabel(Text(.gamesMenuA11Y))
        }
        .accessibilityIdentifier("games.menu")
    }
}

extension GameMenu where Extra == EmptyView {
    init(
        history: GameHistoryLink?,
        openHistory: (() -> Void)? = nil,
        editMark: (() -> Void)? = nil,
        showTutorial: (() -> Void)? = nil
    ) {
        self.init(history: history, openHistory: openHistory, editMark: editMark, showTutorial: showTutorial) {
            EmptyView()
        }
    }
}

/// What a game's menu offers, each only when it applies: its history, the mark
/// on board game pieces, and "How to play". The toolbar menu and the hub card's
/// long-press menu both list these.
struct GameMenuItems: View {
    let history: GameHistoryLink?
    /// Nil pushes `history.destination`.
    var openHistory: (() -> Void)?
    var editMark: (() -> Void)?
    var showTutorial: (() -> Void)?

    var body: some View {
        if let history {
            if let openHistory {
                Button(action: openHistory) { historyLabel(history) }
                    .accessibilityIdentifier("games.menu.history")
            } else {
                NavigationLink(value: history.destination) { historyLabel(history) }
                    .accessibilityIdentifier("games.menu.history")
            }
        }
        if let editMark {
            Button(action: editMark) {
                Label {
                    Text(.boardGamesMarkTitle)
                } icon: {
                    Image(systemName: "scribble.variable")
                }
            }
            .accessibilityIdentifier("games.menu.mark")
        }
        if let showTutorial {
            Button(action: showTutorial) {
                Label {
                    Text(.gamesTutorialOpen)
                } icon: {
                    Image(systemName: "questionmark.circle")
                }
            }
            .accessibilityIdentifier("games.tutorial.open")
        }
    }

    private func historyLabel(_ history: GameHistoryLink) -> some View {
        Label {
            Text(history.title)
        } icon: {
            Image(systemName: "clock")
        }
    }
}

/// The end of a game's toolbar: the game's chat, then its menu. A game puts its
/// score before this, so the score comes first and the two buttons sit together.
struct GameToolbarActions<Menu: View>: ToolbarContent {
    let kind: GameKind
    @ViewBuilder var menu: () -> Menu

    var body: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) { GameConversationButton(kind: kind) }
        ToolbarItem(placement: .topBarTrailing) { menu() }
    }
}
