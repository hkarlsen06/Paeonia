import SwiftUI

/// The identity row at the top of the Me tab, opening the profile screen.
///
/// It is the one row that leads with a photo instead of a glyph, so the tab still
/// opens on the person rather than straight into a list of settings.
struct SettingsProfileRow: View {
    let displayName: String?
    let customProfilePhotoAssetID: UUID?
    let providerProfilePhotoAssetID: UUID?

    @ScaledMetric(relativeTo: .title) private var avatarSize: CGFloat = 56

    var body: some View {
        HStack(spacing: PaeoniaSpacing.space16) {
            PaeoniaProfilePhotoAvatar(
                mediaAssetID: customProfilePhotoAssetID ?? providerProfilePhotoAssetID,
                name: resolvedName,
                tint: .paeoniaPartnerOne,
                size: min(avatarSize, 72)
            )
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: PaeoniaSpacing.space4) {
                Text(resolvedName)
                    .font(PaeoniaTypography.title)
                    .foregroundStyle(.paeoniaTextPrimary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                Text(.settingsProfileRowMessage)
                    .font(PaeoniaTypography.caption)
                    .foregroundStyle(.paeoniaTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Image(systemName: "chevron.right")
                .font(PaeoniaTypography.caption)
                .foregroundStyle(.paeoniaTextTertiary)
                .accessibilityHidden(true)
        }
        .padding(PaeoniaSpacing.space16)
        .contentShape(Rectangle())
    }

    /// The avatar draws initials, and the row still needs a title, before the
    /// account has a name.
    private var resolvedName: String {
        displayName?.trimmedNonEmpty ?? String(localized: .settingsProfileFallbackName)
    }
}
