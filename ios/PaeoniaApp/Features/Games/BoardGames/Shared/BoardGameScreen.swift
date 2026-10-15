import SwiftUI

/// A board game screen: the shared shell around one game's board. It holds no
/// game rules. `BoardGameViewModel` decides what shows, and the board calls its
/// `play`.
struct BoardGameScreen<Board: BoardGameRules, BoardContent: View>: View {
    @Bindable var viewModel: BoardGameViewModel<Board>
    let title: LocalizedStringResource
    /// A game's own line in the status row, such as Ludo's "Roll again". While
    /// there is one, it shows instead of who is here, and the "Another turn"
    /// chip stays quiet because the hint already says it.
    var hint: LocalizedStringResource?
    /// The board draws over the whole screen behind the rows and fits itself in the
    /// free space between them, as Ludo's does. It reads `boardFitHeight` for that.
    var boardBleeds = false
    /// "Past games" of this game. The score opens it.
    var history: GamesDestination?
    /// The game's board, built from the view model's board state.
    @ViewBuilder let board: () -> BoardContent

    @Environment(PaeoniaBannerCenter.self) private var bannerCenter
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showsTutorial = false

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .paeoniaScreenBackground(.paeoniaBackgroundSecondary)
            .navigationTitle(Text(title))
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.paeoniaBackgroundSecondary, for: .navigationBar)
            // A board that bleeds shows its scene under the bar too.
            .toolbarBackgroundVisibility(boardBleeds ? .hidden : .automatic, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar { toolbarItems }
            // A board that bleeds has room for the invite under it. The others keep it in the toolbar.
            .gameInviteToolbar(
                invite: boardBleeds ? .hidden : invite,
                partnerName: viewModel.partnerName,
                send: viewModel.sendInvite,
                identifier: "boardGames.invite"
            )
            .boardGameScoreToolbar(
                score: viewModel.score,
                me: viewModel.meInfo,
                partner: viewModel.partnerInfo,
                history: history
            )
            .preferredColorScheme(.dark)
            .task { await viewModel.start(prefersReducedMotion: reduceMotion) }
            .onChange(of: reduceMotion) { _, newValue in viewModel.prefersReducedMotion = newValue }
            .onDisappear { viewModel.stop() }
            .onChange(of: scenePhase) { _, phase in
                viewModel.scenePhaseChanged(isActive: phase == .active)
            }
            .onChange(of: viewModel.notice, initial: true) { _, notice in
                guard let notice else { return }
                bannerCenter.show(notice.banner)
                viewModel.notice = nil
            }
            .onChange(of: viewModel.partnerStatus) { _, status in
                if status == .here {
                    PaeoniaHaptics.partnerDrawingReceived()
                }
            }
            .sheet(isPresented: isEditingMark) {
                if let model = viewModel.markEditor {
                    BoardMarkEditorView(color: viewModel.meInfo.style.color, model: model)
                }
            }
            .gameTutorial(tutorial, isPresented: $showsTutorial)
            .accessibilityIdentifier("boardGames.screen.\(viewModel.kind.rawValue)")
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.phase {
        case .loading:
            ProgressView()
                .tint(.paeoniaAccentPrimary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .unavailable:
            PaeoniaEmptyStateView(
                title: .boardGamesUnavailableTitle,
                message: .boardGamesUnavailableMessage,
                systemImage: "wifi.slash"
            ) {
                Button {
                    Task { await viewModel.startGame() }
                } label: {
                    Text(.commonTryAgain)
                }
                .buttonStyle(PaeoniaSecondaryButtonStyle(isLoading: viewModel.isStarting))
                .disabled(viewModel.isStarting)
            }
        case .game:
            BoardGameScreenLayout(
                content: shellContent,
                stakeDraft: $viewModel.stakeDraft,
                onCommitStake: {},
                boardBleeds: boardBleeds,
                onPickColor: viewModel.pickColor
            ) {
                // A tap while moves replay or the outcome plays jumps to the end. It
                // is a shortcut for sighted people, since VoiceOver reads the board
                // as it is, so the board gets no button trait.
                // swiftlint:disable:next accessibility_trait_for_button
                board()
                    .simultaneousGesture(TapGesture().onEnded { viewModel.skipToEnd() })
            } bottom: {
                bottom
            }
        }
    }

    private var shellContent: BoardGameShellContent {
        BoardGameShellContent(
            me: viewModel.meInfo,
            partner: viewModel.partnerInfo,
            turn: viewModel.turnLabel,
            stake: viewModel.stakeState,
            partnerStatus: viewModel.partnerStatus,
            extraTurnCount: hint == nil ? viewModel.extraTurnCount : 0,
            score: viewModel.score,
            hint: hint,
            colorChoice: viewModel.colorChoice,
            history: history
        )
    }

    /// The result, the line about a move waiting on this phone, or the invite.
    @ViewBuilder
    private var bottom: some View {
        if let result = viewModel.result {
            BoardGameResultPanel(
                content: result,
                me: viewModel.meInfo,
                partner: viewModel.partnerInfo,
                isCollapsed: $viewModel.isResultCollapsed
            ) {
                if result.isMissedEnding {
                    viewModel.continueAfterMissedEnding()
                } else {
                    Task { await viewModel.rematch() }
                }
            }
        } else if viewModel.isWaitingToSend {
            BoardGameOfflineLine(isWaiting: true, failedWhileOnline: viewModel.failedWhileOnline) {
                Task { await viewModel.retrySending() }
            }
        } else if boardBleeds, invite != .hidden {
            GameInviteButton(
                invite: invite,
                partnerName: viewModel.partnerName,
                send: viewModel.sendInvite,
                identifier: "boardGames.invite"
            )
        }
    }

    /// The invite, while the partner has the turn and the game is not over.
    private var invite: GameInviteState {
        !viewModel.canPlay && viewModel.board.outcome == nil ? viewModel.invite : .hidden
    }

    private var tutorial: GameTutorial? {
        GameTutorial(kind: viewModel.kind, partnerName: viewModel.partnerName)
    }

    @ToolbarContentBuilder
    private var toolbarItems: some ToolbarContent {
        if tutorial != nil {
            ToolbarItem(placement: .topBarTrailing) {
                GameTutorialButton { showsTutorial = true }
            }
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button(action: viewModel.openMarkEditor) {
                Label {
                    Text(.boardGamesMarkTitle)
                } icon: {
                    Image(systemName: "scribble.variable")
                }
            }
            .accessibilityIdentifier("boardGames.mark.open")
        }
    }

    private var isEditingMark: Binding<Bool> {
        Binding(
            get: { viewModel.markEditor != nil },
            set: { isPresented in
                if !isPresented {
                    viewModel.markEditor = nil
                }
            }
        )
    }
}
