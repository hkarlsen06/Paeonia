import SwiftUI

/// The reveal of a finished figure. The folded paper waits for the three
/// drawings, then opens one fold at a time while each part replays its strokes.
/// After the legs the view pulls back to the whole figure with the petal bloom,
/// the title, the credits and the button.
///
/// `ExquisiteCorpseRevealTimeline` runs the beats and `ExquisiteCorpseFigurePlayer`
/// replays the strokes. This view draws their state and turns touches into moves:
/// a tap shows everything at once, and a hold plays the strokes at 4x. With Reduce
/// Motion everything shows at once, and "Play again" replays the parts one by one.
///
/// Give each figure its own view (`.id(content.figureID)`). The reveal plays once
/// per view.
struct ExquisiteCorpseRevealView: View {
    let content: ExquisiteCorpseRevealContent
    let reduceMotion: Bool
    let onContinue: () -> Void
    /// Called after the strokes start playing again. The view replays them itself.
    let onPlayAgain: (() -> Void)?

    @State private var timeline: ExquisiteCorpseRevealTimeline
    @State private var player: ExquisiteCorpseFigurePlayer
    /// Measured with the settled text, so the figure gets the height that is left.
    @State private var textHeight: CGFloat = 0
    @State private var isWide = false
    @State private var bloomStart: Date?
    @State private var holdTask: Task<Void, Never>?
    @State private var didStartHold = false
    @GestureState private var isPressing = false
    @ScaledMetric(relativeTo: .body) private var captionReserve: CGFloat = 72

    /// `timeline` and `player` are for previews and tests, which want to step them.
    init(
        content: ExquisiteCorpseRevealContent,
        reduceMotion: Bool,
        onContinue: @escaping () -> Void,
        onPlayAgain: (() -> Void)? = nil,
        timeline: ExquisiteCorpseRevealTimeline? = nil,
        player: ExquisiteCorpseFigurePlayer? = nil
    ) {
        self.content = content
        self.reduceMotion = reduceMotion
        self.onContinue = onContinue
        self.onPlayAgain = onPlayAgain
        _timeline = State(initialValue: timeline ?? ExquisiteCorpseRevealTimeline())
        _player = State(initialValue: player ?? ExquisiteCorpseFigurePlayer())
    }

    var body: some View {
        GeometryReader { proxy in
            Group {
                if isWide {
                    wide(proxy.size)
                } else {
                    narrow(proxy.size)
                }
            }
            .overlay(alignment: .bottomTrailing) {
                fastForwardGlyph
            }
        }
        // A tap or a hold anywhere on the reveal, while there is something to skip or speed up.
        .simultaneousGesture(pressGesture, isEnabled: isInteractive)
        .paeoniaBottomBar {
            if !isWide {
                bottomBar
            }
        }
        .onGeometryChange(for: Bool.self) { GameMetrics.isWide($0.size) } action: { isWide = $0 }
        .onChange(of: content.isReady, initial: true) { startIfReady() }
        .onChange(of: timeline.stage) { _, stage in
            if case let .playing(part) = stage {
                player.start(part)
            }
        }
        .onChange(of: timeline.showsBloom) { _, shows in
            if shows { bloomStart = .now }
        }
        .onChange(of: timeline.isSettled) { _, isSettled in
            if isSettled {
                AccessibilityNotification.Announcement(readyAnnouncement).post()
            }
        }
        .onChange(of: isPressing) { _, pressing in
            pressChanged(pressing)
        }
        .task(id: bloomStart) {
            // The bloom lasts under a second. Stop its timeline then.
            guard bloomStart != nil else { return }
            try? await Task.sleep(for: .seconds(GamePetalBloom.duration + 0.1))
            bloomStart = nil
        }
        .onAppear {
            player.onPartFinished = { [timeline] part in
                timeline.partReplayFinished(part)
            }
        }
        .onDisappear {
            holdTask?.cancel()
            timeline.stop()
            player.finish()
        }
    }

    // MARK: Layouts

