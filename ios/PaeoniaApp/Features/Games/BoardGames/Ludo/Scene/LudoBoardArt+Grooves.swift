import CoreGraphics
import CoreImage
import Foundation
import simd

/// The carved grooves of the board top: their heights, the darker glaze that pools in
/// them, and the bump picture the light reads.
nonisolated extension LudoBoardArt {
    /// White where the board is flat, dark at the bottom of a groove, soft between.
    static func grooveHeights(viewer: BoardPlayer) -> CGImage? {
        let side = LudoSceneStyle.boardBumpSide
        guard let context = context(side: side, gray: true) else { return nil }
        let extent = CGFloat(half)
        context.setFillColor(gray: 1, alpha: 1)
        context.fill(CGRect(x: -extent, y: -extent, width: extent * 2, height: extent * 2))
        context.setStrokeColor(gray: 0, alpha: 1)
        context.setLineWidth(CGFloat(LudoSceneStyle.grooveWidth))
        context.setLineCap(.round)
        context.setLineJoin(.round)
        for square in squares(viewer: viewer) { context.stroke(square.rect) }
        for corner in 0..<4 {
            context.addPath(panel(yard(corner: corner, viewer: viewer)))
            context.strokePath()
            let role = LudoBoardGeometry.role(ofCorner: corner, viewer: viewer)
            guard role == .mine || role == .partner else { continue }
            for circle in spots(corner: corner, viewer: viewer) { context.strokeEllipse(in: circle) }
        }
        let home = homeRect
        context.strokeEllipse(in: home)
        context.move(to: CGPoint(x: home.minX, y: home.midY))
        context.addLine(to: CGPoint(x: home.maxX, y: home.midY))
        context.strokePath()
        guard let sharp = context.makeImage() else { return nil }
        let scale = Double(side) / Double(half * 2)
        let blurred = CIImage(cgImage: sharp)
            .clampedToExtent()
            .applyingGaussianBlur(sigma: Double(LudoSceneStyle.grooveSoftness) * scale)
            .cropped(to: CGRect(x: 0, y: 0, width: side, height: side))
        return CIContext().createCGImage(
            blurred,
            from: blurred.extent,
            format: .L8,
            colorSpace: CGColorSpace(name: CGColorSpace.linearGray)
        )
    }

    /// The grooves as a picture to multiply the colors by: white on the flat, darker in a groove.
    static func pooled(_ grooves: CGImage) -> CGImage? {
        let floor = CGFloat(1 - LudoSceneStyle.groovePooling)
        let image = CIImage(cgImage: grooves).applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": CIVector(x: 1 - floor, y: 0, z: 0, w: 0),
            "inputGVector": CIVector(x: 1 - floor, y: 0, z: 0, w: 0),
            "inputBVector": CIVector(x: 1 - floor, y: 0, z: 0, w: 0),
            "inputBiasVector": CIVector(x: floor, y: floor, z: floor, w: 0)
        ])
        return CIContext().createCGImage(image, from: image.extent)
    }

    /// A normal map from the groove heights. Red runs along x and green toward the far
    /// edge, the directions the board top's mesh gives.
    static func bumps(from grooves: CGImage) -> CGImage? {
        let side = grooves.width
        var heights = [UInt8](repeating: 255, count: side * side)
        guard let reader = CGContext(
            data: &heights,
            width: side,
            height: side,
            bitsPerComponent: 8,
            bytesPerRow: side,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else { return nil }
        reader.draw(grooves, in: CGRect(x: 0, y: 0, width: side, height: side))
        let normals = normalPixels(heights: heights, side: side)
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let provider = CGDataProvider(data: Data(normals) as CFData)
        else { return nil }
        return CGImage(
            width: side,
            height: side,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: side * 4,
            space: space,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: true,
            intent: .defaultIntent
        )
    }

    /// The bump picture's pixels, four bytes each, from the groove heights. It reads and
    /// writes raw memory, as a million pixels with checked indexes take seconds in a debug build.
    private static func normalPixels(heights: [UInt8], side: Int) -> [UInt8] {
        // Height change for one step of the picture, in cells of depth for each cell across.
        let pixel = Float(half * 2) / Float(side)
        let strength = LudoSceneStyle.grooveDepth / (255 * 2 * pixel)
        var normals = [UInt8](repeating: 255, count: side * side * 4)
        heights.withUnsafeBufferPointer { height in
            normals.withUnsafeMutableBufferPointer { normal in
                for row in 0..<side {
                    let above = max(row - 1, 0) * side
                    let here = row * side
                    let below = min(row + 1, side - 1) * side
                    for column in 0..<side {
                        let left = Float(height[here + max(column - 1, 0)])
                        let right = Float(height[here + min(column + 1, side - 1)])
                        // Rows run toward the viewer, so the far direction is up the picture.
                        let towardFar = Float(height[below + column]) - Float(height[above + column])
                        let across = (left - right) * strength
                        let along = towardFar * strength
                        let length = (across * across + along * along + 1).squareRoot()
                        let offset = (here + column) * 4
                        normal[offset] = UInt8(max(0, min(255, (across / length * 0.5 + 0.5) * 255)))
                        normal[offset + 1] = UInt8(max(0, min(255, (along / length * 0.5 + 0.5) * 255)))
                        normal[offset + 2] = UInt8(max(0, min(255, (1 / length * 0.5 + 0.5) * 255)))
                    }
                }
            }
        }
        return normals
    }
}
