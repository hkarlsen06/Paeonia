import SwiftUI

/// The region the flame front has NOT yet reached: everything from the advancing,
/// angled front to the trailing edge. Masks the burning cover, so at `progress` 1 this
/// region is empty and the cover is fully gone. Animatable so the mask recedes in step
/// with the flame line.
struct UnsweptRegionShape: Shape {
    var progress: CGFloat
    let tilt: CGFloat

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let (topX, bottomX) = SweepFront.edges(in: rect, progress: progress, tilt: tilt)
        // Anchor the right side a full width past the trailing edge, NOT relative to the
        // front. At the start the front sits off the leading edge (a negative x), so a
        // front-relative right edge would fall short of the card's right edge and leave a
        // sliver of map uncovered there. Pinning it past `maxX` keeps the un-swept region
        // covering the whole card-to-the-right at every step.
        let rightEdge = rect.maxX + rect.width

        var path = Path()
        path.move(to: CGPoint(x: topX, y: rect.minY))
        path.addLine(to: CGPoint(x: rightEdge, y: rect.minY))
        path.addLine(to: CGPoint(x: rightEdge, y: rect.maxY))
        path.addLine(to: CGPoint(x: bottomX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

/// The region the flame front HAS reached: everything from the leading edge to the
/// advancing front. Masks the incoming map, so at `progress` 0 the incoming map is
/// fully hidden and cannot flash before the sweep starts.
struct SweptRegionShape: Shape {
    var progress: CGFloat
    let tilt: CGFloat

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let (topX, bottomX) = SweepFront.edges(in: rect, progress: progress, tilt: tilt)
        let leftEdge = rect.minX - rect.width

        var path = Path()
        path.move(to: CGPoint(x: leftEdge, y: rect.minY))
        path.addLine(to: CGPoint(x: topX, y: rect.minY))
        path.addLine(to: CGPoint(x: bottomX, y: rect.maxY))
        path.addLine(to: CGPoint(x: leftEdge, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

/// The glowing pink line at the sweep front: three layered strokes (a soft outer bloom,
/// a brighter inner glow, and a crisp core), all in the brand pink and full-strength the
/// whole length, so it reads as one uniformly thick, glowing streak.
struct FlameSweepLine: View {
    var progress: CGFloat
    let tilt: CGFloat

    var body: some View {
        ZStack {
            FlameFrontShape(progress: progress, tilt: tilt)
                .stroke(outerGlow, style: StrokeStyle(lineWidth: 18, lineCap: .round))
                .blur(radius: 10)
                .blendMode(.screen)

            FlameFrontShape(progress: progress, tilt: tilt)
                .stroke(innerGlow, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                .blur(radius: 2.5)
                .blendMode(.screen)

            FlameFrontShape(progress: progress, tilt: tilt)
                .stroke(core, style: StrokeStyle(lineWidth: 2, lineCap: .round))
        }
    }

    // A glowing line in the brand pink: a deeper-pink halo (paeoniaAccentSecondary)
    // around the CTA pink (paeoniaAccentPrimary) core. Solid, full-strength colour the
    // whole length so the line reads as one uniformly thick pink streak. The layered
    // blur and screen blend give the glow, not a gradient.
    private var outerGlow: Color { .paeoniaAccentSecondary }
    private var innerGlow: Color { .paeoniaAccentPrimary }
    private var core: Color { .paeoniaAccentPrimary }
}

/// The bare line at the sweep front, drawn slightly past the top and bottom edges so
/// the flame's round caps stay out of frame. Animatable so it rides the sweep.
struct FlameFrontShape: Shape {
    var progress: CGFloat
    let tilt: CGFloat

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let (topX, bottomX) = SweepFront.edges(in: rect, progress: progress, tilt: tilt)
        var path = Path()
        path.move(to: CGPoint(x: topX, y: rect.minY - 8))
        path.addLine(to: CGPoint(x: bottomX, y: rect.maxY + 8))
        return path
    }
}

/// Shared geometry for the sweep front so the mask and the flame line always agree on
/// where the advancing, tilted line sits for a given progress.
enum SweepFront {
    /// How far the flame's glow spreads beyond the bright line (outer stroke half-width
    /// plus its blur). The front starts and ends this far *past* each edge so the glow
    /// halo never bleeds onto the card before the line has actually swept in (or after it
    /// has left). It's only at the edge that the front carries a visible glow.
    static let glowMargin: CGFloat = 30

    /// The x of the front where it meets the top and bottom edges. At `progress` 0 the
    /// tilted line, and its full glow, sits just past the leading edge, so the cover
    /// fully covers the tile and nothing glows onto it. At `progress` 1 it sits just past
    /// the trailing edge, fully gone. Travel spans `width + slant` plus a `glowMargin` of
    /// off-tile run at each end so the glow clears the card cleanly without the line
    /// wandering far enough to leave a dead stretch mid-card.
    static func edges(in rect: CGRect, progress: CGFloat, tilt: CGFloat) -> (top: CGFloat, bottom: CGFloat) {
        let slant = rect.height * tan(tilt)
        let startCenter = rect.minX - slant / 2 - glowMargin
        let travel = rect.width + slant + glowMargin * 2
        let center = startCenter + progress * travel
        return (top: center + slant / 2, bottom: center - slant / 2)
    }
}
