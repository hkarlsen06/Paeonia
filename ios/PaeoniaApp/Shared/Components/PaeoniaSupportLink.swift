import SwiftUI

/// "Still not working? Contact us", under a failure that only says to try again
/// later, so the person has somewhere to go when waiting doesn't help. It opens
/// the support page on paeonia.no.
struct PaeoniaSupportLink: View {
    private static let url = URL(string: "https://paeonia.no/support")

    var body: some View {
        if let url = Self.url {
            Link(destination: url) {
                Text(.commonSupportLink)
                    .font(PaeoniaTypography.caption)
                    .foregroundStyle(.paeoniaTextSecondary)
                    .underline()
                    .multilineTextAlignment(.center)
                    .frame(minHeight: PaeoniaSpacing.compactButtonHeight)
                    .contentShape(Rectangle())
            }
            .accessibilityIdentifier("support.link")
        }
    }
}
