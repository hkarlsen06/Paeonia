import SwiftUI

struct PaeoniaLegalLinksView: View {
    var body: some View {
        // Side by side when they fit, stacked at large text sizes so they do not clip.
        ViewThatFits(in: .horizontal) {
            HStack(spacing: PaeoniaSpacing.space12) {
                termsLink
                separator
                privacyLink
            }

            VStack(spacing: 0) {
                termsLink
                privacyLink
            }
        }
        .font(PaeoniaTypography.caption)
        .foregroundStyle(.paeoniaTextSecondary)
    }

    @ViewBuilder
    private var termsLink: some View {
        if let termsURL = Self.termsURL {
            Link(destination: termsURL) {
                footerLabel(.authSignInLegalTerms)
            }
            .accessibilityIdentifier("legal.terms")
        }
    }

    @ViewBuilder
    private var privacyLink: some View {
        if let privacyURL = Self.privacyURL {
            Link(destination: privacyURL) {
                footerLabel(.authSignInLegalPrivacy)
            }
            .accessibilityIdentifier("legal.privacy")
        }
    }

    private func footerLabel(_ text: LocalizedStringResource) -> some View {
        Text(text)
            .frame(minHeight: PaeoniaSpacing.compactButtonHeight)
            .contentShape(Rectangle())
    }

    private var separator: some View {
        Text(verbatim: "·")
            .foregroundStyle(.paeoniaTextTertiary)
            .accessibilityHidden(true)
    }

    private static let termsURL = URL(string: "https://paeonia.no/terms")
    private static let privacyURL = URL(string: "https://paeonia.no/privacy")
}
