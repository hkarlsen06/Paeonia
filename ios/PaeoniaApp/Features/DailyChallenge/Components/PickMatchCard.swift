import SwiftUI

/// How the two picks lined up, as a raised card: the option of a pick-one-of-two
/// question, or the person picked on a partner-choice question. The same pick puts both
/// avatars over it in large type. Different picks split the card, each avatar over its
/// own pick. `PartnerChoiceMatchBanner` adds the bloom and reads the card to VoiceOver
/// as one sentence.
struct PickMatchCard: View {
    let yours: String
    let theirs: String
    /// From the match, not the labels, so two people with the same name still split.
    let isSamePick: Bool
    let participants: DailyChallengeParticipants

    private let avatarSize: CGFloat = 44

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: PaeoniaRadius.radius20, style: .continuous)
        Group {
            if isSamePick {
                samePick
            } else {
                differentPicks
            }
        }
        .padding(PaeoniaSpacing.cardContentPadding)
        .frame(maxWidth: .infinity)
        .background {
            shape
                .fill(
                    LinearGradient(
                        stops: [
                            .init(color: .paeoniaAccentPrimary.opacity(isSamePick ? 0.34 : 0.14), location: 0),
                            .init(color: .paeoniaSurfacePrimary, location: 0.7),
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .shadow(color: isSamePick ? .paeoniaAccentPrimary.opacity(0.3) : .black.opacity(0.22), radius: 14, y: 6)
        }
        .overlay {
            shape.strokeBorder(
                isSamePick ? Color.paeoniaAccentPrimary.opacity(0.6) : Color.paeoniaTextPrimary.opacity(0.1),
                lineWidth: isSamePick ? PaeoniaRadius.strokeEmphasis : PaeoniaRadius.strokeHairline
            )
        }
    }

    private var samePick: some View {
        VStack(spacing: PaeoniaSpacing.space12) {
            HStack(spacing: PaeoniaSpacing.space8) {
                yourAvatar
                partnerAvatar
            }
            VStack(spacing: PaeoniaSpacing.space4) {
                Text(.dailyChallengeMatchBothPickedHeading)
                    .font(PaeoniaTypography.caption.weight(.semibold))
                    .foregroundStyle(.paeoniaAccentPrimary)
                Text(verbatim: yours)
                    .font(PaeoniaTypography.collectionHeroTitle)
                    .foregroundStyle(.paeoniaTextPrimary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var differentPicks: some View {
        HStack(alignment: .top, spacing: PaeoniaSpacing.space12) {
            side(yourAvatar, name: Text(.dailyChallengeMatchYouLabel), option: yours)
            Rectangle()
                .fill(Color.paeoniaTextPrimary.opacity(0.12))
                .frame(width: PaeoniaRadius.strokeHairline)
            side(partnerAvatar, name: Text(verbatim: participants.partnerName), option: theirs)
        }
        // So the divider stretches to the taller side and no further.
        .fixedSize(horizontal: false, vertical: true)
    }

    private func side(_ avatar: some View, name: Text, option: String) -> some View {
        VStack(spacing: PaeoniaSpacing.space8) {
            avatar
            name
                .font(PaeoniaTypography.caption.weight(.semibold))
                .foregroundStyle(.paeoniaTextSecondary)
                .lineLimit(1)
            Text(verbatim: option)
                .font(PaeoniaTypography.collectionTitle)
                .foregroundStyle(.paeoniaTextPrimary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
    }

    private var yourAvatar: some View {
        PaeoniaProfilePhotoAvatar(
            mediaAssetID: participants.currentProfilePhotoAssetID,
            name: participants.currentDisplayName ?? String(localized: .dailyChallengeMatchYouLabel),
            tint: .paeoniaPartnerOne,
            size: avatarSize
        )
    }

    private var partnerAvatar: some View {
        PaeoniaProfilePhotoAvatar(
            mediaAssetID: participants.partnerProfilePhotoAssetID,
            name: participants.partnerName,
            tint: .paeoniaPartnerTwo,
            size: avatarSize
        )
    }
}
