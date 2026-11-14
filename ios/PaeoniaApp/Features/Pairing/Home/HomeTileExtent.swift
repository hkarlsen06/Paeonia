import SwiftUI

/// How far across the Us tab's tile pictures reach: from the calendar's left edge to the
/// drawing's right edge, in `HomeTileExtent.space`. On the map layout the envelope and the
/// words of today's question narrow to it, so they are no wider than the tiles under them.
nonisolated struct HomeTileExtent: Equatable {
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

    /// Narrows this view to the tile pictures' edges where `sharesHomeTileExtent` hands them
    /// down. Elsewhere it keeps its width.
    func narrowsToHomeTiles() -> some View {
        modifier(HomeTileNarrowing())
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

private struct HomeTileNarrowing: ViewModifier {
    @Environment(\.homeTileExtent) private var extent
    /// This view's frame in `HomeTileExtent.space` before it narrows. The insets sit inside
    /// the measured frame, so narrowing doesn't change what is measured.
    @State private var frame: CGRect?

    func body(content: Content) -> some View {
        let insets = if let extent, let frame { extent.insets(for: frame) } else { (leading: 0.0, trailing: 0.0) }
        content
            .padding(.leading, insets.leading)
            .padding(.trailing, insets.trailing)
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(HomeTileExtent.space)) } action: {
                frame = $0
            }
    }
}
