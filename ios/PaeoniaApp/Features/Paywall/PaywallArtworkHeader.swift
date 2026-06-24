import SwiftUI

/// Solid brand hero that bleeds under the status bar with a hard bottom edge
/// into the surface. Pairs the Paeonia app icon on the left with the brand
/// wordmark on the right, forming a proper logo lockup.
///
/// `height` is supplied by the parent so the hero can scale proportionally to
/// the device instead of using a fixed pixel band.
struct PaywallArtworkHeader: View {
    let topSafeAreaInset: CGFloat
    let height: CGFloat

    var body: some View {
        ZStack {
            Color.paeoniaAccentSecondary

            VStack(spacing: 0) {
                Color.clear.frame(height: topSafeAreaInset)

                Spacer(minLength: 0)

                brandRow
                    .padding(.horizontal, PaeoniaSpacing.space20)

                Spacer(minLength: 0)
            }
        }
        .frame(height: height)
        .frame(maxWidth: .infinity)
        .clipped()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(.appTitle))
    }

    private var brandRow: some View {
        HStack(alignment: .center, spacing: PaeoniaSpacing.space16) {
            Image(.paeoniaAppIconMark)
                .resizable()
                .scaledToFit()
                .frame(width: 56, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                .shadow(color: Color.paeoniaBackgroundSecondary.opacity(0.35), radius: 10, y: 5)
                .accessibilityHidden(true)

            Text(.appTitle)
                .font(PaeoniaTypography.wordmark(size: 36))
                .foregroundStyle(.paeoniaTextPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: 430, alignment: .leading)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#Preview {
    PaywallArtworkHeader(topSafeAreaInset: 59, height: 188)
        .background(.paeoniaSurfacePrimary)
        .preferredColorScheme(.dark)
}
