import RealityKit
import SwiftUI
import UIKit
import simd

/// The slab, the center dome, the peonies and the lights.
extension LudoSceneBuilder {
    /// The rounded slab of matte clay under everything.
    static func addSlab(to root: Entity) {
        let side = LudoWorld.halfSlab * 2
        let material = LudoMaterials.satin(
            LudoSceneStyle.color(LudoSceneStyle.slabHex),
            roughness: LudoSceneStyle.slabRoughness,
            clearcoat: LudoSceneStyle.slabClearcoat,
            finish: .clay
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

    /// The center dome in two halves, mine on the near side and my partner's on the
    /// far side, with the seam between the two home columns. Records each half and
    /// the glow shell over it in `paint`, for player one and player two in that order.
    static func addCenter(to root: Entity, viewer: BoardPlayer, colors: CornerColors, paint: inout LudoPaintTargets) {
        let data = LudoMeshGeometry.domeHalf()
        guard let mesh = try? MeshResource.generate(from: [descriptor(data, name: "ludoDome")]) else { return }
        for player in [BoardPlayer.one, .two] {
            let isNear = player == viewer
            let dome = domeMaterials(isNear ? colors.mine : colors.partner)
            let half = ModelEntity(mesh: mesh, materials: [dome.half])
            // Hidden until a pawn gets home, and when the game is won.
            let glow = ModelEntity(mesh: mesh, materials: [dome.glow])
            glow.scale = SIMD3(1.05, 1.04, 1.05)
            glow.components.set(OpacityComponent(opacity: 0))
            glow.isEnabled = false
            for entity in [half, glow] {
                // The mesh covers the near half. The far half is the same mesh turned around.
                if !isNear { entity.orientation = simd_quatf(angle: .pi, axis: SIMD3(0, 1, 0)) }
                root.addChild(entity)
            }
            paint.domeHalves.append(half)
            paint.domeGlows.append(glow)
        }
    }

    /// Turns a tile a quarter turn or more, so its glaze shows a different part, then
    /// twists and sinks it a hair, as a tile set down by hand. It only ever sinks, so the
    /// peonies and the pawns, placed for the full tile height, never end up inside it.
    static func setDownByHand(_ tile: ModelEntity, using random: inout LudoRandom) {
        let quarter = Float(random.next() % 4) * .pi / 2
        let twist = LudoSceneStyle.tileTwistDegrees * .pi / 180
        let angle = quarter + random.float(in: -twist...twist)
        tile.orientation = simd_quatf(angle: angle, axis: SIMD3(0, 1, 0))
        let lift = LudoSceneStyle.tileHeightJitter
        tile.position.y -= random.float(in: 0...lift)
    }

    /// The flat peony on the six safe squares that are not a player's start square.
    static func addPeonies(to root: Entity, viewer: BoardPlayer, texture: TextureResource?) {
        guard let texture else { return }
        let width = LudoSceneStyle.peonyWidth
        let mesh = MeshResource.generatePlane(width: width, depth: width / LudoSceneStyle.peonyAspect)
        let material = LudoMaterials.decal(texture)
        for square in LudoSceneStyle.peonySquares {
            let flower = ModelEntity(mesh: mesh, materials: [material])
            let point = LudoBoardGeometry.point(of: .track(square), viewer: viewer)
            flower.position = LudoWorld.position(point, height: LudoSceneStyle.tileHeight + LudoSceneStyle.peonyLift)
            root.addChild(flower)
        }
    }

    static func addLights(to root: Entity) {
        let key = DirectionalLight()
        key.light = DirectionalLightComponent(
            color: LudoSceneStyle.color(LudoSceneStyle.keyLightHex),
            intensity: LudoSceneStyle.keyLightIntensity,
            isRealWorldProxy: false
        )
        key.shadow = DirectionalLightComponent.Shadow(
            shadowProjection: .fixed(
                zNear: LudoSceneStyle.shadowNear,
                zFar: LudoSceneStyle.shadowFar,
                orthographicScale: LudoSceneStyle.shadowWidth
            ),
            depthBias: LudoSceneStyle.shadowDepthBias
        )
        key.look(at: .zero, from: LudoSceneStyle.keyLightPosition, relativeTo: nil)
        key.name = "ludoKeyLight"
        root.addChild(key)

        let rim = DirectionalLight()
        rim.light = DirectionalLightComponent(
            color: LudoSceneStyle.color(LudoSceneStyle.rimLightHex),
            intensity: LudoSceneStyle.rimLightIntensity,
            isRealWorldProxy: false
        )
        rim.look(at: .zero, from: LudoSceneStyle.rimLightPosition, relativeTo: nil)
        rim.name = "ludoRimLight"
        root.addChild(rim)
    }
}
