import SwiftUI

/// The Guess my spot screen. It shows the part of the game the person is in and
/// holds no game rules: `GuessMySpotViewModel` decides the phase, and the phase
/// views call its actions.
struct GuessMySpotScreen: View {
    @Bindable var viewModel: GuessMySpotViewModel

    @Environment(PaeoniaBannerCenter.self) private var bannerCenter
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
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
        .navigationTitle(Text(.guessMySpotTitle))
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(viewModel.showsCheck)
        .toolbarBackground(.paeoniaBackgroundSecondary, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar { toolbarItems }
        .preferredColorScheme(.dark)
        // A swipe on the map pans it. Only the left edge goes back.
        .background(GameEdgeSwipeOnly())
        .task { await viewModel.start() }
        .onAppear { viewModel.prefersReducedMotion = reduceMotion }
        .onChange(of: reduceMotion) { _, newValue in viewModel.prefersReducedMotion = newValue }
        .onDisappear { viewModel.stop() }
        .onChange(of: scenePhase) { _, phase in
            guard phase != .inactive else { return }
            viewModel.scenePhaseChanged(isActive: phase == .active)
        }
        .onChange(of: viewModel.phase) { old, new in
            // The partner's photo arrived while this person waited for it.
            if old == .waitingForPhoto, new == .guess {
                PaeoniaHaptics.partnerDrawingReceived()
                GameSound.nudge.play(volume: 0.6)
            }
        }
        .onChange(of: viewModel.notice) { _, notice in
            guard let notice else { return }
            bannerCenter.show(notice.banner)
            viewModel.clearNotice()
        }
        .gameTutorial(GameTutorial(kind: .guessMySpot, partnerName: viewModel.partnerName), isPresented: $showsTutorial)
        .accessibilityIdentifier("guessMySpot.screen")
    }

    // MARK: Phases

    /// The reveal only fades in, so its map lines up with the guess map it replaces.
    private var phaseTransition: AnyTransition {
        if reduceMotion { return .opacity }
        if case .reveal = viewModel.phase { return .opacity }
        return .asymmetric(insertion: .opacity.combined(with: .offset(y: 12)), removal: .opacity)
    }

    /// Changes when the screen needs a new view, so a reveal starts fresh for each
    /// round. A held reveal and the one it turns into share an identity, and so do
    /// the picker and the check, so the picker keeps its place under the check.
    private var phaseIdentity: String {
        let round = viewModel.round?.id.uuidString ?? "none"
        switch viewModel.phase {
        case .loading, .starting: return "status"
        case .send: return "send"
        case .guess: return "guess-\(round)"
        case .waitingForGuess: return "waiting-guess-\(round)"
        case .waitingForPhoto: return "waiting-photo"
        case .reveal: return "reveal-\(round)"
        }
    }

    @ViewBuilder
    private var phaseContent: some View {
        switch viewModel.phase {
        case .loading, .starting:
            GuessMySpotStatusView(viewModel: viewModel)
        case .send:
            ZStack {
                GuessMySpotPickView(viewModel: viewModel)
                    .opacity(viewModel.showsCheck ? 0 : 1)
                    .allowsHitTesting(!viewModel.showsCheck)
                    .accessibilityHidden(viewModel.showsCheck)
                if viewModel.showsCheck {
                    GuessMySpotCheckView(viewModel: viewModel)
                        .background(.paeoniaBackgroundSecondary)
                        .transition(phaseTransition)
                }
            }
            .animation(
                reduceMotion ? PaeoniaMotion.buttonPress : PaeoniaMotion.meaningfulMoment,
                value: viewModel.showsCheck
            )
        case .guess:
            GuessMySpotGuessView(viewModel: viewModel)
        case .waitingForGuess, .waitingForPhoto:
            GuessMySpotWaitingView(viewModel: viewModel)
        case .reveal:
            GuessMySpotRevealView(viewModel: viewModel)
        }
    }

    // MARK: Toolbar

    @ToolbarContentBuilder
    private var toolbarItems: some ToolbarContent {
        if viewModel.showsCheck {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    PaeoniaHaptics.selection()
                    viewModel.clearDraft()
                } label: {
                    Image(systemName: "chevron.backward")
                        .accessibilityLabel(Text(.guessMySpotCheckAnother))
                }
                .accessibilityIdentifier("guessMySpot.check.another")
            }
        }
        ToolbarItem(placement: .topBarTrailing) {
            GuessMySpotPointsLink(score: viewModel.score, me: viewModel.me, partner: viewModel.partner)
        }
        .sharedBackgroundVisibility(.hidden)
        ToolbarItem(placement: .topBarTrailing) {
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
            } label: {
                Image(systemName: "ellipsis")
                    .accessibilityLabel(Text(.guessMySpotMenuA11Y))
            }
            .accessibilityIdentifier("guessMySpot.menu")
        }
    }
}

// MARK: - Points

/// The score in the toolbar. Tapping it opens the game's map.
struct GuessMySpotPointsLink: View {
    let score: GuessMySpotScore
    let me: GamePlayer
    let partner: GamePlayer

    var body: some View {
        NavigationLink(value: GamesDestination.guessMySpotHistory) {
            GuessMySpotScoreCapsule(score: score, me: me, partner: partner)
                .contentShape(Capsule(style: .continuous))
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(.guessMySpotHistoryTitle))
                .accessibilityValue(Text(GuessMySpotScoreCapsule.accessibilityText(score, partnerName: partner.name)))
        }
        .buttonStyle(.plain)
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        .accessibilityIdentifier("guessMySpot.history.open")
    }
}

// MARK: - Status

/// Loading and making the game, and the failed start. The spinner waits a moment
/// before it shows, so a quick start does not flash it.
private struct GuessMySpotStatusView: View {
    let viewModel: GuessMySpotViewModel

    @State private var showsSpinner = false

    var body: some View {
        GameFocusedLayout(fillsHeight: true) {
            VStack(spacing: PaeoniaSpacing.space16) {
                Spacer(minLength: 0)
                if let failure = viewModel.startFailure {
                    PaeoniaLoadFailureView(
                        failure: failure,
                        offlineMessage: .guessMySpotOfflineMessage,
                        failedMessage: .guessMySpotStartFailedMessage
                    ) {
                        Button {
                            Task { await viewModel.retryStart() }
                        } label: {
                            Text(.commonTryAgain)
                        }
                        .buttonStyle(PaeoniaSecondaryButtonStyle(isLoading: viewModel.isStartingGame))
                        .accessibilityIdentifier("guessMySpot.retry")
                    }
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
}
