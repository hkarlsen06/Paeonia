import SwiftUI

/// The support group near the bottom of the Me tab. Subscription management lives
/// on the subscription screen, next to purchase restore.
struct SettingsDestinationLinksView: View {
    @Environment(\.openURL) private var openURL

    var body: some View {
        SettingsMenuSection(title: .settingsSectionSupport) {
            Button {
                if let url = URL(string: "https://paeonia.no/support") {
                    openURL(url)
                }
            } label: {
                PaeoniaDisclosureRow(
                    title: .authSignInSupport,
                    message: .settingsSupportRowMessage,
                    systemImage: "questionmark.circle",
                    accessory: .externalLink
                )
            }
            .buttonStyle(.plain)
        }
    }
}
