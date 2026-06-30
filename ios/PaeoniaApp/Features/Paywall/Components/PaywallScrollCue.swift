import SwiftUI

/// A tappable button sitting in the gap above the bottom CTA. Opens the
/// invite-code overlay for users who arrived via a partner invite.
struct PaywallScrollCue: View {
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: PaeoniaSpacing.space8) {
                Image(systemName: "lock.heart")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.paeoniaAccentPrimary)
                    .accessibilityHidden(true)

                Text(.paywallScrollHint)
                    .font(PaeoniaTypography.bodyEmphasis)
                    .foregroundStyle(.paeoniaTextPrimary)
            }
            .padding(.horizontal, PaeoniaSpacing.space20)
            .padding(.vertical, PaeoniaSpacing.space12)
            .background(.paeoniaSurfacePressed)
            .clipShape(Capsule(style: .continuous))
            .contentShape(Capsule(style: .continuous))
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .buttonStyle(.plain)
        .accessibilityLabel(Text(.paywallScrollHint))
    }
}

#Preview {
    PaywallScrollCue(onTap: {})
        .padding()
        .background(.paeoniaSurfacePrimary)
        .preferredColorScheme(.dark)
}
