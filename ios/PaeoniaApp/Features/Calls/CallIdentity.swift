import SwiftUI

/// The partner's face, their name, what the call is doing and their time, in the middle of the call
/// screen while no video fills it. The photo and the name grow out of the ring pill (`callMorph`).
struct CallIdentity: View {
    let engine: any CallEngineActions
    let session: CallSession
    let participants: DailyChallengeParticipants
    let partnerTimeZone: TimeZone?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let avatarSize: CGFloat = 132
    /// The glow at its largest. It breathes between `glowScales`, which never go past 1.
    private static let glowSize = avatarSize * 1.45
    private static let glowScales: [CGFloat] = [0.86, 1]

    private var isEnded: Bool {
        if case .ended = session.phase { return true }
        return false
    }

    var body: some View {
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
        .background {
            CallPictureInPictureAnchorView(
                engine: engine,
                partnerPhoto: participants.partnerProfilePhotoAssetID,
                partnerName: participants.partnerName
            )
        }
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
                    PaeoniaMotion.standardCurve(duration: 1.1)
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
}
