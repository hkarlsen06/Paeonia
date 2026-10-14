import SwiftUI

/// "Saved on this phone. We'll send it when you're online."
struct GameOfflineLine: View {
    var identifier = "game.pending"

    var body: some View {
        Label {
            Text(.gamesPendingSavedOnPhone)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: "clock")
                .accessibilityHidden(true)
        }
        .font(PaeoniaTypography.caption)
        .foregroundStyle(.paeoniaSyncPending)
        .accessibilityIdentifier(identifier)
    }
}
