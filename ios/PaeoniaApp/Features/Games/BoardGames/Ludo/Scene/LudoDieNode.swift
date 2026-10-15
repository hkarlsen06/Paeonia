import Foundation
import RealityKit
import simd

/// The die: a rounded blush cube with plum pips. The stage moves it between the
/// two base yards, bobs it while it waits for a tap, and tumbles it to a face.
@MainActor
final class LudoDieNode {
    /// Moves and turns with the die. Takes the taps.
    let root = Entity()

    /// Where the die rests, and how it is turned there.
    private(set) var restPosition: SIMD3<Float>
    private(set) var restOrientation: simd_quatf
    /// The yard the die rests in now: mine (near) or my partner's.
    private(set) var restsOnNearTray: Bool
    /// The face on top when it last landed, or nil before the first roll.
    private(set) var shownFace: Int?

    init(startsOnNearTray: Bool) {
        restsOnNearTray = startsOnNearTray
        restPosition = LudoWorld.dieRestPosition(isNear: startsOnNearTray)
        restOrientation = LudoDieFaces.orientation(showing: 1)
        let bodyColor = LudoSceneStyle.color(LudoSceneStyle.dieHex)
        let pipColor = LudoSceneStyle.color(LudoSceneStyle.pipHex)
        let bodyMaterial = LudoMaterials.satin(
            bodyColor,
            roughness: LudoSceneStyle.dieRoughness,
            clearcoat: LudoSceneStyle.dieClearcoat
        )
        let pipMaterial = LudoMaterials.satin(
            pipColor,
            roughness: LudoSceneStyle.pipRoughness,
            clearcoat: 0,
            showsBothSides: true,
            finish: .plain
        )
        let body = ModelEntity(
            mesh: .generateBox(size: LudoSceneStyle.dieSize, cornerRadius: LudoSceneStyle.dieCornerRadius),
            materials: [bodyMaterial]
        )
        body.components.set(DynamicLightShadowComponent(castsShadow: true))
        root.addChild(body)
        addPips(material: pipMaterial)
        root.name = "ludoDie"
        // A box well past the die, because a fingertip is bigger than the pips.
        let size = SIMD3<Float>(repeating: LudoSceneStyle.dieSize * 1.7)
        root.components.set(CollisionComponent(shapes: [ShapeResource.generateBox(size: size)]))
        root.components.set(InputTargetComponent())
        apply(position: restPosition, orientation: restOrientation, scale: 1)
    }

    /// Sets the resting pose. The die goes there at once unless a clip moves it.
    func setRest(position: SIMD3<Float>, orientation: simd_quatf, isNear: Bool, face: Int?) {
        restPosition = position
        restOrientation = orientation
        restsOnNearTray = isNear
        if let face { shownFace = face }
    }

    func apply(position: SIMD3<Float>, orientation: simd_quatf, scale: Float) {
        root.position = position
        root.orientation = orientation
        root.scale = SIMD3(repeating: scale)
    }

    /// Where the die is right now.
    var currentPosition: SIMD3<Float> { root.position }
    var currentOrientation: simd_quatf { root.orientation }

    /// A gentle bob and sway while the die waits for a tap.
    func updateIdle(clock: Double, isReady: Bool, reduceMotion: Bool) {
        var position = restPosition
        var orientation = restOrientation
        var scale: Float = 1
        if isReady, !reduceMotion {
            let angle = Float(clock / LudoSceneStyle.dieBobPeriod * 2 * .pi)
            position.y += LudoSceneStyle.dieBobHeight * (0.5 + 0.5 * sin(angle))
            let sway = simd_quatf(angle: LudoSceneStyle.dieBobYaw * sin(angle * 0.5), axis: SIMD3(0, 1, 0))
            orientation = sway * restOrientation
            scale = 1 + 0.03 * (0.5 + 0.5 * sin(angle))
        }
        apply(position: position, orientation: orientation, scale: scale)
    }

    // MARK: Pips

    private func addPips(material: PhysicallyBasedMaterial) {
        let heart = LudoSceneBuilder.descriptor(LudoMeshGeometry.heart(), name: "ludoHeart")
        guard let mesh = try? MeshResource.generate(from: [heart]) else { return }
        let half = LudoSceneStyle.dieSize / 2 - 0.002
        for value in 1...6 {
            let face = LudoDieFaces.face(value)
            // The heart is made lying flat with its point toward +z. Turn it onto the face.
            let along = simd_cross(face.normal, face.down)
            let turn = simd_quatf(simd_float3x3(columns: (along, face.normal, face.down)))
            for step in LudoDieFaces.pips(value) {
                let pip = ModelEntity(mesh: mesh, materials: [material])
                pip.position = face.normal * half
                    + face.across * (step.x * LudoSceneStyle.pipSpread)
                    + face.down * (step.y * LudoSceneStyle.pipSpread)
                pip.orientation = turn
                root.addChild(pip)
            }
        }
    }
}
