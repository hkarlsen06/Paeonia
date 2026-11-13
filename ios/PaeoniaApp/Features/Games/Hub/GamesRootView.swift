import SwiftUI

/// The Games tab: the hub, and over it the first-time steps when a game opens
/// for the first time. A banner shows problems.
struct GamesRootView: View {
    @Bindable var viewModel: GamesViewModel
    @Binding var path: [GamesDestination]
    let tabBarVisibility: Visibility

    @Environment(PaeoniaBannerCenter.self) private var bannerCenter

    var body: some View {
        NavigationStack(path: $path) {
            content
                .animation(PaeoniaMotion.stateChange, value: viewModel.screen)
                .analyticsScreen("games")
                .paeoniaTabBackdrop()
                .toolbarVisibility(tabBarVisibility, for: .tabBar)
                .navigationDestination(for: GamesDestination.self) { destination in
                    viewModel.screen(for: destination)
                        .analyticsScreen(destination.analyticsName)
                }
        }
        .dismissesKeyboardOnPush(path)
        .onChange(of: viewModel.notice) { _, notice in
            guard let notice else { return }
            bannerCenter.show(notice.banner)
            viewModel.clearNotice()
        }
        .sheet(isPresented: isShowingIntro) {
            GamesIntroSheet(viewModel: viewModel)
                .analyticsScreen("games_intro")
        }
        // The hub, Home and notifications open screens through the view model, so
        // the first game can show the first-time steps before it.
        .onChange(of: viewModel.destinationToOpen, initial: true) { _, destination in
            guard let destination else { return }
            path = [destination]
            viewModel.destinationToOpen = nil
        }
        .onChange(of: path.isEmpty, initial: true) { _, isEmpty in
            // Loads the sounds while the game slides in, so its first sound is on time.
            if !isEmpty { GameSoundPlayer.shared.prepare() }
        }
    }

    private var isShowingIntro: Binding<Bool> {
        Binding(
            get: { viewModel.introStep != nil },
            set: { isPresented in
                if !isPresented {
                    viewModel.introDismissed()
                }
            }
        )
    }

    /// Opens a screen from the hub. A second tap while it opens does nothing.
    private func open(_ destination: GamesDestination) {
        guard path.isEmpty else { return }
        viewModel.open(destination)
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.screen {
        case .loading:
            ProgressView()
                .tint(.paeoniaAccentPrimary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .navigationTitle(Text(.mainTabGames))
                .navigationBarTitleDisplayMode(.inline)
        case .unavailable(let failure):
            unavailable(failure)
        case .hub:
            GamesHubView(viewModel: viewModel, isShowingGame: !path.isEmpty, open: open)
        }
    }

    /// Centered, and it scrolls when large text makes it taller than the screen.
    private func unavailable(_ failure: PaeoniaFailure) -> some View {
        GeometryReader { proxy in
            ScrollView {
                PaeoniaLoadFailureView(
                    failure: failure,
                    offlineTitle: .gamesUnavailableTitle,
                    offlineMessage: .gamesUnavailableMessage,
                    failedMessage: .gamesUnavailableFailedMessage
                ) {
                    Button {
                        Task { await viewModel.refresh() }
                    } label: {
                        Text(.commonTryAgain)
                    }
                    .buttonStyle(PaeoniaSecondaryButtonStyle())
                    .frame(maxWidth: PaeoniaSpacing.focusedContentWidth)
                }
                .padding(PaeoniaSpacing.screenHorizontalPadding)
                .frame(maxWidth: .infinity, minHeight: proxy.size.height)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .navigationTitle(Text(.mainTabGames))
        .navigationBarTitleDisplayMode(.inline)
    }
}

private extension GamesDestination {
    /// The screen's name in usage statistics, such as `game_ludo`.
    var analyticsName: String {
        switch self {
        case let .game(kind): "game_\(kind.rawValue)"
        case .drawAndGuessHistory: "draw_and_guess_history"
        case .drawAndGuessHistoryDetail: "draw_and_guess_history_detail"
        case .storyChainHistory: "story_chain_history"
        case .storyChainHistoryDetail: "story_chain_history_detail"
        case .mindMeldHistory: "mind_meld_history"
        case .mindMeldHistoryDetail: "mind_meld_history_detail"
        case .consensioHistory: "consensio_history"
        case .consensioHistoryDetail: "consensio_history_detail"
        case .guessMySpotHistory: "guess_my_spot_history"
        case .exquisiteCorpseHistory: "exquisite_corpse_history"
        case .exquisiteCorpseHistoryDetail: "exquisite_corpse_history_detail"
        case let .boardGameHistory(kind): "\(kind.rawValue)_history"
        case let .boardGameReplay(kind, _): "\(kind.rawValue)_replay"
        }
    }
}
