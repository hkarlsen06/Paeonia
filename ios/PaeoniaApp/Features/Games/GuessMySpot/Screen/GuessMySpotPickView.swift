import PhotosUI
import SwiftUI

/// The camera roll inside the screen. The system picker runs outside the app, so
/// the app gets only the photo the person taps and needs no photo library
/// permission. Screenshots and videos are left out. It stays alive under the
/// check, so "Choose another photo" comes back to the same place in the roll.
/// The system draws the picker on black that the app can't recolor, and clipping
/// or covering it stops it taking touches. So its top bar is hidden, and the photo
/// grid starts right under the header without a black band above it.
struct GuessMySpotPickView: View {
    @Bindable var viewModel: GuessMySpotViewModel

    @Environment(PaeoniaBannerCenter.self) private var bannerCenter
    @State private var selection: PhotosPickerItem?
    /// The load of the latest tapped photo. A newer tap cancels it, so a slow photo
    /// from iCloud can't replace the one tapped after it.
    @State private var loadTask: Task<Void, Never>?
    @State private var showsSpinner = false

    var body: some View {
        VStack(spacing: PaeoniaSpacing.space12) {
            header
            picker
        }
        .onChange(of: selection) { _, item in
            guard let item else { return }
            PaeoniaHaptics.selection()
            GameSound.tap.play(volume: 0.7)
            loadTask?.cancel()
            loadTask = Task { await load(item) }
        }
        .onChange(of: viewModel.pickFailed) { _, failed in
            guard failed else { return }
            viewModel.pickFailed = false
            bannerCenter.show(.error(message: String(localized: .guessMySpotPickUnreadable)))
        }
        .gameInviteToolbar(
            // The picker stays alive under the check, so the bell goes with it.
            invite: viewModel.showsCheck ? .hidden : viewModel.invite,
            partnerName: viewModel.partnerName,
            send: viewModel.sendInvite,
            identifier: "guessMySpot.invite"
        )
        .accessibilityIdentifier("guessMySpot.pick")
    }

    private var header: some View {
        VStack(spacing: PaeoniaSpacing.space4) {
            Text(.guessMySpotPickTitle)
                .font(PaeoniaTypography.title)
                .foregroundStyle(.paeoniaTextPrimary)
                .accessibilityAddTraits(.isHeader)
            Text(viewModel.isFirstTurn
                ? .guessMySpotPickSubtitleFirst(viewModel.partnerName)
                : .guessMySpotPickSubtitle(viewModel.partnerName))
                .font(PaeoniaTypography.body)
                .foregroundStyle(.paeoniaTextSecondary)
        }
        .multilineTextAlignment(.center)
        .padding(.horizontal, PaeoniaSpacing.screenHorizontalPadding)
        .padding(.top, PaeoniaSpacing.space8)
    }

    private var picker: some View {
        PhotosPicker(
            selection: $selection,
            matching: .all(of: [.images, .not(.screenshots)]),
            preferredItemEncoding: .current,
            photoLibrary: .shared()
        ) {
            EmptyView()
        }
        .photosPickerStyle(.inline)
        .photosPickerDisabledCapabilities([.selectionActions])
        .photosPickerAccessoryVisibility(.hidden, edges: .all)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay {
            if viewModel.isPreparingPhoto {
                ZStack {
                    Color.paeoniaBackgroundSecondary.opacity(0.6)
                    ProgressView()
                        .tint(.paeoniaAccentPrimary)
                        .controlSize(.large)
                }
                .opacity(showsSpinner ? 1 : 0)
                .task {
                    showsSpinner = false
                    try? await Task.sleep(for: .seconds(0.3))
                    showsSpinner = true
                }
                .accessibilityHidden(true)
            }
        }
        .disabled(viewModel.isPreparingPhoto)
    }

    private func load(_ item: PhotosPickerItem) async {
        let data = try? await item.loadTransferable(type: Data.self)
        guard !Task.isCancelled else { return }
        // Cleared, so tapping the same photo after "Choose another photo" picks it again.
        selection = nil
        guard let data else {
            viewModel.pickFailed = true
            return
        }
        await viewModel.pick(data)
    }
}
