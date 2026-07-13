import SwiftUI

/// A tappable destination row inside a `PaeoniaCard`: leading icon, title with
/// an optional supporting message, and a trailing affordance — a chevron for
/// in-app destinations or an outward arrow for links that leave the app.
/// Wrap it in the presenting `Button`/`NavigationLink` with `.plain` style.
struct PaeoniaDisclosureRow: View {
    enum Accessory {
        case navigation
        case externalLink

        fileprivate var systemImage: String {
            switch self {
            case .navigation:
                "chevron.right"
            case .externalLink:
                "arrow.up.right"
            }
        }
    }

    let title: LocalizedStringResource
    var message: LocalizedStringResource?
    let systemImage: String
    var iconTint: Color = .paeoniaAccentPrimary
    var accessory: Accessory = .navigation

    var body: some View {
        HStack(spacing: PaeoniaSpacing.space12) {
            Image(systemName: systemImage)
                .font(PaeoniaTypography.bodyEmphasis)
                .foregroundStyle(iconTint)
                .frame(width: PaeoniaSpacing.space24)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: PaeoniaSpacing.space4) {
                Text(title)
                    .font(PaeoniaTypography.bodyEmphasis)
                    .foregroundStyle(.paeoniaTextPrimary)

                if let message {
                    Text(message)
                        .font(PaeoniaTypography.caption)
                        .foregroundStyle(.paeoniaTextSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Image(systemName: accessory.systemImage)
                .font(PaeoniaTypography.caption)
                .foregroundStyle(.paeoniaTextTertiary)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, PaeoniaSpacing.space16)
        .padding(.vertical, message == nil ? 0 : PaeoniaSpacing.space16)
        .frame(maxWidth: .infinity, minHeight: PaeoniaSpacing.buttonHeight)
        .contentShape(Rectangle())
    }
}
