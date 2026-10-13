import SwiftUI

/// The Games tab. It shows setup for a couple that has not played, the moment
/// that explains what the partner chose, or the hub. A banner shows problems.
struct GamesRootView: View {
    @Bindable var viewModel: GamesViewModel
    @Binding var path: [GamesDestination]
    let participants: DrawAndGuessParticipants

    @Environment(PaeoniaBannerCenter.self) private var bannerCenter
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        NavigationStack(path: $path) {
            content
                .background(.paeoniaBackgroundPrimary)
                // Hide the tab bar from the stack root, in the same update as the push. Hiding
                // it from the pushed screen shifts the content and brings the bar back late.
                .toolbar(path.isEmpty ? .automatic : .hidden, for: .tabBar)
                .navigationDestination(for: GamesDestination.self) { destination in
                    switch destination {
                    case .drawAndGuess:
                        DrawAndGuessScreen(viewModel: viewModel.drawAndGuess)
                    }
                }
        }
        .task(id: participants.currentUserID) {
            viewModel.configure(participants: participants)
            await viewModel.load()
        }
        .task(id: participants.currentUserID) {
            await viewModel.observeStoreChanges()
        }
        // Names, photos and the couple arrive after launch. They never reload the screen.
        .onChange(of: participants) { _, newValue in viewModel.configure(participants: newValue) }
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
            GamesHubView(viewModel: viewModel)
        }
    }

    private var unavailable: some View {
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
        .navigationTitle(Text(.mainTabGames))
        .navigationBarTitleDisplayMode(.inline)
    }
}
