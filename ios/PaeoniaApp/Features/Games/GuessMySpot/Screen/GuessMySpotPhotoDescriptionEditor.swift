import SwiftUI

struct GuessMySpotPhotoDescriptionEditor: View {
    let viewModel: GuessMySpotViewModel
    @State private var isPresented = false
    @Environment(PaeoniaBannerCenter.self) private var bannerCenter

    var body: some View {
        Button(title) { isPresented = true }
            .frame(minHeight: PaeoniaSpacing.compactButtonHeight)
            .accessibilityIdentifier("guessMySpot.description.open")
            .sheet(isPresented: $isPresented) {
                NavigationStack {
                    Form {
                        Section {
                            PhotoDescriptionField(text: Binding(
                                get: { viewModel.draft?.accessibilityText ?? "" },
                                set: viewModel.updatePhotoDescription
                            ))
                            .accessibilityIdentifier("guessMySpot.description.text")
                            Text(.guessMySpotPhotoDescriptionHelp)
                                .foregroundStyle(.paeoniaTextSecondary)
                        }
                    }
                    .paeoniaGroupedList()
                    .navigationTitle(Text(.mediaAccessibilityPhotoDescription))
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button(.commonDone) { isPresented = false }
                                .disabled(viewModel.photoDescriptionTooLong)
                                .accessibilityIdentifier("guessMySpot.description.done")
                        }
                    }
                }
                .preferredColorScheme(.dark)
                .paeoniaTopBanner(bannerCenter)
            }
    }

    private var title: LocalizedStringResource {
        viewModel.draft?.accessibilityText.trimmedNonEmpty == nil
            ? .mediaAccessibilityPhotoDescription : .mediaAccessibilityEditPhoto
    }
}
