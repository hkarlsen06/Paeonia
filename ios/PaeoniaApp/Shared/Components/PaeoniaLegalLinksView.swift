import SwiftUI

struct PaeoniaLegalLinksView: View {
    var body: some View {
        HStack(spacing: PaeoniaSpacing.space12) {
            if let termsURL = Self.termsURL {
                Link(destination: termsURL) {
                    footerLabel(.authSignInLegalTerms)
                }
                .accessibilityIdentifier("legal.terms")
            }

            separator

            if let privacyURL = Self.privacyURL {
                Link(destination: privacyURL) {
                    footerLabel(.authSignInLegalPrivacy)
                }
                .accessibilityIdentifier("legal.privacy")
            }
        }
        .font(PaeoniaTypography.caption)
        .foregroundStyle(.paeoniaTextSecondary)
    }

    private func footerLabel(_ text: LocalizedStringResource) -> some View {
        Text(text)
            .frame(minHeight: 44)
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
