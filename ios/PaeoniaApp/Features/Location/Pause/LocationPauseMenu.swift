import SwiftUI

/// The pause button in the map's top corner. Pausing is the quick way to stop sharing for
/// a while, so it sits on the map where the person sees their own pin. A tap opens a menu
/// of lengths, with no picker to fiddle with.
struct LocationPauseMenu: View {
    static let size: CGFloat = 32

    let onChoose: (Date) -> Void

    var body: some View {
        Menu {
            LocationPauseChoices(onChoose: onChoose)
        } label: {
            Image(systemName: "pause.fill")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.paeoniaAccentPrimary)
                .frame(width: Self.size, height: Self.size)
                .background(Color.paeoniaBackgroundSecondary.opacity(0.9), in: Circle())
        }
        .accessibilityLabel(Text(.settingsLocationPauseButton))
        .padding(PaeoniaSpacing.space12)
    }
}
