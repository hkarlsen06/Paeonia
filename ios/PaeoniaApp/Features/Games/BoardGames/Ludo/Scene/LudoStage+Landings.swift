import RealityKit
import simd
import UIKit

/// While a player picks which pawn to move, the squares their movable pawns would
/// land on glow softly in their color: mine once my die has landed, the partner's
/// once their live roll shows. The glow goes out when the pawn is picked.
extension LudoStage {
    /// What the discs show: whose roll, and where.
    struct LandingKey: Equatable {
        let mover: BoardPlayer
        let color: UIColor
        let points: [LudoGridPoint]
    }

    /// Two discs, one per pawn that can move. They take no taps.
    static func makeLandingMarks(in root: Entity) -> [ModelEntity] {
        let size = LudoSceneStyle.landingSize
        let mesh = MeshResource.generatePlane(width: size, depth: size, cornerRadius: size / 2)
        return (0..<LudoBoard.pawnsPerPlayer).map { _ in
            let mark = ModelEntity(mesh: mesh, materials: [])
            mark.components.set(DynamicLightShadowComponent(castsShadow: false))
            mark.components.set(OpacityComponent(opacity: 0))
            mark.isEnabled = false
            root.addChild(mark)
            return mark
        }
    }

    func syncLandings(_ new: Input) {
        let key = landings(for: new)
        guard key != landingKey else { return }
        landingKey = key
        guard let key else { return }
        let material = LudoMaterials.glowing(key.color, showsBothSides: true, finish: .plain)
        for (index, mark) in landingMarks.enumerated() {
            guard index < key.points.count else {
                mark.isEnabled = false
                continue
            }
            mark.model?.materials = [material]
            mark.position = LudoWorld.position(key.points[index], height: LudoSceneStyle.landingLift)
            mark.isEnabled = true
        }
        landingLevel = 0
        appliedLandingLevel = -1
    }

    /// The landings while the mover chooses. Mine show with my glowing pawns. The
    /// partner's show while their rolled die rests in their yard.
    private func landings(for new: Input) -> LandingKey? {
        guard new.board.outcome == nil, case let .showing(die, side) = new.die, new.board.next == side else {
            return nil
        }
        if side == new.me, !new.movableChoices.contains(where: { $0 != .pass }) { return nil }
        let points = new.board.landings(die: die).map {
            LudoBoardGeometry.point(of: $0.square, homeLane: $0.pawn, viewer: viewer)
        }
        guard !points.isEmpty else { return nil }
        let colors = LudoSceneBuilder.CornerColors(viewer: viewer, colors: new.colors)
        return LandingKey(mover: side, color: colors.pawnColor(of: side), points: points)
    }

    /// Fades the discs in, then lets them breathe with the movable pawns' bob.
    func updateLandings(deltaTime: Double) {
        let target: Float = landingKey == nil ? 0 : 1
        landingLevel += (target - landingLevel) * Float(1 - exp(-deltaTime * 12))
        let breathing = reduceMotion ? 1 : Float(0.8 + 0.2 * sin(clock * 2 * .pi / LudoSceneStyle.pawnBobPeriod))
        var value = landingLevel * breathing * LudoSceneStyle.landingOpacity
        if target == 0, value < 0.02 { value = 0 }
        guard abs(value - appliedLandingLevel) > 0.004 || (value == 0 && appliedLandingLevel != 0) else { return }
        appliedLandingLevel = value
        for mark in landingMarks {
            mark.components.set(OpacityComponent(opacity: value))
            if value == 0 { mark.isEnabled = false }
        }
    }
}
