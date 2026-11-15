import SwiftUI

/// The full call screen. The partner's face and name on both partners' petal colors, what the
/// call is doing, their local time, and the controls. During video the partner's video fills the
/// screen and your own sits in a corner. A swipe down, or the chevron, shrinks it to the bubble, or
/// to the ring pill while the partner's call rings inside the app.
struct CallScreen: View {
    let center: CallCenter
    let session: CallSession
    let participants: DailyChallengeParticipants

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.openURL) private var openURL
    @State private var partnerTimeZone: TimeZone?
    @State private var dragOffset: CGFloat = 0
    /// The height of what sits under the face while the call runs. An ended call keeps it, so the
    /// face and the name stay put when the call ends.
    @State private var bottomHeight: CGFloat?

    private static let avatarSize: CGFloat = 132
    /// The glow at its largest. It breathes between `glowScales`, which never go past 1.
    private static let glowSize = avatarSize * 1.45
    private static let glowScales: [CGFloat] = [0.86, 1]
    private static let localTileSize = CGSize(width: 104, height: 152)
    /// How far a drag goes before letting go shrinks the screen.
    private static let minimizeDistance: CGFloat = 120

    private var showsPartnerVideo: Bool { session.isPartnerCameraOn && !isEnded }
    private var isEnded: Bool {
        if case .ended = session.phase { return true }
        return false
    }

    var body: some View {
        ZStack {
            background
            if showsPartnerVideo {
                CallVideoView(engine: center.engine, source: .partner)
                    .ignoresSafeArea()
                    .transition(.opacity)
                scrims
            }
            VStack(spacing: 0) {
                topBar
                if showsPartnerVideo {
                    Spacer(minLength: 0)
                } else {
                    Spacer(minLength: PaeoniaSpacing.space24)
                    identity
                    Spacer(minLength: PaeoniaSpacing.space24)
                }
                bottom
            }
            .padding(.horizontal, PaeoniaSpacing.screenHorizontalPadding)
            .padding(.bottom, PaeoniaSpacing.space24)
            .frame(maxWidth: PaeoniaSpacing.focusedContentWidth)
        }
        .overlay(alignment: .topTrailing) { localTile }
        .offset(y: dragOffset)
        .gesture(swipeDown)
        .animation(reduceMotion ? nil : PaeoniaMotion.stateChange, value: session)
        .task(id: session.id) {
            partnerTimeZone = await center.engine.partnerTimeZone()
        }
        .accessibilityAction(.escape, minimize)
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

    /// Dark edges over the partner's video, so the name and the buttons stay readable.
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

    private var topBar: some View {
        HStack(alignment: .top, spacing: PaeoniaSpacing.space12) {
            Button(action: minimize) {
                Image(systemName: "chevron.down")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.paeoniaTextPrimary)
                    .frame(width: PaeoniaSpacing.compactButtonHeight, height: PaeoniaSpacing.compactButtonHeight)
                    .glassEffect(.regular.interactive(), in: Circle())
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(.callsMinimize))
            .accessibilityIdentifier("calls.minimize")

            if showsPartnerVideo {
                VStack(alignment: .leading, spacing: PaeoniaSpacing.space2) {
                    Text(verbatim: participants.partnerName)
                        .font(PaeoniaTypography.sectionTitle)
                        .foregroundStyle(.paeoniaTextPrimary)
                    CallStatusLine(phase: session.phase, direction: session.direction, font: PaeoniaTypography.caption)
                }
                .accessibilityElement(children: .combine)
                .transition(.opacity)
            }
            Spacer(minLength: 0)
        }
        .padding(.top, PaeoniaSpacing.space8)
    }

    /// The partner's face, their name, what the call is doing and their time.
    private var identity: some View {
        VStack(spacing: PaeoniaSpacing.space16) {
            avatar
            VStack(spacing: PaeoniaSpacing.space4) {
                Text(verbatim: participants.partnerName)
                    .font(PaeoniaTypography.collectionHeroTitle)
                    .foregroundStyle(.paeoniaTextPrimary)
                    .multilineTextAlignment(.center)
                    .callMorph(.name)
                CallStatusLine(phase: session.phase, direction: session.direction)
                partnerTime
            }
            .accessibilityElement(children: .combine)
            // On the combined element, because the children it merges are not exposed.
            .accessibilityIdentifier("calls.status")
        }
    }

    private var avatar: some View {
        PaeoniaCoupleAvatar(
            mediaAssetID: participants.partnerProfilePhotoAssetID,
            name: participants.partnerName,
            tint: .paeoniaPartnerTwo,
            size: Self.avatarSize,
            isCurrentUser: false
        )
        // The photo's own frame, which the pill's and the partner's avatar's photos match. A
        // decoration reaches past it.
        .frame(width: Self.avatarSize, height: Self.avatarSize)
        // The glow grows and moves with the photo.
        .background { ringingGlow.frame(width: Self.glowSize, height: Self.glowSize) }
        .callMorph(.photo, size: Self.avatarSize)
        // The frame holds the glow at its largest in every phase, so it never reaches the name
        // and the name stays put when the call connects.
        .frame(width: Self.glowSize, height: Self.glowSize)
        .accessibilityHidden(true)
    }

    /// A soft glow that breathes while the call rings or connects.
    @ViewBuilder
    private var ringingGlow: some View {
        let glow = Circle().fill(Color.paeoniaPartnerTwo.opacity(0.22))
        switch session.phase {
        case .ringing, .connecting, .reconnecting:
            if reduceMotion {
                glow
            } else {
                glow.phaseAnimator(Self.glowScales) { view, scale in
                    view.scaleEffect(scale)
                } animation: { _ in
                    .easeInOut(duration: 1.1)
                }
            }
        case .active, .ended:
            EmptyView()
        }
    }

    /// Hidden once the call ends, but it keeps its line, so the face above stays put.
    @ViewBuilder
    private var partnerTime: some View {
        if let partnerTimeZone {
            TimelineView(.everyMinute) { context in
                Text(.callsPartnerTime(
                    CallNightCheck.localTime(at: context.date, in: partnerTimeZone), participants.partnerName))
                    .font(PaeoniaTypography.caption)
                    .foregroundStyle(.paeoniaTextTertiary)
            }
            .opacity(isEnded ? 0 : 1)
            .accessibilityHidden(isEnded)
        }
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
                controls
            }
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { bottomHeight = $0 }
        }
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

    /// Your own camera in the top corner, under the chevron's row.
    @ViewBuilder
    private var localTile: some View {
        if session.isCameraOn, !isEnded {
            CallVideoView(engine: center.engine, source: .local)
                .frame(width: Self.localTileSize.width, height: Self.localTileSize.height)
                .clipShape(.rect(cornerRadius: PaeoniaRadius.radius20))
                .overlay {
                    RoundedRectangle(cornerRadius: PaeoniaRadius.radius20).strokeBorder(.white.opacity(0.25))
                }
                .shadow(color: .black.opacity(0.35), radius: 12, y: 4)
                .padding(.top, PaeoniaSpacing.compactButtonHeight + PaeoniaSpacing.space16)
                .padding(.trailing, PaeoniaSpacing.screenHorizontalPadding)
                .accessibilityElement()
                .accessibilityLabel(Text(.callsYourCamera))
                .transition(.scale(scale: 0.8, anchor: .topTrailing).combined(with: .opacity))
        }
    }

    // MARK: - Minimizing

    private var swipeDown: some Gesture {
        DragGesture(minimumDistance: 20)
            .onChanged { value in
                dragOffset = max(0, value.translation.height)
            }
            .onEnded { value in
                if value.translation.height > Self.minimizeDistance
                    || value.predictedEndTranslation.height > Self.minimizeDistance * 2 {
                    minimize()
                } else {
                    withAnimation(reduceMotion ? nil : .spring(duration: 0.3, bounce: 0.2)) { dragOffset = 0 }
                }
            }
    }

    private func minimize() {
        withAnimation(reduceMotion ? nil : PaeoniaMotion.stateChange) {
            center.presentation = .bubble
        }
    }
}
