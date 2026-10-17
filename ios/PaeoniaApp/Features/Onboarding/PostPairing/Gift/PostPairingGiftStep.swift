import SwiftUI

/// The partner's first drawing as a gift. It waits in a sealed envelope until the
/// person taps it. The envelope jumps, the flap folds back, and the drawing slides out
/// and plays back stroke by stroke, the way the partner drew it. Holding the drawing
/// speeds it up. When the last stroke lands, petals burst and the step offers to
/// draw one back.
///
/// Under Reduce Motion the envelope fades away and the finished drawing fades in.
struct PostPairingGiftStep: View {
    let model: PostPairingGiftModel
    let partnerName: String
    /// The envelope was tapped. The caller saves that the gift was opened.
    let onOpen: () -> Void
    let onDrawBack: () -> Void
    let onLater: () -> Void

    @State private var stage = PostPairingEnvelopeStage.sealed
    /// The envelope's idle float, from 0 to 1.
    @State private var float: CGFloat = 0
    @State private var sealBloomStart: Date?
    @State private var finishBloomStart: Date?
    @State private var glow: Double = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The square stops growing here, like the widget canvas, so strokes keep their weight.
    private static let maxSide: CGFloat = 340

    var body: some View {
        OnboardingStepScaffold(
            title: title,
            message: message,
            placement: .standalone,
            primary: model.phase == .finished
                ? OnboardingStepAction(title: .onboardingFirstDayGiftDrawBackButton, action: onDrawBack)
                : nil,
            secondary: model.phase == .finished
                ? OnboardingStepAction(title: .onboardingFirstDayLaterButton, action: onLater)
                : nil
        ) {
            Color.clear
                .aspectRatio(1, contentMode: .fit)
                .frame(maxWidth: Self.maxSide)
                .overlay { GeometryReader { proxy in stageView(side: proxy.size.width) } }
                .frame(maxWidth: .infinity)
        } content: {
            EmptyView()
        }
        .animation(PaeoniaMotion.stateChange, value: model.phase)
        .onAppear {
            guard !reduceMotion else {
                return
            }
            withAnimation(.easeInOut(duration: 2.4).repeatForever(autoreverses: true)) {
                float = 1
            }
        }
        .onChange(of: model.phase) { _, phase in
            if phase == .finished {
                payoff()
            }
        }
        .onDisappear {
            model.stop()
        }
    }

    private var title: LocalizedStringResource {
        model.phase == .finished
            ? .onboardingFirstDayGiftFinishedTitle(partnerName)
            : .onboardingFirstDayGiftTitle(partnerName)
    }

    private var message: LocalizedStringResource {
        switch model.phase {
        case .wrapped, .opening: .onboardingFirstDayGiftTapMessage
        case .replaying: .onboardingFirstDayGiftHoldHint
        case .finished: .onboardingFirstDayGiftFinishedMessage(partnerName)
        }
    }

    // MARK: Stage

