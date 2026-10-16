import RealityKit
import UIKit

/// The two mugs of hot chocolate on the table, made in code.
extension LudoRoom {
    /// My mug in front of the board and my partner's behind it, each with its handle
    /// turned to the right of the person it belongs to.
    static func addMugs(to root: Entity) async {
        let style = LudoSceneStyle.self
        guard let body = try? MeshResource.generate(
                  from: [LudoSceneBuilder.descriptor(LudoMeshGeometry.mug(), name: "ludoMug")]
              ),
              let handle = try? MeshResource.generate(
                  from: [LudoSceneBuilder.descriptor(LudoMeshGeometry.mugHandle(), name: "ludoMugHandle")]
              ),
              let cocoa = try? MeshResource.generate(
                  from: [LudoSceneBuilder.descriptor(LudoMeshGeometry.cocoa(), name: "ludoCocoa")]
              )
        else { return }
        let drink = await hotChocolate()
        let mine = mug(color: style.color(style.myMugHex), body: body, handle: handle, cocoa: cocoa, drink: drink)
        place(mine, at: style.myMugPosition, turn: -0.5, on: root)
        let partners = mug(
            color: style.color(style.partnerMugHex), body: body, handle: handle, cocoa: cocoa, drink: drink
        )
        place(partners, at: style.partnerMugPosition, turn: .pi - 0.3, on: root)
    }

    private static func mug(
        color: UIColor,
        body: MeshResource,
        handle: MeshResource,
        cocoa: MeshResource,
        drink: PhysicallyBasedMaterial
    ) -> Entity {
        let style = LudoSceneStyle.self
        let glaze = LudoMaterials.satin(
            color,
            roughness: style.pawnRoughness,
            clearcoat: style.pawnClearcoat,
            showsBothSides: true,
            finish: .smoothGlaze
        )
        let mug = Entity()
        mug.addChild(ModelEntity(mesh: body, materials: [glaze]))

        // The half ring lies flat with its ends on the x axis. Standing it up puts the
        // ends above and below each other, bulging out along +x, against the mug's side.
        let ring = ModelEntity(mesh: handle, materials: [glaze])
        ring.orientation = simd_quatf(angle: -.pi / 2, axis: SIMD3(0, 0, 1))
            * simd_quatf(angle: -.pi / 2, axis: SIMD3(1, 0, 0))
        ring.position = SIMD3(style.mugRadius - style.mugHandleThickness, style.mugHeight * 0.52, 0)
        mug.addChild(ring)

        let surface = ModelEntity(mesh: cocoa, materials: [drink])
        surface.position.y = style.mugHeight * style.cocoaLevel
        mug.addChild(surface)
        return mug
    }

    /// The surface of the hot chocolate: wet and glossy, so it shows the lamp and the
    /// room in it, darkest in the middle and milky where it meets the wall.
    private static func hotChocolate() async -> PhysicallyBasedMaterial {
        let style = LudoSceneStyle.self
        var material = PhysicallyBasedMaterial()
        material.baseColor = .init(tint: style.color(style.cocoaMiddleHex))
        if let image = cocoaShades(),
           let texture = try? await TextureResource(image: image, options: .init(semantic: .color)) {
            material.baseColor = .init(tint: .white, texture: .init(texture))
        }
        material.roughness = .init(floatLiteral: style.cocoaRoughness)
        material.metallic = .init(floatLiteral: 0)
        material.specular = .init(floatLiteral: 1)
        material.clearcoat = .init(floatLiteral: 1)
        material.clearcoatRoughness = .init(floatLiteral: 0.02)
        return material
    }

    /// The colors of the hot chocolate from its middle (left) to the wall (right).
    private static func cocoaShades() -> CGImage? {
        let style = LudoSceneStyle.self
        let middle = style.color(style.cocoaMiddleHex)
        let edge = style.color(style.cocoaEdgeHex)
        let colors = [middle, middle, middle.ludoMixed(with: edge, amount: 0.35), edge].map(\.cgColor) as CFArray
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let gradient = CGGradient(colorsSpace: space, colors: colors, locations: [0, 0.6, 0.86, 1]),
              let context = CGContext(
                  data: nil,
                  width: 64,
                  height: 4,
                  bitsPerComponent: 8,
                  bytesPerRow: 0,
                  space: space,
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              )
        else { return nil }
        context.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: 64, y: 0), options: [])
        return context.makeImage()
    }
}
