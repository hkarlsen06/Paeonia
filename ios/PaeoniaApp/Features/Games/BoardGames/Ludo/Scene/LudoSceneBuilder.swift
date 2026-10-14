import RealityKit
import SwiftUI
import UIKit

/// The pieces of the scene the stage keeps hold of.
@MainActor
struct LudoSceneParts {
    let root: Entity
    let pawns: [LudoPawnNode]
    let die: LudoDieNode
    /// A glow plate under each player's home pad, by `player.rawValue - 1`.
    let homeGlows: [ModelEntity]
    /// The picture material on top of each player's pawns, by `player.rawValue - 1`.
    let capMaterials: [PhysicallyBasedMaterial]
}

/// Builds the board, the pawns, the die and the lights. Meshes and
/// materials are made once and shared, so the scene stays at about 150 entities.
@MainActor
enum LudoSceneBuilder {
    static func build(viewer: BoardPlayer, styles: BoardPieceStyles) async -> LudoSceneParts {
        let colors = CornerColors(viewer: viewer, styles: styles)
        let root = Entity()
        root.name = "ludoScene"
        addSlab(to: root)
        addTiles(to: root, viewer: viewer, colors: colors)
        addYards(to: root, viewer: viewer, colors: colors)
        let homeGlows = addCenter(to: root, viewer: viewer, colors: colors)
        let peony = await LudoPeonyPicture.texture()
        addPeonies(to: root, viewer: viewer, texture: peony)
        addLights(to: root)

        let capMaterials = await makeCapMaterials(styles: styles, colors: colors)
        let die = LudoDieNode(startsOnNearTray: true)
        root.addChild(die.root)
        let pawns = makePawns(viewer: viewer, colors: colors, capMaterials: capMaterials)
        for pawn in pawns { root.addChild(pawn.root) }
        return LudoSceneParts(root: root, pawns: pawns, die: die, homeGlows: homeGlows, capMaterials: capMaterials)
    }

    /// The picture material for each player's pawn tops, made from their marks.
    static func makeCapMaterials(
        styles: BoardPieceStyles,
        colors: CornerColors
    ) async -> [PhysicallyBasedMaterial] {
        var materials: [PhysicallyBasedMaterial] = []
        for player in [BoardPlayer.one, .two] {
            let color = colors.pawnColor(of: player)
            if let texture = await LudoMarkPicture.texture(style: styles[player], pawnColor: color) {
                materials.append(LudoMaterials.picture(texture))
            } else {
                materials.append(LudoMaterials.satin(color.ludoDarkened(1 - LudoSceneStyle.markBackgroundShade)))
            }
        }
        return materials
    }

    // MARK: Colors

    /// The four corner colors of the board for one viewer.
    struct CornerColors {
        let viewer: BoardPlayer
        let mine: UIColor
        let partner: UIColor
        let gold = LudoSceneStyle.color(LudoSceneStyle.goldCornerHex)
        let sky = LudoSceneStyle.color(LudoSceneStyle.skyCornerHex)

        init(viewer: BoardPlayer, styles: BoardPieceStyles) {
            self.viewer = viewer
            mine = UIColor(styles[viewer].color)
            partner = UIColor(styles[viewer.other].color)
        }

        func color(ofCorner corner: Int) -> UIColor {
            switch LudoBoardGeometry.role(ofCorner: corner, viewer: viewer) {
            case .mine: mine
            case .partner: partner
            case .gold: gold
            case .sky: sky
            }
        }

        func pawnColor(of player: BoardPlayer) -> UIColor {
            color(ofCorner: LudoBoardGeometry.corner(of: player))
        }
    }

    // MARK: Board

    private static func addSlab(to root: Entity) {
        let side = LudoWorld.halfSlab * 2
        let material = LudoMaterials.satin(
            LudoSceneStyle.color(LudoSceneStyle.slabHex),
            roughness: LudoSceneStyle.slabRoughness,
            clearcoat: LudoSceneStyle.slabClearcoat
        )
        let slab = ModelEntity(
            mesh: .generateBox(
                width: side,
                height: LudoSceneStyle.slabThickness,
                depth: side,
                cornerRadius: LudoSceneStyle.slabCornerRadius
            ),
            materials: [material]
        )
        slab.position.y = -LudoSceneStyle.slabThickness / 2
        slab.name = "ludoSlab"
        root.addChild(slab)
    }

