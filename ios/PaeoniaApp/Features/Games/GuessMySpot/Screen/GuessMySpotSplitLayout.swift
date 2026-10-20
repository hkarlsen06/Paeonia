import SwiftUI

/// The photo on the top half and the map on the bottom half, or side by side on a
/// wide screen, with text above and under them and a pinned button bar. Nothing
/// here scrolls, so the map's pan and pinch never fight a scroll view. Larger text
/// takes its room from the photo and the map. `photoShare` is the photo's part of
/// that room, so a screen whose photo the person already knows can give the map more.
struct GuessMySpotSplitLayout<Header: View, Photo: View, MapPane: View, Footer: View, Bottom: View>: View {
    var photoShare: CGFloat = 0.5
    @ViewBuilder var header: Header
    @ViewBuilder var photo: Photo
    @ViewBuilder var map: MapPane
    @ViewBuilder var footer: Footer
    @ViewBuilder var bottom: Bottom

    @State private var isWide = false

    var body: some View {
        VStack(spacing: PaeoniaSpacing.space12) {
            header
            // Read in the same pass that lays out the panes, so the photo never
            // starts at half and then shrinks.
            GeometryReader { proxy in
                let spacing = PaeoniaSpacing.space12
                if isWide {
                    HStack(spacing: spacing) {
                        pane { photo }
                            .frame(width: max(0, proxy.size.width - spacing) * photoShare)
                        pane { map }
                    }
                } else {
                    VStack(spacing: spacing) {
                        pane { photo }
                            .frame(height: max(0, proxy.size.height - spacing) * photoShare)
                        pane { map }
                    }
                }
            }
            footer
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, PaeoniaSpacing.screenHorizontalPadding)
        .padding(.top, PaeoniaSpacing.space8)
        .padding(.bottom, PaeoniaSpacing.space4)
        .onGeometryChange(for: Bool.self) { proxy in
            proxy.size.width >= 700 && proxy.size.width > proxy.size.height
        } action: { isWide = $0 }
        .paeoniaBottomBar(spacing: 0) {
            VStack(spacing: PaeoniaSpacing.space12) {
                bottom
            }
            .padding(.horizontal, PaeoniaSpacing.screenHorizontalPadding)
            .padding(.vertical, PaeoniaSpacing.space8)
            .paeoniaReadableWidth(PaeoniaSpacing.focusedContentWidth)
            .background(.paeoniaBackgroundSecondary)
        }
    }

    private func pane(@ViewBuilder _ content: () -> some View) -> some View {
        content()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.paeoniaSurfacePrimary)
            .clipShape(RoundedRectangle(cornerRadius: PaeoniaRadius.radius16, style: .continuous))
    }
}
