import SwiftUI

/// The full call screen. The partner's face and name on both partners' petal colors, what the
/// call is doing, their local time, and the controls. During video the partner's video fills the
/// screen and your own sits in a corner. A swipe down, or the chevron, shrinks it to the bubble.
struct CallScreen: View {
    let center: CallCenter
    let session: CallSession
    let participants: DailyChallengeParticipants

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.openURL) private var openURL
    @State private var partnerTimeZone: TimeZone?
    @State private var dragOffset: CGFloat = 0

    private static let avatarSize: CGFloat = 132
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

    private var background: some View {
        LinearGradient(
            colors: [
                Color.paeoniaBackgroundPrimary.mix(with: .paeoniaPartnerTwo, by: 0.34),
                Color.paeoniaBackgroundPrimary,
                Color.paeoniaBackgroundPrimary.mix(with: .paeoniaPartnerOne, by: 0.26),
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
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
                    CallStatusLine(phase: session.phase, font: PaeoniaTypography.caption)
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
                CallStatusLine(phase: session.phase)
                    .accessibilityIdentifier("calls.status")
                partnerTime
            }
            .accessibilityElement(children: .combine)
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
        .background { ringingGlow }
        .accessibilityHidden(true)
    }

    /// A soft glow that breathes while the call rings or connects.
    @ViewBuilder
    private var ringingGlow: some View {
        let glow = Circle().fill(Color.paeoniaPartnerTwo.opacity(0.22)).frame(
            width: Self.avatarSize * 1.45, height: Self.avatarSize * 1.45)
        switch session.phase {
        case .ringing, .connecting, .reconnecting:
            if reduceMotion {
                glow
            } else {
                glow.phaseAnimator([0.9, 1.08]) { view, scale in
                    view.scaleEffect(scale)
                } animation: { _ in
                    .easeInOut(duration: 1.1)
                }
            }
        case .active, .ended:
            EmptyView()
        }
    }

    @ViewBuilder
    private var partnerTime: some View {
        if let partnerTimeZone, !isEnded {
            TimelineView(.everyMinute) { context in
                Text(.callsPartnerTime(
                    CallNightCheck.localTime(at: context.date, in: partnerTimeZone), participants.partnerName))
                    .font(PaeoniaTypography.caption)
                    .foregroundStyle(.paeoniaTextTertiary)
            }
        }
    }

    @ViewBuilder
    private var bottom: some View {
        if isEnded {
            endedActions
                .frame(minHeight: CallControlButton.size + PaeoniaSpacing.space32)
        } else {
            controls
        }
    }

    @ViewBuilder
    private var controls: some View {
        #if targetEnvironment(simulator)
        if session.direction == .incoming, session.phase == .ringing {
            CallAnswerControls(engine: center.engine)
        } else {
            CallControls(session: session, engine: center.engine)
        }
        #else
        CallControls(session: session, engine: center.engine)
        #endif
    }

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
