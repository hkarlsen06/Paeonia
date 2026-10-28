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
    /// Where the cards and chips of each revealed round sit, so the words can fly between them.
    @State private var wordFrames: [MindMeldWordSlot: CGRect] = [:]
    @State private var wordFlight: MindMeldWordFlight?

    var body: some View {
        ZStack {
            phaseContent
                .id(phaseIdentity)
                .transition(phaseTransition)
        }
        .animation(reduceMotion ? PaeoniaMotion.buttonPress : PaeoniaMotion.meaningfulMoment, value: phaseIdentity)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .coordinateSpace(.named(MindMeldWordFrames.space))
        .onPreferenceChange(MindMeldWordFrames.self) { frames in
            wordFrames.merge(frames) { $1 }
        }
        .overlay {
            if let wordFlight {
                MindMeldWordFlightView(flight: wordFlight, frames: wordFrames)
            }
        }
        .onChange(of: viewModel.phase) { old, new in
            startWordFlight(from: old, to: new)
        }
        .task(id: wordFlight?.roundID) { await landWordFlight() }
        .paeoniaScreenBackground(.paeoniaBackgroundSecondary)
        .paeoniaFittingNavigationTitle(Text(.mindMeldTitle))
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
            // Control Center, a system alert or the app switcher only make the app inactive. Keep the game live.
            guard phase != .inactive else { return }
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

    private var tutorial: GameTutorial? {
        GameTutorial(kind: .mindMeld, partnerName: viewModel.partnerName)
    }

    // MARK: Phases

    /// Cross-fade and a 12 point rise. Reduce Motion keeps only the cross-fade.
    /// A later round's write phase only fades in, because the last words fly
    /// into it and must land where its chips are.
    private var phaseTransition: AnyTransition {
        reduceMotion || (viewModel.phase == .write && viewModel.resolution.connectingPair != nil)
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
            MindMeldWriteView(
                viewModel: viewModel,
                canShowKeyboard: !showsTutorial && tutorial?.hasBeenShown != false,
                hidesPairWords: wordFlight != nil
            )
        case .waiting:
            MindMeldWaitingView(viewModel: viewModel)
        case .reveal, .over:
            MindMeldRevealView(viewModel: viewModel)
        }
    }

    // MARK: Word flight

    /// The reveal moved on to the next round: its two words shrink from the
    /// cards into the chips that the next round shows under its title.
    private func startWordFlight(from old: MindMeldPhase, to new: MindMeldPhase) {
        guard !reduceMotion, old == .reveal, new == .write,
              let pair = viewModel.resolution.connectingPair,
              let roundID = viewModel.resolution.connectingRoundID,
              wordFrames[MindMeldWordSlot(roundID: roundID, isMine: true, place: .card)] != nil
        else { return }
        wordFlight = MindMeldWordFlight(roundID: roundID, mine: pair.mine, theirs: pair.theirs)
    }

    /// Waits for the chips to report where they sit, drops the words onto them,
    /// taps the phone as each one lands, and then hands over to the chips.
    private func landWordFlight() async {
        guard let flight = wordFlight else { return }
        let chip = MindMeldWordSlot(roundID: flight.roundID, isMine: true, place: .chip)
        for _ in 0..<10 where wordFrames[chip] == nil {
            try? await Task.sleep(for: .milliseconds(16))
        }
        guard !Task.isCancelled, wordFrames[chip] != nil else {
            wordFlight = nil
            return
        }
        withAnimation(MindMeldWordFlight.fall) { wordFlight?.myWordFell = true }
        try? await Task.sleep(for: .seconds(MindMeldWordFlight.partnerDelay))
        withAnimation(MindMeldWordFlight.fall) { wordFlight?.partnerWordFell = true }
        try? await Task.sleep(for: .seconds(MindMeldWordFlight.fallDuration - MindMeldWordFlight.partnerDelay))
        guard !Task.isCancelled else { return }
        await landWord(isMine: true)
        try? await Task.sleep(for: .seconds(MindMeldWordFlight.partnerDelay - MindMeldWordFlight.squashDuration))
        await landWord(isMine: false)
        try? await Task.sleep(for: .seconds(MindMeldWordFlight.settleDuration))
        guard !Task.isCancelled else { return }
        wordFlight = nil
    }

    /// A word hits the screen: it squashes, taps the phone, and springs back.
    private func landWord(isMine: Bool) async {
        PaeoniaHaptics.streakTick(intensity: 0.7)
        GameSound.tap.play(volume: 0.6)
        withAnimation(MindMeldWordFlight.squash) { setSquash(true, isMine: isMine) }
        try? await Task.sleep(for: .seconds(MindMeldWordFlight.squashDuration))
        withAnimation(MindMeldWordFlight.settle) { setSquash(false, isMine: isMine) }
    }

    private func setSquash(_ squashed: Bool, isMine: Bool) {
        if isMine {
            wordFlight?.myWordSquashed = squashed
        } else {
            wordFlight?.partnerWordSquashed = squashed
        }
    }

    // MARK: Toolbar

    /// The melds capsule, which opens "Our melds", and the game's menu. Nothing
    /// else, so the title keeps its room.
    @ToolbarContentBuilder
    private var toolbarItems: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            MindMeldMeldsLink(melds: viewModel.stats?.melds ?? 0, me: viewModel.me, partner: viewModel.partner)
        }
        .sharedBackgroundVisibility(.hidden)
        ToolbarItem(placement: .topBarTrailing) {
            GameMenu(history: .mindMeld, showTutorial: { showsTutorial = true }) {
                if viewModel.game?.state == .playing {
                    restartButton
                }
            }
        }
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
                if let failure = viewModel.startFailure {
                    failedState(failure)
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

    private func failedState(_ failure: PaeoniaFailure) -> some View {
        PaeoniaLoadFailureView(
            failure: failure,
            offlineMessage: .mindMeldOfflineMessage,
            failedMessage: .mindMeldStartFailedMessage
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
