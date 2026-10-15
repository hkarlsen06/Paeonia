import RealityKit
import SwiftUI
import UIKit

/// The pieces of the scene the stage keeps hold of.
@MainActor
struct LudoSceneParts {
    let root: Entity
    let pawns: [LudoPawnNode]
    let die: LudoDieNode
    /// The glow over each player's half of the middle, by `player.rawValue - 1`.
    let homeGlows: [ModelEntity]
    /// The picture material on top of each player's pawns, by `player.rawValue - 1`.
    let capMaterials: [PhysicallyBasedMaterial]
    /// The pieces that take the players' colors, so a new pick can paint them again.
    let paint: LudoPaintTargets
    /// The table, the candle and the tea round the board.
    let room: LudoRoom
}

/// The board pieces that change color when a player picks another one.
@MainActor
struct LudoPaintTargets {
    /// The painted top of the board.
    var boardTop: ModelEntity?
    /// By player (`player.rawValue - 1`): the glow over that player's half of the middle.
    var homeGlows: [ModelEntity] = []
}

/// Builds the board, the pawns, the die and the lights. The board is one slab with
/// its layout painted and carved on the top, so the scene has about 40 entities.
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
        // The painting and the room take the longest, so the room loads while the board is painted.
        async let builtRoom = LudoRoom.build()
        var paint = LudoPaintTargets()
        addSlab(to: root)
        paint.homeGlows = addHomeGlows(to: root, viewer: viewer, colors: colors)
        addLights(to: root)
        paint.boardTop = addBoardTop(to: root, material: await boardTopMaterial(viewer: viewer, colors: colors))
        let room = await builtRoom
        root.addChild(room.root)

        let capMaterials = await makeCapMaterials(styles: styles, colors: colors)
        let die = LudoDieNode(startsOnNearTray: true)
        root.addChild(die.root)
        let pawns = makePawns(viewer: viewer, colors: colors, capMaterials: capMaterials)
        for pawn in pawns { root.addChild(pawn.root) }
        return LudoSceneParts(
            root: root,
            pawns: pawns,
            die: die,
            homeGlows: paint.homeGlows,
            capMaterials: capMaterials,
            paint: paint,
            room: room
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

    /// The colors the board top is painted in, for one viewer.
    static func palette(viewer: BoardPlayer, colors: CornerColors) -> LudoBoardArt.Palette {
        let corners = (0..<4).map { corner in
            let color = colors.color(ofCorner: corner)
            let light = color.ludoLightened(LudoSceneStyle.yardLightening)
            let role = LudoBoardGeometry.role(ofCorner: corner, viewer: viewer)
            // Only the two players' yards hold pawns, so the two empty corners get no spots.
            let plays = role == .mine || role == .partner
            return LudoBoardArt.Corner(
                color: color.cgColor,
                light: light.cgColor,
                spot: plays ? light.ludoDarkened(LudoSceneStyle.slotDarkening).cgColor : nil
            )
        }
        return LudoBoardArt.Palette(
            base: LudoSceneStyle.color(LudoSceneStyle.slabHex).cgColor,
            track: LudoSceneStyle.color(LudoSceneStyle.trackTileHex).cgColor,
            corners: corners,
            homeNear: colors.mine.cgColor,
            homeFar: colors.partner.cgColor,
            peony: UIImage(named: LudoSceneStyle.peonyAsset)?.cgImage,
            grain: UIImage(named: "LudoGlazeDetail")?.cgImage
        )
    }

    /// The grooves' bump texture, made once. It is the same for every board.
    private static var bumps: TextureResource?

    /// The glazed material of the painted board top. The painting runs off the main actor.
    static func boardTopMaterial(viewer: BoardPlayer, colors: CornerColors) async -> PhysicallyBasedMaterial? {
        let palette = palette(viewer: viewer, colors: colors)
        let makesBumps = bumps == nil
        let pictures = await Task.detached(priority: .userInitiated) {
            LudoBoardArt.paint(viewer: viewer, palette: palette, makesBumps: makesBumps)
        }.value
        guard let pictures,
              let color = try? await TextureResource(image: pictures.color, options: .init(semantic: .color))
        else { return nil }
        if bumps == nil, let picture = pictures.bumps {
            bumps = try? await TextureResource(image: picture, options: .init(semantic: .normal))
        }
        var material = LudoMaterials.satin(.white, finish: .plain)
        material.baseColor = .init(tint: .white, texture: .init(color))
        if let bumps { material.normal = .init(texture: .init(bumps)) }
        return material
    }

    /// The glow over one player's half of the middle.
    static func homeGlowMaterial(_ color: UIColor) -> PhysicallyBasedMaterial {
        LudoMaterials.glowing(color, showsBothSides: true, finish: .plain)
    }

    /// Paints the glows of the middle in new colors, such as when a player picks another one.
    static func repaintGlows(_ paint: LudoPaintTargets, colors: CornerColors) {
        for (index, player) in [BoardPlayer.one, .two].enumerated() where index < paint.homeGlows.count {
            paint.homeGlows[index].model?.materials = [homeGlowMaterial(colors.pawnColor(of: player))]
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
