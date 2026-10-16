import RealityKit
import UIKit

/// The walls of the room and the furniture on the floor: two chairs and a painted chest
/// of drawers, CC0 models from Poly Haven (painted_wooden_chair_01, painted_wooden_cabinet)
/// kept as geometry only (`LudoChair.usdz`, `LudoCabinet.usdz`). The wall is Poly Haven's
/// beige_wall_001. All of it is cheap: flat walls, two small models, no lights.
extension LudoRoom {
    /// One wall: its middle on the floor, how long it is, and its turn so it faces in.
    private struct Wall {
        let middle: SIMD2<Float>
        let length: Float
        let turn: Float
    }

    static func addWalls(to root: Entity) async {
        let style = LudoSceneStyle.self
        let plaster = await plaster()
        var skirting = PhysicallyBasedMaterial()
        skirting.baseColor = .init(tint: style.color(style.skirtingHex))
        skirting.roughness = .init(floatLiteral: 0.6)
        skirting.metallic = .init(floatLiteral: 0)

        let walls = [
            Wall(middle: SIMD2(0, -style.roomHalfDepth), length: style.roomHalfWidth * 2, turn: 0),
            Wall(middle: SIMD2(0, style.roomHalfDepth), length: style.roomHalfWidth * 2, turn: .pi),
            Wall(middle: SIMD2(-style.roomHalfWidth, 0), length: style.roomHalfDepth * 2, turn: .pi / 2),
            Wall(middle: SIMD2(style.roomHalfWidth, 0), length: style.roomHalfDepth * 2, turn: -.pi / 2)
        ]
        for wall in walls {
            var material = plaster
            material.textureCoordinateTransform = .init(
                scale: SIMD2(wall.length / style.wallGrainCells, style.wallHeight / style.wallGrainCells)
            )
            let holder = Entity()
            holder.position = SIMD3(wall.middle.x, floorHeight, wall.middle.y)
            holder.orientation = simd_quatf(angle: wall.turn, axis: SIMD3(0, 1, 0))
            let face = ModelEntity(
                mesh: .generatePlane(width: wall.length, height: style.wallHeight),
                materials: [material]
            )
            face.position.y = style.wallHeight / 2
            face.components.set(DynamicLightShadowComponent(castsShadow: false))
            holder.addChild(face)
            let board = ModelEntity(
                mesh: .generatePlane(width: wall.length, height: style.skirtingHeight),
                materials: [skirting]
            )
            board.position = SIMD3(0, style.skirtingHeight / 2, 0.08)
            board.components.set(DynamicLightShadowComponent(castsShadow: false))
            holder.addChild(board)
            holder.name = "ludoWall"
            root.addChild(holder)
        }
    }

    /// Beige plaster, darkened like the floor.
    private static func plaster() async -> PhysicallyBasedMaterial {
        let style = LudoSceneStyle.self
        var plaster = PhysicallyBasedMaterial()
        plaster.baseColor = .init(tint: UIColor(white: style.wallShade, alpha: 1))
        if let color = await texture("LudoWallColor", .color) {
            plaster.baseColor = .init(tint: UIColor(white: style.wallShade, alpha: 1), texture: tiled(color))
        }
        if let normal = await texture("LudoWallNormal", .normal) {
            plaster.normal = .init(texture: tiled(normal))
        }
        if let roughness = await texture("LudoWallRoughness", .scalar) {
            plaster.roughness = .init(scale: 1, texture: tiled(roughness))
        }
        plaster.metallic = .init(floatLiteral: 0)
        return plaster
    }

    static func addFurniture(to root: Entity) async {
        let style = LudoSceneStyle.self
        if let chair = await prop("LudoChair", shade: style.paintedShade) {
            for (index, seat) in style.chairSpots.enumerated() {
                stand(index == 0 ? chair : chair.clone(recursive: true), at: seat.spot, turn: seat.turn, on: root)
            }
        }
        if let cabinet = await prop("LudoCabinet", shade: style.paintedShade) {
            stand(cabinet, at: style.cabinetSpot, turn: 0, on: root)
        }
    }

    /// Stands a model on the floor at (x, z) in cells, turned round the vertical axis.
    private static func stand(_ model: Entity, at spot: SIMD2<Float>, turn: Float, on root: Entity) {
        let holder = Entity()
        holder.position = SIMD3(spot.x, floorHeight + LudoSceneStyle.rugLift, spot.y)
        holder.orientation = simd_quatf(angle: turn, axis: SIMD3(0, 1, 0))
        holder.addChild(model)
        root.addChild(holder)
    }
}
