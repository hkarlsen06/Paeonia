import RealityKit
import UIKit

/// The floor under the table: herringbone parquet with a cream wool rug, both dim so they
/// do not pull the eye from the board. Both textures are CC0 from Poly Haven
/// (herringbone_parquet, curly_teddy_natural).
extension LudoRoom {
    static var floorHeight: Float { tableTop - LudoSceneStyle.tableHeight }

    static func addFloor(to root: Entity) async {
        let style = LudoSceneStyle.self
        let floor = await surface(
            "LudoFloor",
            size: SIMD2(repeating: style.floorSize),
            grain: style.floorGrainCells,
            cornerRadius: 0,
            shade: style.floorShade
        )
        floor.position.y = floorHeight
        floor.name = "ludoFloor"
        root.addChild(floor)

        let rug = await surface(
            "LudoRug",
            size: SIMD2(style.rugWidth, style.rugDepth),
            grain: style.rugGrainCells,
            cornerRadius: style.rugCornerRadius,
            shade: style.rugShade,
            isMatte: true
        )
        rug.position.y = floorHeight + style.rugLift
        rug.name = "ludoRug"
        root.addChild(rug)
    }

    /// A flat textured surface `size` across and deep from the pictures named after
    /// `name`, repeating every `grain` cells and darkened by `shade`. A matte surface
    /// has no gloss and no bumps: the rug's wool glittered like foil seen from low.
    private static func surface(
        _ name: String,
        size: SIMD2<Float>,
        grain: Float,
        cornerRadius: Float,
        shade: CGFloat,
        isMatte: Bool = false
    ) async -> ModelEntity {
        var material = PhysicallyBasedMaterial()
        material.baseColor = .init(tint: LudoSceneStyle.color(LudoSceneStyle.roomHex))
        if let color = await texture(name + "Color", .color) {
            material.baseColor = .init(tint: UIColor(white: shade, alpha: 1), texture: tiled(color))
        }
        if isMatte {
            material.roughness = .init(floatLiteral: 1)
            material.specular = .init(floatLiteral: 0.1)
        } else {
            if let normal = await texture(name + "Normal", .normal) {
                material.normal = .init(texture: tiled(normal))
            }
            if let roughness = await texture(name + "Roughness", .scalar) {
                material.roughness = .init(scale: 1, texture: tiled(roughness))
            }
        }
        material.metallic = .init(floatLiteral: 0)
        material.textureCoordinateTransform = .init(scale: size / grain)
        let mesh = MeshResource.generatePlane(width: size.x, depth: size.y, cornerRadius: cornerRadius)
        return ModelEntity(mesh: mesh, materials: [material])
    }
}
