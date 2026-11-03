import SwiftUI

extension View {
    /// Keep native title behavior, including the system's large content viewer.
    /// Full content headings can wrap without inheriting the navigation bar's compact text size.
    func paeoniaFittingNavigationTitle(_ title: Text) -> some View {
        navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
    }
}
