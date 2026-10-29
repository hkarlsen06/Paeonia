import SwiftUI

/// The partner's avatar and one line about what they are doing, on the leading
/// side of the write phase's top line. It keeps one height, so the content under
/// it never moves when the line changes.
///
/// - Locked in: the line arrives with a spring, the avatar pulses once and
///   VoiceOver says it. The view model's attention cue taps the phone.
/// - Joins: the same pulse and a tap, without the announcement.
struct MindMeldPartnerStatusRow: View {
    let partner: MindMeldPlayer
    let status: MindMeldPartnerStatus
    let isPresent: Bool

    private static let avatarSize: CGFloat = 24

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulse: CGFloat = 1

    var body: some View {
        HStack(spacing: PaeoniaSpacing.space8) {
            PaeoniaProfilePhotoAvatar(
                mediaAssetID: partner.photoAssetID,
                name: partner.name,
                tint: .paeoniaPartnerTwo,
                size: Self.avatarSize
            )
            .overlay {
                if isPresent {
                    Circle().strokeBorder(.paeoniaAccentPrimary, lineWidth: 2).padding(-2)
                }
            }
            .gamePresenceDot(isPresent, size: 10)
            .scaleEffect(pulse)
            .accessibilityHidden(true)
            line
                .id(String(describing: status))
                .transition(reduceMotion ? .opacity : .opacity.combined(with: .offset(y: 6)))
        }
        .frame(minHeight: Self.avatarSize)
        .animation(reduceMotion ? PaeoniaMotion.buttonPress : PaeoniaMotion.cardReveal, value: status)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("mindMeld.partnerStatus")
        .onChange(of: status) { old, new in
            statusChanged(from: old, to: new)
        }
    }

    @ViewBuilder
    private var line: some View {
        switch status {
        case .locked:
            Label {
                Text(.mindMeldPartnerLocked(partner.name))
            } icon: {
                Image(systemName: "lock.fill").accessibilityHidden(true)
            }
            .font(PaeoniaTypography.caption.weight(.semibold))
            .foregroundStyle(.paeoniaAccentPrimary)
        case .typing:
            HStack(spacing: PaeoniaSpacing.space8) {
                Text(.mindMeldPartnerTyping(partner.name))
                MindMeldTypingDots()
            }
            .font(PaeoniaTypography.caption.weight(.semibold))
            .foregroundStyle(.paeoniaTextPrimary)
        case .here:
            Text(.mindMeldPartnerHere(partner.name))
                .font(PaeoniaTypography.caption.weight(.semibold))
                .foregroundStyle(.paeoniaTextPrimary)
        case .away:
            Text(.mindMeldPartnerLater(partner.name))
                .font(PaeoniaTypography.caption.weight(.semibold))
                .foregroundStyle(.paeoniaTextTertiary)
        }
    }

    private func statusChanged(from old: MindMeldPartnerStatus, to new: MindMeldPartnerStatus) {
        let locked = new == .locked && old != .locked
        let joined = old == .away && (new == .here || new == .typing)
        guard locked || joined else { return }
        if joined {
            PaeoniaHaptics.partnerDrawingReceived()
            GameSound.nudge.play(volume: 0.7)
        }
        if locked {
            AccessibilityNotification.Announcement(String(localized: .mindMeldPartnerLocked(partner.name))).post()
        }
        guard !reduceMotion else { return }
        withAnimation(PaeoniaMotion.stateChange) { pulse = 1.12 }
        withAnimation(PaeoniaMotion.stateChange.delay(PaeoniaMotion.motionDefault)) { pulse = 1 }
    }
}

#if DEBUG
#Preview {
    VStack(alignment: .leading, spacing: PaeoniaSpacing.space16) {
        let robin = MindMeldPlayer(name: "Robin", photoAssetID: nil)
        MindMeldPartnerStatusRow(partner: robin, status: .locked, isPresent: false)
        MindMeldPartnerStatusRow(partner: robin, status: .typing, isPresent: true)
        MindMeldPartnerStatusRow(partner: robin, status: .here, isPresent: true)
        MindMeldPartnerStatusRow(partner: robin, status: .away, isPresent: false)
    }
    .padding()
    .background(.paeoniaBackgroundSecondary)
    .preferredColorScheme(.dark)
}
#endif
