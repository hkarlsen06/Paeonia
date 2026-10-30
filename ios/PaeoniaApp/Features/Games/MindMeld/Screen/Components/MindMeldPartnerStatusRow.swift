import SwiftUI

/// Presence and locked-word progress remain independent.
struct MindMeldPartnerStatusRow: View {
    let partner: MindMeldPlayer
    let status: MindMeldPartnerStatus
    let isPresent: Bool

    private static let avatarSize: CGFloat = 24

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: PaeoniaSpacing.space8) {
            PaeoniaProfilePhotoAvatar(
                mediaAssetID: partner.photoAssetID,
                name: partner.name,
                tint: .paeoniaPartnerTwo,
                size: Self.avatarSize
            )
            .gamePresenceRing(isPresent)
            .accessibilityHidden(true)
            line
                .id(String(describing: status))
                .transition(reduceMotion ? .opacity : .opacity.combined(with: .offset(y: 6)))
        }
        .frame(minHeight: Self.avatarSize)
        .animation(reduceMotion ? PaeoniaMotion.buttonPress : PaeoniaMotion.cardReveal, value: status)
        .accessibilityElement(children: .combine)
        .accessibilityValue(Text(isPresent ? .gamesPresenceHere : .gamesPresenceAway))
        .accessibilityIdentifier("mindMeld.partnerStatus")
        .onChange(of: isPresent) { old, new in
            guard new, !old else { return }
            PaeoniaHaptics.partnerDrawingReceived()
            GameSound.nudge.play(volume: 0.7)
        }
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
                GameTypingDots()
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
        if locked {
            AccessibilityNotification.Announcement(String(localized: .mindMeldPartnerLocked(partner.name))).post()
        }
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
