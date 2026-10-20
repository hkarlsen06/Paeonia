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
    @State private var paneSpace = CGSize.zero

    var body: some View {
        VStack(spacing: PaeoniaSpacing.space12) {
            header
            Group {
                if isWide {
                    HStack(spacing: PaeoniaSpacing.space12) {
                        pane { photo }
                            .frame(width: photoLength(of: paneSpace.width))
                        pane { map }
                    }
                } else {
                    VStack(spacing: PaeoniaSpacing.space12) {
                        pane { photo }
                            .frame(height: photoLength(of: paneSpace.height))
                        pane { map }
                    }
                }
            }
            .frame(maxHeight: .infinity)
            .onGeometryChange(for: CGSize.self) { $0.size } action: { paneSpace = $0 }
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

    /// Nil until the room is measured, so the first pass splits it evenly.
    private func photoLength(of total: CGFloat) -> CGFloat? {
        guard total > 0 else { return nil }
        return max(0, (total - PaeoniaSpacing.space12) * photoShare)
    }

    private func pane(@ViewBuilder _ content: () -> some View) -> some View {
        content()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.paeoniaSurfacePrimary)
            .clipShape(RoundedRectangle(cornerRadius: PaeoniaRadius.radius16, style: .continuous))
    }
}
