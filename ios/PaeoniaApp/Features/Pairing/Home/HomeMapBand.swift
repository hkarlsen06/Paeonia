import SwiftUI

/// Gives the map and its overlays the height being displayed while the cards resize.
struct HomeMapBand<Content: View>: View {
    @ViewBuilder var content: (CGFloat) -> Content

    var body: some View {
        GeometryReader { geometry in
            AnimatedBand(height: geometry.size.height, content: content)
        }
    }

    private struct AnimatedBand: View, Animatable {
        var height: CGFloat
        var content: (CGFloat) -> Content

        var animatableData: CGFloat {
            get { height }
            set { height = newValue }
        }

        var body: some View {
            content(height)
                // Positions already follow the interpolated height and the map's camera.
                // A second animation here would make the avatars lag behind them.
                .transaction { $0.animation = nil }
        }
    }
}
