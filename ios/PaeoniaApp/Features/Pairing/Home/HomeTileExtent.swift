import SwiftUI

/// How far across the Us tab's tile pictures reach: from the calendar's left edge to the
/// drawing's right edge, in `HomeTileExtent.space`. On the map layout the waiting question
/// row narrows to it, so it is no wider than the tiles under it.
struct HomeTileExtent: Equatable {
    static let space = "homeTiles"

    var minX: CGFloat
    var maxX: CGFloat

    /// How far a view with this frame in `space` must be inset on each side to fit.
    func insets(for frame: CGRect) -> (leading: CGFloat, trailing: CGFloat) {
        (max(0, minX - frame.minX), max(0, frame.maxX - maxX))
    }
}

enum HomeTileExtentKey: PreferenceKey {
    static let defaultValue: HomeTileExtent? = nil

    static func reduce(value: inout HomeTileExtent?, nextValue: () -> HomeTileExtent?) {
        guard let next = nextValue() else { return }
        value = value.map { HomeTileExtent(minX: min($0.minX, next.minX), maxX: max($0.maxX, next.maxX)) } ?? next
    }
}

extension EnvironmentValues {
    /// Set on the map layout's cards. Nil elsewhere, where nothing narrows to the tiles.
    @Entry var homeTileExtent: HomeTileExtent?
}

extension View {
    /// Reports this tile picture's edges to `HomeTileExtentKey`.
    func homeTilePicture() -> some View {
        background {
            GeometryReader { proxy in
                let frame = proxy.frame(in: .named(HomeTileExtent.space))
                Color.clear.preference(
                    key: HomeTileExtentKey.self, value: HomeTileExtent(minX: frame.minX, maxX: frame.maxX)
                )
            }
        }
    }

    /// Hands the tile pictures' edges inside this view to the views around them.
    func sharesHomeTileExtent() -> some View {
        modifier(HomeTileExtentSharing())
    }
}

private struct HomeTileExtentSharing: ViewModifier {
    @State private var extent: HomeTileExtent?

    func body(content: Content) -> some View {
        content
            .environment(\.homeTileExtent, extent)
            .onPreferenceChange(HomeTileExtentKey.self) { extent = $0 }
            .coordinateSpace(.named(HomeTileExtent.space))
    }
}
