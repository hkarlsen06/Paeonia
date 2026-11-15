import SwiftUI

/// "Show when I'm here", the row under Location in the More tab's Relationship section. Off, the
/// partner no longer sees this person's avatar and where they are, and this person no longer sees
/// the partner's. Hidden outside a couple's tabs, which own the presence model.
struct PresenceSettingsRow: View {
    let partnerName: String

    @Environment(PartnerPresenceModel.self) private var presence: PartnerPresenceModel?

    var body: some View {
        if let presence {
            NavigationLink {
                PresenceSettingsView(presence: presence, partnerName: partnerName)
                    .analyticsScreen("settings_presence")
            } label: {
                SettingsMenuLabel(.settingsPresenceToggle, systemImage: "person.wave.2.fill", value: value(presence))
            }
            .accessibilityIdentifier("settings.presence")
        }
    }

    /// Nothing shows until the saved choice has loaded, so the row never shows a guess.
    private func value(_ presence: PartnerPresenceModel) -> Text? {
        guard presence.isSettingLoaded else { return nil }
        return Text(presence.showsPresence ? .settingsValueOn : .settingsValueOff)
    }
}

/// The switch and what it covers, one step behind the row.
private struct PresenceSettingsView: View {
    let presence: PartnerPresenceModel
    let partnerName: String

    @Environment(PaeoniaBannerCenter.self) private var bannerCenter

    var body: some View {
        Form {
            Section {
                Toggle(isOn: Binding(get: { presence.showsPresence }, set: save)) {
                    Text(.settingsPresenceToggle)
                }
                .disabled(!presence.isSettingLoaded)
                .accessibilityIdentifier("settings.presence.toggle")
            } footer: {
                Text(.settingsPresenceFooter(partnerName))
            }
            .listRowBackground(Color.paeoniaSurfacePrimary)
        }
        .paeoniaGroupedList()
        .navigationTitle(Text(.settingsPresenceToggle))
        .navigationBarTitleDisplayMode(.inline)
    }

    private func save(_ shows: Bool) {
        Task {
            guard await !presence.setShowsPresence(shows) else { return }
            bannerCenter.show(.error(message: String(localized: .commonActionFailedMessage)))
        }
    }
}
