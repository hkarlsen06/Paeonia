import SwiftUI

/// The guesser's screen from the first stroke to the result. One view covers
/// watching live, guessing on the replay and the reveal, so the answer slots and
/// the square stay where they are while the result plays.
struct DrawAndGuessGuessView: View {
    @Bindable var viewModel: DrawAndGuessViewModel

    @State private var timeline = DrawAndGuessRevealTimeline()
    @State private var isShowMeAlertPresented = false
    @Namespace private var tileNamespace
    @AccessibilityFocusState private var isTitleFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var isRevealed: Bool { viewModel.phase == .reveal }
    private var isLive: Bool { viewModel.phase == .watchingLive }
    private var revealProgress: Int {
        [timeline.titleShown, timeline.panelShown].count { $0 }
    }

    var body: some View {
        // A tap anywhere skips to the settled result. It is a shortcut, and the buttons stay.
        // swiftlint:disable:next accessibility_trait_for_button
        DrawAndGuessPhaseLayout(scrollTrigger: revealProgress, freezesSide: isRevealed) {
            // The rows that only matter while guessing fade out but keep their space,
            // so nothing above or below the square jumps when the guess is right.
            liveRow
                .opacity(isRevealed ? 0 : 1)
                .animation(PaeoniaMotion.stateChange, value: isRevealed)
                .accessibilityHidden(isRevealed)
        } square: { side in
            square(side: side)
        } footer: {
            footer
        } bottom: {
            bottom
        }
        .drawAndGuessSaveToolbar(viewModel, isShown: isRevealed && timeline.saveShown)
        .simultaneousGesture(TapGesture().onEnded {
            if timeline.titleShown { timeline.skip() }
        })
        .onChange(of: viewModel.phase, initial: true) { _, phase in
            if phase == .reveal {
                beginReveal()
            } else if timeline.hasBegun {
                // A refused correct guess sends the same round back to guessing.
                timeline.reset()
            }
        }
        .onChange(of: timeline.titleShown) { _, shown in
            if shown, UIAccessibility.isVoiceOverRunning { isTitleFocused = true }
        }
        .onChange(of: viewModel.wrongGuessCount) {
            PaeoniaHaptics.gameWrongGuess()
            AccessibilityNotification.Announcement(String(localized: .gamesDrawAndGuessGuessWrong)).post()
        }
        .alert(Text(.gamesDrawAndGuessShowMeConfirmTitle), isPresented: $isShowMeAlertPresented) {
            Button {
                Task { await viewModel.giveUp() }
            } label: {
                Text(.gamesDrawAndGuessShowMe)
            }
            Button(role: .cancel) {} label: {
                Text(.gamesDrawAndGuessKeepGuessing)
            }
        } message: {
            Text(.gamesDrawAndGuessShowMeConfirmMessage)
        }
        .onDisappear { timeline.stop() }
    }

    // MARK: Live row

    private var liveRow: some View {
        DrawAndGuessLiveRow {
            DrawAndGuessPresenceLabel(
                player: viewModel.partner,
                text: isLive
                    ? .gamesDrawAndGuessWaitDrawing(viewModel.partnerName)
                    : .gamesDrawAndGuessGuessDrawnBy(viewModel.partnerName),
                showsRing: isLive
            )
        } trailing: {
            if viewModel.speedBonus != .hidden {
                DrawAndGuessSpeedBonusLabel(viewModel: viewModel)
            }
        }
    }

    // MARK: Square

    private func square(side: CGFloat) -> some View {
        VStack(spacing: PaeoniaSpacing.space4) {
            DrawAndGuessSquare(
                side: side,
                scale: timeline.canvasShrunk ? 0.8 : 1,
                glow: timeline.glow
            ) {
                ZStack {
                    if !timeline.isSettled {
                        DrawAndGuessReplayCanvas(viewModel: viewModel, side: side)
                    }
                    if showsRevealDrawing {
                        DrawAndGuessRevealDrawing(viewModel: viewModel, side: side)
                            .transition(.opacity)
                    }
                }
            }
            .modifier(DrawAndGuessReplayAccessibility(viewModel: viewModel, isDrawingShown: !showsPlaceholder))
            if viewModel.settings?.playStyle == .against, !reduceMotion {
                if viewModel.speedBonus != .hidden {
                    DrawAndGuessSpeedBonusLine(viewModel: viewModel, width: side)
                } else {
                    Color.clear.frame(height: 3)
                }
            }
        }
    }

