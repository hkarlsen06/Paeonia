import SwiftUI

/// The top of the join screen: the inviter's photo, who they are, and the safety
/// note. It is laid out before the preview arrives and drops in once it does, so
/// nothing jumps when the name loads.
struct PairingJoinInviterContent: View {
    let preview: PairingInvitePreview?
    /// The joiner has no subscription of their own, so the screen says the
    /// partner's covers them.
    let showsCoverage: Bool

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
                Text(PairingJoinCopy.title(for: preview))
                    .font(PaeoniaTypography.title)
                    .foregroundStyle(.paeoniaTextPrimary)
                    .contentTransition(.identity)
                    .accessibilityAddTraits(.isHeader)

                Text(PairingJoinCopy.message(for: preview))
                    .font(PaeoniaTypography.body)
                    .foregroundStyle(.paeoniaTextSecondary)
                    .contentTransition(.identity)

                if showsCoverage {
                    Text(.pairingJoinCovered)
                        .font(PaeoniaTypography.body)
                        .foregroundStyle(.paeoniaTextSecondary)
                }
            }
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .screenEntrance(order: 2, isReady: isReady)

            safetyNote
                .screenEntrance(order: 3, isReady: isReady)
        }
        .frame(maxWidth: .infinity)
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
    /// The screen title, which is also the Join button's label.
    static func title(for preview: PairingInvitePreview?) -> LocalizedStringResource {
        guard let name = preview?.inviterDisplayName?.trimmedNonEmpty else {
            return .pairingJoinTitleFallback
        }

        return .pairingJoinTitle(name)
    }

    static func message(for preview: PairingInvitePreview?) -> LocalizedStringResource {
        guard let name = preview?.inviterDisplayName?.trimmedNonEmpty else {
            return .pairingJoinMessageFallback
        }

        return .pairingJoinMessage(name)
    }
}
