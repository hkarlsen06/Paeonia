import SwiftUI

/// The Us tab row that opens the nickname screen. It shows the nickname once one is set.
struct PartnerNicknameSettingsRow: View {
    let editor: PartnerNicknameEditorModel
    let partner: PartnerName?

    var body: some View {
        NavigationLink {
            PartnerNicknameView(
                editor: editor,
                partnerAccountName: partner?.accountName,
                savedNickname: partner?.nickname
            )
            .analyticsScreen("settings_partner_nickname")
        } label: {
            LabeledContent {
                if let nickname = partner?.nickname {
                    Text(verbatim: nickname)
                } else {
                    Text(.settingsPartnerNicknameRowEmpty)
                }
            } label: {
                Label {
                    Text(.settingsPartnerNicknameRowTitle(nameForCopy))
                        .foregroundStyle(.paeoniaTextPrimary)
                } icon: {
                    Image(systemName: "heart.text.square.fill")
                }
            }
        }
        .accessibilityIdentifier("settings.partnerNickname")
    }

    private var nameForCopy: String {
        partner?.accountName ?? String(localized: .pairingCelebrationPartnerName)
    }
}
