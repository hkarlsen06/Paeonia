import SwiftUI

/// The reveal of a round: both cards flip, the outcome lands, and the title and
/// buttons follow. It owns the timeline and starts it when the screen opens.
///
/// - A round the person has not seen plays the whole reveal.
/// - A game whose ending the person has seen opens settled, with the trail of
///   earlier rounds above the cards.
/// - "Count it" on a near miss turns the reveal into a meld in place.
struct MindMeldRevealView: View {
    @Bindable var viewModel: MindMeldViewModel

    @State private var timeline = MindMeldRevealTimeline()
    /// Only a reveal that played for this person is announced to VoiceOver.
    @State private var announces = false
    @State private var lastAnnounced: MindMeldRevealOutcome?
    @State private var isWide = false
    /// The earlier rounds show only when the screen opens on a finished game, so
    /// the cards do not move when the ending is marked as seen.
    @State private var showsTrail: Bool
    @AccessibilityFocusState private var isTitleFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let cardWidth: CGFloat = 160
    private static let wideCardWidth: CGFloat = 220

    init(viewModel: MindMeldViewModel) {
        self.viewModel = viewModel
        _showsTrail = State(initialValue: viewModel.phase == .over)
    }

    var body: some View {
        // A tap anywhere skips to the settled result. It is a shortcut, and the buttons stay.
        // swiftlint:disable:next accessibility_trait_for_button
        GameFocusedLayout(contentWidth: PaeoniaSpacing.readableContentWidth) {
            VStack(spacing: PaeoniaSpacing.space32) {
                earlierRounds
                stage
                result
            }
            .frame(maxWidth: .infinity)
            .padding(.top, PaeoniaSpacing.space24)
        } bottom: {
            actions
        }
        .simultaneousGesture(TapGesture().onEnded {
            if timeline.canSkip { timeline.skip() }
        })
        .onGeometryChange(for: Bool.self) { proxy in
            proxy.size.width >= 700 && proxy.size.width > proxy.size.height
        } action: { isWide = $0 }
        .onChange(of: viewModel.phase, initial: true) {
            beginIfNeeded()
        }
        .onChange(of: viewModel.revealOutcome) { old, new in
            guard timeline.hasBegun else {
                beginIfNeeded()
                return
            }
            // A partner counted the near miss, or this person did.
            if old == .near, new == .meld {
                announces = true
                timeline.meldFromNear()
            }
        }
        .onChange(of: shownOutcome) { _, outcome in
            guard announces, let outcome, outcome != lastAnnounced else { return }
            lastAnnounced = outcome
            announce(outcome)
        }
        .onChange(of: timeline.titleShown) { _, shown in
            guard shown else { return }
            viewModel.revealSettled()
            if UIAccessibility.isVoiceOverRunning { isTitleFocused = true }
        }
        .onDisappear { timeline.stop() }
        .accessibilityIdentifier("mindMeld.reveal")
    }

    // MARK: Timeline

    private func beginIfNeeded() {
        guard !timeline.hasBegun, let outcome = viewModel.revealOutcome else { return }
        let plan = MindMeldRevealPlan(outcome: outcome)
        switch viewModel.phase {
        case .reveal:
            announces = true
            timeline.begin(plan, reduceMotion: reduceMotion)
        case .over:
            timeline.showSettled(plan)
        default:
            break
        }
    }

    /// The outcome the cards show right now, or nil before the verdict. The text
    /// and the buttons follow the cards, so a counted near miss does not show the
    /// meld's title before the cards have merged.
    private var shownOutcome: MindMeldRevealOutcome? {
        if timeline.merged { return .meld }
        if timeline.leaning { return .near }
        if timeline.linkDrawn { return viewModel.revealOutcome }
        return nil
    }

