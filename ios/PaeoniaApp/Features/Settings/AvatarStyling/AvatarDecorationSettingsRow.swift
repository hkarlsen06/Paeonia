import SwiftUI

struct AvatarDecorationSettingsRow: View {
    let name: String
    let photoAssetID: UUID?
    @Environment(\.avatarStyling) private var model

    var body: some View {
        if let model {
            NavigationLink {
                AvatarDecorationPicker(model: model, name: name, photoAssetID: photoAssetID)
            } label: {
                SettingsMenuLabel(.avatarDecorationTitle, systemImage: "sparkles")
            }
            .accessibilityIdentifier("settings.avatarDecoration")
        }
    }
}
