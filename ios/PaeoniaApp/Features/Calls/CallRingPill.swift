import SwiftUI

/// Places the ring pill where `CallOverlayModel.ringAnchor` says: grown out of the partner's avatar,
/// with the photo where the avatar's was, or at the top of the screen under the status bar and the
/// Dynamic Island. Either way it keeps the screen's side padding, as wide as the tab bar. At the
/// avatar its end lines up with the avatar's far edge, so it keeps the avatar's gap to the tab bar.
struct CallRingLayer: View {
    let model: CallOverlayModel
    let session: CallSession

    var body: some View {
        switch model.ringAnchor {
        case .top:
            VStack(spacing: 0) {
                pill(photoEdge: .leading, opensDownward: true)
                Spacer(minLength: 0)
            }
            .padding(.top, PaeoniaSpacing.space8)
            .padding(.horizontal, PaeoniaSpacing.screenHorizontalPadding)
        case let .avatar(spot):
            GeometryReader { proxy in
                let placement = model.placement(in: proxy)
                let rowY = placement.center(of: spot, bubble: PresenceAvatar.outerSize).y
                let opensDownward = placement.growsDownward(fromY: rowY, rowHeight: CallRingPill.height)
                pill(photoEdge: spot.edge, opensDownward: opensDownward)
                    .padding(.horizontal, PaeoniaSpacing.screenHorizontalPadding - CallBubblePlacement.margin)
                    .placed(on: spot.edge, rowY: rowY, rowHeight: PresenceAvatar.outerSize.height, in: placement)
            }
        }
    }

    private func pill(photoEdge: HorizontalEdge, opensDownward: Bool) -> some View {
        CallRingPill(
            center: model.center, session: session, participants: model.participants, photoEdge: photoEdge,
            opensDownward: opensDownward, open: model.showFull
        )
        .frame(maxWidth: PaeoniaSpacing.focusedContentWidth)
        // The window passes every touch outside this frame to the app underneath.
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { model.ringFrame = $0 }
    }
}

/// The partner's call ringing inside the app: their face and name, "Calling you", and Decline and
/// Answer. A tap anywhere else on it opens the full call screen. A ring that ends unanswered says
/// why until the call clears. The photo sits at `photoEdge`, the side of the partner's avatar it
/// grew out of.
struct CallRingPill: View {
    let center: CallCenter
    let session: CallSession
    let participants: DailyChallengeParticipants
    var photoEdge = HorizontalEdge.leading
    /// A pull down opens the full call screen when the pill is at the top, and a pull up when it is
    /// at the bottom.
    var opensDownward = true
    /// Opens the full call screen.
    let open: () -> Void

    private static let avatarSize: CGFloat = 48
    private static let buttonSize: CGFloat = 52
    private static let symbolSize: CGFloat = 20
    /// The pill's height, with its padding around the buttons.
    static let height = buttonSize + 2 * PaeoniaSpacing.space8

    /// How far a pull goes before letting go opens the full call screen.
    private static let openDistance: CGFloat = 32

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pull: CGFloat = 0

    private var isRinging: Bool { session.phase == .ringing }

    var body: some View {
        HStack(spacing: PaeoniaSpacing.space12) {
            if photoEdge == .leading { caller }
            if isRinging {
                CallRoundButton(
                    systemImage: "phone.down.fill", label: .callsControlDecline, size: Self.buttonSize,
                    symbolSize: Self.symbolSize, fill: .paeoniaError, identifier: "calls.ring.decline",
                    morphPart: .decline
                ) { center.engine.decline() }
                CallRoundButton(
                    systemImage: "phone.fill", label: .callsControlAnswer, size: Self.buttonSize,
                    symbolSize: Self.symbolSize, fill: .paeoniaSuccess, identifier: "calls.ring.answer",
                    morphPart: .answer
                ) {
                    open()
                    center.engine.answer()
                }
            }
            if photoEdge == .trailing { caller }
        }
        .padding(PaeoniaSpacing.space8)
        .background {
            Color.clear
                .glassEffect(.regular.interactive(), in: Capsule())
                .shadow(color: .black.opacity(0.3), radius: 16, y: 6)
                .callMorph(.background)
        }
        .offset(y: pull)
        .gesture(pullToOpen)
    }

    /// A pull toward the middle of the screen opens the full call screen, as a pull on a notification
    /// expands it.
    private var pullToOpen: some Gesture {
        let direction: CGFloat = opensDownward ? 1 : -1
        return DragGesture(minimumDistance: 10)
            .onChanged { value in
                // Follows the finger less and less, so the pill stays near its edge.
                pull = max(0, value.translation.height * direction) * 0.35 * direction
            }
            .onEnded { value in
                if value.translation.height * direction > Self.openDistance
                    || value.predictedEndTranslation.height * direction > Self.openDistance * 3 {
                    open()
                }
                withAnimation(reduceMotion ? nil : .spring(duration: 0.3, bounce: 0.2)) { pull = 0 }
            }
    }

    private var caller: some View {
        HStack(spacing: PaeoniaSpacing.space12) {
            if photoEdge == .leading {
                photo
            } else {
                Spacer(minLength: 0)
            }
            VStack(alignment: photoEdge == .leading ? .leading : .trailing, spacing: PaeoniaSpacing.space2) {
                Text(verbatim: participants.partnerName)
                    .font(PaeoniaTypography.bodyEmphasis)
                    .foregroundStyle(.paeoniaTextPrimary)
                    .lineLimit(1)
                    .callMorph(.name)
                CallStatusLine(phase: session.phase, direction: session.direction, font: PaeoniaTypography.caption)
                    .lineLimit(1)
            }
            if photoEdge == .trailing {
                photo
            } else {
                Spacer(minLength: 0)
            }
        }
        .contentShape(.rect)
        .onTapGesture(perform: open)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(.callsRingAccessibilityLabel(participants.partnerName)), isEnabled: isRinging)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(named: Text(.callsOpenCall), open)
        .accessibilityIdentifier("calls.ring")
    }

    private var photo: some View {
        PaeoniaProfilePhotoAvatar(
            mediaAssetID: participants.partnerProfilePhotoAssetID,
            name: participants.partnerName,
            tint: .paeoniaPartnerTwo,
            size: Self.avatarSize
        )
        .callMorph(.photo, size: Self.avatarSize)
        .accessibilityHidden(true)
    }
}
