import SwiftUI

/// What comes back and what does not when two people bring back what they had. The
/// join screen and the inviter's answer screen both show it.
struct RelationshipRestoreSummary: View {
    let title: LocalizedStringResource?
    let message: LocalizedStringResource

    var body: some View {
        VStack(alignment: .leading, spacing: PaeoniaSpacing.space8) {
            if let title {
                Text(title)
                    .font(PaeoniaTypography.bodyEmphasis)
                    .foregroundStyle(.paeoniaTextPrimary)
                    .accessibilityAddTraits(.isHeader)
            }

            Text(message)
                .font(PaeoniaTypography.body)
                .foregroundStyle(.paeoniaTextPrimary)

            Text(.pairingRestoreGone)
                .font(PaeoniaTypography.caption)
                .foregroundStyle(.paeoniaTextSecondary)
        }
        .multilineTextAlignment(.leading)
        .fixedSize(horizontal: false, vertical: true)
        .padding(PaeoniaSpacing.space16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.paeoniaSurfaceSecondary, in: RoundedRectangle(cornerRadius: PaeoniaRadius.radius16))
        .accessibilityElement(children: .combine)
    }
}
