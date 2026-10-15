import CoreGraphics
import CoreImage
import Foundation
import simd

/// The painted top of the board: one glazed slab with the whole layout painted on it,
/// and grooves carved round every square, yard, pawn spot and the middle. The glaze
/// pools darker in the grooves, as on real carved ceramic. It makes two pictures: the
/// colors, and the bumps of the grooves for the light.
///
/// Pictures cover the board top from -`half` to `half` cells on x and z. The top row
/// of a picture is the far edge (negative z). Pure drawing, so it runs off the main actor.
nonisolated enum LudoBoardArt {
    /// The colors of one fixed-frame corner.
    struct Corner: @unchecked Sendable {
        /// The start square.
        let color: CGColor
        /// The home column and the yard.
        let light: CGColor
        /// The round spots where pawns wait. Nil for a corner nobody plays.
        let spot: CGColor?
    }

    struct Palette: @unchecked Sendable {
        let base: CGColor
        let track: CGColor
        /// By fixed-frame corner, 0 to 3.
        let corners: [Corner]
        /// The halves of the middle: mine on the near side, my partner's on the far side.
        let homeNear: CGColor
        let homeFar: CGColor
        /// The peony on the safe squares, and the glaze grain laid over everything.
        let peony: CGImage?
        let grain: CGImage?
    }

    struct Pictures: @unchecked Sendable {
        let color: CGImage
        /// Nil when it was not asked for. The grooves are the same for both players and
        /// every color, so one bump picture serves every board.
        let bumps: CGImage?
    }

    /// Half the width of the pictures, in cells.
    static var half: Float { LudoWorld.halfSlab - LudoSceneStyle.slabEdgeRadius }

    static func paint(viewer: BoardPlayer, palette: Palette, makesBumps: Bool = true) -> Pictures? {
        guard let grooves = grooveHeights(viewer: viewer),
              let color = colors(viewer: viewer, palette: palette, grooves: grooves)
        else { return nil }
        return Pictures(color: color, bumps: makesBumps ? bumps(from: grooves) : nil)
    }

    // MARK: Layout

    private static let cellHalf = 0.5

    static func center(_ point: LudoGridPoint) -> CGPoint {
        let position = LudoWorld.position(point)
        return CGPoint(x: Double(position.x), y: Double(position.z))
    }

    private static func cell(_ point: LudoGridPoint) -> CGRect {
        let middle = center(point)
        return CGRect(x: middle.x - cellHalf, y: middle.y - cellHalf, width: 1, height: 1)
    }

    /// A track or home column square, with the corner it belongs to when it is colored.
    struct Square {
        let rect: CGRect
        let corner: Int?
        let isStart: Bool
    }

    static func squares(viewer: BoardPlayer) -> [Square] {
        var result = (0..<LudoBoard.trackLength).map { index in
            let isStart = index % LudoBoardGeometry.squaresPerQuarter == 0
            let corner = index / LudoBoardGeometry.squaresPerQuarter
            let point = LudoBoardGeometry.point(of: .track(index), viewer: viewer)
            return Square(rect: cell(point), corner: isStart ? corner : nil, isStart: isStart)
        }
        for corner in 0..<4 {
            for step in 1...5 {
                let point = LudoBoardGeometry.columnPoint(corner: corner, step: step, viewer: viewer)
                result.append(Square(rect: cell(point), corner: corner, isStart: false))
            }
        }
        return result
    }

    /// The yard of a corner: its 6 by 6 cells.
    static func yard(corner: Int, viewer: BoardPlayer) -> CGRect {
        let middle = center(LudoBoardGeometry.yardCenter(corner: corner, viewer: viewer))
        return CGRect(x: middle.x - 3, y: middle.y - 3, width: 6, height: 6)
    }

    /// A yard's painted shape: square where it meets the track, round at the board's corner.
    static func yardShape(_ yard: CGRect) -> CGPath {
        let radius = CGFloat(LudoSceneStyle.yardOuterCornerRadius)
        // The outer corner is the one farthest from the middle of the board.
        let outer = CGPoint(x: yard.midX > 0 ? yard.maxX : yard.minX, y: yard.midY > 0 ? yard.maxY : yard.minY)
        let path = CGMutablePath()
        let corners = [
            CGPoint(x: yard.minX, y: yard.minY), CGPoint(x: yard.maxX, y: yard.minY),
            CGPoint(x: yard.maxX, y: yard.maxY), CGPoint(x: yard.minX, y: yard.maxY)
        ]
        // Start halfway along the edge that leads into the first corner, then round each corner in turn.
        path.move(to: CGPoint(x: yard.minX, y: yard.midY))
        for (index, corner) in corners.enumerated() {
            let next = corners[(index + 1) % 4]
            let isOuter = corner == outer
            path.addArc(tangent1End: corner, tangent2End: next, radius: isOuter ? radius : 0)
        }
        path.closeSubpath()
        return path
    }

    /// The carved panel inside a yard.
    static func panel(_ yard: CGRect) -> CGPath {
        let inset = CGFloat(LudoSceneStyle.yardPanelInset)
        let radius = CGFloat(LudoSceneStyle.yardPanelCornerRadius)
        return CGPath(
            roundedRect: yard.insetBy(dx: inset, dy: inset),
            cornerWidth: radius,
            cornerHeight: radius,
            transform: nil
        )
    }

    static func spots(corner: Int, viewer: BoardPlayer) -> [CGRect] {
        let radius = Double(LudoSceneStyle.yardSlotRadius)
        return (0..<LudoBoard.pawnsPerPlayer).map { slot in
            let middle = center(LudoBoardGeometry.slotPoint(corner: corner, slot: slot, viewer: viewer))
            return CGRect(x: middle.x - radius, y: middle.y - radius, width: radius * 2, height: radius * 2)
        }
    }

    static var homeRect: CGRect {
        let radius = Double(LudoSceneStyle.homeDiameter / 2)
        return CGRect(x: -radius, y: -radius, width: radius * 2, height: radius * 2)
    }

    // MARK: Drawing

    /// A context whose units are board cells, with (x, z) of the board as (x, y) and y down.
    static func context(side: Int, gray: Bool) -> CGContext? {
        let space = gray ? CGColorSpace(name: CGColorSpace.linearGray) : CGColorSpace(name: CGColorSpace.sRGB)
        guard let space,
              let context = CGContext(
                  data: nil,
                  width: side,
                  height: side,
                  bitsPerComponent: 8,
                  bytesPerRow: 0,
                  space: space,
                  bitmapInfo: gray ? CGImageAlphaInfo.none.rawValue : CGImageAlphaInfo.noneSkipLast.rawValue
              )
        else { return nil }
        let scale = CGFloat(side) / CGFloat(half * 2)
        context.translateBy(x: 0, y: CGFloat(side))
        context.scaleBy(x: scale, y: -scale)
        context.translateBy(x: CGFloat(half), y: CGFloat(half))
        context.interpolationQuality = .high
        return context
    }

    /// A picture drawn the right way up in a context whose y runs down.
    static func drawUpright(_ image: CGImage, in rect: CGRect, of context: CGContext) {
        context.saveGState()
        context.translateBy(x: rect.minX, y: rect.maxY)
        context.scaleBy(x: 1, y: -1)
        context.draw(image, in: CGRect(origin: .zero, size: rect.size))
        context.restoreGState()
    }

    private static func colors(viewer: BoardPlayer, palette: Palette, grooves: CGImage) -> CGImage? {
        guard let context = context(side: LudoSceneStyle.boardArtSide, gray: false) else { return nil }
        let whole = CGRect(x: -CGFloat(half), y: -CGFloat(half), width: CGFloat(half * 2), height: CGFloat(half * 2))
        context.setFillColor(palette.base)
        context.fill(whole)
        paintYards(viewer: viewer, palette: palette, in: context)
        for square in squares(viewer: viewer) {
            if let corner = square.corner, corner < palette.corners.count {
                let colors = palette.corners[corner]
                context.setFillColor(square.isStart ? colors.color : colors.light)
            } else {
                context.setFillColor(palette.track)
            }
            context.fill(square.rect)
        }
        paintHome(palette: palette, in: context)
        if let peony = palette.peony { paintPeonies(peony, viewer: viewer, in: context) }
        context.setBlendMode(.multiply)
        if let grain = palette.grain {
            let tile = CGFloat(LudoSceneStyle.boardGrainCells)
            context.saveGState()
            context.clip(to: whole)
            context.draw(grain, in: CGRect(x: whole.minX, y: whole.minY, width: tile, height: tile), byTiling: true)
            context.restoreGState()
        }
        // The glaze pools darker in the grooves.
        if let pooled = pooled(grooves) {
            drawUpright(pooled, in: whole, of: context)
        }
        return context.makeImage()
    }

    private static func paintYards(viewer: BoardPlayer, palette: Palette, in context: CGContext) {
        for corner in 0..<4 where corner < palette.corners.count {
            let colors = palette.corners[corner]
            context.setFillColor(colors.light)
            context.addPath(yardShape(yard(corner: corner, viewer: viewer)))
            context.fillPath()
            if let spot = colors.spot {
                context.setFillColor(spot)
                for circle in spots(corner: corner, viewer: viewer) { context.fillEllipse(in: circle) }
            }
        }
    }

    /// The round middle: my partner's half on the far side and mine on the near side.
    private static func paintHome(palette: Palette, in context: CGContext) {
        let home = homeRect
        context.saveGState()
        context.addEllipse(in: home)
        context.clip()
        context.setFillColor(palette.homeFar)
        context.fill(CGRect(x: home.minX, y: home.minY, width: home.width, height: home.height / 2))
        context.setFillColor(palette.homeNear)
        context.fill(CGRect(x: home.minX, y: home.midY, width: home.width, height: home.height / 2))
        context.restoreGState()
    }

    private static func paintPeonies(_ peony: CGImage, viewer: BoardPlayer, in context: CGContext) {
        let width = Double(LudoSceneStyle.peonyWidth)
        let height = width / Double(LudoSceneStyle.peonyAspect)
        for square in LudoSceneStyle.peonySquares {
            let middle = center(LudoBoardGeometry.point(of: .track(square), viewer: viewer))
            let rect = CGRect(x: middle.x - width / 2, y: middle.y - height / 2, width: width, height: height)
            drawUpright(peony, in: rect, of: context)
        }
    }
}
