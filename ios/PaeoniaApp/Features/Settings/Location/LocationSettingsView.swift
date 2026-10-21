import SwiftUI
import UIKit

/// Location sharing on its own screen, so the one switch that decides whether a
/// partner can see where you are is a deliberate stop rather than something you
/// pass on the way down the Us tab.
struct LocationSettingsView: View {
    let viewModel: LocationMapViewModel
    /// Names the partner in the copy instead of saying "your partner".
    let partnerName: String
    var updates: LocationUpdateController = .shared

    @Environment(\.openURL) private var openURL
    @State private var isChoosingPause = false

    var body: some View {
        Form {
            Group {
                sharingSection

                if viewModel.sharingEnabled, viewModel.authorizationState != .denied {
                    pauseSection
                }

                if viewModel.authorizationState == .denied {
                    settingsNote(
                        title: .homeMapAccessOffTitle,
                        message: .settingsLocationAccessOffMessage(partnerName)
                    )
                }
            }
            .listRowBackground(Color.paeoniaSurfacePrimary)
        }
        .paeoniaGroupedList()
        .navigationTitle(Text(.settingsLocationSectionTitle))
        .navigationBarTitleDisplayMode(.inline)
    }

    private var sharingSection: some View {
        Section {
            Toggle(isOn: sharingBinding) {
                Text(.settingsLocationSharingTitle)
                Text(.settingsLocationSharingSubtitle(partnerName))
            }
            // A choice that is still saving cannot be flipped again, so a
            // second tap is never silently dropped.
            .disabled(!viewModel.isSharingLoaded || viewModel.isUpdatingSharing)

            if viewModel.sharingEnabled, viewModel.authorizationState != .denied {
                whileClosedRows
            }
        }
    }

    /// Pause sharing for a while, or end a pause. A pause is not an off switch: sharing
    /// stays on and starts again by itself, so the footer says what the pause hides.
    private var pauseSection: some View {
        Section {
            if let pausedUntil = viewModel.pausedUntil, viewModel.isSharingPaused {
                pausedRows(until: pausedUntil)
            } else {
                pauseButton
            }
        } footer: {
            Text(.settingsLocationPauseFooter(partnerName))
        }
    }

    @ViewBuilder
    private func pausedRows(until end: Date) -> some View {
        Label {
            Text(.settingsLocationPauseStatus(LocationPauseEndText.text(for: end)))
                .foregroundStyle(.paeoniaTextPrimary)
        } icon: {
            Image(systemName: "pause.circle.fill")
        }
        Button {
            Task { await viewModel.resumeSharing() }
        } label: {
            Label {
                Text(.settingsLocationPauseResume)
                    .foregroundStyle(.paeoniaTextPrimary)
            } icon: {
                Image(systemName: "play.fill")
            }
        }
        .disabled(viewModel.isUpdatingSharing)
    }

    private var pauseButton: some View {
        Button {
            isChoosingPause = true
        } label: {
            Label {
                Text(.settingsLocationPauseButton)
                    .foregroundStyle(.paeoniaTextPrimary)
            } icon: {
                Image(systemName: "pause.circle")
            }
        }
        .disabled(viewModel.isUpdatingSharing)
        .confirmationDialog(
            Text(.settingsLocationPauseDialogTitle),
            isPresented: $isChoosingPause,
            titleVisibility: .visible
        ) {
            LocationPauseChoices { end in
                Task { await viewModel.pauseSharing(until: end) }
            }
        }
    }

    /// Off by default, and only offered while sharing is on. It needs iOS
    /// location access set to Always, so the note says how to get there.
    @ViewBuilder
    private var whileClosedRows: some View {
        Toggle(isOn: whileClosedBinding) {
            Text(.settingsLocationWhileClosedTitle)
            Text(.settingsLocationWhileClosedSubtitle(partnerName))
        }
        .disabled(viewModel.isUpdatingSharing)

        if updates.prefersUpdatesWhileClosed, !updates.updatesWhileClosedActive {
            noteRows(
                title: .settingsLocationWhileClosedNeedsAlwaysTitle,
                message: .settingsLocationWhileClosedNeedsAlwaysMessage
            )
        }
    }

    /// A switch cannot share anything while iOS holds back the access it
    /// needs, so say that plainly and offer the way to fix it.
    private func settingsNote(title: LocalizedStringResource, message: LocalizedStringResource) -> some View {
        Section {
            noteRows(title: title, message: message)
        }
    }

    @ViewBuilder
    private func noteRows(title: LocalizedStringResource, message: LocalizedStringResource) -> some View {
        VStack(alignment: .leading, spacing: PaeoniaSpacing.space4) {
            Text(title)
                .font(PaeoniaTypography.bodyEmphasis)
                .foregroundStyle(.paeoniaTextPrimary)
            Text(message)
                .font(PaeoniaTypography.caption)
                .foregroundStyle(.paeoniaTextSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }

        Button {
            if let url = URL(string: UIApplication.openSettingsURLString) {
                openURL(url)
            }
        } label: {
            Text(.commonOpenSettings)
        }
    }

    private var whileClosedBinding: Binding<Bool> {
        Binding(
            get: { updates.prefersUpdatesWhileClosed },
            set: { updates.setUpdatesWhileClosed($0) }
        )
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