    /// One column that scrolls. The title and the credits take the bottom of the
    /// stage. The whole figure sits above them, and a playing part sits in the
    /// middle of the screen. At accessibility sizes the text makes the stage taller
    /// than the screen.
    private func narrow(_ size: CGSize) -> some View {
        let padding = PaeoniaSpacing.screenHorizontalPadding
        let width = min(size.width, PaeoniaSpacing.readableContentWidth) - padding * 2
        let spacing = PaeoniaSpacing.space16
        let viewport = size.height - PaeoniaSpacing.space8 - PaeoniaSpacing.space16
        let height = max(viewport, size.height * Self.minOverviewShare + textHeight + spacing)
        return ScrollView {
            stage(
                width: width,
                height: height,
                overviewHeight: height - textHeight - spacing,
                viewportHeight: viewport
            )
            .overlay(alignment: .bottom) {
                textBlock
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { textHeight = $0 }
                    .modifier(RevealEntrance(isShown: timeline.showsTitle, reduceMotion: reduceMotion))
            }
            .padding(.horizontal, padding)
            .padding(.top, PaeoniaSpacing.space8)
            .padding(.bottom, PaeoniaSpacing.space16)
            .paeoniaReadableWidth()
        }
        .scrollBounceBehavior(.basedOnSize)
        // The figure stays put while it plays. It scrolls once the reveal has settled.
        .scrollDisabled(!timeline.isSettled)
    }