    private func stageView(side: CGFloat) -> some View {
        // `GiftAccessibility` adds the button trait while a tap still opens it,
        // which the rule cannot see.
        // swiftlint:disable:next accessibility_trait_for_button
        PostPairingEnvelope(side: side, stage: stage, float: float) {
            GameSquare(side: side, glow: glow) {
                squareContent(side: side)
            }
        }
        .overlay { blooms }
        .contentShape(Rectangle())
        .onTapGesture {
            Task { await open() }
        }
        // Hold to fast-forward, only while it plays, so it never takes the tap that opens it.
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in holdChanged(true) }
                .onEnded { _ in holdChanged(false) },
            isEnabled: model.phase == .replaying
        )
        .modifier(GiftAccessibility(model: model, partnerName: partnerName, open: { Task { await open() } }))
    }

    private func squareContent(side: CGFloat) -> some View {
        ZStack {
            if model.phase == .replaying || model.phase == .finished {
                GameReplaySurface(frames: model.frames, side: side)
                    .allowsHitTesting(false)
            }
            if model.isFastForwarding {
                Image(systemName: "forward.fill")
                    .font(.title3)
                    .foregroundStyle(.paeoniaAccentPrimary)
                    .padding(PaeoniaSpacing.space12)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    .accessibilityHidden(true)
            }
        }
    }

    @ViewBuilder
    private var blooms: some View {
        if let sealBloomStart {
            // From the tip of the envelope's flap.
            GamePetalBloom(
                start: sealBloomStart,
                seed: "firstDay.seal",
                origin: UnitPoint(x: 0.5, y: 0.66),
                intensity: 0.6
            )
        }
        if let finishBloomStart {
            GamePetalBloom(start: finishBloomStart, seed: "firstDay.gift", origin: UnitPoint(x: 0.5, y: 0.5))
                .padding(-PaeoniaSpacing.space40)
        }
    }

    // MARK: Script

    private func open() async {
        guard model.beginOpening() else {
            return
        }
        onOpen()
        PaeoniaHaptics.giftUnwrapped()
        GameSound.fold.play()
        withAnimation(PaeoniaMotion.stateChange) {
            float = 0
        }

        if reduceMotion {
            withAnimation(.easeOut(duration: PaeoniaMotion.motionSlow)) {
                stage = .cardFull
            }
            model.startReplay(showsAtOnce: true)
            return
        }

        guard await playOpening() else { return }
        model.startReplay(showsAtOnce: false)
        AccessibilityNotification.Announcement(
            String(localized: .onboardingFirstDayGiftReplayAccessibility(partnerName))
        ).post()
    }

    /// The envelope jumps, the flap folds back, and the card slides out and grows.
    /// Returns false if the step went away meanwhile.
    private func playOpening() async -> Bool {
        withAnimation(.spring(duration: 0.3, bounce: 0.4)) {
            stage = .unsealed
        }
        sealBloomStart = Date()
        guard await sleep(0.15) else { return false }

        withAnimation(.spring(duration: 0.5, bounce: 0.12)) {
            stage = .flapOpening
        }
        // The flap is past upright, so it can go behind the card.
        guard await sleep(0.22) else { return false }
        withAnimation(.easeOut(duration: PaeoniaMotion.motionFast)) {
            stage = .cardInside
        }
        guard await sleep(0.2) else { return false }

        GameSound.flip.play(volume: 0.7)
        withAnimation(.spring(duration: 0.55, bounce: 0.22)) {
            stage = .cardOut
        }
        guard await sleep(0.5) else { return false }

        withAnimation(PaeoniaMotion.celebrationReveal) {
            stage = .cardFull
        }
        // The first stroke starts while the card settles, so the empty card never sits still.
        return await sleep(PaeoniaMotion.motionDefault)
    }

    private func payoff() {
        if !reduceMotion {
            finishBloomStart = Date()
        }
        withAnimation(.easeOut(duration: PaeoniaMotion.motionFast)) {
            glow = 0.55
        }
        withAnimation(.easeInOut(duration: 1.2).delay(PaeoniaMotion.motionFast)) {
            glow = 0.25
        }
        AccessibilityNotification.Announcement(
            String(localized: .onboardingFirstDayGiftFinishedTitle(partnerName))
        ).post()
    }

    private func holdChanged(_ isPressing: Bool) {
        guard model.phase == .replaying, model.isFastForwarding != isPressing else {
            return
        }
        if isPressing {
            PaeoniaHaptics.selection()
        }
        model.setFastForward(isPressing)
    }

    /// Sleeps for `seconds`, returning false if the step went away meanwhile.
    private func sleep(_ seconds: TimeInterval) async -> Bool {
        try? await Task.sleep(for: .seconds(seconds))
        return !Task.isCancelled
    }
}

/// VoiceOver reads the envelope as a button that opens it, and the drawing as what
/// it is, with an action that shows all of it at once. One shape for every phase,
/// so the stage under it keeps its identity and its animations.
private struct GiftAccessibility: ViewModifier {
    let model: PostPairingGiftModel
    let partnerName: String
    let open: () -> Void

    private var isWrapped: Bool { model.phase == .wrapped }
    private var isReplaying: Bool { model.phase == .replaying }

    func body(content: Content) -> some View {
        content
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(
                isWrapped
                    ? Text(.onboardingFirstDayGiftOpenAccessibility(partnerName))
                    : Text(.onboardingFirstDayGiftReplayAccessibility(partnerName))
            )
            .accessibilityAddTraits(isWrapped ? .isButton : [])
            .accessibilityHidden(model.phase == .opening)
            .accessibilityAction {
                if isWrapped {
                    open()
                }
            }
            .accessibilityActions {
                if isReplaying {
                    Button {
                        model.showWholeDrawing()
                    } label: {
                        Text(.onboardingFirstDayGiftShowWholeAction)
                    }
                }
            }
    }
}

#if DEBUG
#Preview("Gift") {
    PostPairingGiftStep(
        model: PostPairingGiftModel(
            gift: PostPairingGift(revisionID: UUID(), drawing: DeveloperPostPairingFixture.heart())
        ),
        partnerName: "Hjalmar",
        onOpen: {},
        onDrawBack: {},
        onLater: {}
    )
    .preferredColorScheme(.dark)
}
#endif
