import SwiftUI

/// The Us tab row that opens the nickname screen. It shows the nickname once one is set.
struct PartnerNicknameSettingsRow: View {
    let editor: PartnerNicknameEditorModel
    let partner: PartnerName?

    var body: some View {
        NavigationLink {
            Self.destination(editor: editor, partner: partner)
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

    /// The nickname screen. The partner's photo in the couple header opens it too.
    static func destination(editor: PartnerNicknameEditorModel, partner: PartnerName?) -> some View {
        PartnerNicknameView(
            editor: editor,
            partnerAccountName: partner?.accountName,
            savedNickname: partner?.nickname
        )
        .analyticsScreen("settings_partner_nickname")
    }

    private var nameForCopy: String {
        partner?.accountName ?? String(localized: .pairingCelebrationPartnerName)
    }
}
