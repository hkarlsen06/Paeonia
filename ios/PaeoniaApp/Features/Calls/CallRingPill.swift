import SwiftUI

/// Places the ring pill at the top of the screen, under the status bar and the Dynamic Island.
struct CallRingLayer: View {
    let model: CallOverlayModel
    let session: CallSession

    var body: some View {
        VStack(spacing: 0) {
            CallRingPill(center: model.center, session: session, participants: model.participants)
                .frame(maxWidth: PaeoniaSpacing.focusedContentWidth)
                // The window passes every touch outside this frame to the app underneath.
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { model.ringFrame = $0 }
            Spacer(minLength: 0)
        }
        .padding(.top, PaeoniaSpacing.space8)
        .padding(.horizontal, PaeoniaSpacing.screenHorizontalPadding)
    }
}

/// The partner's call ringing inside the app: their face and name, "Calling you", and Decline and
/// Answer. A tap anywhere else on it opens the full call screen. A ring that ends unanswered says
/// why until the call clears.
struct CallRingPill: View {
    let center: CallCenter
    let session: CallSession
    let participants: DailyChallengeParticipants

    private static let avatarSize: CGFloat = 48
    private static let buttonSize: CGFloat = 52
    private static let symbolSize: CGFloat = 20

    private var isRinging: Bool { session.phase == .ringing }

    var body: some View {
        HStack(spacing: PaeoniaSpacing.space12) {
            caller
            if isRinging {
                CallRoundButton(
                    systemImage: "phone.down.fill", label: .callsControlDecline, size: Self.buttonSize,
                    symbolSize: Self.symbolSize, fill: .paeoniaError, identifier: "calls.ring.decline"
                ) { center.engine.decline() }
                CallRoundButton(
                    systemImage: "phone.fill", label: .callsControlAnswer, size: Self.buttonSize,
                    symbolSize: Self.symbolSize, fill: .paeoniaSuccess, identifier: "calls.ring.answer"
                ) { center.engine.answer() }
            }
        }
        .padding(PaeoniaSpacing.space8)
        .glassEffect(.regular.interactive(), in: Capsule())
        .shadow(color: .black.opacity(0.3), radius: 16, y: 6)
    }

    private var caller: some View {
        HStack(spacing: PaeoniaSpacing.space12) {
            PaeoniaProfilePhotoAvatar(
                mediaAssetID: participants.partnerProfilePhotoAssetID,
                name: participants.partnerName,
                tint: .paeoniaPartnerTwo,
                size: Self.avatarSize
            )
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: PaeoniaSpacing.space2) {
                Text(verbatim: participants.partnerName)
                    .font(PaeoniaTypography.bodyEmphasis)
                    .foregroundStyle(.paeoniaTextPrimary)
                    .lineLimit(1)
                CallStatusLine(phase: session.phase, direction: session.direction, font: PaeoniaTypography.caption)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .contentShape(.rect)
        .onTapGesture(perform: open)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(.callsRingAccessibilityLabel(participants.partnerName)), isEnabled: isRinging)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(named: Text(.callsOpenCall), open)
        .accessibilityIdentifier("calls.ring")
    }

    private func open() {
        center.presentation = .full
    }
}
