import CoreGraphics
import Foundation
import RealityKit
import simd

/// Throwing the die by hand: a drag that starts on the ready die picks it up, the
/// die follows the finger above its yard, and letting go throws it with the
/// finger's speed. `LudoDiePhysics` works out the flight.
extension LudoStage {
    /// The height of the middle of a held die.
    private var holdHeight: Float {
        LudoWorld.dieRestPosition(isNear: true).y + LudoSceneStyle.dieHoldLift
    }

    /// True when a drag that starts on `entity` picks up the die.
    func canPickUpDie(_ entity: Entity) -> Bool {
        input?.die == .ready && target(of: entity) == .die && !hasClip(.die)
    }

    /// A drag began on the ready die at `point`, from 0 to 1 across and down the view.
    func pickUpDie(at point: CGPoint) {
        releasedAt = nil
        heldDie = holdPoint(at: point) ?? dieNode.map { $0.restPosition + SIMD3(0, LudoSceneStyle.dieHoldLift, 0) }
        PaeoniaHaptics.selection()
    }

    func moveHeldDie(to point: CGPoint) {
        guard heldDie != nil, releasedAt == nil, let spot = holdPoint(at: point) else { return }
        heldDie = spot
    }

    /// The finger let go at `point`, moving at `velocity` in shares of the view a
    /// second. The die waits in the air for its roll and returns how it was thrown.
    func releaseDie(at point: CGPoint, velocity: CGPoint) -> LudoToss? {
        guard heldDie != nil, let die = dieNode, let rig else {
            dropHeldDie()
            return nil
        }
        releasedAt = clock
        let span = 0.05
        let later = CGPoint(x: point.x + velocity.x * span, y: point.y + velocity.y * span)
        var floorVelocity = SIMD2<Float>.zero
        let height = Double(holdHeight)
        if let now = rig.boardPoint(at: point, height: height), let next = rig.boardPoint(at: later, height: height) {
            floorVelocity = SIMD2(Float(next.x - now.x), Float(next.y - now.y)) / Float(span)
        }
        return .thrown(
            from: die.currentPosition,
            orientation: die.currentOrientation,
            floorVelocity: floorVelocity,
            fallbackDirection: SIMD2(0, -1)
        )
    }

    /// The throw of a tap on my die: it rises from where it rests, as it is turned,
    /// and leaves away from me. Nil when the die is not in my yard.
    func tapToss() -> LudoToss? {
        guard let die = dieNode, die.restsOnNearTray else { return nil }
        let back = LudoDieTray.near(waitingSlots: []).minimum.y
        return .standard(
            seed: UInt64.random(in: .min ... .max),
            rest: die.restPosition,
            target: SIMD2(die.restPosition.x, back),
            orientation: die.restOrientation
        )
    }

    /// The drag ended without a throw. The die settles back where it rested.
    func dropHeldDie() {
        guard heldDie != nil else { return }
        heldDie = nil
        releasedAt = nil
        returnDieToRest()
    }

    /// Moves a held die toward the finger for one frame. Returns false when no die
    /// is held. A die let go whose roll never came drops back.
    func updateHeldDie(deltaTime: Double) -> Bool {
        guard let held = heldDie, let die = dieNode else { return false }
        if let releasedAt, clock - releasedAt > 0.3 {
            dropHeldDie()
            return false
        }
        let current = die.currentPosition
        let follow = Float(1 - exp(-deltaTime * 30))
        die.apply(position: current + (held - current) * follow, orientation: die.currentOrientation, scale: 1)
        return true
    }

    /// Where the held die goes for the finger at `point`, kept inside the yard.
    private func holdPoint(at point: CGPoint) -> SIMD3<Float>? {
        guard let rig, let spot = rig.boardPoint(at: point, height: Double(holdHeight)) else { return nil }
        let tray = LudoDieTray.near(waitingSlots: [])
        let inset = LudoSceneStyle.dieSize / 2
        return SIMD3(
            min(max(Float(spot.x), tray.minimum.x + inset), tray.maximum.x - inset),
            holdHeight,
            min(max(Float(spot.y), tray.minimum.y + inset), tray.maximum.y - inset)
        )
    }

    // MARK: Flight

    /// The slots of `player`'s pawns that wait in their base on the board shown now.
    func waitingSlots(of player: BoardPlayer) -> [Int] {
        let first = player == .one ? 0 : LudoBoard.pawnsPerPlayer
        return (first..<(first + LudoBoard.pawnsPerPlayer)).compactMap { index in
            if case let .base(_, slot) = shownBoard.square(ofPawn: index) { return slot }
            return nil
        }
    }

    /// A pose of the throw's frame on this phone: the near yard as it is, the far
    /// yard turned half a circle around the middle of the board.
    static func worldPose(
        _ pose: (position: SIMD3<Float>, orientation: simd_quatf),
        isNear: Bool
    ) -> (position: SIMD3<Float>, orientation: simd_quatf) {
        guard !isNear else { return pose }
        let halfTurn = simd_quatf(angle: .pi, axis: SIMD3(0, 1, 0))
        return (halfTurn.act(pose.position), simd_normalize(halfTurn * pose.orientation))
    }
}

nonisolated extension LudoDieTray {
    /// The roller's yard as their own phone shows it, with their pawns that wait in
    /// these slots. The die bounces back from the edge of the yard's carved panel.
    static func near(waitingSlots: [Int]) -> LudoDieTray {
        let corner = LudoWorld.rollerCorner(isNear: true)
        let middle = LudoWorld.position(LudoBoardGeometry.yardCenter(corner: corner, viewer: .one))
        let half = 3 - LudoSceneStyle.yardPanelInset
        return LudoDieTray(
            floor: 0,
            minimum: SIMD2(middle.x - half, middle.z - half),
            maximum: SIMD2(middle.x + half, middle.z + half),
            pawns: waitingSlots.map { slot in
                let point = LudoWorld.position(LudoBoardGeometry.slotPoint(corner: corner, slot: slot, viewer: .one))
                return SIMD2(point.x, point.z)
            }
        )
    }
}

nonisolated extension LudoToss {
    /// The throw of a tap, picked by `seed`: the die rises from its resting spot and
    /// leaves away from the roller, give or take a little.
    static func tap(seed: UInt64) -> LudoToss {
        let rest = LudoWorld.dieRestPosition(isNear: true)
        let back = LudoDieTray.near(waitingSlots: []).minimum.y
        return standard(seed: seed, rest: rest, target: SIMD2(rest.x, back))
    }
}

nonisolated extension LudoPosition {
    /// A number both phones make from the position, for the throw of a tap.
    var tossSeed: UInt64 {
        var hash: UInt64 = 0xCBF2_9CE4_8422_2325
        for byte in gameID.uuidString.utf8 {
            hash = (hash ^ UInt64(byte)) &* 0x0000_0100_0000_01B3
        }
        for number in [gameNumber, moveCount] {
            hash = (hash ^ UInt64(bitPattern: Int64(number))) &* 0x0000_0100_0000_01B3
        }
        return hash
    }
}
