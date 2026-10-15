import RealityKit
import SwiftUI
import UIKit
import simd

/// The slab, its painted top, the glows of the middle and the lights.
extension LudoSceneBuilder {
    /// The glazed slab under the painted top: round corners, a softly rounded top edge
    /// and straight sides.
    static func addSlab(to root: Entity) {
        let style = LudoSceneStyle.self
        let data = LudoMeshGeometry.slabSides(
            half: LudoWorld.halfSlab,
            cornerRadius: style.slabCornerRadius,
            edge: style.slabEdgeRadius,
            thickness: style.slabThickness
        )
        guard let mesh = try? MeshResource.generate(from: [descriptor(data, name: "ludoSlab")]) else { return }
        let material = LudoMaterials.satin(style.color(style.slabHex), finish: .smoothGlaze)
        let slab = ModelEntity(mesh: mesh, materials: [material])
        slab.name = "ludoSlab"
        root.addChild(slab)
    }

    /// The flat painted top of the board, at height 0, where every piece stands.
    static func addBoardTop(to root: Entity, material: PhysicallyBasedMaterial?) -> ModelEntity? {
        guard let mesh = boardTopMesh(), let material else { return nil }
        let top = ModelEntity(mesh: mesh, materials: [material])
        top.name = "ludoBoardTop"
        root.addChild(top)
        return top
    }

    /// The top inside the rounded edge, with the directions a bump picture needs:
    /// along x, and toward the far edge.
    private static func boardTopMesh() -> MeshResource? {
        let style = LudoSceneStyle.self
        let data = LudoMeshGeometry.slabTop(
            half: LudoWorld.halfSlab,
            cornerRadius: style.slabCornerRadius,
            edge: style.slabEdgeRadius,
            pictureHalf: LudoBoardArt.half
        )
        var descriptor = descriptor(data, name: "ludoBoardTop")
        descriptor.tangents = MeshBuffers.Tangents(Array(repeating: SIMD3(1, 0, 0), count: data.positions.count))
        descriptor.bitangents = MeshBuffers.Tangents(Array(repeating: SIMD3(0, 0, -1), count: data.positions.count))
        return try? MeshResource.generate(from: [descriptor])
    }

    /// A glow over each player's half of the middle, mine on the near side and my
    /// partner's on the far side. Hidden until a pawn gets home, and when the game is won.
    /// Returned for player one and player two in that order.
    static func addHomeGlows(to root: Entity, viewer: BoardPlayer, colors: CornerColors) -> [ModelEntity] {
        let data = LudoMeshGeometry.homeHalf()
        guard let mesh = try? MeshResource.generate(from: [descriptor(data, name: "ludoHomeGlow")]) else { return [] }
        return [BoardPlayer.one, .two].map { player in
            let glow = ModelEntity(mesh: mesh, materials: [homeGlowMaterial(colors.pawnColor(of: player))])
            glow.position.y = LudoSceneStyle.homeGlowLift
            // The mesh covers the near half. The far half is the same mesh turned around.
            if player != viewer { glow.orientation = simd_quatf(angle: .pi, axis: SIMD3(0, 1, 0)) }
            glow.components.set(OpacityComponent(opacity: 0))
            glow.components.set(DynamicLightShadowComponent(castsShadow: false))
            glow.isEnabled = false
            root.addChild(glow)
            return glow
        }
    }

    static func addLights(to root: Entity) {
        let lamp = SpotLight()
        lamp.light = SpotLightComponent(
            color: LudoSceneStyle.color(LudoSceneStyle.lampHex),
            intensity: LudoSceneStyle.lampLumens,
            innerAngleInDegrees: LudoSceneStyle.lampConeDegrees * LudoSceneStyle.lampFullShare,
            outerAngleInDegrees: LudoSceneStyle.lampConeDegrees,
            attenuationRadius: LudoSceneStyle.lampReach
        )
        var shadow = SpotLightComponent.Shadow()
        shadow.lightSize = LudoSceneStyle.lampSize
        shadow.quality = .high
        lamp.shadow = shadow
        lamp.look(at: .zero, from: LudoSceneStyle.lampPosition, relativeTo: nil)
        lamp.name = "ludoLamp"
        root.addChild(lamp)

        let style = LudoSceneStyle.self
        addLight("ludoKeyLight", style.keyLightHex, style.keyLightIntensity, from: style.keyLightPosition, to: root)
        addLight("ludoFillLight", style.fillLightHex, style.fillLightIntensity, from: style.fillLightPosition, to: root)
        addLight("ludoRimLight", style.rimLightHex, style.rimLightIntensity, from: style.rimLightPosition, to: root)
    }

    /// A directional light with no shadows, shining toward the middle of the board.
    private static func addLight(
        _ name: String,
        _ hex: UInt32,
        _ intensity: Float,
        from position: SIMD3<Float>,
        to root: Entity
    ) {
        let light = DirectionalLight()
        light.light = DirectionalLightComponent(
            color: LudoSceneStyle.color(hex),
            intensity: intensity,
            isRealWorldProxy: false
        )
        light.look(at: .zero, from: position, relativeTo: nil)
        light.name = name
        root.addChild(light)
    }
}
