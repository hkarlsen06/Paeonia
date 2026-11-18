import SwiftUI

/// The join screen when the code belongs to a former partner and what the two had
/// can still come back: both photos, the offer, and what comes back. While the
/// person waits for the partner's answer, only the photos and a short note.
struct PairingJoinRestoreContent: View {
    let preview: PairingInvitePreview
    let session: AuthSession?
    /// The joiner has no subscription of their own, so the screen says the
    /// partner's covers them.
    let showsCoverage: Bool
    let isWaitingForPartner: Bool

    private var partnerName: String? {
        preview.inviterDisplayName?.trimmedNonEmpty
    }

    var body: some View {
        VStack(spacing: PaeoniaSpacing.space24) {
            RelationshipRestoreCouple(
                ownName: session?.displayName ?? "",
                ownPhotoAssetID: session?.profilePhotoAssetID,
                partnerName: partnerName ?? "",
                partnerPhotoAssetID: nil,
                partnerPhotoProvider: InviterPhotoProvider(url: preview.inviterPhotoURL),
                isWaiting: isWaitingForPartner
            )
            // The partner's photo loads once per invite, so a new code starts a new load.
            .id(preview.inviteID)
            .screenEntrance(order: 1)

            header
                .screenEntrance(order: 2)

            if !isWaitingForPartner {
                RelationshipRestoreSummary(
                    title: partnerName.map { .pairingRestoreComesBackPartner($0) }
                        ?? .pairingRestoreComesBackPartnerFallback
                )
                .screenEntrance(order: 3)

                PairingJoinSafetyNote(hasWarning: preview.hasSafetyWarning)
                    .screenEntrance(order: 3)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var header: some View {
        VStack(spacing: PaeoniaSpacing.space8) {
            Text(title)
                .font(PaeoniaTypography.heroTitle)
                .foregroundStyle(.paeoniaTextPrimary)
                .accessibilityAddTraits(.isHeader)

            Text(message)
                .font(PaeoniaTypography.body)
                .foregroundStyle(.paeoniaTextSecondary)

            if showsCoverage, !isWaitingForPartner {
                Text(.pairingJoinCovered)
                    .font(PaeoniaTypography.body)
                    .foregroundStyle(.paeoniaTextSecondary)
            }
        }
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var title: LocalizedStringResource {
        if isWaitingForPartner {
            return partnerName.map { .pairingRestoreWaitingTitle($0) } ?? .pairingRestoreWaitingTitleFallback
        }
        return partnerName.map { .pairingRestoreOfferTitle($0) } ?? .pairingRestoreOfferTitleFallback
    }

    private var message: LocalizedStringResource {
        if isWaitingForPartner {
            return partnerName.map { .pairingRestoreWaitingMessage($0) } ?? .pairingRestoreWaitingMessageFallback
        }
        return .pairingRestoreOfferMessage
    }
}
