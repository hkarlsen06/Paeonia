import SwiftUI

struct AvatarDecorationSettingsRow: View {
    let name: String
    let photoAssetID: UUID?
    @Environment(\.avatarStyling) private var model
    @State private var isPresented = false

    var body: some View {
        if let model {
            Button { isPresented = true } label: {
                Label {
                    Text(.avatarDecorationTitle).foregroundStyle(.paeoniaTextPrimary)
                } icon: {
                    Image(systemName: "person.crop.circle").foregroundStyle(.paeoniaAccentPrimary)
                }
            }
            .accessibilityIdentifier("settings.avatarDecoration")
            .sheet(isPresented: $isPresented) {
                NavigationStack {
                    AvatarDecorationPicker(model: model, name: name, photoAssetID: photoAssetID)
                }
            }
        }
    }
}
