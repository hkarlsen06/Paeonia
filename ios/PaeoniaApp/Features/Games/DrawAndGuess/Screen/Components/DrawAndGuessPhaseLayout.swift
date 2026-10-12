import SwiftUI

/// How big the square is, so a phase never resizes it. The width decides, and a
/// fixed budget for the rows around it keeps it on screen.
enum DrawAndGuessMetrics {
    /// The square never grows past this, so strokes keep their weight.
    static let maxSquare: CGFloat = 640
    /// The widest the right column grows in the wide layout.
    static let sideColumnWidth: CGFloat = 420
    /// Height kept for the rows above and below the square on a phone.
    static let reservedHeight: CGFloat = 340
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
        return max(200, min(maxSquare, size.width - padding, byHeight))
    }
}

/// A phase with the drawing square. Narrow screens scroll one column with the
/// bottom cluster pinned. Wide screens put the square on the left and everything
/// else in a column on the right.
struct DrawAndGuessPhaseLayout<Header: View, Square: View, Footer: View, Bottom: View>: View {
    /// Scrolls to the end when this number goes up, so new rows of a result are seen.
    var scrollTrigger = 0
    @ViewBuilder var header: Header
    @ViewBuilder var square: (CGFloat) -> Square
    @ViewBuilder var footer: Footer
    @ViewBuilder var bottom: Bottom

    var body: some View {
        GeometryReader { proxy in
            let side = DrawAndGuessMetrics.squareSide(in: proxy.size)
            if DrawAndGuessMetrics.isWide(proxy.size) {
                wide(side: side)
            } else {
                narrow(side: side)
            }
        }
    }

    private func narrow(side: CGFloat) -> some View {
        ScrollViewReader { reader in
            ScrollView {
                VStack(spacing: PaeoniaSpacing.space12) {
                    header
                    square(side)
                    footer
                    Color.clear.frame(height: 1).id("end")
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
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            pinnedBottom
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
