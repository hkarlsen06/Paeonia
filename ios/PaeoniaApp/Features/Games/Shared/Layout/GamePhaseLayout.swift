import SwiftUI

/// A phase with the drawing square. Narrow screens scroll one column with the
/// bottom cluster pinned. Wide screens put the square on the left and everything
/// else in a column on the right.
///
/// On a phone the square fills the height the other rows leave. The layout
/// measures them once the rows exist, so every row and text size counts.
struct GamePhaseLayout<Header: View, Square: View, Footer: View, Bottom: View>: View {
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
    var sideMemory: GameSideMemory?
    /// The square content's height divided by its side. It is 1 for a plain
    /// square. A game that shows a strip above its canvas passes more than 1, so
    /// the strip and the canvas fit the height together.
    var squareHeightRatio: CGFloat = 1
    @ViewBuilder var header: Header
    @ViewBuilder var square: (CGFloat) -> Square
    @ViewBuilder var footer: Footer
    @ViewBuilder var bottom: Bottom

    /// The scrolling rows' height and the side they had when it was taken.
    @State private var measuredContent: (height: CGFloat, side: CGFloat)?
    @State private var measuredBottom: CGFloat?
    /// The live height of the pinned cluster, unlike `measuredBottom`, which a frozen side stops updating.
    @State private var pinnedHeight: CGFloat = 0
    /// The live height of the scrolling rows. A result row can get its height a few
    /// layout passes after it appears, so the layout scrolls again when it grows.
    @State private var contentHeight: CGFloat = 0
    @State private var scrollPosition = ScrollPosition(edge: .top)
    @State private var scrollTask: Task<Void, Never>?
    @State private var wideBottomHeight: CGFloat = 0
    /// The height of the scrolling rows in the wide layout.
    @State private var wideContentHeight: CGFloat = 0
    /// The square's height as drawn in the wide layout. A result shows it smaller
    /// than `side`, and the column matches what is on screen.
    @State private var wideSquareHeight: CGFloat?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { proxy in
            if GameMetrics.isWide(proxy.size) {
                wide(
                    side: GameMetrics.squareSide(in: proxy.size, heightRatio: squareHeightRatio),
                    height: proxy.size.height
                )
            } else {
                narrow(size: proxy.size)
            }
        }
    }

    private func narrowSide(in size: CGSize) -> CGFloat {
        var side = GameMetrics.squareSide(in: size, heightRatio: squareHeightRatio)
        if let measuredContent, let measuredBottom {
            side = GameMetrics.fittedSide(
                in: size,
                measuredSide: measuredContent.side,
                contentHeight: measuredContent.height,
                bottomHeight: measuredBottom,
                heightRatio: squareHeightRatio
            )
        }
        if sharing == .inherits, let shared = sideMemory?.side {
            side = min(side, max(GameMetrics.minSquare, shared))
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

    /// Scrolls to the last row one layout pass later, because a row that appears in
    /// the same update has no height yet. It scrolls again once the row's entrance
    /// has settled, because the scroll view can drop a scroll asked for while a
    /// spring in its content still runs. The second scroll does nothing when the
    /// first one landed.
    private func scrollToEnd() {
        scrollTask?.cancel()
        scrollTask = Task { @MainActor in
            await Task.yield()
            scrollToBottom()
            try? await Task.sleep(for: .seconds(PaeoniaMotion.motionCelebration))
            guard !Task.isCancelled else { return }
            scrollToBottom()
        }
    }

    private func scrollToBottom() {
        if reduceMotion {
            scrollPosition.scrollTo(edge: .bottom)
        } else {
            withAnimation(PaeoniaMotion.meaningfulMoment) { scrollPosition.scrollTo(edge: .bottom) }
        }
    }

    private func narrow(size: CGSize) -> some View {
        let side = narrowSide(in: size)
        return ScrollView {
            VStack(spacing: PaeoniaSpacing.space12) {
                header
                square(side)
                footer
            }
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
                contentHeight = height
                take(contentHeight: height, side: side)
            }
            .padding(.horizontal, PaeoniaSpacing.screenHorizontalPadding)
            .padding(.top, PaeoniaSpacing.space8)
            .padding(.bottom, PaeoniaSpacing.space16)
            .paeoniaReadableWidth()
        }
        .scrollPosition($scrollPosition)
        .scrollBounceBehavior(.basedOnSize)
        .onChange(of: scrollTrigger) { scrollToEnd() }
        .onChange(of: contentHeight) {
            guard scrollTrigger > 0 else { return }
            scrollToEnd()
        }
        // The main button joins the pinned cluster after the last result row,
        // which would cover that row again.
        .onChange(of: pinnedHeight) {
            guard scrollTrigger > 0 else { return }
            scrollToEnd()
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

    private func wide(side: CGFloat, height: CGFloat) -> some View {
        // A tall cluster, such as four rows of tiles on a landscape phone, would
        // leave the rows above it no room. It then scrolls with them.
        let scrollsBottom = wideBottomHeight > height * 0.55
        // The column is as tall as the square, so its rows line up with the square's
        // edges. It grows toward the full height only when the rows need more room.
        let rowsHeight = wideContentHeight + (scrollsBottom ? 0 : wideBottomHeight)
        let squareHeight = side * squareHeightRatio
        let columnHeight = min(height, max(wideSquareHeight ?? squareHeight, rowsHeight))
        return HStack(alignment: .center, spacing: PaeoniaSpacing.space32) {
            square(side)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { wideSquareHeight = $0 }
                .frame(width: side, height: squareHeight)
            VStack(spacing: 0) {
                ScrollView {
                    VStack(spacing: PaeoniaSpacing.space12) {
                        header
                        footer
                        if scrollsBottom {
                            measuredWideBottom
                        }
                    }
                    .padding(.vertical, PaeoniaSpacing.space8)
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { wideContentHeight = $0 }
                }
                .scrollBounceBehavior(.basedOnSize)
                if !scrollsBottom {
                    measuredWideBottom
                }
            }
            .frame(width: GameMetrics.sideColumnWidth, height: columnHeight)
            // Moves with the square when a result shrinks it.
            .animation(reduceMotion ? nil : PaeoniaMotion.meaningfulMoment, value: columnHeight)
        }
        .padding(.horizontal, PaeoniaSpacing.screenHorizontalPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var measuredWideBottom: some View {
        pinnedBottomContent
            .padding(.vertical, PaeoniaSpacing.space12)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { wideBottomHeight = $0 }
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

extension GamePhaseLayout where Footer == EmptyView {
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
