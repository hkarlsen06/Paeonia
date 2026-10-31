import SwiftUI

/// The glass hint over a map's lower edge before the first pin. It sits above
/// the map's logo and Legal link, which must stay visible.
struct GuessMySpotMapHint: View {
    let text: LocalizedStringResource

    var body: some View {
        Text(text)
            .font(PaeoniaTypography.caption.weight(.semibold))
            .foregroundStyle(.paeoniaTextPrimary)
            .padding(.horizontal, PaeoniaSpacing.space12)
            .padding(.vertical, PaeoniaSpacing.space8)
            .glassEffect(.regular.tint(Color.paeoniaBackgroundSecondary.opacity(0.6)), in: Capsule())
            .padding(PaeoniaSpacing.space12)
            .padding(.bottom, PaeoniaMapAttribution.height)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}
