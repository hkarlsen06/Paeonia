import SwiftUI

/// The Story Chain screen. It shows the part of the game the person is in and
/// holds no game rules: `StoryChainViewModel` decides the phase, and the phase
/// views call its actions.
struct StoryChainScreen: View {
    let viewModel: StoryChainViewModel

    @Environment(PaeoniaBannerCenter.self) private var bannerCenter
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            phaseContent
                .id(phaseIdentity)
                .transition(phaseTransition)
        }
        .animation(reduceMotion ? PaeoniaMotion.buttonPress : PaeoniaMotion.meaningfulMoment, value: phaseIdentity)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .paeoniaScreenBackground(.paeoniaBackgroundSecondary)
        .paeoniaFittingNavigationTitle(Text(.storyChainName))
        .toolbarBackground(.paeoniaBackgroundSecondary, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar { historyButton }
        .preferredColorScheme(.dark)
        .task { await viewModel.start() }
        .onDisappear { viewModel.stop() }
        .onChange(of: scenePhase) { _, phase in
            // Control Center, a system alert or the app switcher only make the app inactive. Keep the game live.
            guard phase != .inactive else { return }
            viewModel.scenePhaseChanged(isActive: phase == .active)
        }
        .onChange(of: viewModel.notice) { _, notice in
            guard let notice else { return }
            bannerCenter.show(notice.banner)
            viewModel.clearNotice()
        }
        .accessibilityIdentifier("storyChain.screen")
    }

    /// Opens "Our stories".
    @ToolbarContentBuilder
    private var historyButton: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            NavigationLink(value: GamesDestination.storyChainHistory) {
                Label {
                    Text(.storyChainHistoryTitle)
                } icon: {
                    Image(systemName: "books.vertical")
                }
            }
            .accessibilityIdentifier("storyChain.history.open")
        }
    }

    /// Cross-fade and a 12 point rise. Reduce Motion keeps only the cross-fade.
    private var phaseTransition: AnyTransition {
        reduceMotion
            ? .opacity
            : .asymmetric(insertion: .opacity.combined(with: .offset(y: 12)), removal: .opacity)
    }

    // MARK: Phases

    /// The screens of the game. Writing, waiting, naming and the finished story
    /// are one screen, so the page never jumps when the turn passes.
    private enum Screen {
        case status, chooseOpening, waitingForOpening, story
    }

    private var screen: Screen {
        switch viewModel.phase {
        case .loading, .needsSetup, .preparing, .waitingToSync: .status
        case .chooseOpening: .chooseOpening
        case .waitingForOpening: .waitingForOpening
        case .writing, .waitingForLine, .naming, .waitingForName, .finished: .story
        }
    }

    /// Changes when the screen needs a new view. Each story is one view from its
    /// first line to its reveal, so its page, scroll position and reveal carry on.
    private var phaseIdentity: String {
        switch screen {
        case .story: "story-\(viewModel.story?.id.uuidString ?? "none")"
        case .status: "status"
        case .chooseOpening: "chooseOpening"
        case .waitingForOpening: "waitingForOpening"
        }
    }

    @ViewBuilder
    private var phaseContent: some View {
        switch screen {
        case .status:
            StoryChainStatusView(viewModel: viewModel)
        case .chooseOpening:
            StoryChainChooseOpeningView(viewModel: viewModel)
        case .waitingForOpening:
            StoryChainWaitingView(viewModel: viewModel)
        case .story:
            StoryChainStoryView(viewModel: viewModel)
        }
    }
}
