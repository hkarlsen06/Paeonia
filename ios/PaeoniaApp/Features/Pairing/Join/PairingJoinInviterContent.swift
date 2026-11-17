import SwiftUI

/// The top of the join screen: the inviter's photo, who they are, and the safety
/// note. It is laid out before the preview arrives and drops in once it does, so
/// nothing jumps when the name loads.
struct PairingJoinInviterContent: View {
    let preview: PairingInvitePreview?
    /// The joiner has no subscription of their own, so the screen says the
    /// partner's covers them.
    let showsCoverage: Bool
    /// The joiner asked to bring back what the two had and waits for the answer.
    var isWaitingForPartner = false

    private static let avatarSize: CGFloat = 132

    private var isReady: Bool {
        preview != nil
    }

    private var inviterName: String? {
        preview?.inviterDisplayName?.trimmedNonEmpty
    }

    var body: some View {
        VStack(spacing: PaeoniaSpacing.space24) {
            avatar
                .screenEntrance(order: 1, isReady: isReady)

            VStack(spacing: PaeoniaSpacing.space8) {
                // The name arrives in the same update that starts the entrance, so the
                // text swaps at once instead of blending with the placeholder copy.
                Text(PairingJoinCopy.title(for: preview, waiting: isWaitingForPartner))
                    .font(PaeoniaTypography.title)
                    .foregroundStyle(.paeoniaTextPrimary)
                    .contentTransition(.identity)
                    .accessibilityAddTraits(.isHeader)

                Text(PairingJoinCopy.message(for: preview, waiting: isWaitingForPartner))
                    .font(PaeoniaTypography.body)
                    .foregroundStyle(.paeoniaTextSecondary)
                    .contentTransition(.identity)

                if showsCoverage, !isWaitingForPartner {
                    Text(.pairingJoinCovered)
                        .font(PaeoniaTypography.body)
                        .foregroundStyle(.paeoniaTextSecondary)
                }
            }
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .screenEntrance(order: 2, isReady: isReady)

            belowTitle
        }
        .frame(maxWidth: .infinity)
    }

    /// While waiting for the inviter's answer only a spinner. Otherwise the restore
    /// offer, when the two can bring back what they had, and the safety note.
    @ViewBuilder
    private var belowTitle: some View {
        if isWaitingForPartner {
            ProgressView()
                .tint(.paeoniaAccentPrimary)
                .accessibilityHidden(true)
        } else {
            if preview?.canRestore == true {
                RelationshipRestoreSummary(
                    title: .pairingRestoreOfferTitle,
                    message: PairingJoinCopy.restoreOffer(for: preview)
                )
                .screenEntrance(order: 3, isReady: isReady)
            }

            safetyNote
                .screenEntrance(order: 3, isReady: isReady)
        }
    }

    private var avatar: some View {
        PaeoniaProfilePhotoAvatar(
            mediaAssetID: nil,
            name: inviterName ?? "",
            tint: .paeoniaPartnerTwo,
            size: Self.avatarSize,
            profilePhotoProvider: InviterPhotoProvider(url: preview?.inviterPhotoURL)
        )
        // The avatar loads once per identity, so a new invite starts a new load.
        .id(preview?.inviteID)
        // No crossfade from the placeholder. The entrance brings the new one in.
        .transition(.identity)
        // The title right under it already names the person.
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var safetyNote: some View {
        if preview?.hasSafetyWarning == true {
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

enum PairingJoinCopy {
    /// The screen title. Without waiting it is also the Join button's label.
    static func title(for preview: PairingInvitePreview?, waiting: Bool = false) -> LocalizedStringResource {
        let name = preview?.inviterDisplayName?.trimmedNonEmpty
        if waiting {
            return name.map { .pairingRestoreWaitingTitle($0) } ?? .pairingRestoreWaitingTitleFallback
        }
        return name.map { .pairingJoinTitle($0) } ?? .pairingJoinTitleFallback
    }

    static func message(for preview: PairingInvitePreview?, waiting: Bool = false) -> LocalizedStringResource {
        let name = preview?.inviterDisplayName?.trimmedNonEmpty
        if waiting {
            return name.map { .pairingRestoreWaitingMessage($0) } ?? .pairingRestoreWaitingMessageFallback
        }
        return name.map { .pairingJoinMessage($0) } ?? .pairingJoinMessageFallback
    }

    static func restoreOffer(for preview: PairingInvitePreview?) -> LocalizedStringResource {
        preview?.inviterDisplayName?.trimmedNonEmpty.map { .pairingRestoreOfferMessage($0) }
            ?? .pairingRestoreOfferMessageFallback
    }
}
