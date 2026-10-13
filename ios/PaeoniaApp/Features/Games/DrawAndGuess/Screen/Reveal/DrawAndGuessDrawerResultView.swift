import SwiftUI

/// The drawer's screen after sending the drawing. It shows who has seen it, the
/// guesses as they come, and when the round ends the result. While the partner is
/// on their guess screen, it shows their letters and plays the drawing where
/// their replay is. The chips are the drawer's payoff for the turn, so on a round
/// that ended earlier they play back one by one.
struct DrawAndGuessDrawerResultView: View {
    @Bindable var viewModel: DrawAndGuessViewModel

    @State private var timeline = DrawAndGuessRevealTimeline()
    @State private var shownWrongCount: Int
    @State private var playbackTask: Task<Void, Never>?
    @State private var partnerPulse: CGFloat = 1
    @AccessibilityFocusState private var isTitleFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(viewModel: DrawAndGuessViewModel) {
        self.viewModel = viewModel
        let wrong = viewModel.round?.attempts.filter { !$0.isCorrect }.count ?? 0
        // A round that ended earlier plays its chips from the first one.
        _shownWrongCount = State(initialValue: viewModel.phase == .reveal ? 0 : wrong)
    }

    private var isRevealed: Bool { viewModel.phase == .reveal }
    /// The button that leads to the partner's next round, while it is on screen.
    private var nextRoundCall: DrawAndGuessPartnerNextRound? {
        isRevealed && timeline.buttonShown ? viewModel.partnerNextRound : nil
    }
    private var revealProgress: Int {
        [timeline.titleShown, timeline.panelShown, timeline.actionsShown].count { $0 }
    }
    /// The partner's guess screen, while the round is open and they are on it.
    private var partnerGuess: DrawAndGuessPartnerGuess? { isRevealed ? nil : viewModel.partnerGuess }
    private var wrongAttempts: [DrawAndGuessAttemptView] { viewModel.round?.attempts.filter { !$0.isCorrect } ?? [] }
    private var visibleWrong: [DrawAndGuessAttemptView] {
        isRevealed ? Array(wrongAttempts.prefix(shownWrongCount)) : wrongAttempts
    }

    var body: some View {
        // A tap anywhere skips to the settled result. It is a shortcut, and the buttons stay.
        // swiftlint:disable:next accessibility_trait_for_button
        DrawAndGuessPhaseLayout(
            scrollTrigger: revealProgress,
            freezesSide: isRevealed,
            sharing: .inherits,
            sideMemory: viewModel.squareMemory
        ) {
            if !isRevealed {
                statusRow
            }
        } square: { side in
            DrawAndGuessSquare(side: side, scale: 0.8, glow: timeline.glow) {
                DrawAndGuessDrawerSquareContent(viewModel: viewModel, partnerGuess: partnerGuess, side: side)
            }
            .drawAndGuessDrawingAccessibility(
                label: Text(.gamesDrawAndGuessGuessReplayLabel(viewModel.me.name)),
                isDrawingShown: viewModel.finalDrawing != nil
            )
        } footer: {
            footer
        } bottom: {
            if isRevealed, timeline.buttonShown, viewModel.isPartnerChoosingNextWord {
                DrawAndGuessLiveHint(text: .gamesDrawAndGuessWaitChoosing(viewModel.partnerName))
                    .transition(.opacity)
                    .accessibilityIdentifier("draw.reveal.partnerChoosing")
            }
            if isRevealed, timeline.buttonShown {
                Button {
                    Task { await viewModel.continueFromReveal() }
                } label: {
                    switch viewModel.partnerNextRound {
                    case .drawing:
                        DrawAndGuessWatchLabel(partnerName: viewModel.partnerName)
                    case .sent:
                        Text(.gamesDrawAndGuessHandoffSeeDrawing(viewModel.partnerName))
                    case nil:
                        Text(.gamesDrawAndGuessHandoffContinue)
                    }
                }
                .buttonStyle(PaeoniaPrimaryButtonStyle())
                .transition(reduceMotion ? .opacity : .opacity.combined(with: .offset(y: 12)))
                .accessibilityIdentifier("draw.reveal.continue")
            }
        }
        .animation(PaeoniaMotion.stateChange, value: viewModel.isPartnerChoosingNextWord)
        .simultaneousGesture(TapGesture().onEnded { finishNow() })
        .drawAndGuessStarToolbar(viewModel, isShown: isRevealed && timeline.actionsShown)
        .onChange(of: viewModel.phase, initial: true) { _, phase in
            if phase == .reveal {
                if playbackTask == nil, !timeline.hasBegun {
                    playbackTask = Task { await playResult() }
                }
            } else if playbackTask != nil || timeline.hasBegun {
                // The round is playable again, such as after a refused correct guess.
                playbackTask?.cancel()
                playbackTask = nil
                timeline.reset()
                shownWrongCount = wrongAttempts.count
            }
        }
        .onChange(of: wrongAttempts.count) { old, new in
            if !isRevealed, new > old, !viewModel.board.isStrokeInProgress {
                PaeoniaHaptics.partnerDrawingReceived()
            }
        }
        .onChange(of: viewModel.round?.guesserReaction) { old, new in
            // A reaction that shows up while the result is on screen. One that was
            // there when the screen opened comes in with the result instead.
            guard new != nil, new != old, timeline.actionsShown else { return }
            PaeoniaHaptics.partnerDrawingReceived()
        }
        .onChange(of: nextRoundCall) { _, call in
            guard let call else { return }
            PaeoniaHaptics.partnerDrawingReceived()
            let announcement: String = switch call {
            case .drawing: String(localized: .gamesDrawAndGuessWaitDrawing(viewModel.partnerName))
            case .sent: String(localized: .gamesDrawAndGuessHandoffSeeDrawing(viewModel.partnerName))
            }
            AccessibilityNotification.Announcement(announcement).post()
        }
        .onChange(of: viewModel.partnerPresence.isHere) { old, new in
            guard new, !old else { return }
            PaeoniaHaptics.partnerDrawingReceived()
            guard !reduceMotion else { return }
            withAnimation(PaeoniaMotion.stateChange) { partnerPulse = 1.12 }
            withAnimation(PaeoniaMotion.stateChange.delay(PaeoniaMotion.motionDefault)) { partnerPulse = 1 }
        }
        .onChange(of: timeline.titleShown) { _, shown in
            if shown, UIAccessibility.isVoiceOverRunning { isTitleFocused = true }
        }
        .animation(reduceMotion ? nil : PaeoniaMotion.cardReveal, value: visibleWrong.count)
        .animation(PaeoniaMotion.stateChange, value: partnerGuess == nil)
        .onDisappear {
            playbackTask?.cancel()
            timeline.stop()
        }
    }

