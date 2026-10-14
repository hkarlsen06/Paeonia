import SwiftUI

/// The column every Mind Meld phase sits in: content that scrolls at one width,
/// and a bar of buttons pinned at the bottom. `paeoniaBottomBar` lets the
/// keyboard cover the bar instead of lifting it. A bar whose button belongs to
/// the field, like Lock in, rides above the keyboard instead.
struct MindMeldPhaseLayout<Content: View, Bottom: View>: View {
    /// The content grows to the height the bar leaves, so it can center itself
    /// with spacers. It still scrolls when it is taller.
    var fillsHeight = false
    var contentWidth = PaeoniaSpacing.focusedContentWidth
    var barRidesKeyboard = false
    @ViewBuilder var content: Content
    @ViewBuilder var bottom: Bottom

    @State private var barHeight: CGFloat = 0

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                content
                    .padding(.horizontal, PaeoniaSpacing.screenHorizontalPadding)
                    .padding(.vertical, PaeoniaSpacing.space16)
                    .frame(minHeight: fillsHeight ? max(0, proxy.size.height - barHeight) : 0, alignment: .top)
                    .paeoniaReadableWidth(contentWidth)
            }
            .scrollBounceBehavior(.basedOnSize)
            .scrollDismissesKeyboard(.interactively)
            .modifier(BottomBar(ridesKeyboard: barRidesKeyboard) { bar })
        }
    }

    private var bar: some View {
        VStack(spacing: PaeoniaSpacing.space12) {
            bottom
        }
        .padding(.horizontal, PaeoniaSpacing.screenHorizontalPadding)
        .padding(.vertical, PaeoniaSpacing.space8)
        .paeoniaReadableWidth(PaeoniaSpacing.focusedContentWidth)
        .background(.paeoniaBackgroundSecondary)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { barHeight = $0 }
    }
}

private struct BottomBar<Bar: View>: ViewModifier {
    let ridesKeyboard: Bool
    @ViewBuilder let bar: () -> Bar

    func body(content: Content) -> some View {
        if ridesKeyboard {
            content.safeAreaInset(edge: .bottom, spacing: 0) { bar() }
        } else {
            content.paeoniaBottomBar { bar() }
        }
    }
}

extension MindMeldPhaseLayout where Bottom == EmptyView {
    init(
        fillsHeight: Bool = false,
        contentWidth: CGFloat = PaeoniaSpacing.focusedContentWidth,
        @ViewBuilder content: () -> Content
    ) {
        self.init(fillsHeight: fillsHeight, contentWidth: contentWidth, content: content, bottom: { EmptyView() })
    }
}