    /// The figure on the left, the title, the credits and the button on the right.
    private func wide(_ size: CGSize) -> some View {
        let padding = PaeoniaSpacing.screenHorizontalPadding
        let column = GameMetrics.sideColumnWidth
        let width = max(Self.minWideStage, size.width - column - PaeoniaSpacing.space32 - padding * 2)
        let height = size.height - PaeoniaSpacing.space16
        return HStack(spacing: PaeoniaSpacing.space32) {
            stage(width: width, height: height, overviewHeight: height, viewportHeight: size.height)
            VStack(spacing: 0) {
                ScrollView {
                    textBlock
                        .modifier(RevealEntrance(isShown: timeline.showsTitle, reduceMotion: reduceMotion))
                        .padding(.vertical, PaeoniaSpacing.space8)
                }
                .defaultScrollAnchor(.center)
                .scrollBounceBehavior(.basedOnSize)
                buttons
                    .padding(.vertical, PaeoniaSpacing.space12)
            }
            .frame(width: column)
        }
        .padding(.horizontal, padding)
        .padding(.vertical, PaeoniaSpacing.space8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var textBlock: some View {
        VStack(spacing: PaeoniaSpacing.space16) {
            ExquisiteCorpseRevealTitle(number: content.number)
            ExquisiteCorpseRevealCredits(parts: content.parts)
        }
        .frame(maxWidth: .infinity)
        .accessibilityHidden(!timeline.showsTitle)
    }

    // MARK: Stage

    /// The figure with its light, its petals and the caption of the part that plays.
    private func stage(width: CGFloat, height: CGFloat, overviewHeight: CGFloat, viewportHeight: CGFloat) -> some View {
        ExquisiteCorpseRevealStage(
            content: content,
            timeline: timeline,
            player: player,
            camera: ExquisiteCorpseRevealCamera(
                stage: CGSize(width: width, height: height),
                overviewHeight: overviewHeight,
                viewportHeight: viewportHeight,
                captionHeight: captionReserve
            ),
            bloomStart: bloomStart,
            reduceMotion: reduceMotion,
            canShowAll: isInteractive,
            onShowAll: showEverything,
            onPlayAgain: playAgain
        )
    }

    // MARK: Buttons

    private var bottomBar: some View {
        buttons
            .padding(.horizontal, PaeoniaSpacing.screenHorizontalPadding)
            .padding(.vertical, PaeoniaSpacing.space8)
            .paeoniaReadableWidth()
            .background(.paeoniaBackgroundSecondary)
    }

    /// The buttons keep their space from the start, so the figure never moves
    /// when they appear.
    private var buttons: some View {
        let isShown = timeline.showsButtons
        return VStack(spacing: PaeoniaSpacing.space12) {
            Button {
                PaeoniaHaptics.gameContinued()
                onContinue()
            } label: {
                Text(content.nextIsMine ? .exquisiteCorpseRevealNextHead : .exquisiteCorpseRevealContinue)
            }
            .buttonStyle(PaeoniaPrimaryButtonStyle())
            .accessibilityIdentifier("corpse.reveal.continue")
            if reduceMotion {
                Button { playAgain() } label: { Text(.exquisiteCorpseRevealReplay) }
                    .buttonStyle(PaeoniaQuietButtonStyle())
                    .accessibilityIdentifier("corpse.reveal.replay")
            }
        }
        .opacity(isShown ? 1 : 0)
        .offset(y: isShown || reduceMotion ? 0 : 18)
        .animation(reduceMotion ? nil : PaeoniaMotion.celebrationReveal, value: isShown)
        .allowsHitTesting(isShown)
        .disabled(!isShown)
        .accessibilityHidden(!isShown)
    }

    @ViewBuilder
    private var fastForwardGlyph: some View {
        if player.isFastForwarding {
            Image(systemName: "forward.fill")
                .font(.title3)
                .foregroundStyle(.paeoniaAccentPrimary)
                .padding(PaeoniaSpacing.space12)
                .transition(.opacity)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }

    // MARK: Derived state

    /// A tap or a hold has something to do: the reveal still runs, or a replay does.
    private var isInteractive: Bool {
        timeline.canSkip || player.isPlaying
    }

    private var readyAnnouncement: String {
        String(localized: .exquisiteCorpseRevealReadyA11Y(content.spokenCredits))
    }

    // MARK: Moves

    /// Begins the reveal once the three drawings are on the phone.
    private func startIfReady() {
        guard content.isReady, !timeline.hasBegun else { return }
        player.load(content.drawings)
        if reduceMotion {
            player.finish()
        }
        timeline.begin(reduceMotion: reduceMotion)
    }

    /// A tap or "Show the whole figure": every part in full and the settled screen.
    private func showEverything() {
        timeline.skip()
        player.finish()
    }

    /// "Play again" replays the strokes part by part on the settled screen, with no folds.
    private func playAgain() {
        guard timeline.isSettled, content.isReady else { return }
        player.playInSequence()
        onPlayAgain?()
    }

    /// A press that ends quickly is a tap. One that lasts is a hold, which plays
    /// at 4x until the finger lifts.
    private func pressChanged(_ pressing: Bool) {
        holdTask?.cancel()
        holdTask = nil
        if pressing {
            didStartHold = false
            holdTask = Task {
                try? await Task.sleep(for: .seconds(Self.holdDelay))
                guard !Task.isCancelled else { return }
                didStartHold = true
                player.setFastForward(true)
            }
        } else if didStartHold {
            didStartHold = false
            player.setFastForward(false)
        } else if isInteractive {
            showEverything()
        }
    }

    /// Reports a press as soon as the finger is down, and again when it lifts.
    private var pressGesture: some Gesture {
        LongPressGesture(minimumDuration: 0, maximumDistance: .infinity)
            .updating($isPressing) { current, state, _ in
                state = current
            }
    }

    // MARK: Constants

    /// How long a press lasts before it counts as a hold and not a tap.
    private static let holdDelay: TimeInterval = 0.2
    /// The whole figure never gets less than this share of the height, so a tall text block scrolls instead.
    private static let minOverviewShare: CGFloat = 0.6
    private static let minWideStage: CGFloat = 200
}

/// The title and credits come in with a short rise. Reduce Motion fades them only.
private struct RevealEntrance: ViewModifier {
    let isShown: Bool
    let reduceMotion: Bool

    func body(content: Content) -> some View {
        content
            .opacity(isShown ? 1 : 0)
            .offset(y: isShown || reduceMotion ? 0 : 12)
            .animation(reduceMotion ? nil : PaeoniaMotion.celebrationReveal, value: isShown)
    }
}
