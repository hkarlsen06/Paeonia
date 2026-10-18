import SwiftUI

/// The Exquisite corpse screen. It shows the part of the game the person is in
/// and holds no game rules: `ExquisiteCorpseViewModel` decides the phase, and the
/// phase views call its actions.
struct ExquisiteCorpseScreen: View {
    let viewModel: ExquisiteCorpseViewModel
    /// Opens "Our creatures". The hub model passes its navigation.
    let openHistory: () -> Void

    @Environment(PaeoniaBannerCenter.self) private var bannerCenter
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// The strip slides from the watched square to the next canvas. Both screens
    /// match their strip in this namespace, so the shell owns it.
    @Namespace private var handoff

    var body: some View {
        ZStack {
            phaseContent
                .id(phaseIdentity)
                .transition(phaseTransition)
        }
        .animation(reduceMotion ? PaeoniaMotion.buttonPress : PaeoniaMotion.meaningfulMoment, value: phaseIdentity)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .paeoniaScreenBackground(.paeoniaBackgroundSecondary)
        .navigationTitle(Text(.exquisiteCorpseName))
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.paeoniaBackgroundSecondary, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar { historyButton }
        .gameStarToolbar(
            stars: viewModel.stars,
            id: viewModel.figure?.id,
            isShown: viewModel.phase == .reveal,
            hintKey: "games.exquisiteCorpse.starHintShown",
            identifier: "corpse.reveal.star"
        )
        .preferredColorScheme(.dark)
        .onAppear { viewModel.screenAppeared() }
        .task { await viewModel.start() }
        .onDisappear { viewModel.screenDisappeared() }
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
        .onChange(of: viewModel.partnerPresence) { old, new in
            partnerPresenceChanged(from: old, to: new)
        }
        .onChange(of: viewModel.phase) { old, new in
            if old == .watching, new == .drawing {
                handoffLanded()
            }
        }
        .accessibilityIdentifier("corpse.screen")
    }

    /// Opens "Our creatures".
    @ToolbarContentBuilder
    private var historyButton: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Button(action: openHistory) {
                Label {
                    Text(.exquisiteCorpseHistoryTitle)
                } icon: {
                    Image(systemName: "square.grid.2x2")
                }
            }
            .accessibilityIdentifier("corpse.history.open")
        }
    }

    /// The partner came into the game while this person waits. The drawing screen
    /// does this on its own, with the pulse on the avatar.
    private func partnerPresenceChanged(
        from old: ExquisiteCorpsePartnerPresence,
        to new: ExquisiteCorpsePartnerPresence
    ) {
        guard !old.isHere, new.isHere else { return }
        switch viewModel.phase {
        case .waiting, .watching, .waitingToSync:
            PaeoniaHaptics.partnerDrawingReceived()
            GameSound.nudge.play(volume: 0.7)
        default:
            break
        }
    }

    /// The turn came to this person while they watched: the strip slides from the
    /// watched square to the top of their canvas over `meaningfulMoment`. The fold
    /// sound creases for 0.1 seconds before its knock, so it starts early, and the
    /// knock and the tap land as the strip settles.
    private func handoffLanded() {
        Task {
            try? await Task.sleep(for: .seconds(PaeoniaMotion.motionSlow - Self.foldSoundLead))
            GameSound.fold.play(volume: 0.7)
            try? await Task.sleep(for: .seconds(Self.foldSoundLead))
            PaeoniaHaptics.partnerDrawingReceived()
        }
    }

    /// How long the fold sound creases before its knock.
    private static let foldSoundLead: TimeInterval = 0.1

    /// Cross-fade and a 12 point rise. Reduce Motion keeps only the cross-fade.
    private var phaseTransition: AnyTransition {
        reduceMotion
            ? .opacity
            : .asymmetric(insertion: .opacity.combined(with: .offset(y: 12)), removal: .opacity)
    }

    /// Changes when the screen needs a new view, so state such as a canvas, a
    /// timer or a reveal starts fresh for each part and each figure.
    private var phaseIdentity: String {
        let part = viewModel.part.map { String($0.rawValue) } ?? "none"
        let figure = viewModel.figureNumber
        switch viewModel.phase {
        case .reveal:
            return "reveal-\(viewModel.figure?.id.uuidString ?? "none")"
        case .drawing, .waiting, .watching:
            return "\(viewModel.phase)-\(figure)-\(part)"
        case .loading, .needsSetup, .preparing, .waitingToSync:
            return "\(viewModel.phase)"
        }
    }

    // MARK: Phases

    @ViewBuilder
    private var phaseContent: some View {
        switch viewModel.phase {
        case .loading, .needsSetup, .preparing:
            ExquisiteCorpseStatusView(viewModel: viewModel)
        case .drawing:
            ExquisiteCorpseDrawingView(viewModel: viewModel, handoff: handoffNamespace)
        case .waiting, .watching, .waitingToSync:
            ExquisiteCorpseWaitingView(viewModel: viewModel, handoff: handoffNamespace)
        case .reveal:
            revealContent
        }
    }

    /// The hand-off slides the strip. Reduce Motion only cross-fades.
    private var handoffNamespace: Namespace.ID? {
        reduceMotion ? nil : handoff
    }

    /// The reveal plays once per figure, so each figure gets its own view. While
    /// a drawing is on its way, the reveal waits with the folded paper. If a
    /// drawing can't be fetched, this offers to try again.
    @ViewBuilder
    private var revealContent: some View {
        if viewModel.revealLoadFailed {
            GameFocusedLayout(fillsHeight: true) {
                VStack {
                    Spacer(minLength: 0)
                    GameDrawingPlaceholder(loadFailed: true) {
                        viewModel.retryLoadingReveal()
                    }
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity)
            }
        } else if let content = viewModel.revealContent {
            ExquisiteCorpseRevealView(content: content, reduceMotion: reduceMotion) {
                Task { await viewModel.continueFromReveal() }
            }
            .id(content.figureID)
        } else {
            Color.clear
        }
    }
}
