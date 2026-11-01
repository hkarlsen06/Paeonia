import SwiftUI

struct GuessMySpotPhotoDescriptionEditor: View {
    let viewModel: GuessMySpotViewModel
    @State private var isPresented = false
    @Environment(PaeoniaBannerCenter.self) private var bannerCenter
    @AccessibilityPresentation(.media) private var showsMedia

    var body: some View {
        Group {
            if showsMedia || isPresented || viewModel.photoDescriptionTooLong {
                Button(title) { isPresented = true }
                    .frame(minHeight: PaeoniaSpacing.compactButtonHeight)
                    .accessibilityIdentifier("guessMySpot.description.open")
            }
        }
        .sheet(isPresented: $isPresented) {
            NavigationStack {
                Form {
                    Section {
                        PhotoDescriptionField(text: Binding(
                            get: { viewModel.draft?.accessibilityText ?? "" },
                            set: viewModel.updatePhotoDescription
                        ), alwaysVisible: true)
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
