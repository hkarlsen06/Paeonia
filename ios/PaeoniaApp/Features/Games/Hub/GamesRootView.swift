import SwiftUI

/// The Games tab. It shows setup for a couple that has not played, the moment
/// that explains what the partner chose, or the hub. A banner shows problems.
struct GamesRootView: View {
    @Bindable var viewModel: GamesViewModel
    @Binding var path: [GamesDestination]

    @Environment(PaeoniaBannerCenter.self) private var bannerCenter
    @Environment(\.scenePhase) private var scenePhase

    /// The iPad tab bar sits at the top and stays during a game. Hiding it in a push
    /// lays the game out below the bar and moves it up when the push ends, and the bar
    /// comes back late after a pop.
    private let hidesTabBarInGame = UIDevice.current.userInterfaceIdiom != .pad

    var body: some View {
        NavigationStack(path: $path) {
            content
                .background(.paeoniaBackgroundPrimary)
                // Hide the tab bar from the stack root, in the same update as the push. Hiding
                // it from the pushed screen shifts the content and brings the bar back late.
                .toolbar(hidesTabBarInGame && !path.isEmpty ? .hidden : .automatic, for: .tabBar)
                .navigationDestination(for: GamesDestination.self) { destination in
                    viewModel.screen(for: destination)
                }
        }
        .onChange(of: viewModel.notice) { _, notice in
            guard let notice else { return }
            bannerCenter.show(notice.banner)
            viewModel.clearNotice()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task { await viewModel.refresh() }
            }
        }
    }

    /// Opens a game from the hub. A second tap while it opens does nothing.
    private func open(_ destination: GamesDestination) {
        guard path.isEmpty else { return }
        path.append(destination)
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.screen {
        case .loading:
            Color.paeoniaBackgroundPrimary
        case .unavailable:
            unavailable
        case .setup:
            GamesSetupView(viewModel: viewModel)
        case let .partnerPicked(settings):
            GamesPartnerPickedView(viewModel: viewModel, settings: settings)
        case .hub:
            GamesHubView(viewModel: viewModel, open: open)
        }
    }

    /// Centered, and it scrolls when large text makes it taller than the screen.
    private var unavailable: some View {
        GeometryReader { proxy in
            ScrollView {
                PaeoniaEmptyStateView(
                    title: .gamesUnavailableTitle,
                    message: .gamesUnavailableMessage,
                    systemImage: "wifi.slash"
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
