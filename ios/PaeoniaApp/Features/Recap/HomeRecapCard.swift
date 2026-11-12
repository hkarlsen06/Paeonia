import SwiftUI

struct HomeRecapCard: View {
    let recap: AnniversaryRecap
    let isAnniversaryToday: Bool
    let onOpen: () -> Void

    private static let iconSize: CGFloat = 32

    var body: some View {
        Button(action: onOpen) {
            PaeoniaCard(padding: PaeoniaSpacing.space12) {
                HStack(spacing: PaeoniaSpacing.space12) {
                    Image(systemName: "sparkles")
                        .font(PaeoniaTypography.caption.weight(.semibold))
                        .foregroundStyle(.paeoniaAccentPrimary)
                        .frame(width: Self.iconSize, height: Self.iconSize)
                        .background(.paeoniaSurfaceSecondary, in: Circle())
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: PaeoniaSpacing.space2) {
                        if isAnniversaryToday {
                            Text(.recapCardAnniversary)
                                .paeoniaEyebrowStyle(foreground: .paeoniaAccentPrimary)
                        }
                        Text(recap.sinceJoined ? .recapCardTitleSinceJoined : .recapCardTitle)
                            .font(PaeoniaTypography.bodyEmphasis)
                            .foregroundStyle(.paeoniaTextPrimary)
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    Image(systemName: "chevron.right")
                        .font(PaeoniaTypography.caption.weight(.semibold))
                        .foregroundStyle(.paeoniaTextTertiary)
                        .accessibilityHidden(true)
                }
            }
        }
        .buttonStyle(.paeoniaPressableCard)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("home.recap.open")
    }
}
