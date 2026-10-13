import SwiftUI

/// A list row that does something right here instead of opening a screen, with a
/// spinner while its work runs. It reads like the other rows, a plum icon and
/// plain text, except a destructive role, which draws the whole row in red.
struct SettingsActionRow: View {
    let title: LocalizedStringResource
    let systemImage: String
    var role: ButtonRole?
    var isBusy = false
    let action: () -> Void

    var body: some View {
        Button(role: role, action: action) {
            HStack {
                Label {
                    Text(title)
                        .foregroundStyle(role == .destructive ? Color.paeoniaError : Color.paeoniaTextPrimary)
                } icon: {
                    Image(systemName: systemImage)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if isBusy {
                    ProgressView()
                        .accessibilityHidden(true)
                }
            }
        }
        .disabled(isBusy)
    }
}
