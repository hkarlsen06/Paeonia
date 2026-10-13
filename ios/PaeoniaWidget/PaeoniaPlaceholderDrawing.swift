import SwiftUI

/// The sample drawing shown before a couple saves their first one. The app's
/// home card shows the same `PlaceholderSketch` image.
struct PaeoniaPlaceholderDrawing: View {
    var body: some View {
        Image(.placeholderSketch)
            .resizable()
            .interpolation(.high)
            .scaledToFit()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(PaeoniaWidgetSpacing.space12)
            .accessibilityHidden(true)
    }
}
