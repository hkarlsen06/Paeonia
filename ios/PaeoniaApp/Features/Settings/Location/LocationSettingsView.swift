import SwiftUI

/// Location sharing on its own screen, so the one switch that decides whether a
/// partner can see where you are is a deliberate stop rather than something you
/// pass on the way down the Me tab.
struct LocationSettingsView: View {
    let viewModel: LocationMapViewModel
    /// Names the partner in the copy instead of saying "your partner".
    let partnerName: String

    var body: some View {
        SettingsDetailScreen(title: .settingsLocationSectionTitle) {
            PaeoniaCard {
                SettingsToggleRow(
                    title: .settingsLocationSharingTitle,
                    subtitle: .settingsLocationSharingSubtitle(partnerName),
                    isOn: sharingBinding,
                    isEnabled: viewModel.isSharingLoaded
                )
            }
        }
    }

    private var sharingBinding: Binding<Bool> {
        Binding(
            get: { viewModel.sharingEnabled },
            set: { newValue in
                Task { await viewModel.setSharingEnabled(newValue) }
            }
        )
    }
}

#Preview {
    NavigationStack {
        LocationSettingsView(viewModel: LocationMapViewModel(), partnerName: "Oda")
    }
    .preferredColorScheme(.dark)
}
