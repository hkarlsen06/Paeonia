import RealityKit
import SwiftUI
import UIKit
import simd

/// The center dome, the peonies and the lights.
extension LudoSceneBuilder {
    /// The center dome in two halves, mine on the near side and my partner's on the
    /// far side, with the seam between the two home columns. Returns a glow shell
    /// over each half, for player one and player two in that order.
    static func addCenter(to root: Entity, viewer: BoardPlayer, colors: CornerColors) -> [ModelEntity] {
        let data = LudoMeshGeometry.domeHalf()
        guard let mesh = try? MeshResource.generate(from: [descriptor(data, name: "ludoDome")]) else { return [] }
        var glows: [ModelEntity] = []
        for player in [BoardPlayer.one, .two] {
            let isNear = player == viewer
            let color = isNear ? colors.mine : colors.partner
            let half = ModelEntity(
                mesh: mesh,
                materials: [LudoMaterials.satin(
                    color,
                    roughness: LudoSceneStyle.domeRoughness,
                    clearcoat: LudoSceneStyle.domeClearcoat,
                    showsBothSides: true
                )]
            )
            // Hidden until a pawn gets home, and when the game is won.
            let glow = ModelEntity(
                mesh: mesh,
                materials: [LudoMaterials.glowing(
                    color,
                    roughness: LudoSceneStyle.domeRoughness,
                    clearcoat: LudoSceneStyle.domeClearcoat,
                    showsBothSides: true
                )]
            )
            glow.scale = SIMD3(1.05, 1.04, 1.05)
            glow.components.set(OpacityComponent(opacity: 0))
            glow.isEnabled = false
            for entity in [half, glow] {
                // The mesh covers the near half. The far half is the same mesh turned around.
                if !isNear { entity.orientation = simd_quatf(angle: .pi, axis: SIMD3(0, 1, 0)) }
                root.addChild(entity)
            }
            glows.append(glow)
        }
        return glows
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
            shadowProjection: .automatic(maximumDistance: LudoSceneStyle.shadowDistance),
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