    /// The live canvas or the replay is on screen, as `DrawAndGuessReplayCanvas` decides.
    private var showsReplay: Bool {
        let showsLive = (viewModel.guessSource == .live || isLive) && viewModel.live != nil
        return showsLive || viewModel.isReplayReady
    }

    /// The reveal shows the whole drawing over the replay. With no replay to show,
    /// such as a reveal opened after a relaunch, it takes over right away.
    private var showsRevealDrawing: Bool {
        timeline.finalDrawingShown || (isRevealed && !showsReplay)
    }

    /// The square shows the spinner, or the load error and its retry button,
    /// instead of a drawing.
    private var showsPlaceholder: Bool {
        showsRevealDrawing ? viewModel.finalDrawing == nil : !showsReplay
    }

    // MARK: Footer

    private var footer: some View {
        VStack(spacing: PaeoniaSpacing.space16) {
            if let language = viewModel.guessLanguageNotice {
                // Fades out with the live row, keeping its space.
                Label {
                    Text(language.guessNoticeTitle)
                } icon: {
                    Image(systemName: "globe")
                }
                .font(PaeoniaTypography.caption)
                .foregroundStyle(.paeoniaTextSecondary)
                .opacity(isRevealed ? 0 : 1)
                .animation(PaeoniaMotion.stateChange, value: isRevealed)
                .accessibilityHidden(isRevealed)
            }
            if !pinsSlots {
                slots
            }

            if isRevealed {
                revealSections
            }
        }
        .frame(maxWidth: .infinity)
    }

    /// At accessibility text sizes the tiles are tall, so the slots join them at the bottom
    /// while guessing, where they stay in view.
    private var pinsSlots: Bool {
        dynamicTypeSize.isAccessibilitySize && !isRevealed
    }

    private var slots: some View {
        DrawAndGuessAnswerSlots(
            viewModel: viewModel,
            timeline: timeline,
            namespace: tileNamespace,
            isRevealed: isRevealed,
            litsGreen: viewModel.reveal?.isSolved == true
        )
        .overlay {
            if let start = timeline.bloomStart {
                DrawAndGuessPetalBloom(start: start, seed: viewModel.round?.id.uuidString ?? "")
                    .frame(width: 560, height: 420)
            }
        }
        .zIndex(1)
    }

    @ViewBuilder
    private var revealSections: some View {
        if let reveal = viewModel.reveal {
            let transition = reduceMotion ? AnyTransition.opacity : .opacity.combined(with: .offset(y: 12))
            VStack(spacing: PaeoniaSpacing.space16) {
                if timeline.titleShown {
                    DrawAndGuessRevealTitle(
                        title: reveal.isSolved ? .gamesDrawAndGuessRevealTitle : .gamesDrawAndGuessMissedTitle,
                        lines: lines(for: reveal),
                        isFocused: $isTitleFocused
                    )
                    .transition(transition)
                }
                if timeline.panelShown, let score = viewModel.revealScore {
                    DrawAndGuessScorePanel(
                        score: score,
                        me: viewModel.me,
                        partner: viewModel.partner,
                        isCounting: timeline.scoreCounting,
                        animates: !timeline.wasSkipped,
                        showsSpeedBonus: timeline.speedBonusShown,
                        isHeldOnPhone: viewModel.isHeldOnPhone
                    )
                    .transition(transition)
                }
                if timeline.saveShown, viewModel.savePrompt == .saving, viewModel.isHeldOnPhone {
                    DrawAndGuessOfflineLine()
                        .transition(transition)
                }
            }
        }
    }

    private func lines(for reveal: DrawAndGuessReveal) -> [Text] {
        guard reveal.isSolved else { return [Text(.gamesDrawAndGuessMissedLine)] }
        guard let duration = reveal.shownSolveDuration else { return [] }
        return [Text(.gamesDrawAndGuessRevealSolveTime(DrawAndGuessReveal.spokenDuration(duration)))]
    }

