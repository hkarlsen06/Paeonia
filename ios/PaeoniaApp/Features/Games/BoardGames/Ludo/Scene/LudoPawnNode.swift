import Foundation
import RealityKit
import simd
import UIKit

/// One pawn in the scene: a turned body and a flat disc on top that carries the
/// owner's mark. The stage moves it, either with a clip or by easing toward its
/// resting place.
@MainActor
final class LudoPawnNode {
    let index: Int
    let player: BoardPlayer
    /// Moves with the pawn. Takes the taps.
    let root = Entity()

    private let body: ModelEntity
    private let cap: ModelEntity
    private let normalMaterial: PhysicallyBasedMaterial
    private let glowMaterial: PhysicallyBasedMaterial

    /// Where the pawn stands when nothing moves it, with its size.
    private(set) var rest = SIMD3<Float>.zero
    private(set) var restScale: Float = 1
    /// Set by a clip to fade the pawn, 0 to 1.
    var fade: Float = 1 {
        didSet { updateOpacity() }
    }
    /// What the pawn dims to, 1 when it does not dim. Eased in the idle update.
    var dimTarget: Float = 1
    private var dim: Float = 1
    private var lift: Float = 0
    private var appliedOpacity: Float = 1
    private let phase: Double

    /// True while the pawn lifts and glows to say it can move.
    var isMovable = false {
        didSet {
            guard isMovable != oldValue else { return }
            body.model?.materials = [isMovable ? glowMaterial : normalMaterial]
        }
    }

    init(
        index: Int,
        player: BoardPlayer,
        bodyMesh: MeshResource,
        capMesh: MeshResource,
        color: UIColor,
        capMaterial: PhysicallyBasedMaterial
    ) {
        self.index = index
        self.player = player
        // Both sides draw, so the turned body shows whichever way its triangles face.
        let normal = LudoMaterials.pawn(color, glowing: false)
        normalMaterial = normal
        glowMaterial = LudoMaterials.pawn(color, glowing: true)
        body = ModelEntity(mesh: bodyMesh, materials: [normal])
        cap = ModelEntity(mesh: capMesh, materials: [capMaterial])
        phase = Double(index) * 0.9
        cap.position = SIMD3(0, LudoMeshGeometry.pawnTopHeight + LudoSceneStyle.markLift, 0)
        // Pawns cast soft shadows on the board.
        body.components.set(DynamicLightShadowComponent(castsShadow: true))
        root.addChild(body)
        root.addChild(cap)
        root.name = "ludoPawn\(index)"
        // A box that is wider and taller than the pawn, so a fingertip lands on it.
        let side = LudoSceneStyle.pawnBaseRadius * 2.3
        let size = SIMD3<Float>(side, LudoSceneStyle.pawnHeight + 0.5, side)
        let shape = ShapeResource.generateBox(size: size)
            .offsetBy(translation: SIMD3(0, size.y / 2 - 0.1, 0))
        root.components.set(CollisionComponent(shapes: [shape]))
        root.components.set(InputTargetComponent())
    }

    /// Changes the picture on top.
    func setCapMaterial(_ material: PhysicallyBasedMaterial) {
        cap.model?.materials = [material]
    }

    /// Sets the resting place. The pawn goes there at once unless a clip moves it.
    func setRest(position: SIMD3<Float>, scale: Float) {
        rest = position
        restScale = scale
    }

    /// Puts the pawn at a pose. Clips use it every frame.
    func apply(position: SIMD3<Float>, scale: Float) {
        root.position = position
        root.scale = SIMD3(repeating: scale)
    }

    /// Eases the lift, the bob and the dimming when no clip moves the pawn.
    func updateIdle(deltaTime: Double, clock: Double, reduceMotion: Bool) {
        let liftTarget: Float = isMovable ? LudoSceneStyle.pawnLift : 0
        lift += (liftTarget - lift) * Float(1 - exp(-deltaTime * 14))
        var height = lift
        if isMovable, !reduceMotion {
            let angle = (clock / LudoSceneStyle.pawnBobPeriod + phase) * 2 * .pi
            height += LudoSceneStyle.pawnBobHeight * Float(sin(angle))
        }
        apply(position: rest + SIMD3(0, height, 0), scale: restScale)
        updateDim(deltaTime: deltaTime)
    }

    /// Eases the dimming when a clip moves the pawn.
    func updateDim(deltaTime: Double) {
        guard abs(dim - dimTarget) > 0.002 else {
            if dim != dimTarget {
                dim = dimTarget
                updateOpacity()
            }
            return
        }
        dim += (dimTarget - dim) * Float(1 - exp(-deltaTime * 9))
        updateOpacity()
    }

    /// Jumps to the dimming target, for Reduce Motion and for a fresh board.
    func snapDim() {
        dim = dimTarget
        updateOpacity()
    }

    /// Puts the pawn on its resting place at once, with no lift and no dimming left over.
    func jumpToRest() {
        lift = 0
        apply(position: rest, scale: restScale)
    }

    private func updateOpacity() {
        let opacity = min(max(dim * fade, 0), 1)
        guard abs(opacity - appliedOpacity) > 0.002 else { return }
        appliedOpacity = opacity
        for entity in [body, cap] {
            if opacity >= 0.998 {
                entity.components.remove(OpacityComponent.self)
            } else {
                entity.components.set(OpacityComponent(opacity: opacity))
            }
        }
    }
}
