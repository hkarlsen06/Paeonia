import SwiftUI

/// The support and legal group at the bottom of the Me tab. It stays quiet so it
/// remains easy to find without competing with the relationship and app settings
/// above it. Subscription management lives on the purchases screen, next to
/// purchase restore.
struct SettingsDestinationLinksView: View {
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(spacing: PaeoniaSpacing.space16) {
            SettingsMenuSection(title: .settingsSectionSupport) {
                destinationButton(
                    .authSignInSupport,
                    message: .settingsSupportRowMessage,
                    systemImage: "questionmark.circle",
                    urlString: "https://paeonia.no/support"
                )
            }

            PaeoniaLegalLinksView()
                .frame(maxWidth: .infinity)
        }
    }

    private func destinationButton(
        _ title: LocalizedStringResource,
        message: LocalizedStringResource,
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
                message: message,
                systemImage: systemImage,
                accessory: .externalLink
            )
        }
        .buttonStyle(.plain)
    }
}
