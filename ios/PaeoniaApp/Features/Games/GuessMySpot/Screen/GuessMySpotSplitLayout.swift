import SwiftUI

/// The photo on the top half and the map on the bottom half, or side by side on a
/// wide screen, with text above and under them and a pinned button bar. Nothing
/// here scrolls, so the map's pan and pinch never fight a scroll view. Larger text
/// takes its room from the photo and the map.
struct GuessMySpotSplitLayout<Header: View, Photo: View, MapPane: View, Footer: View, Bottom: View>: View {
    @ViewBuilder var header: Header
    @ViewBuilder var photo: Photo
    @ViewBuilder var map: MapPane
    @ViewBuilder var footer: Footer
    @ViewBuilder var bottom: Bottom

    @State private var isWide = false

    var body: some View {
        VStack(spacing: PaeoniaSpacing.space12) {
            header
            Group {
                if isWide {
                    HStack(spacing: PaeoniaSpacing.space12) {
                        pane { photo }
                        pane { map }
                    }
                } else {
                    VStack(spacing: PaeoniaSpacing.space12) {
                        pane { photo }
                        pane { map }
                    }
                }
            }
            .frame(maxHeight: .infinity)
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
