import SwiftUI

/// A phase without the square: choose a word, waiting, status. One column at the
/// focused width, with the bottom cluster pinned.
struct GameFocusedLayout<Content: View, Bottom: View>: View {
    /// The content fills the screen height, so it can place itself with spacers.
    var fillsHeight = false
    @ViewBuilder var content: Content
    @ViewBuilder var bottom: Bottom

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                content
                    .padding(.horizontal, PaeoniaSpacing.screenHorizontalPadding)
                    .padding(.vertical, PaeoniaSpacing.space16)
                    .frame(minHeight: fillsHeight ? max(0, proxy.size.height - 120) : 0, alignment: .top)
                    .paeoniaReadableWidth(PaeoniaSpacing.focusedContentWidth)
            }
            .scrollBounceBehavior(.basedOnSize)
            .scrollDismissesKeyboard(.interactively)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                VStack(spacing: PaeoniaSpacing.space12) {
                    bottom
                }
                .padding(.horizontal, PaeoniaSpacing.screenHorizontalPadding)
                .padding(.vertical, PaeoniaSpacing.space8)
                .paeoniaReadableWidth(PaeoniaSpacing.focusedContentWidth)
                .background(.paeoniaBackgroundSecondary)
            }
        }
    }
}

extension GameFocusedLayout where Bottom == EmptyView {
    init(fillsHeight: Bool = false, @ViewBuilder content: () -> Content) {
        self.init(fillsHeight: fillsHeight, content: content, bottom: { EmptyView() })
    }
}
