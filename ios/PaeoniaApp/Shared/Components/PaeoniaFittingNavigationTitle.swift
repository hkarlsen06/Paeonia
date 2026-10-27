import SwiftUI

extension View {
    /// An inline title that shows in full or not at all. Beside a back button and
    /// several toolbar buttons a title gets cut off, so it gives the bar up instead.
    /// The back button's history menu and VoiceOver still read it.
    func paeoniaFittingNavigationTitle(_ title: Text) -> some View {
        navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    ViewThatFits(in: .horizontal) {
                        title
                            .font(.headline)
                            .lineLimit(1)
                            .accessibilityAddTraits(.isHeader)
                        Color.clear.frame(width: 0, height: 0)
                    }
                }
            }
    }
}
