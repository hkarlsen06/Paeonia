import SwiftUI

/// The Consensio screen. It shows the part of the game the person is in and
/// holds no game rules: `ConsensioViewModel` decides the phase, and the phase
/// views call its actions.
struct ConsensioScreen: View {
    @Bindable var viewModel: ConsensioViewModel

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
        .navigationTitle(Text(.consensioTitle))
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(viewModel.showsPlacing)
        .toolbarBackground(.paeoniaBackgroundSecondary, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar { toolbarItems }
        .preferredColorScheme(.dark)
        .task { await viewModel.start() }
        .onAppear { viewModel.prefersReducedMotion = reduceMotion }
        .onChange(of: reduceMotion) { _, newValue in viewModel.prefersReducedMotion = newValue }
        .onDisappear { viewModel.stop() }
        .onChange(of: scenePhase) { _, phase in
            guard phase != .inactive else { return }
            viewModel.scenePhaseChanged(isActive: phase == .active)
        }
        .onChange(of: viewModel.notice) { _, notice in
            guard let notice else { return }
            bannerCenter.show(notice.banner)
            viewModel.clearNotice()
        }
        .gameTutorial(GameTutorial(kind: .consensio, partnerName: viewModel.partnerName), isPresented: $showsTutorial)
        .accessibilityIdentifier("consensio.screen")
    }

    // MARK: Phases

    private var phaseTransition: AnyTransition {
        reduceMotion
            ? .opacity
            : .asymmetric(insertion: .opacity.combined(with: .offset(y: 12)), removal: .opacity)
    }

    /// Changes when the screen needs a new view, so a reveal starts fresh for
    /// each round. A held reveal and the one it turns into share an identity.
    private var phaseIdentity: String {
        let round = viewModel.round?.id.uuidString ?? "none"
        switch viewModel.phase {
        case .loading, .starting: return "status"
        case .choose: return viewModel.showsPlacing ? "place" : "choose"
        case .guess: return "guess-\(round)"
        case .waitingForGuess: return "waiting-guess-\(round)"
        case .waitingForTopic: return "waiting-topic"
        case .reveal: return "reveal-\(round)"
        }
    }

    @ViewBuilder
    private var phaseContent: some View {
        switch viewModel.phase {
        case .loading, .starting:
            ConsensioStatusView(viewModel: viewModel)
        case .choose:
            if viewModel.showsPlacing {
                ConsensioLineView(viewModel: viewModel, role: .place)
            } else {
                ConsensioChooseView(viewModel: viewModel)
            }
        case .guess:
            ConsensioLineView(viewModel: viewModel, role: .guess)
        case .waitingForGuess, .waitingForTopic:
            ConsensioWaitingView(viewModel: viewModel)
        case .reveal:
            ConsensioRevealView(viewModel: viewModel)
        }
    }

    // MARK: Toolbar

    @ToolbarContentBuilder
    private var toolbarItems: some ToolbarContent {
        if viewModel.showsPlacing {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    PaeoniaHaptics.selection()
                    viewModel.cancelPlacing()
                } label: {
                    Image(systemName: "chevron.backward")
                        .accessibilityLabel(Text(.consensioPlaceBack))
                }
                .accessibilityIdentifier("consensio.place.back")
            }
        }
        ToolbarItem(placement: .topBarTrailing) {
            ConsensioPointsLink(points: viewModel.sharedPoints)
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
                    .accessibilityLabel(Text(.consensioMenuA11Y))
            }
            .accessibilityIdentifier("consensio.menu")
        }
    }
}

// MARK: - Points

/// The couple's shared total in the toolbar. Tapping it opens "What we know".
struct ConsensioPointsLink: View {
    let points: Int

    var body: some View {
        NavigationLink(value: GamesDestination.consensioHistory) {
            HStack(spacing: PaeoniaSpacing.space4) {
                Image(systemName: "heart.fill")
                    .foregroundStyle(.paeoniaAccentPrimary)
                    .accessibilityHidden(true)
                Text(verbatim: "\(points)")
                    .contentTransition(.numericText(value: Double(points)))
            }
            .font(PaeoniaTypography.caption.weight(.semibold))
            .monospacedDigit()
            .foregroundStyle(.paeoniaTextPrimary)
            .padding(.horizontal, PaeoniaSpacing.space12)
            .padding(.vertical, PaeoniaSpacing.space4)
            .background(.paeoniaSurfaceSecondary, in: Capsule(style: .continuous))
            .contentShape(Capsule(style: .continuous))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(.consensioHistoryTitle))
            .accessibilityValue(Text(.consensioPointsTogether(points)))
        }
        .buttonStyle(.plain)
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        .accessibilityIdentifier("consensio.history.open")
    }
}

// MARK: - Status

/// Loading and making the game, and the failed start. The spinner waits a moment
/// before it shows, so a quick start does not flash it.
private struct ConsensioStatusView: View {
    let viewModel: ConsensioViewModel

    @State private var showsSpinner = false

    var body: some View {
        GameFocusedLayout(fillsHeight: true) {
            VStack(spacing: PaeoniaSpacing.space16) {
                Spacer(minLength: 0)
                if let failure = viewModel.startFailure {
                    PaeoniaLoadFailureView(
                        failure: failure,
                        offlineMessage: .consensioOfflineMessage,
                        failedMessage: .consensioStartFailedMessage
                    ) {
                        Button {
                            Task { await viewModel.retryStart() }
                        } label: {
                            Text(.commonTryAgain)
                        }
                        .buttonStyle(PaeoniaSecondaryButtonStyle(isLoading: viewModel.isStartingGame))
                        .accessibilityIdentifier("consensio.retry")
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
