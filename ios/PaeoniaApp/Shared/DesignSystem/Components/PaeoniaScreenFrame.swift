import SwiftUI

/// The frame of the full-screen steps around sign-in: the signed-out steps after
/// welcome, and every screen between sign-in and the paired app (profile setup, the
/// paywall, pairing, joining and the account notices). It draws the glow background,
/// the narrow column and the side margins. Only the welcome screen shows the logo, so
/// the content gets the whole height and sets its own top spacing.
struct PaeoniaScreenFrame<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .paeoniaReadableWidth(PaeoniaSpacing.focusedContentWidth)
            .padding(.horizontal, PaeoniaSpacing.screenHorizontalPadding)
            .padding(.bottom, PaeoniaSpacing.space16)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(PaeoniaGlowBackground())
    }
}

/// The scrolling content of a screen in `PaeoniaScreenFrame`. Content shorter than
/// the space above the bottom bar sits a little above the middle of it, where the
/// eye lands first. Taller content, such as at large text sizes, scrolls from the top.
struct PaeoniaScreenScroll<Content: View>: View {
    @ViewBuilder let content: Content

    /// The scroll view's height above the bottom bar.
    @State private var visibleHeight: CGFloat = 0

    var body: some View {
        ScrollView {
            content
                .padding(.vertical, PaeoniaSpacing.space24)
                .paeoniaOpticallyCentered(in: visibleHeight)
        }
        .scrollIndicators(.hidden)
        .scrollBounceBehavior(.basedOnSize)
        .onScrollGeometryChange(for: CGFloat.self) { geometry in
            geometry.containerSize.height
        } action: { _, height in
            visibleHeight = height
        }
    }
}

extension View {
    /// Grows the view to `height` and sets its content a little above the middle:
    /// two fifths of the free space above it and three fifths below. A geometric
    /// middle looks low on a phone, because the bottom bar weighs the screen down.
    func paeoniaOpticallyCentered(in height: CGFloat) -> some View {
        frame(
            maxWidth: .infinity,
            minHeight: height,
            alignment: Alignment(horizontal: .center, vertical: .paeoniaOpticalCenter)
        )
    }
}

private extension VerticalAlignment {
    enum PaeoniaOpticalCenter: AlignmentID {
        static func defaultValue(in dimensions: ViewDimensions) -> CGFloat {
            dimensions.height * 0.4
        }
    }

    static let paeoniaOpticalCenter = VerticalAlignment(PaeoniaOpticalCenter.self)
}
