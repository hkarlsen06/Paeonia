import SwiftUI

/// The Mind Meld screen. It shows the part of the game the person is in and holds
/// no game rules: `MindMeldViewModel` decides the phase, and the phase views call
/// its actions.
struct MindMeldScreen: View {
    @Bindable var viewModel: MindMeldViewModel

    @Environment(PaeoniaBannerCenter.self) private var bannerCenter
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isConfirmingRestart = false
    @State private var showsTutorial = false

    var body: some View {
        ZStack {
            phaseContent
                .id(phaseIdentity)
                .transition(phaseTransition)
        }
        .animation(reduceMotion ? PaeoniaMotion.buttonPress : PaeoniaMotion.meaningfulMoment, value: phaseIdentity)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .paeoniaScreenBackground(.paeoniaBackgroundSecondary)
        .navigationTitle(Text(.mindMeldTitle))
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.paeoniaBackgroundSecondary, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar { toolbarItems }
        .alert(Text(.mindMeldRestartTitle), isPresented: $isConfirmingRestart) {
            Button(role: .cancel) {} label: { Text(.mindMeldRestartCancel) }
            Button(role: .destructive) {
                Task { await viewModel.restart() }
            } label: {
                Text(.mindMeldRestartConfirm)
            }
        } message: {
            Text(.mindMeldRestartMessage)
        }
        .preferredColorScheme(.dark)
        .task { await viewModel.start() }
        .onAppear { viewModel.prefersReducedMotion = reduceMotion }
        .onChange(of: reduceMotion) { _, newValue in viewModel.prefersReducedMotion = newValue }
        .onDisappear { viewModel.stop() }
        .onChange(of: scenePhase) { _, phase in
            viewModel.scenePhaseChanged(isActive: phase == .active)
        }
        .onChange(of: viewModel.notice) { _, notice in
            guard let notice else { return }
            bannerCenter.show(notice.banner)
            viewModel.clearNotice()
        }
        .gameTutorial(tutorial, isPresented: $showsTutorial)
        .accessibilityIdentifier("mindMeld.screen")
    }

    private var tutorial: GameTutorial {
        GameTutorial(kind: .mindMeld, partnerName: viewModel.partnerName)
    }

    // MARK: Phases

    /// Cross-fade and a 12 point rise. Reduce Motion keeps only the cross-fade.
    private var phaseTransition: AnyTransition {
        reduceMotion
            ? .opacity
            : .asymmetric(insertion: .opacity.combined(with: .offset(y: 12)), removal: .opacity)
    }

    /// Changes when the screen needs a new view, so state such as the reveal
    /// starts fresh for each round. A reveal and the finished game that follows it
    /// share one identity, so the cards stay on screen when the ending is marked
    /// as seen, and when Count it turns a near miss into a meld.
    private var phaseIdentity: String {
        let round = viewModel.round?.id.uuidString ?? "none"
        switch viewModel.phase {
        case .loading, .starting: return "status"
        case .write: return "write-\(round)"
        case .waiting: return "waiting-\(round)"
        case .reveal, .over: return viewModel.revealIdentity
        }
    }

    @ViewBuilder
    private var phaseContent: some View {
        switch viewModel.phase {
        case .loading, .starting:
            MindMeldStatusView(viewModel: viewModel)
        case .write:
            // The cards open on their own the first time, so the keyboard waits
            // for them to close instead of showing over them.
            MindMeldWriteView(viewModel: viewModel, canShowKeyboard: !showsTutorial && tutorial.hasBeenShown)
        case .waiting:
            MindMeldWaitingView(viewModel: viewModel)
        case .reveal, .over:
            MindMeldRevealView(viewModel: viewModel)
        }
    }

    // MARK: Toolbar

    /// The melds capsule, which opens "Our melds", and the menu with "How to play".
    /// Nothing else, so the title keeps its room.
    @ToolbarContentBuilder
    private var toolbarItems: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            MindMeldMeldsLink(melds: viewModel.stats?.melds ?? 0, me: viewModel.me, partner: viewModel.partner)
        }
        .sharedBackgroundVisibility(.hidden)
        ToolbarItem(placement: .topBarTrailing) {
            moreMenu
        }
    }

    private var moreMenu: some View {
        Menu {
            Button {
                showsTutorial = true
            } label: {
                Label {
                    Text(.gamesTutorialOpen)
                } icon: {
                    Image(systemName: "questionmark.circle")
                }
            }
            .accessibilityIdentifier("games.tutorial.open")
            if viewModel.game?.state == .playing {
                restartButton
            }
        } label: {
            Image(systemName: "ellipsis")
                .accessibilityLabel(Text(.mindMeldMenuA11Y))
        }
        .accessibilityIdentifier("mindMeld.menu")
    }

    private var restartButton: some View {
        Button {
            isConfirmingRestart = true
        } label: {
            Label {
                Text(.mindMeldRestartMenu)
            } icon: {
                Image(systemName: "arrow.counterclockwise")
            }
        }
        .disabled(viewModel.isStartingGame)
        .accessibilityIdentifier("mindMeld.restart")
    }
}

// MARK: - Status

/// Loading and starting a game, and the failed start. The spinner waits a moment
/// before it shows, so a quick start does not flash it.
private struct MindMeldStatusView: View {
    let viewModel: MindMeldViewModel

    @State private var showsSpinner = false

    var body: some View {
        GameFocusedLayout(fillsHeight: true) {
            VStack(spacing: PaeoniaSpacing.space16) {
                Spacer(minLength: 0)
                if viewModel.startFailed {
                    failedState
                } else {
                    ProgressView()
                        .tint(.paeoniaAccentPrimary)
                        .controlSize(.large)
                        .opacity(showsSpinner ? 1 : 0)
                        .animation(PaeoniaMotion.stateChange, value: showsSpinner)
                        .accessibilityHidden(!showsSpinner)
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity)
        }
        .task {
            try? await Task.sleep(for: .seconds(0.3))
            guard !Task.isCancelled else { return }
            showsSpinner = true
        }
    }

    private var failedState: some View {
        PaeoniaEmptyStateView(
            title: .mindMeldOfflineTitle,
            message: .mindMeldOfflineMessage,
            systemImage: "wifi.slash"
        ) {
            Button {
                Task { await viewModel.retryStart() }
            } label: {
                Text(.commonTryAgain)
            }
            .buttonStyle(PaeoniaSecondaryButtonStyle(isLoading: viewModel.isStartingGame))
            .accessibilityIdentifier("mindMeld.retry")
        }
    }
}
