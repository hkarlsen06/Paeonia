import SwiftUI

/// A board game screen: the shared shell around one game's board. It holds no
/// game rules. `BoardGameViewModel` decides what shows, and the board calls its
/// `play`.
struct BoardGameScreen<Board: BoardGameRules, BoardContent: View>: View {
    @Bindable var viewModel: BoardGameViewModel<Board>
    let title: LocalizedStringResource
    /// The game's board, built from the view model's board state.
    @ViewBuilder let board: () -> BoardContent

    @Environment(PaeoniaBannerCenter.self) private var bannerCenter
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .paeoniaScreenBackground(.paeoniaBackgroundSecondary)
            .navigationTitle(Text(title))
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.paeoniaBackgroundSecondary, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar { markButton }
            .boardGameScoreToolbar(score: viewModel.score, me: viewModel.meInfo, partner: viewModel.partnerInfo)
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
                    BoardMarkEditorView(
                        color: .boardGameMine,
                        initial: viewModel.meInfo.style.initial,
                        model: model
                    )
                }
            }
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
                onDrawMark: viewModel.openMarkEditor,
                onCommitStake: {}
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
            showsDrawMarkLink: !viewModel.hasDrawnMark,
            stake: viewModel.stakeState,
            partnerStatus: viewModel.partnerStatus,
            extraTurnCount: viewModel.extraTurnCount,
            score: viewModel.score
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
        } else if !viewModel.canPlay, viewModel.board.outcome == nil, viewModel.invite != .hidden {
            GameInviteButton(
                invite: viewModel.invite,
                partnerName: viewModel.partnerName,
                send: viewModel.sendInvite,
                identifier: "boardGames.invite"
            )
        }
    }

    @ToolbarContentBuilder
    private var markButton: some ToolbarContent {
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
