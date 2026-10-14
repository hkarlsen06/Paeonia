import SwiftUI

/// Where the figure sits in the stage and how big it is, for each shot of the
/// reveal. Pure sizes, so tests can read them.
///
/// The figure is laid out once, at `layoutSide` per part, and the camera scales
/// and moves it. A part is never drawn bigger than it was laid out, so strokes
/// stay crisp. The whole figure is the smallest shot.
struct ExquisiteCorpseRevealCamera: Equatable {
    enum Shot: Equatable {
        /// The whole figure, centered.
        case overview
        /// One part, big, with the parts before it sliding up out of view.
        case framing(ExquisiteCorpsePartKind)
    }

    /// Where the camera puts the figure: scale first, then move.
    struct Placement: Equatable {
        /// The factor from `layoutSide`.
        var scale: CGFloat
        /// Where the figure's top leading corner lands in the stage.
        var origin: CGPoint
    }

    /// How much of the height a part may take while it plays.
    static let framedShare: CGFloat = 0.55
    /// Room kept above and below the figure.
    static let margin: CGFloat = PaeoniaSpacing.space8

    /// The space the figure and the caption share. It can be taller than the screen,
    /// when the text under the figure makes the reveal scroll.
    let stage: CGSize
    /// The part of the stage's top where the whole figure sits. The title and the
    /// credits take the rest.
    let overviewHeight: CGFloat
    /// The height of the screen. The 55% rule works from it, and a framed part
    /// sits in the middle of it.
    let viewportHeight: CGFloat
    /// The height under a playing part, kept for the caption.
    let captionHeight: CGFloat

    private var partCount: CGFloat { CGFloat(ExquisiteCorpsePartKind.allCases.count) }

    /// The height a framed part and its caption share.
    private var framingHeight: CGFloat {
        min(stage.height, viewportHeight)
    }

    /// The side of a part when the whole figure shows: the smaller of the width and
    /// a third of the height.
    var fitSide: CGFloat {
        max(1, min(stage.width, (overviewHeight - Self.margin * 2) / partCount))
    }

    /// The side of a part while it plays: up to 55% of the screen's height, never
    /// wider than the stage, and never so tall that the caption has no room.
    var layoutSide: CGFloat {
        let framed = min(
            stage.width,
            viewportHeight * Self.framedShare,
            framingHeight - captionHeight - Self.margin * 2
        )
        return max(fitSide, framed)
    }

    /// The scale of the whole-figure shot.
    var overviewScale: CGFloat {
        fitSide / layoutSide
    }

    /// The top of a framed part. The part and its caption sit in the middle of the screen.
    private var framedTop: CGFloat {
        max(0, (framingHeight - captionHeight - layoutSide) / 2)
    }

    func placement(for shot: Shot) -> Placement {
        switch shot {
        case .overview:
            Placement(
                scale: overviewScale,
                origin: CGPoint(x: (stage.width - fitSide) / 2, y: (overviewHeight - fitSide * partCount) / 2)
            )
        case let .framing(part):
            Placement(
                scale: 1,
                origin: CGPoint(
                    x: (stage.width - layoutSide) / 2,
                    y: framedTop - CGFloat(part.rawValue) * layoutSide
                )
            )
        }
    }

    /// How much of the stage's height shows the figure. A framed part hides what
    /// comes after it, so the caption sits on empty space.
    func visibleHeight(for shot: Shot) -> CGFloat {
        switch shot {
        case .overview: stage.height
        case .framing: min(stage.height, framedTop + layoutSide)
        }
    }

    /// Where the caption zone starts: the bottom edge of a framed part.
    var captionTop: CGFloat {
        visibleHeight(for: .framing(.head))
    }

    /// The space under a framed part, down to the bottom of the screen.
    var captionZone: CGFloat {
        framingHeight - captionTop
    }

    /// The thickness that draws a 2 pt line between parts when the whole figure
    /// shows, in the figure's own units.
    var hairline: CGFloat {
        2 / overviewScale
    }
}
