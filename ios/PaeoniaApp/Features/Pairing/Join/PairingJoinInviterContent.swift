import SwiftUI

/// The top of the join screen: the two photos, who invited the person, what the
/// inviter made for them, and a warning when there was an earlier safety concern.
/// It is laid out before the preview arrives and drops in once it does, so nothing
/// jumps when the name loads. A former partner sees `PairingJoinRestoreContent`
/// instead.
struct PairingJoinInviterContent: View {
    let preview: PairingInvitePreview?
    /// This person, whose photo leans in next to the inviter's.
    let session: AuthSession?

    private var isReady: Bool {
        preview != nil
    }

    private var inviterName: String? {
        preview?.inviterDisplayName?.trimmedNonEmpty
    }

    var body: some View {
        VStack(spacing: PaeoniaSpacing.space24) {
            PairingCouplePhotos(
                ownName: session?.displayName ?? "",
                ownPhotoAssetID: session?.profilePhotoAssetID,
                partnerName: inviterName ?? "",
                partnerPhotoAssetID: nil,
                partnerPhotoProvider: InviterPhotoProvider(url: preview?.inviterPhotoURL)
            )
            // The inviter's photo loads once per invite, so a new code starts a new load.
            .id(preview?.inviteID)
            // No crossfade from the placeholder. The entrance brings the new one in.
            .transition(.identity)
            .screenEntrance(order: 1, isReady: isReady)

            header
                .screenEntrance(order: 2, isReady: isReady)

            if let gifts = preview?.firstDayGifts, !gifts.isEmpty {
                PairingJoinGifts(gifts: gifts)
                    .screenEntrance(order: 3, isReady: isReady)
            }

            if preview?.hasSafetyWarning == true {
                PairingJoinSafetyNote(hasWarning: true)
                    .screenEntrance(order: 3, isReady: isReady)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var header: some View {
        VStack(spacing: PaeoniaSpacing.space8) {
            // The name arrives in the same update that starts the entrance, so the
            // text swaps at once instead of blending with the placeholder copy.
            Text(inviterName.map { .pairingJoinInvitedTitle($0) } ?? .pairingJoinInvitedTitleFallback)
                .font(PaeoniaTypography.heroTitle)
                .foregroundStyle(.paeoniaTextPrimary)
                .contentTransition(.identity)
                .accessibilityAddTraits(.isHeader)

            Text(inviterName.map { .pairingJoinMessage($0) } ?? .pairingJoinMessageFallback)
                .font(PaeoniaTypography.body)
                .foregroundStyle(.paeoniaTextSecondary)
                .contentTransition(.identity)
        }
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
    }
}

/// What the inviter made before this person joined. It names the things without
/// showing them, because the person unwraps them after joining.
private struct PairingJoinGifts: View {
    let gifts: [PairingInviteGift]

    var body: some View {
        VStack(alignment: .leading, spacing: PaeoniaSpacing.space12) {
            Text(.pairingJoinGiftsTitle)
                .font(PaeoniaTypography.bodyEmphasis)
                .foregroundStyle(.paeoniaTextPrimary)
                .accessibilityAddTraits(.isHeader)

            ForEach(gifts, id: \.self) { gift in
                Label {
                    Text(gift.title)
                        .font(PaeoniaTypography.body)
                        .foregroundStyle(.paeoniaTextPrimary)
                } icon: {
                    SettingsMenuIcon(systemName: gift.symbol)
                }
            }
        }
        .multilineTextAlignment(.leading)
        .fixedSize(horizontal: false, vertical: true)
        .padding(PaeoniaSpacing.cardContentPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .paeoniaCardSurface(
            in: RoundedRectangle(cornerRadius: PaeoniaRadius.standard, style: .continuous),
            fill: .paeoniaSurfacePrimary
        )
        .accessibilityElement(children: .combine)
    }
}

private extension PairingInviteGift {
    var title: LocalizedStringResource {
        switch self {
        case .drawing: .pairingJoinGiftsDrawing
        case .answer: .pairingJoinGiftsAnswer
        }
    }

    var symbol: String {
        switch self {
        case .drawing: "scribble.variable"
        case .answer: "text.bubble.fill"
        }
    }
}

/// Asks the person to join only their real partner. A stronger warning shows when
/// there was an earlier safety concern about the person who made the code.
struct PairingJoinSafetyNote: View {
    let hasWarning: Bool

    var body: some View {
        if hasWarning {
            Label {
                Text(.pairingJoinSafetyWarning)
            } icon: {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.paeoniaWarning)
                    .accessibilityHidden(true)
            }
            .font(PaeoniaTypography.body)
            .foregroundStyle(.paeoniaTextPrimary)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            .padding(PaeoniaSpacing.space16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.paeoniaSurfaceSecondary, in: RoundedRectangle(cornerRadius: PaeoniaRadius.radius16))
        } else {
            Text(.pairingJoinSafety)
                .font(PaeoniaTypography.caption)
                .foregroundStyle(.paeoniaTextSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
