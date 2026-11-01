import SwiftUI

struct GuessMySpotPhotoDescriptionReader: View {
    let text: String?
    var editingTarget: MediaAlternativeTarget?
    var isIconOnly = false
    @State private var isPresented = false
    @Environment(PaeoniaBannerCenter.self) private var bannerCenter
    @AccessibilityPresentation(.media) private var showsMedia

    var body: some View {
        Group {
            if showsMedia || isPresented {
                Button { isPresented = true } label: {
                    if isIconOnly {
                        Image(systemName: "text.bubble")
                            .accessibilityHidden(true)
                            .frame(width: 44, height: 44)
                    } else {
                        Label(.mediaAccessibilityPhotoDescription, systemImage: "text.bubble")
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(minHeight: PaeoniaSpacing.compactButtonHeight)
                    }
                }
                .accessibilityLabel(Text(.mediaAccessibilityPhotoDescription))
                .accessibilityIdentifier("guessMySpot.description.read")
            }
        }
        .sheet(isPresented: $isPresented) {
            NavigationStack {
                Form {
                    MediaAlternativeReadout(text: text, isVoice: false, editingTarget: editingTarget,
                                            alwaysVisible: true)
                }
                .paeoniaGroupedList()
                .navigationTitle(Text(.mediaAccessibilityPhotoDescription))
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button(.commonDone) { isPresented = false }
                            .accessibilityIdentifier("guessMySpot.description.read.close")
                    }
                }
            }
            .preferredColorScheme(.dark)
            .paeoniaTopBanner(bannerCenter)
        }
    }
}