    private func announce(_ outcome: MindMeldRevealOutcome) {
        let mine = viewModel.round?.myWord ?? ""
        let theirs = viewModel.round?.partnerWord ?? ""
        let text = outcome == .meld
            ? String(localized: .mindMeldRevealMeldAnnouncement(mine))
            : String(localized: .mindMeldRevealMissAnnouncement(mine, viewModel.partnerName, theirs))
        AccessibilityNotification.Announcement(text).post()
    }

    // MARK: Stage

    private var stage: some View {
        MindMeldRevealStage(
            me: (name: viewModel.me.name, photoAssetID: viewModel.me.photoAssetID),
            partner: (name: viewModel.partner.name, photoAssetID: viewModel.partner.photoAssetID),
            myWord: viewModel.round?.myWord ?? "",
            partnerWord: viewModel.round?.partnerWord ?? "",
            myCardFlipped: timeline.myCardFlipped,
            partnerCardFlipped: timeline.partnerCardFlipped,
            pulse: timeline.pulse,
            merged: timeline.merged,
            joined: timeline.joined,
            leaning: timeline.leaning,
            linkDrawn: timeline.linkDrawn,
            glow: timeline.glow,
            bloomStart: timeline.bloomStart,
            seed: viewModel.round?.id.uuidString ?? "",
            cardMaxWidth: isWide ? Self.wideCardWidth : Self.cardWidth
        )
    }

    /// The rounds before the last one, for a game that was over when the screen opened.
    @ViewBuilder
    private var earlierRounds: some View {
        let earlier = viewModel.resolution.trail.dropLast().map {
            (mine: $0.mine, theirs: $0.theirs, isMeld: false, isCounted: false)
        }
        if showsTrail, !earlier.isEmpty {
            MindMeldTrailView(pairs: earlier)
                .transition(.opacity)
        }
    }

    // MARK: Result

