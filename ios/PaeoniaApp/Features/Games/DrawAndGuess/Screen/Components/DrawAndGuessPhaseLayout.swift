import SwiftUI

/// How big the square is, so a phase never resizes it. The width decides, and the
/// height left after the rows around it keeps it on screen.
enum DrawAndGuessMetrics {
    /// The square never grows past this, so strokes keep their weight.
    static let maxSquare: CGFloat = 640
    /// The widest the right column grows in the wide layout.
    static let sideColumnWidth: CGFloat = 420
    /// Height kept for the rows above and below the square on a phone, until the
    /// layout has measured them (`DrawAndGuessPhaseLayout`).
    static let reservedHeight: CGFloat = 340
    /// The square on a phone never shrinks below this. Smaller screens scroll.
    static let minSquare: CGFloat = 200
    /// Space above and below the scrolling rows.
    static let scrollPadding = PaeoniaSpacing.space8 + PaeoniaSpacing.space16
    static let wideMinWidth: CGFloat = 700

    static func isWide(_ size: CGSize) -> Bool {
        size.width >= wideMinWidth && size.width > size.height
    }

    static func squareSide(in size: CGSize) -> CGFloat {
        let padding = PaeoniaSpacing.screenHorizontalPadding * 2
        if isWide(size) {
            let beside = size.width - sideColumnWidth - PaeoniaSpacing.space32 - padding
            return max(200, min(maxSquare, beside, size.height - PaeoniaSpacing.space24 * 2))
        }
        let byHeight = max(220, size.height - reservedHeight)
        return max(minSquare, min(maxSquare, size.width - padding, byHeight))
    }

    /// The side that makes the rows and the square fill the height exactly.
    /// - Parameters:
    ///   - measuredSide: The side the rows were measured with.
    ///   - contentHeight: The height of the scrolling rows with that side.
    ///   - bottomHeight: The height of the pinned bottom cluster.
    static func fittedSide(
        in size: CGSize,
        measuredSide: CGFloat,
        contentHeight: CGFloat,
        bottomHeight: CGFloat
    ) -> CGFloat {
        let slack = size.height - bottomHeight - contentHeight - scrollPadding
        let widthLimit = min(maxSquare, size.width - PaeoniaSpacing.screenHorizontalPadding * 2)
        // Whole points, so a measurement that lands a hair off does not move the square again.
        return max(minSquare, min(widthLimit, (measuredSide + slack).rounded(.down)))
    }
}

/// The square's side as the drawer's drawing screen settled it. The drawer's result
/// screen takes the same side, so the square does not change size when the
/// drawing is sent.
@MainActor
final class DrawAndGuessSideMemory {
    var side: CGFloat?
}

/// A phase with the drawing square. Narrow screens scroll one column with the
/// bottom cluster pinned. Wide screens put the square on the left and everything
/// else in a column on the right.
///
/// On a phone the square fills the height the other rows leave. The layout
/// measures them once the rows exist, so every row and text size counts.
struct DrawAndGuessPhaseLayout<Header: View, Square: View, Footer: View, Bottom: View>: View {
    enum SideSharing {
        case none
        /// Remembers the side for the next screen of the round.
        case publishes
        /// Uses the remembered side when it is smaller than the one that fits.
        case inherits
    }

    /// Scrolls to the end when this number goes up, so new rows of a result are seen.
    var scrollTrigger = 0
    /// A result is playing and its rows grow. The square keeps the side it had
    /// while the screen was a plain guess or drawing screen.
    var freezesSide = false
    var sharing = SideSharing.none
    var sideMemory: DrawAndGuessSideMemory?
    @ViewBuilder var header: Header
    @ViewBuilder var square: (CGFloat) -> Square
    @ViewBuilder var footer: Footer
    @ViewBuilder var bottom: Bottom

    /// The scrolling rows' height and the side they had when it was taken.
    @State private var measuredContent: (height: CGFloat, side: CGFloat)?
    @State private var measuredBottom: CGFloat?
    /// The live height of the pinned cluster, unlike `measuredBottom`, which a frozen side stops updating.
    @State private var pinnedHeight: CGFloat = 0

    var body: some View {
        GeometryReader { proxy in
            if DrawAndGuessMetrics.isWide(proxy.size) {
                wide(side: DrawAndGuessMetrics.squareSide(in: proxy.size))
            } else {
                narrow(size: proxy.size)
            }
        }
    }

