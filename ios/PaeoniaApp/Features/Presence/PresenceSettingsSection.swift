import SwiftUI

/// "Show when I'm here" on the More tab. Off, the partner no longer sees this person's avatar and
/// where they are, and this person no longer sees the partner's. Hidden outside a couple's tabs,
/// which own the presence model.
struct PresenceSettingsSection: View {
    let partnerName: String

    @Environment(PartnerPresenceModel.self) private var presence: PartnerPresenceModel?
    @Environment(PaeoniaBannerCenter.self) private var bannerCenter

    var body: some View {
        if let presence {
            Section {
                Toggle(isOn: Binding(get: { presence.showsPresence }, set: { save($0, in: presence) })) {
                    SettingsMenuLabel(.settingsPresenceToggle, systemImage: "person.wave.2.fill")
                }
                .disabled(!presence.isSettingLoaded)
                .accessibilityIdentifier("settings.presence")
            } footer: {
                Text(.settingsPresenceFooter(partnerName))
            }
        }
    }

    private func save(_ shows: Bool, in presence: PartnerPresenceModel) {
        Task {
            guard await !presence.setShowsPresence(shows) else { return }
            bannerCenter.show(.error(message: String(localized: .commonActionFailedMessage)))
        }
    }
}