    private var result: some View {
        VStack(spacing: PaeoniaSpacing.space8) {
            if timeline.titleShown, let outcome = shownOutcome {
                MindMeldRevealTitle(
                    title: title(for: outcome),
                    lines: lines(for: outcome),
                    isFocused: $isTitleFocused
                )
                .transition(reduceMotion ? .opacity : .opacity.combined(with: .offset(y: 12)))
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func title(for outcome: MindMeldRevealOutcome) -> LocalizedStringResource {
        switch outcome {
        case .meld: .mindMeldRevealMeldTitle
        case .near: .mindMeldRevealNearTitle
        case .miss: .mindMeldRevealMissTitle
        case .gotAway: .mindMeldRevealGotAwayTitle
        }
    }

    private func lines(for outcome: MindMeldRevealOutcome) -> [MindMeldRevealTitle.Line] {
        let mine = (viewModel.round?.myWord ?? "").localizedUppercase
        let theirs = (viewModel.round?.partnerWord ?? "").localizedUppercase
        switch outcome {
        case .meld:
            return meldLines
        case .near:
            return [.init(text: Text(.mindMeldRevealNearLine(mine, theirs)))]
        case .miss:
            return [.init(text: Text(.mindMeldRevealMissLine(mine, theirs)))]
        case .gotAway:
            return [.init(text: Text(.mindMeldRevealGotAwayLine))]
        }
    }

    /// How many rounds it took, who counted a near miss, and the couple's numbers.
    private var meldLines: [MindMeldRevealTitle.Line] {
        var lines = [MindMeldRevealTitle.Line(text: Text(.mindMeldRevealMeldRounds(viewModel.resolution.roundNumber)))]
        if let countedBy = viewModel.round?.countedByUserID {
            let text = countedBy == viewModel.currentUserID
                ? Text(.mindMeldRevealMeldCountedByYou)
                : Text(.mindMeldRevealMeldCounted(viewModel.partnerName))
            lines.append(.init(text: text))
        }
        if timeline.statsShown, let stats = statsLine {
            lines.append(.init(text: Text(verbatim: stats.text), isAccent: stats.isAccent))
        }
        return lines
    }

    /// "Your fewest rounds yet." on a record, else "Meld number 3. Your fewest is 2 rounds."
    /// Nothing until the server has numbered the meld.
    private var statsLine: (text: String, isAccent: Bool)? {
        guard let game = viewModel.game, game.state == .melded, let number = game.meldNumber else { return nil }
        if game.isRecord {
            return (String(localized: .mindMeldRevealMeldRecord), true)
        }
        if number == 1 {
            return (String(localized: .mindMeldRevealMeldFirst), false)
        }
        var sentences = [String(localized: .mindMeldRevealMeldNumber(number))]
        if let fewest = viewModel.stats?.fewestRounds {
            sentences.append(String(localized: .mindMeldRevealMeldFewest(fewest)))
        }
        return (sentences.joined(separator: " "), false)
    }

    // MARK: Actions

    /// The bar keeps its place before the buttons appear, so the cards above do not move.
    @ViewBuilder
    private var actions: some View {
        if let outcome = shownOutcome ?? viewModel.revealOutcome {
            VStack(spacing: PaeoniaSpacing.space12) {
                switch outcome {
                case .miss:
                    nextRoundButton
                case .near:
                    if viewModel.game?.isFinished == true { playAgainButton } else { nextRoundButton }
                    if viewModel.resolution.canCount { countItButton }
                case .meld, .gotAway:
                    playAgainButton
                    seeMeldsLink
                }
            }
            .opacity(timeline.actionsShown ? 1 : 0)
            .offset(y: timeline.actionsShown || reduceMotion ? 0 : 12)
            .allowsHitTesting(timeline.actionsShown)
            .accessibilityHidden(!timeline.actionsShown)
        }
    }

    private var nextRoundButton: some View {
        Button {
            viewModel.continueFromReveal()
        } label: {
            Text(.mindMeldRevealNext)
        }
        .buttonStyle(PaeoniaPrimaryButtonStyle())
        .accessibilityIdentifier("mindMeld.nextRound")
    }

    private var playAgainButton: some View {
        Button {
            Task { await viewModel.playAgain() }
        } label: {
            Text(.mindMeldRevealPlayAgain)
        }
        .buttonStyle(PaeoniaPrimaryButtonStyle(isLoading: viewModel.isStartingGame))
        .accessibilityIdentifier("mindMeld.playAgain")
    }

    private var countItButton: some View {
        Button {
            PaeoniaHaptics.selection()
            GameSound.tap.play()
            viewModel.countIt()
        } label: {
            Text(.mindMeldRevealNearCount)
        }
        .buttonStyle(PaeoniaQuietButtonStyle())
        .accessibilityIdentifier("mindMeld.countIt")
    }

    private var seeMeldsLink: some View {
        NavigationLink(value: GamesDestination.mindMeldHistory) {
            Text(.mindMeldRevealSeeMelds)
        }
        .buttonStyle(PaeoniaQuietButtonStyle())
        .accessibilityIdentifier("mindMeld.seeMelds")
    }
}

// MARK: - Title

/// "You melded!" with a line or two under it.
private struct MindMeldRevealTitle: View {
    struct Line {
        let text: Text
        /// The line stands out, such as a new record.
        var isAccent = false
    }

    let title: LocalizedStringResource
    let lines: [Line]
    var isFocused: AccessibilityFocusState<Bool>.Binding

    var body: some View {
        VStack(spacing: PaeoniaSpacing.space4) {
            Text(title)
                .font(PaeoniaTypography.largeTitle)
                .foregroundStyle(.paeoniaTextPrimary)
                .multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)
            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                line.text
                    .font(PaeoniaTypography.body)
                    .foregroundStyle(line.isAccent ? .paeoniaAccentPrimary : .paeoniaTextSecondary)
                    .multilineTextAlignment(.center)
                    .transition(.opacity.combined(with: .offset(y: 8)))
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityFocused(isFocused)
        .accessibilityIdentifier("mindMeld.reveal.title")
    }
}