    private func narrowSide(in size: CGSize) -> CGFloat {
        var side = DrawAndGuessMetrics.squareSide(in: size)
        if let measuredContent, let measuredBottom {
            side = DrawAndGuessMetrics.fittedSide(
                in: size,
                measuredSide: measuredContent.side,
                contentHeight: measuredContent.height,
                bottomHeight: measuredBottom
            )
        }
        if sharing == .inherits, let shared = sideMemory?.side {
            side = min(side, max(DrawAndGuessMetrics.minSquare, shared))
        }
        return side
    }

    /// Takes the rows' heights, unless a result is growing them.
    private func take(contentHeight: CGFloat, side: CGFloat) {
        guard !(freezesSide && measuredContent != nil && measuredBottom != nil) else { return }
        if measuredContent?.height != contentHeight || measuredContent?.side != side {
            measuredContent = (contentHeight, side)
        }
    }

    private func take(bottomHeight: CGFloat) {
        guard !(freezesSide && measuredContent != nil && measuredBottom != nil) else { return }
        if measuredBottom != bottomHeight {
            measuredBottom = bottomHeight
        }
    }

    private func narrow(size: CGSize) -> some View {
        let side = narrowSide(in: size)
        return ScrollViewReader { reader in
            ScrollView {
                VStack(spacing: PaeoniaSpacing.space12) {
                    header
                    square(side)
                    footer
                    Color.clear.frame(height: 1).id("end")
                }
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
                    take(contentHeight: height, side: side)
                }
                .padding(.horizontal, PaeoniaSpacing.screenHorizontalPadding)
                .padding(.top, PaeoniaSpacing.space8)
                .padding(.bottom, PaeoniaSpacing.space16)
                .paeoniaReadableWidth()
            }
            .scrollBounceBehavior(.basedOnSize)
            .onChange(of: scrollTrigger) {
                withAnimation(PaeoniaMotion.meaningfulMoment) { reader.scrollTo("end", anchor: .bottom) }
            }
            // A result row can grow the pinned cluster after the scroll above ran
            // (the save button joins it), which would hide the last rows again.
            .onChange(of: pinnedHeight) {
                guard scrollTrigger > 0 else { return }
                withAnimation(PaeoniaMotion.meaningfulMoment) { reader.scrollTo("end", anchor: .bottom) }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            pinnedBottom
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
                    pinnedHeight = height
                    take(bottomHeight: height)
                }
        }
        .onChange(of: side, initial: true) { _, newSide in
            if sharing == .publishes { sideMemory?.side = newSide }
        }
    }

    private func wide(side: CGFloat) -> some View {
        HStack(alignment: .center, spacing: PaeoniaSpacing.space32) {
            square(side)
                .frame(width: side, height: side)
            VStack(spacing: 0) {
                ScrollView {
                    VStack(spacing: PaeoniaSpacing.space12) {
                        header
                        footer
                    }
                    .padding(.vertical, PaeoniaSpacing.space8)
                }
                .scrollBounceBehavior(.basedOnSize)
                pinnedBottomContent
                    .padding(.vertical, PaeoniaSpacing.space12)
            }
            .frame(width: DrawAndGuessMetrics.sideColumnWidth)
        }
        .padding(.horizontal, PaeoniaSpacing.screenHorizontalPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var pinnedBottom: some View {
        pinnedBottomContent
            .padding(.horizontal, PaeoniaSpacing.screenHorizontalPadding)
            .padding(.top, PaeoniaSpacing.space8)
            .padding(.bottom, PaeoniaSpacing.space8)
            .paeoniaReadableWidth()
            .background(.paeoniaBackgroundSecondary)
    }

    private var pinnedBottomContent: some View {
        VStack(spacing: PaeoniaSpacing.space12) {
            bottom
        }
    }
}

extension DrawAndGuessPhaseLayout where Footer == EmptyView {
    init(
        @ViewBuilder header: () -> Header,
        @ViewBuilder square: @escaping (CGFloat) -> Square,
        @ViewBuilder bottom: () -> Bottom
    ) {
        self.init(
            header: header,
            square: square,
            footer: { EmptyView() },
            bottom: bottom
        )
    }
}

/// A phase without the square: choose a word, waiting, status. One column at the
/// focused width, with the bottom cluster pinned.
struct DrawAndGuessFocusedLayout<Content: View, Bottom: View>: View {
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

extension DrawAndGuessFocusedLayout where Bottom == EmptyView {
    init(fillsHeight: Bool = false, @ViewBuilder content: () -> Content) {
        self.init(fillsHeight: fillsHeight, content: content, bottom: { EmptyView() })
    }
}