    // MARK: Status

    private var statusRow: some View {
        HStack(spacing: PaeoniaSpacing.space12) {
            DrawAndGuessAvatar(player: viewModel.partner, isMe: false, size: 40)
                .overlay {
                    if viewModel.sentStatus == .looking {
                        Circle().strokeBorder(.paeoniaAccentPrimary, lineWidth: 2).padding(-2)
                    }
                }
                .scaleEffect(partnerPulse)
            VStack(alignment: .leading, spacing: PaeoniaSpacing.space2) {
                Text(.gamesDrawAndGuessResultSent(viewModel.partnerName))
                    .font(PaeoniaTypography.title)
                    .foregroundStyle(.paeoniaTextPrimary)
                Text(viewModel.sentStatus.line(partnerName: viewModel.partnerName))
                    .font(PaeoniaTypography.caption)
                    .foregroundStyle(.paeoniaTextSecondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, PaeoniaSpacing.space8)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("draw.result.status")
    }

    // MARK: Footer

    private var footer: some View {
        VStack(spacing: PaeoniaSpacing.space16) {
            if viewModel.isHeldOnPhone, !isRevealed {
                DrawAndGuessOfflineLine()
            }
            if let partnerGuess {
                DrawAndGuessPartnerSlots(guess: partnerGuess, partnerName: viewModel.partnerName)
                    .transition(.opacity)
            }
            guessArea
                .overlay {
                    if let start = timeline.bloomStart {
                        DrawAndGuessPetalBloom(
                            start: start,
                            seed: viewModel.round?.id.uuidString ?? "",
                            intensity: 0.5
                        )
                        .frame(width: 480, height: 320)
                    }
                }
            if isRevealed, let reveal = viewModel.reveal {
                revealSections(reveal)
            }
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var guessArea: some View {
        let hasChips = !visibleWrong.isEmpty || timeline.litLetters > 0
        if hasChips {
            DrawAndGuessAttemptChips(
                partnerName: viewModel.partnerName,
                wrongAttempts: visibleWrong,
                correctWord: timeline.litLetters > 0 ? viewModel.round?.word : nil,
                litLetters: timeline.litLetters,
                rippleIndex: timeline.rippleIndex
            )
        } else if !isRevealed {
            Text(.gamesDrawAndGuessResultNoTries(viewModel.partnerName))
                .font(PaeoniaTypography.caption)
                .foregroundStyle(.paeoniaTextSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
        }
    }

    @ViewBuilder
    private func revealSections(_ reveal: DrawAndGuessReveal) -> some View {
        let transition = reduceMotion ? AnyTransition.opacity : .opacity.combined(with: .offset(y: 12))
        VStack(spacing: PaeoniaSpacing.space16) {
            if timeline.titleShown {
                DrawAndGuessRevealTitle(
                    title: reveal.isSolved
                        ? .gamesDrawAndGuessResultGotIt(viewModel.partnerName)
                        : .gamesDrawAndGuessResultMissed(viewModel.partnerName),
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
                    showsFirstTryBonus: timeline.firstTryBonusShown,
                    isHeldOnPhone: viewModel.isHeldOnPhone
                )
                .transition(transition)
            }
            if timeline.actionsShown, let reaction = reveal.reaction {
                DrawAndGuessReactionCapsule(reaction: reaction, partnerName: viewModel.partnerName)
                    .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.9)))
            }
        }
        .animation(reduceMotion ? nil : PaeoniaMotion.cardReveal, value: reveal.reaction)
    }

    private func lines(for reveal: DrawAndGuessReveal) -> [DrawAndGuessRevealTitle.Line] {
        guard reveal.isSolved else { return [.init(text: Text(.gamesDrawAndGuessResultNoPoints))] }
        var lines = [DrawAndGuessRevealTitle.Line(text: Text(reveal.solvedLine(partnerName: viewModel.partnerName)))]
        if reveal.personalBest {
            lines.append(.init(
                text: Text(.gamesDrawAndGuessResultPersonalBest(viewModel.partnerName)),
                isAccent: true
            ))
        }
        return lines
    }
}

// MARK: - Playback

extension DrawAndGuessDrawerResultView {
    private func playResult() async {
        let total = wrongAttempts.count
        if !reduceMotion, shownWrongCount < total {
            let gap = DrawAndGuessChipPlayback.interval(chipCount: total)
            for index in shownWrongCount..<total {
                try? await Task.sleep(for: .seconds(gap))
                guard !Task.isCancelled else { return }
                withAnimation(PaeoniaMotion.cardReveal) { shownWrongCount = index + 1 }
                PaeoniaHaptics.partnerDrawingReceived()
            }
        }
        shownWrongCount = total
        beginReveal()
    }

    private func beginReveal() {
        guard let reveal = viewModel.reveal, !timeline.hasBegun else { return }
        let added = viewModel.revealScore?.largestGain ?? 0
        // "Together" has no bonuses, so no bonus beat plays.
        let isAgainst = viewModel.settings?.playStyle == .against
        timeline.begin(
            DrawAndGuessRevealTimeline.Plan(
                kind: reveal.isSolved ? .solved : .missed,
                letterCount: reveal.isSolved ? DrawAndGuessAnswer.letters(of: reveal.word).count : 0,
                pointsAdded: added,
                hasSpeedBonus: isAgainst && reveal.speedBonus > 0,
                hasFirstTryBonus: isAgainst && reveal.firstTryBonus > 0
            ),
            reduceMotion: reduceMotion
        )
    }

    /// A tap finishes the chips, then the result.
    private func finishNow() {
        guard isRevealed else { return }
        if !timeline.hasBegun {
            playbackTask?.cancel()
            shownWrongCount = wrongAttempts.count
            beginReveal()
        }
        if timeline.titleShown { timeline.skip() }
    }
}

/// "Watch [Name] draw" with a dot that pulses, as the live badge of the game does.
struct DrawAndGuessWatchLabel: View {
    let partnerName: String

    var body: some View {
        HStack(spacing: PaeoniaSpacing.space8) {
            DrawAndGuessLiveDot(color: .paeoniaTextInverse)
            Text(.gamesDrawAndGuessHandoffWatch(partnerName))
        }
    }
}

/// A line above a result screen's button about what the partner does right now.
struct DrawAndGuessLiveHint: View {
    let text: LocalizedStringResource

    var body: some View {
        HStack(spacing: PaeoniaSpacing.space8) {
            DrawAndGuessLiveDot(color: .paeoniaAccentPrimary)
            Text(text)
                .font(PaeoniaTypography.caption)
                .foregroundStyle(.paeoniaTextSecondary)
        }
        .accessibilityElement(children: .combine)
    }
}

/// A dot that pulses to show the partner is there right now.
struct DrawAndGuessLiveDot: View {
    let color: Color
    @State private var isDim = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 10, height: 10)
            .opacity(isDim ? 0.35 : 1)
            .scaleEffect(isDim ? 0.8 : 1)
            .accessibilityHidden(true)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) { isDim = true }
            }
    }
}
