import SwiftUI

/// Space occupied around the portrait's center, including its note, frame and action.
nonisolated struct StoryMarkerMeasurements: Equatable, Sendable {
    var above: CGFloat = 0
    var below: CGFloat = 0
    var halfWidth: CGFloat = 0

    init() {}

    init(content: CGRect, portrait: CGRect) {
        above = portrait.midY - content.minY
        below = content.maxY - portrait.midY
        halfWidth = max(portrait.midX - content.minX, content.maxX - portrait.midX)
    }

    init(anchors: [StoryMarkerPart: Anchor<CGRect>], geometry: GeometryProxy) {
        self.init()
        for (content, portrait) in [
            (StoryMarkerPart.ownContent, StoryMarkerPart.ownPortrait),
            (.partnerContent, .partnerPortrait),
        ] {
            if let content = anchors[content], let portrait = anchors[portrait] {
                include(Self(content: geometry[content], portrait: geometry[portrait]))
            }
        }
    }

    mutating func include(_ other: Self) {
        above = max(above, other.above)
        below = max(below, other.below)
        halfWidth = max(halfWidth, other.halfWidth)
    }
}

nonisolated enum StoryMarkerPart: Hashable {
    case ownContent, ownPortrait, partnerContent, partnerPortrait
}

struct StoryMarkerAnchors: PreferenceKey {
    static var defaultValue: [StoryMarkerPart: Anchor<CGRect>] { [:] }

    static func reduce(
        value: inout [StoryMarkerPart: Anchor<CGRect>],
        nextValue: () -> [StoryMarkerPart: Anchor<CGRect>]
    ) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

extension View {
    func storyMarkerPart(_ part: StoryMarkerPart) -> some View {
        transformAnchorPreference(key: StoryMarkerAnchors.self, value: .bounds) { anchors, anchor in
            anchors[part] = anchor
        }
    }

    func measureStoryMarkers(_ onChange: @escaping (StoryMarkerMeasurements) -> Void) -> some View {
        backgroundPreferenceValue(StoryMarkerAnchors.self) { anchors in
            GeometryReader { geometry in
                let measurements = StoryMarkerMeasurements(anchors: anchors, geometry: geometry)
                Color.clear
                    .onChange(of: measurements, initial: true) { _, measurements in
                        onChange(measurements)
                    }
            }
        }
    }
}
