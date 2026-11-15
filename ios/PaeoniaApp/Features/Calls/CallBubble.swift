import SwiftUI

/// The call, shrunk to a bubble that floats over every screen. A voice call shows the partner's
/// face, the call time, mute and end. A video call shows the partner's video, at the size the
/// person pinched it to. A tap opens the call screen again.
struct CallBubble: View {
    let center: CallCenter
    let session: CallSession
    let participants: DailyChallengeParticipants
    /// How much bigger or smaller than `videoSize(for:)` the video shows.
    var videoScale: CGFloat = 1
    /// VoiceOver's swipe up or down makes the video bigger or smaller.
    var resizeVideo: (AccessibilityAdjustmentDirection) -> Void = { _ in }
    /// Pushes the bubble into the side of the screen.
    var tuck: () -> Void = {}

    /// The video before a pinch, in the shape of the partner's picture so none of it is cut off.
    /// Every shape covers the same area as a 104 by 148 point bubble.
    static func videoSize(for session: CallSession) -> CGSize {
        let area: CGFloat = 104 * 148
        let ratio = session.partnerVideoAspectRatio ?? 104 / 148
        return CGSize(width: (area * ratio).squareRoot(), height: (area / ratio).squareRoot())
    }

    /// How far a pinch may shrink or grow the video.
    static let videoScales: ClosedRange<CGFloat> = 0.75...2.5
    private static let avatarSize: CGFloat = 44

    /// The bubble shows `session`'s video, which a pinch resizes, and not its voice controls.
    static func showsVideo(_ session: CallSession) -> Bool {
        if case .ended = session.phase { return false }
        return session.isPartnerCameraOn
    }

    private var isEnded: Bool {
        if case .ended = session.phase { return true }
        return false
    }

    var body: some View {
        Group {
            if Self.showsVideo(session) {
                video
            } else {
                voice
            }
        }
        .contentShape(.rect)
        .onTapGesture(perform: open)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(named: Text(.callsOpenCall), open)
        .accessibilityAction(named: Text(.presenceActionTuck), tuck)
    }

    private var voice: some View {
        HStack(spacing: PaeoniaSpacing.space8) {
            HStack(spacing: PaeoniaSpacing.space8) {
                PaeoniaProfilePhotoAvatar(
                    mediaAssetID: participants.partnerProfilePhotoAssetID,
                    name: participants.partnerName,
                    tint: .paeoniaPartnerTwo,
                    size: Self.avatarSize
                )
                .accessibilityHidden(true)
                CallStatusLine(phase: session.phase, direction: session.direction, font: PaeoniaTypography.bodyEmphasis)
                    .lineLimit(2)
                    .frame(maxWidth: 132, alignment: .leading)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(Text(.callsBubbleAccessibilityLabel(participants.partnerName)))
            .accessibilityAddTraits(.isButton)
            // Here and not on the whole bubble, where it would replace the mute and end buttons' own.
            .accessibilityIdentifier("calls.bubble")

            if !isEnded {
                CallRoundButton(
                    systemImage: session.isMuted ? "mic.slash.fill" : "mic.fill",
                    label: session.isMuted ? .callsUnmute : .callsControlMute,
                    isOn: session.isMuted, identifier: "calls.bubble.mute"
                ) { center.engine.setMuted(!session.isMuted) }
                CallRoundButton(
                    systemImage: "phone.down.fill", label: .callsControlEnd, fill: .paeoniaError,
                    identifier: "calls.bubble.end"
                ) { center.engine.end() }
            }
        }
        .padding(PaeoniaSpacing.space8)
        .glassEffect(.regular.interactive(), in: Capsule())
        .shadow(color: .black.opacity(0.3), radius: 16, y: 6)
    }

    private var video: some View {
        let size = Self.videoSize(for: session)
        return CallVideoView(engine: center.engine, source: .partner)
            .frame(width: size.width * videoScale, height: size.height * videoScale)
            .clipShape(.rect(cornerRadius: PaeoniaRadius.radius20))
            .overlay {
                RoundedRectangle(cornerRadius: PaeoniaRadius.radius20).strokeBorder(.white.opacity(0.25))
            }
            .shadow(color: .black.opacity(0.35), radius: 16, y: 6)
            .accessibilityElement()
            .accessibilityLabel(Text(.callsBubbleAccessibilityLabel(participants.partnerName)))
            .accessibilityAddTraits(.isButton)
            .accessibilityAdjustableAction(resizeVideo)
            .accessibilityIdentifier("calls.bubble")
    }

    private func open() {
        center.presentation = .full
    }
}
