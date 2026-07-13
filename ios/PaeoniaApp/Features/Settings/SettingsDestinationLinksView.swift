import SwiftUI

/// Production support, legal, and subscription destinations for paired users.
/// They stay grouped and quiet so they remain easy to find without competing with
/// the relationship and notification settings above them.
struct SettingsDestinationLinksView: View {
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(spacing: PaeoniaSpacing.space12) {
            PaeoniaCard(padding: 0) {
                VStack(spacing: 0) {
                    destinationButton(
                        .paywallManageSubscription,
                        systemImage: "creditcard",
                        urlString: "https://apps.apple.com/account/subscriptions"
                    )

                    Divider()
                        .overlay(.paeoniaSurfacePressed)

                    destinationButton(
                        .authSignInSupport,
                        systemImage: "questionmark.circle",
                        urlString: "https://paeonia.no/support"
                    )
                }
            }

            PaeoniaLegalLinksView()
                .frame(maxWidth: .infinity)
        }
    }

    private func destinationButton(
        _ title: LocalizedStringResource,
        systemImage: String,
        urlString: String
    ) -> some View {
        Button {
            guard let url = URL(string: urlString) else {
                return
            }
            openURL(url)
        } label: {
            PaeoniaDisclosureRow(
                title: title,
                systemImage: systemImage,
                accessory: .externalLink
            )
        }
        .buttonStyle(.plain)
    }
}
