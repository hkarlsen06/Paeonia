import SwiftUI

extension View {
    /// Keep native title behavior, including the system's large content viewer.
    /// Full content headings can wrap without inheriting the navigation bar's compact text size.
    func paeoniaFittingNavigationTitle(_ title: Text) -> some View {
        navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
    }
}

/// A custom principal item for a screen that sometimes replaces its title with presence.
/// Large Content Viewer keeps the full title available within the compact control bar.
struct PaeoniaFittingTitle: View {
    let title: Text

    var body: some View {
        title
            .font(.headline)
            .lineLimit(1)
            .accessibilityAddTraits(.isHeader)
            .accessibilityShowsLargeContentViewer { title }
    }
}
