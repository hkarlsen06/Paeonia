import SwiftUI
import UIKit

/// Location sharing on its own screen, so the one switch that decides whether a
/// partner can see where you are is a deliberate stop rather than something you
/// pass on the way down the Me tab.
struct LocationSettingsView: View {
    let viewModel: LocationMapViewModel
    /// Names the partner in the copy instead of saying "your partner".
    let partnerName: String

    @Environment(\.openURL) private var openURL

    var body: some View {
        SettingsDetailScreen(title: .settingsLocationSectionTitle) {
            PaeoniaCard {
                VStack(alignment: .leading, spacing: PaeoniaSpacing.space16) {
                    SettingsToggleRow(
                        title: .settingsLocationSharingTitle,
                        subtitle: .settingsLocationSharingSubtitle(partnerName),
                        isOn: sharingBinding,
                        // A choice that is still saving cannot be flipped again,
                        // so a second tap is never silently dropped.
                        isEnabled: viewModel.isSharingLoaded && !viewModel.isUpdatingSharing
                    )

                    if viewModel.authorizationState == .denied {
                        accessOffNote
                    }
                }
            }
        }
    }

    /// The switch alone cannot share anything while iOS has location off for
    /// Paeonia, so say that plainly and offer the way to fix it.
    private var accessOffNote: some View {
        VStack(alignment: .leading, spacing: PaeoniaSpacing.space8) {
            Divider()
                .overlay(.paeoniaSurfacePressed)

            Text(.homeMapAccessOffTitle)
                .font(PaeoniaTypography.bodyEmphasis)
                .foregroundStyle(.paeoniaTextPrimary)
            Text(.settingsLocationAccessOffMessage(partnerName))
                .font(PaeoniaTypography.caption)
                .foregroundStyle(.paeoniaTextSecondary)
                .fixedSize(horizontal: false, vertical: true)

            Button {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    openURL(url)
                }
            } label: {
                Text(.commonOpenSettings)
            }
            .buttonStyle(PaeoniaSecondaryButtonStyle())
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
