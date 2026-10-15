import CoreImage
import RealityKit
import UIKit

/// The soft darkening on the slab where the tiles, the yards and the dome stand on
/// it, as light gets less into a corner. It is drawn once into a picture that lies
/// just above the slab. The board's layout is the same turned any way, so one
/// picture serves both players.
@MainActor
enum LudoContactShade {
    /// A see-through plane over the slab, dark where pieces touch it.
    static func make() async -> ModelEntity? {
        guard let image = picture(),
              let texture = try? await TextureResource(image: image, withName: nil, options: .init(semantic: .color))
        else { return nil }
        var material = UnlitMaterial()
        material.color = .init(tint: .white, texture: .init(texture))
        material.blending = .transparent(opacity: .init(floatLiteral: 1))
        let side = LudoWorld.halfSlab * 2
        let plane = ModelEntity(mesh: .generatePlane(width: side, depth: side), materials: [material])
        plane.position.y = LudoSceneStyle.contactShadeLift
        plane.components.set(DynamicLightShadowComponent(castsShadow: false))
        plane.name = "ludoContactShade"
        return plane
    }

    /// Black with the shade in its alpha: each piece's outline a little larger, blurred.
    static func picture() -> CGImage? {
        let side = LudoSceneStyle.contactShadeTextureSide
        let cellsAcross = CGFloat(LudoWorld.halfSlab * 2)
        let scale = CGFloat(side) / cellsAcross
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                  data: nil,
                  width: side,
                  height: side,
                  bitsPerComponent: 8,
                  bytesPerRow: 0,
                  space: space,
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              )
        else { return nil }
        context.setFillColor(UIColor.black.withAlphaComponent(LudoSceneStyle.contactShadeStrength).cgColor)
        let grow = CGFloat(LudoSceneStyle.contactShadeSpread)
        for footprint in footprints() {
            let rect = footprint.rect.insetBy(dx: -grow, dy: -grow)
            let canvas = CGRect(
                x: (rect.minX + cellsAcross / 2) * scale,
                y: (rect.minY + cellsAcross / 2) * scale,
                width: rect.width * scale,
                height: rect.height * scale
            )
            let radius = min((footprint.cornerRadius + grow) * scale, canvas.width / 2)
            context.addPath(CGPath(roundedRect: canvas, cornerWidth: radius, cornerHeight: radius, transform: nil))
        }
        context.fillPath()
        guard let sharp = context.makeImage() else { return nil }
        let blurred = CIImage(cgImage: sharp)
            .clampedToExtent()
            .applyingGaussianBlur(sigma: Double(LudoSceneStyle.contactShadeBlur * Float(scale)))
            .cropped(to: CGRect(x: 0, y: 0, width: side, height: side))
        return CIContext().createCGImage(blurred, from: blurred.extent)
    }

    private struct Footprint {
        /// In board cells around the middle, x across and y toward the viewer.
        let rect: CGRect
        let cornerRadius: CGFloat
    }

    /// The outline of every piece that stands on the slab.
    private static func footprints() -> [Footprint] {
        func square(_ point: LudoGridPoint, side: Float, radius: Float) -> Footprint {
            let middle = LudoWorld.position(point)
            let half = CGFloat(side / 2)
            return Footprint(
                rect: CGRect(
                    x: CGFloat(middle.x) - half,
                    y: CGFloat(middle.z) - half,
                    width: half * 2,
                    height: half * 2
                ),
                cornerRadius: CGFloat(radius)
            )
        }
        let tile = LudoSceneStyle.tileSize
        let tileRadius = LudoSceneStyle.tileCornerRadius
        var footprints = (0..<LudoBoard.trackLength).map { index in
            square(LudoBoardGeometry.point(of: .track(index), viewer: .one), side: tile, radius: tileRadius)
        }
        for corner in 0..<4 {
            for step in 1...5 {
                let point = LudoBoardGeometry.columnPoint(corner: corner, step: step, viewer: .one)
                footprints.append(square(point, side: tile, radius: tileRadius))
            }
            let yard = LudoBoardGeometry.yardCenter(corner: corner, viewer: .one)
            footprints.append(square(yard, side: LudoSceneStyle.yardSize, radius: LudoSceneStyle.yardCornerRadius))
        }
        let dome = LudoSceneStyle.domeDiameter
        let middle = LudoGridPoint(row: LudoBoardGeometry.middle, column: LudoBoardGeometry.middle)
        footprints.append(square(middle, side: dome, radius: dome / 2))
        return footprints
    }
}