    // MARK: Bottom

    @ViewBuilder
    private var bottom: some View {
        if !timeline.gridCollapsed {
            VStack(spacing: PaeoniaSpacing.space12) {
                if pinsSlots {
                    slots
                }
                DrawAndGuessTileGrid(viewModel: viewModel, namespace: tileNamespace)
                Button {
                    isShowMeAlertPresented = true
                } label: {
                    Text(.gamesDrawAndGuessShowMe)
                }
                .buttonStyle(PaeoniaQuietButtonStyle())
                .opacity(isRevealed ? 0 : 1)
                .animation(PaeoniaMotion.stateChange, value: isRevealed)
                .disabled(isRevealed)
                .accessibilityHidden(isRevealed)
                .accessibilityIdentifier("draw.showMe")
            }
            .transition(.opacity.combined(with: .move(edge: .bottom)))
        }
        if isRevealed, timeline.buttonShown {
            Button {
                Task { await viewModel.continueFromReveal() }
            } label: {
                Text(viewModel.isNextTurnMine ? .gamesDrawAndGuessHandoffDraw : .gamesDrawAndGuessHandoffContinue)
            }
            .buttonStyle(PaeoniaPrimaryButtonStyle())
            .transition(reduceMotion ? .opacity : .opacity.combined(with: .offset(y: 12)))
            .accessibilityIdentifier("draw.reveal.continue")
        }
    }

    // MARK: Reveal

    private func beginReveal() {
        guard let reveal = viewModel.reveal, !timeline.hasBegun else { return }
        let letters = viewModel.slots.slots.count { !$0.isGap }
        let added = viewModel.revealScore?.largestGain ?? 0
        timeline.begin(
            DrawAndGuessRevealTimeline.Plan(
                kind: reveal.isSolved ? .solved : .missed,
                letterCount: letters,
                pointsAdded: added,
                hasSpeedBonus: (reveal.speedBonus ?? 0) > 0
            ),
            reduceMotion: reduceMotion
        )
        if reveal.isSolved {
            let points = String(localized: .gamesDrawAndGuessPoints(reveal.pointsForMe))
            AccessibilityNotification.Announcement(
                String(localized: .gamesDrawAndGuessRevealA11Y(DrawAndGuessAnswer.display(reveal.word), points))
            ).post()
        }
    }
}

/// The drawing is one VoiceOver element with its replay actions. While it loads
/// or cannot load, the spinner, or the error and its retry button, are reachable instead.
private struct DrawAndGuessReplayAccessibility: ViewModifier {
    let viewModel: DrawAndGuessViewModel
    let isDrawingShown: Bool

    func body(content: Content) -> some View {
        content
            .drawAndGuessDrawingAccessibility(
                label: Text(.gamesDrawAndGuessGuessReplayLabel(viewModel.partnerName)),
                hint: Text(.gamesDrawAndGuessGuessReplayHint),
                isDrawingShown: isDrawingShown
            )
            .accessibilityActions {
                if isDrawingShown {
                    Button {
                        viewModel.setFastForward(!viewModel.isFastForwarding)
                    } label: {
                        Text(.gamesDrawAndGuessGuessReplayFaster)
                    }
                    Button {
                        viewModel.showWholeDrawing()
                    } label: {
                        Text(.gamesDrawAndGuessGuessReplaySkip)
                    }
                }
            }
    }
}

/// "Got it!" with a line or two under it.
struct DrawAndGuessRevealTitle: View {
    let title: LocalizedStringResource
    let lines: [Text]
    var isFocused: AccessibilityFocusState<Bool>.Binding

    var body: some View {
        VStack(spacing: PaeoniaSpacing.space4) {
            Text(title)
                .font(PaeoniaTypography.largeTitle)
                .foregroundStyle(.paeoniaTextPrimary)
                .multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)
            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                line
                    .font(PaeoniaTypography.body)
                    .foregroundStyle(.paeoniaTextSecondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityFocused(isFocused)
        .accessibilityIdentifier("draw.reveal.title")
    }
}
