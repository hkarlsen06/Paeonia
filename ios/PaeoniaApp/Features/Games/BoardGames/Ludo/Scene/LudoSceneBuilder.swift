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
    /// The pieces that take the players' colors, so a new pick can paint them again.
    let paint: LudoPaintTargets
}

/// The board pieces that change color when a player picks another one.
@MainActor
struct LudoPaintTargets {
    /// By corner: the start tile and the five home column tiles.
    var startTiles: [ModelEntity] = []
    var columnTiles: [[ModelEntity]] = []
    /// By corner: the yard plate, and the dents where pawns wait. A corner nobody plays has no dents.
    var plates: [ModelEntity] = []
    var dents: [[ModelEntity]] = []
    /// By player (`player.rawValue - 1`): the dome half and the glow shell over it.
    var domeHalves: [ModelEntity] = []
    var domeGlows: [ModelEntity] = []
}

/// Builds the board, the pawns, the die and the lights. Meshes and
/// materials are made once and shared, so the scene stays at about 150 entities.
@MainActor
enum LudoSceneBuilder {
    static func build(
        viewer: BoardPlayer,
        styles: BoardPieceStyles,
        colors playerColors: LudoColorPair
    ) async -> LudoSceneParts {
        await LudoSurfaces.load()
        let colors = CornerColors(viewer: viewer, colors: playerColors)
        let root = Entity()
        root.name = "ludoScene"
        var paint = LudoPaintTargets()
        addSlab(to: root)
        addTiles(to: root, viewer: viewer, colors: colors, paint: &paint)
        addYards(to: root, viewer: viewer, colors: colors, paint: &paint)
        addCenter(to: root, viewer: viewer, colors: colors, paint: &paint)
        if let shade = await LudoContactShade.make() { root.addChild(shade) }
        let peony = await LudoPeonyPicture.texture()
        addPeonies(to: root, viewer: viewer, texture: peony)
        addLights(to: root)

        let capMaterials = await makeCapMaterials(styles: styles, colors: colors)
        let die = LudoDieNode(startsOnNearTray: true)
        root.addChild(die.root)
        let pawns = makePawns(viewer: viewer, colors: colors, capMaterials: capMaterials)
        for pawn in pawns { root.addChild(pawn.root) }
        return LudoSceneParts(
            root: root,
            pawns: pawns,
            die: die,
            homeGlows: paint.domeGlows,
            capMaterials: capMaterials,
            paint: paint
        )
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
                let shade = color.ludoDarkened(1 - LudoSceneStyle.markBackgroundShade)
                materials.append(LudoMaterials.satin(shade, finish: .smoothGlaze))
            }
        }
        return materials
    }

    // MARK: Colors

    /// The four corner colors of the board for one viewer. The two players have
    /// the colors they picked. The two colors nobody picked fill the empty
    /// corners, the first one at the top left and the second at the bottom right.
    struct CornerColors {
        let viewer: BoardPlayer
        let mine: UIColor
        let partner: UIColor
        let topLeftEmpty: UIColor
        let bottomRightEmpty: UIColor

        init(viewer: BoardPlayer, colors: LudoColorPair) {
            self.viewer = viewer
            mine = colors.mine.uiColor
            partner = colors.partner.uiColor
            let unused = colors.unused
            topLeftEmpty = unused[0].uiColor
            bottomRightEmpty = unused[1].uiColor
        }

        func color(ofCorner corner: Int) -> UIColor {
            switch LudoBoardGeometry.role(ofCorner: corner, viewer: viewer) {
            case .mine: mine
            case .partner: partner
            case .gold: topLeftEmpty
            case .sky: bottomRightEmpty
            }
        }

        func pawnColor(of player: BoardPlayer) -> UIColor {
            color(ofCorner: LudoBoardGeometry.corner(of: player))
        }
    }

    // MARK: Board

    /// The satin materials that depend on the corner colors, by corner.
    struct CornerMaterials {
        let start: [PhysicallyBasedMaterial]
        let column: [PhysicallyBasedMaterial]
        let plate: [PhysicallyBasedMaterial]
        let slot: [PhysicallyBasedMaterial]

        init(_ colors: CornerColors) {
            let corners = Array(0..<4)
            start = corners.map { LudoMaterials.satin(colors.color(ofCorner: $0)) }
            column = corners.map {
                LudoMaterials.satin(colors.color(ofCorner: $0).ludoLightened(LudoSceneStyle.columnLightening))
            }
            let floors = corners.map { colors.color(ofCorner: $0).ludoLightened(LudoSceneStyle.yardLightening) }
            plate = floors.map { LudoMaterials.satin($0) }
            slot = floors.map { LudoMaterials.satin($0.ludoDarkened(LudoSceneStyle.slotDarkening)) }
        }
    }

    /// The center dome's materials for one player's color: the half and the glow shell.
    static func domeMaterials(_ color: UIColor) -> (half: PhysicallyBasedMaterial, glow: PhysicallyBasedMaterial) {
        (
            LudoMaterials.satin(
                color,
                roughness: LudoSceneStyle.domeRoughness,
                clearcoat: LudoSceneStyle.domeClearcoat,
                showsBothSides: true,
                finish: .smoothGlaze
            ),
            LudoMaterials.glowing(
                color,
                roughness: LudoSceneStyle.domeRoughness,
                clearcoat: LudoSceneStyle.domeClearcoat,
                showsBothSides: true,
                finish: .smoothGlaze
            )
        )
    }

    /// Paints the board pieces in new colors, such as when a player picks another one.
    static func repaint(_ paint: LudoPaintTargets, colors: CornerColors) {
        let materials = CornerMaterials(colors)
        for corner in 0..<4 where corner < paint.startTiles.count {
            paint.startTiles[corner].model?.materials = [materials.start[corner]]
            for tile in paint.columnTiles[corner] { tile.model?.materials = [materials.column[corner]] }
            paint.plates[corner].model?.materials = [materials.plate[corner]]
            for dent in paint.dents[corner] { dent.model?.materials = [materials.slot[corner]] }
        }
        for (index, player) in [BoardPlayer.one, .two].enumerated() where index < paint.domeHalves.count {
            let dome = domeMaterials(colors.pawnColor(of: player))
            paint.domeHalves[index].model?.materials = [dome.half]
            paint.domeGlows[index].model?.materials = [dome.glow]
        }
    }

    private static func addTiles(
        to root: Entity,
        viewer: BoardPlayer,
        colors: CornerColors,
        paint: inout LudoPaintTargets
    ) {
        let mesh = MeshResource.generateBox(
            width: LudoSceneStyle.tileSize,
            height: LudoSceneStyle.tileHeight,
            depth: LudoSceneStyle.tileSize,
            cornerRadius: LudoSceneStyle.tileCornerRadius
        )
        let plain = LudoMaterials.satin(LudoSceneStyle.color(LudoSceneStyle.trackTileHex))
        let materials = CornerMaterials(colors)
        let height = LudoSceneStyle.tileHeight / 2
        // The same tiles on every phone and every launch, each set down a little differently by hand.
        var random = LudoRandom(seed: 0x7115)
        var starts: [ModelEntity?] = Array(repeating: nil, count: 4)
        for index in 0..<LudoBoard.trackLength {
            let corner = index / LudoBoardGeometry.squaresPerQuarter
            let isStart = index % LudoBoardGeometry.squaresPerQuarter == 0
            let tile = ModelEntity(mesh: mesh, materials: [isStart ? materials.start[corner] : plain])
            let point = LudoBoardGeometry.point(of: .track(index), viewer: viewer)
            tile.position = LudoWorld.position(point, height: height)
            setDownByHand(tile, using: &random)
            root.addChild(tile)
            if isStart { starts[corner] = tile }
        }
        paint.startTiles = starts.compactMap { $0 }
        for corner in 0..<4 {
            var column: [ModelEntity] = []
            for step in 1...5 {
                let tile = ModelEntity(mesh: mesh, materials: [materials.column[corner]])
                let point = LudoBoardGeometry.columnPoint(corner: corner, step: step, viewer: viewer)
                tile.position = LudoWorld.position(point, height: height)
                setDownByHand(tile, using: &random)
                root.addChild(tile)
                column.append(tile)
            }
            paint.columnTiles.append(column)
        }
    }

    private static func addYards(
        to root: Entity,
        viewer: BoardPlayer,
        colors: CornerColors,
        paint: inout LudoPaintTargets
    ) {
        let materials = CornerMaterials(colors)
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
            let plate = ModelEntity(mesh: plateMesh, materials: [materials.plate[corner]])
            let center = LudoBoardGeometry.yardCenter(corner: corner, viewer: viewer)
            plate.position = LudoWorld.position(center, height: LudoSceneStyle.yardHeight / 2)
            root.addChild(plate)
            paint.plates.append(plate)
            var dents: [ModelEntity] = []
            defer { paint.dents.append(dents) }
            // Only the two players' yards hold pawns, so the two empty corners get no dents.
            let role = LudoBoardGeometry.role(ofCorner: corner, viewer: viewer)
            guard role == .mine || role == .partner else { continue }
            for slot in 0..<LudoBoard.pawnsPerPlayer {
                let dent = ModelEntity(mesh: slotMesh, materials: [materials.slot[corner]])
                let point = LudoBoardGeometry.slotPoint(corner: corner, slot: slot, viewer: viewer)
                dent.position = LudoWorld.position(point, height: slotHeight)
                root.addChild(dent)
                dents.append(dent)
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
