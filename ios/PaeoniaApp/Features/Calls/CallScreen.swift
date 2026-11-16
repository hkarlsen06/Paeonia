import SwiftUI

/// The full call screen. The partner's face and name on both partners' petal colors, what the
/// call is doing, their local time, and the controls. During video one of up to three videos fills
/// the screen, the partner's camera, their shared screen or your own, and the others are previews in
/// a corner you drag them to (`CallStageView`). A tap on a preview makes it the big one. A swipe down,
/// or the chevron, shrinks the call to the bubble, or to the ring pill while the partner's call rings
/// inside the app. The message button at the top right shrinks the call to its bubble and slides
/// "Just us" in over the app, as a tap on the partner's message notice does. What the partner just did
/// and the call's own news show above the controls (`CallNotices`), because the partner's avatar and
/// the app's banners are under the call. During video the controls fade out after a few seconds without a touch, so
/// nothing covers the video, and a tap brings them back. With the back camera on, a zoom slider sits
/// above them (`CallZoomSlider`). A phone held on its side turns the videos and the symbols the way
/// it is held, while the screen stays upright (`CallTurn`).
struct CallScreen: View {
    let center: CallCenter
    let session: CallSession
    let participants: DailyChallengeParticipants
    var callout: PresenceCallout?
    /// Shrinks the call to its bubble and opens what the callout is about.
    var openCallout: (PresenceDestination) -> Void = { _ in }
    /// Shrinks the call to its bubble, or to the ring pill while the partner's call rings in the app.
    var minimize: () -> Void = {}
    /// Which video fills the screen and how the previews follow it.
    @Binding var stageOrder: CallStageOrder
    /// Where the person dragged the previews to.
    @Binding var previewCorner: CallPreviewCorner
    /// "Just us" can open, which needs a couple.
    var canOpenChat = false
    /// How the phone is held. It turns the videos only while one shows.
    var deviceTurn = CallTurn.none

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.openURL) private var openURL
    @AccessibilityPresentation(.controls) private var showsControls
    @State private var partnerTimeZone: TimeZone?
    @State private var dragOffset: CGFloat = 0
    /// The height of what sits under the face while the call runs. An ended call keeps it, so the
    /// face and the name stay put when the call ends.
    @State private var bottomHeight: CGFloat?
    @State private var isHUDHidden = false
    /// Counts taps on the controls, so each one starts the wait before they hide again.
    @State private var hudTouches = 0
    @State private var isAdjustingZoom = false
    /// Measured here, because the stage ignores the safe area and reads none of its own.
    @State private var safeArea = EdgeInsets()
    /// The turn the videos and symbols show, which follows `wantedTurn`.
    @State private var turn = CallTurn.none
    /// Under Reduce Motion the videos fade out and back in instead of moving (`changeStage`).
    @State private var stageOpacity: Double = 1

    /// How far a drag goes before letting go shrinks the screen.
    private static let minimizeDistance: CGFloat = 120

    private var isEnded: Bool {
        if case .ended = session.phase { return true }
        return false
    }

    private var isUnderWay: Bool {
        switch session.phase {
        case .active, .reconnecting: true
        default: false
        }
    }

    private var stage: CallStage {
        stageOrder.stage(for: session)
    }

    private var hasMainVideo: Bool {
        stage.main != nil
    }

    /// The turn the videos should take: none without video.
    private var wantedTurn: CallTurn {
        stage.sources.isEmpty ? .none : deviceTurn
    }

    var body: some View {
        // The taps only hide and show the controls, which never hide for VoiceOver or Switch Control.
        // swiftlint:disable:next accessibility_trait_for_button
        ZStack {
            background
            CallScreenStage(
                engine: center.engine, session: session, stage: stage, partnerName: participants.partnerName,
                makesRoomForControls: showsHUD || reduceMotion,
                controlsHeight: bottomHeight ?? 0, safeArea: safeArea, turn: turn, corner: $previewCorner,
                bringForward: bringForward)
            .opacity(stageOpacity)
            if hasMainVideo {
                scrims.callHUD(isShown: showsHUD)
            }
            hud
                .environment(\.callTurn, turn)
        }
        // Buttons and the callout win their own taps. While the controls are hidden they take
        // none, so the first tap only brings them back.
        .onGeometryChange(for: EdgeInsets.self, of: { $0.safeAreaInsets }, action: { safeArea = $0 })
        .contentShape(.rect)
        .gesture(TapGesture().onEnded { toggleHUD() })
        .offset(y: dragOffset)
        .gesture(swipeDown)
        .animation(reduceMotion ? nil : PaeoniaMotion.stateChange, value: session)
        .animation(reduceMotion ? nil : PaeoniaMotion.callOverlay, value: shownCallout)
        .animation(reduceMotion ? nil : PaeoniaMotion.stateChange, value: center.backCameraZoom != nil)
        .task(id: session.id) {
            partnerTimeZone = await center.engine.partnerTimeZone()
        }
        .task(id: HUDTimer(canHide: canHideHUD, isHidden: isHUDHidden, touches: hudTouches)) {
            await hideHUDWhenIdle()
        }
        .onChange(of: wantedTurn, initial: true) { _, wanted in follow(wanted) }
        .accessibilityAction(.escape) { shrink() }
    }

    // MARK: - Layout

    /// Concentric with the display, so it fills the screen and is a pill while it grows out of
    /// the ring pill.
    private var background: some View {
        ConcentricRectangle(corners: .concentric, isUniform: true)
            .fill(LinearGradient(
                colors: [
                    Color.paeoniaBackgroundPrimary.mix(with: .paeoniaPartnerTwo, by: 0.34),
                    Color.paeoniaBackgroundPrimary,
                    Color.paeoniaBackgroundPrimary.mix(with: .paeoniaPartnerOne, by: 0.26),
                ],
                startPoint: .top,
                endPoint: .bottom
            ))
            .ignoresSafeArea()
            .callMorph(.background)
    }

    /// Dark edges over the big video, so the name and the buttons stay readable.
    private var scrims: some View {
        VStack(spacing: 0) {
            LinearGradient(colors: [.black.opacity(0.55), .clear], startPoint: .top, endPoint: .bottom)
                .frame(height: 200)
            Spacer(minLength: 0)
            LinearGradient(colors: [.clear, .black.opacity(0.6)], startPoint: .top, endPoint: .bottom)
                .frame(height: 260)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    private var hud: some View {
        VStack(spacing: 0) {
            topBar.callHUD(isShown: showsHUD)
            if hasMainVideo {
                Spacer(minLength: 0)
            } else {
                Spacer(minLength: PaeoniaSpacing.space24)
                CallIdentity(session: session, participants: participants, partnerTimeZone: partnerTimeZone)
                Spacer(minLength: PaeoniaSpacing.space24)
            }
            bottom
        }
        .padding(.horizontal, PaeoniaSpacing.screenHorizontalPadding)
        .padding(.bottom, PaeoniaSpacing.space24)
        .frame(maxWidth: PaeoniaSpacing.focusedContentWidth)
    }

    private var topBar: some View {
        HStack(alignment: .top, spacing: PaeoniaSpacing.space12) {
            Button(action: shrink) {
                Image(systemName: "chevron.down")
                    .font(.system(size: 17, weight: .semibold))
                    .callTurned()
            }
            .buttonStyle(PaeoniaGlassCircleButtonStyle(face: PaeoniaSpacing.compactButtonHeight))
            .accessibilityLabel(Text(.callsMinimize))
            .accessibilityIdentifier("calls.minimize")

            if hasMainVideo {
                VStack(alignment: .leading, spacing: PaeoniaSpacing.space2) {
                    Text(verbatim: participants.partnerName)
                        .font(PaeoniaTypography.sectionTitle)
                        .foregroundStyle(.paeoniaTextPrimary)
                        .lineLimit(1)
                    CallStatusLine(phase: session.phase, direction: session.direction, font: PaeoniaTypography.caption)
                }
                .accessibilityElement(children: .combine)
                .transition(.opacity)
            }
            Spacer(minLength: 0)
            if isUnderWay {
                CallTopBarButtons(
                    session: session, engine: center.engine, partnerName: participants.partnerName,
                    canOpenChat: canOpenChat, openChat: { openCallout(.chat(.couple)) })
                    .transition(.opacity)
            }
        }
        // Without it the chevron's accessibility frame spans the whole row once Share and Message
        // sit in it, so VoiceOver outlines the row and a tap at the frame's middle misses.
        .accessibilityElement(children: .contain)
        .padding(.top, PaeoniaSpacing.space8)
    }

    @ViewBuilder
    private var bottom: some View {
        if isEnded {
            // In a stack, because a frame on the empty view an ordinary ending shows takes no space.
            VStack(spacing: 0) { endedActions }
                .frame(maxWidth: .infinity, minHeight: bottomHeight ?? CallControlButton.size + PaeoniaSpacing.space32)
        } else {
            VStack(spacing: 0) {
                if session.isWaitingForMicrophone {
                    Text(.callsMicrophoneWaiting(participants.partnerName))
                        .font(PaeoniaTypography.body)
                        .foregroundStyle(.paeoniaTextPrimary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.bottom, PaeoniaSpacing.space16)
                        .transition(.opacity)
                }
                VStack(spacing: PaeoniaSpacing.space16) {
                    if let zoom = center.backCameraZoom {
                        CallZoomSlider(zoom: zoom, setZoom: center.engine.setBackCameraZoom) { isAdjustingZoom = $0 }
                            .transition(.opacity)
                    }
                    // swiftlint:disable:next accessibility_trait_for_button
                    controls
                        .simultaneousGesture(TapGesture().onEnded { hudTouches += 1 })
                }
                .callHUD(isShown: showsHUD)
            }
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { bottomHeight = $0 }
            .overlay(alignment: .top) { noticesView }
        }
    }

    private var shownCallout: PresenceCallout? {
        isEnded ? nil : callout
    }

    /// Above the controls, with no height of its own, so nothing on the screen moves for it. While the
    /// controls are hidden it moves down into their room, like the previews, and back up when they
    /// show again.
    private var noticesView: some View {
        CallNotices(
            session: session, engine: center.engine, partnerName: participants.partnerName, callout: shownCallout,
            openCallout: openCallout)
            .frame(height: 0, alignment: .bottom)
            .offset(y: showsHUD || reduceMotion ? -PaeoniaSpacing.space16 : bottomHeight ?? 0)
    }

    /// Answering swaps Answer and Decline for the call controls in one place, one fading out
    /// before the other fades in, so the two rows never show on top of each other.
    private var controls: some View {
        ZStack {
            if session.direction == .incoming, session.phase == .ringing {
                CallAnswerControls(engine: center.engine)
                    .transition(Self.controlsSwap)
            } else {
                CallControls(session: session, engine: center.engine)
                    .transition(Self.controlsSwap)
            }
        }
    }

    private static let controlsSwap = AnyTransition.asymmetric(
        insertion: .opacity.animation(.easeOut(duration: 0.2).delay(0.12)),
        removal: .opacity.animation(.easeIn(duration: 0.12))
    )

    /// What the person can do about a call that could not go through. Waiting does not help with
    /// the microphone, so that one opens Settings.
    @ViewBuilder
    private var endedActions: some View {
        switch session.phase {
        case .ended(.failed(.microphoneDenied)):
            Button {
                if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
            } label: {
                Text(.commonOpenSettings)
            }
            .buttonStyle(PaeoniaQuietButtonStyle())
        case .ended(.failed(.other)):
            PaeoniaSupportLink()
        default:
            EmptyView()
        }
    }

    private func bringForward(_ source: CallVideoSource) {
        changeStage(.spring(duration: 0.4, bounce: 0.12)) { stageOrder.bringForward(source, in: session) }
        hudTouches += 1
    }
}

// MARK: - Minimizing

extension CallScreen {
    private var swipeDown: some Gesture {
        DragGesture(minimumDistance: 20)
            .onChanged { value in
                dragOffset = max(0, value.translation.height)
            }
            .onEnded { value in
                if value.translation.height > Self.minimizeDistance
                    || value.predictedEndTranslation.height > Self.minimizeDistance * 2 {
                    shrink()
                } else {
                    withAnimation(reduceMotion ? nil : .spring(duration: 0.3, bounce: 0.2)) { dragOffset = 0 }
                }
            }
    }

    private func shrink() {
        withAnimation(reduceMotion ? nil : PaeoniaMotion.stateChange) { minimize() }
    }
}

// MARK: - Moving the videos

extension CallScreen {
    /// Turns like the Camera app.
    private func follow(_ wanted: CallTurn) {
        guard wanted != turn else { return }
        changeStage(PaeoniaMotion.stateChange) { turn = wanted }
    }

    /// Moves the videos with `animation`, or under Reduce Motion fades them out and back in at their
    /// new places.
    private func changeStage(_ animation: Animation, _ change: @escaping () -> Void) {
        guard reduceMotion else {
            withAnimation(animation, change)
            return
        }
        let fade = PaeoniaMotion.standardCurve(duration: 0.15)
        withAnimation(fade) {
            stageOpacity = 0
        } completion: {
            change()
            withAnimation(fade) { stageOpacity = 1 }
        }
    }
}

// MARK: - Hiding the controls

extension CallScreen {
    private static let hudDelay = Duration.seconds(4)
    private static let hudFade = PaeoniaMotion.standardCurve(duration: 0.3)

    /// Someone who uses VoiceOver, Switch Control or Extra controls keeps the controls on screen.
    /// They also stay while a finger zooms.
    private var canHideHUD: Bool {
        guard hasMainVideo, case .active = session.phase else { return false }
        return !session.isWaitingForMicrophone && !showsControls && !isAdjustingZoom
    }

    private var showsHUD: Bool { !canHideHUD || !isHUDHidden }

    /// Any change to these starts the wait over.
    private struct HUDTimer: Equatable {
        let canHide: Bool
        let isHidden: Bool
        let touches: Int
    }

    private func hideHUDWhenIdle() async {
        guard canHideHUD else {
            // So they wait the full delay before hiding once hiding is allowed again.
            isHUDHidden = false
            return
        }
        guard !isHUDHidden else { return }
        do {
            try await Task.sleep(for: Self.hudDelay)
        } catch {
            return
        }
        withAnimation(Self.hudFade) { isHUDHidden = true }
    }

    /// Like FaceTime, a tap hides shown controls at once and brings hidden ones back.
    private func toggleHUD() {
        guard canHideHUD else { return }
        withAnimation(Self.hudFade) { isHUDHidden.toggle() }
    }
}

private extension View {
    func callHUD(isShown: Bool) -> some View {
        opacity(isShown ? 1 : 0)
            .allowsHitTesting(isShown)
            .accessibilityHidden(!isShown)
    }
}