    private static func addTiles(to root: Entity, viewer: BoardPlayer, colors: CornerColors) {
        let mesh = MeshResource.generateBox(
            width: LudoSceneStyle.tileSize,
            height: LudoSceneStyle.tileHeight,
            depth: LudoSceneStyle.tileSize,
            cornerRadius: LudoSceneStyle.tileCornerRadius
        )
        let plain = LudoMaterials.satin(LudoSceneStyle.color(LudoSceneStyle.trackTileHex))
        let corners = Array(0..<4)
        let startMaterials = corners.map { LudoMaterials.satin(colors.color(ofCorner: $0)) }
        let columnMaterials = corners.map {
            LudoMaterials.satin(colors.color(ofCorner: $0).ludoLightened(LudoSceneStyle.columnLightening))
        }
        let height = LudoSceneStyle.tileHeight / 2
        for index in 0..<LudoBoard.trackLength {
            let corner = index / LudoBoardGeometry.squaresPerQuarter
            let isStart = index % LudoBoardGeometry.squaresPerQuarter == 0
            let tile = ModelEntity(mesh: mesh, materials: [isStart ? startMaterials[corner] : plain])
            let point = LudoBoardGeometry.point(of: .track(index), viewer: viewer)
            tile.position = LudoWorld.position(point, height: height)
            root.addChild(tile)
        }
        for corner in corners {
            for step in 1...5 {
                let tile = ModelEntity(mesh: mesh, materials: [columnMaterials[corner]])
                let point = LudoBoardGeometry.columnPoint(corner: corner, step: step, viewer: viewer)
                tile.position = LudoWorld.position(point, height: height)
                root.addChild(tile)
            }
        }
    }

    private static func addYards(to root: Entity, viewer: BoardPlayer, colors: CornerColors) {
        let plateMesh = MeshResource.generateBox(
            width: LudoSceneStyle.yardSize,
            height: LudoSceneStyle.yardHeight,
            depth: LudoSceneStyle.yardSize,
            cornerRadius: LudoSceneStyle.yardCornerRadius
        )
        let slotMesh = MeshResource.generateCylinder(
            height: LudoSceneStyle.yardSlotHeight,
            radius: LudoSceneStyle.yardSlotRadius
        )
        let slotHeight = LudoSceneStyle.yardHeight + LudoSceneStyle.yardSlotHeight / 2
        for corner in 0..<4 {
            let color = colors.color(ofCorner: corner)
            let plate = ModelEntity(
                mesh: plateMesh,
                materials: [LudoMaterials.satin(color.ludoLightened(LudoSceneStyle.yardLightening))]
            )
            let center = LudoBoardGeometry.yardCenter(corner: corner, viewer: viewer)
            plate.position = LudoWorld.position(center, height: LudoSceneStyle.yardHeight / 2)
            root.addChild(plate)
            let floor = color.ludoLightened(LudoSceneStyle.yardLightening)
            let slotColor = floor.ludoDarkened(LudoSceneStyle.slotDarkening)
            let slotMaterial = LudoMaterials.satin(slotColor)
            for slot in 0..<LudoBoard.pawnsPerPlayer {
                let dent = ModelEntity(mesh: slotMesh, materials: [slotMaterial])
                let point = LudoBoardGeometry.slotPoint(corner: corner, slot: slot, viewer: viewer)
                dent.position = LudoWorld.position(point, height: slotHeight)
                root.addChild(dent)
            }
        }
    }

    // MARK: Pawns

    private static func makePawns(
        viewer: BoardPlayer,
        colors: CornerColors,
        capMaterials: [PhysicallyBasedMaterial]
    ) -> [LudoPawnNode] {
        let pawnData = LudoMeshGeometry.pawn()
        let discData = LudoMeshGeometry.disc(
            radius: LudoSceneStyle.pawnTopRadius,
            segments: LudoSceneStyle.turnedSegments,
            flipsVertically: LudoSceneStyle.flipsMarkVertically
        )
        guard let bodyMesh = try? MeshResource.generate(from: [descriptor(pawnData, name: "ludoPawn")]),
              let capMesh = try? MeshResource.generate(from: [descriptor(discData, name: "ludoPawnTop")])
        else { return [] }
        return (0..<(LudoBoard.pawnsPerPlayer * 2)).map { index in
            let player: BoardPlayer = index < LudoBoard.pawnsPerPlayer ? .one : .two
            return LudoPawnNode(
                index: index,
                player: player,
                bodyMesh: bodyMesh,
                capMesh: capMesh,
                color: colors.pawnColor(of: player),
                capMaterial: capMaterials[player.rawValue - 1]
            )
        }
    }

    /// RealityKit's description of a mesh made by `LudoMeshGeometry`.
    static func descriptor(_ data: LudoMeshData, name: String) -> MeshDescriptor {
        var descriptor = MeshDescriptor(name: name)
        descriptor.positions = MeshBuffers.Positions(data.positions)
        descriptor.normals = MeshBuffers.Normals(data.normals)
        descriptor.textureCoordinates = MeshBuffers.TextureCoordinates(data.uvs)
        descriptor.primitives = .triangles(data.indices)
        return descriptor
    }
}
