import SwiftUI

/// The call, shrunk to a bubble that floats over every screen. A voice call shows the partner's
/// face, the call time, mute and end. A video call shows the partner's video. A tap opens the
/// call screen again.
struct CallBubble: View {
    let center: CallCenter
    let session: CallSession
    let participants: DailyChallengeParticipants

    static let videoSize = CGSize(width: 104, height: 148)
    private static let avatarSize: CGFloat = 44

    private var isEnded: Bool {
        if case .ended = session.phase { return true }
        return false
    }

    var body: some View {
        Group {
            if session.isPartnerCameraOn, !isEnded {
                video
            } else {
                voice
            }
        }
        .contentShape(.rect)
        .onTapGesture(perform: open)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(named: Text(.callsOpenCall), open)
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
                CallStatusLine(phase: session.phase, font: PaeoniaTypography.bodyEmphasis)
                    .lineLimit(2)
                    .frame(maxWidth: 132, alignment: .leading)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(Text(.callsBubbleAccessibilityLabel(participants.partnerName)))
            .accessibilityAddTraits(.isButton)
            // Here and not on the whole bubble, where it would replace the mute and end buttons' own.
            .accessibilityIdentifier("calls.bubble")

            if !isEnded {
                bubbleButton(
                    systemImage: session.isMuted ? "mic.slash.fill" : "mic.fill",
                    label: session.isMuted ? .callsUnmute : .callsControlMute,
                    isOn: session.isMuted, identifier: "calls.bubble.mute"
                ) { center.engine.setMuted(!session.isMuted) }
                bubbleButton(
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
        CallVideoView(engine: center.engine, source: .partner)
            .frame(width: Self.videoSize.width, height: Self.videoSize.height)
            .clipShape(.rect(cornerRadius: PaeoniaRadius.radius20))
            .overlay {
                RoundedRectangle(cornerRadius: PaeoniaRadius.radius20).strokeBorder(.white.opacity(0.25))
            }
            .shadow(color: .black.opacity(0.35), radius: 16, y: 6)
            .accessibilityElement()
            .accessibilityLabel(Text(.callsBubbleAccessibilityLabel(participants.partnerName)))
            .accessibilityAddTraits(.isButton)
            .accessibilityIdentifier("calls.bubble")
    }

    private func bubbleButton(
        systemImage: String, label: LocalizedStringResource, isOn: Bool = false, fill: Color? = nil,
        identifier: String, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(isOn ? Color.paeoniaTextInverse : Color.paeoniaTextPrimary)
                .contentTransition(.symbolEffect(.replace))
                .frame(width: PaeoniaSpacing.compactButtonHeight, height: PaeoniaSpacing.compactButtonHeight)
                .background(fill ?? (isOn ? Color.paeoniaTextPrimary : Color.white.opacity(0.12)), in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(label))
        .accessibilityIdentifier(identifier)
    }

    private func open() {
        center.presentation = .full
    }
}
