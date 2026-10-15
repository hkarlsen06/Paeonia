import SwiftUI

extension View {
    /// Puts a native grouped `List` or `Form` on the plum background. Give its rows
    /// `.listRowBackground(Color.paeoniaSurfacePrimary)` so they match the cards
    /// elsewhere in the app.
    ///
    /// On iPad the sections stop at `PaeoniaSpacing.readableContentWidth`, and the
    /// list still scrolls from anywhere on the screen.
    /// `showsTabBackdrop` is for a tab's first screen, which shows the tabs' shared light.
    func paeoniaGroupedList(showsTabBackdrop: Bool = false) -> some View {
        modifier(PaeoniaGroupedListModifier(showsTabBackdrop: showsTabBackdrop))
    }
}

private struct PaeoniaGroupedListModifier: ViewModifier {
    let showsTabBackdrop: Bool
    @State private var width: CGFloat = 0

    func body(content: Content) -> some View {
        content
            // Row icons, switches, and action rows take the tint, not the system blue.
            .tint(.paeoniaAccentPrimary)
            .scrollContentBackground(.hidden)
            .background {
                if showsTabBackdrop {
                    PaeoniaTabBackdrop()
                } else {
                    Color.paeoniaBackgroundPrimary.ignoresSafeArea()
                }
            }
            .contentMargins(.horizontal, horizontalMargin, for: .scrollContent)
            .onGeometryChange(for: CGFloat.self) { proxy in
                proxy.size.width
            } action: { newWidth in
                width = newWidth
            }
    }

    /// The readable width includes the screen padding on both sides.
    private var horizontalMargin: CGFloat {
        let columnWidth = PaeoniaSpacing.readableContentWidth - 2 * PaeoniaSpacing.screenHorizontalPadding
        return max(PaeoniaSpacing.screenHorizontalPadding, (width - columnWidth) / 2)
    }
}
