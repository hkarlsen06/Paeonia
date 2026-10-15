import Foundation
import simd

/// How the die leaves the hand. Positions and directions are in the frame of the
/// near yard: the scene as the roller's own phone shows it, with the roller's yard
/// at the bottom left. The partner's phone turns it half a circle onto its far
/// yard, so both phones play the same flight. It travels in `LudoLiveMessage`.
nonisolated struct LudoToss: Codable, Equatable, Sendable {
    var position: SIMD3<Float>
    /// The die's turn, as the vector of a quaternion.
    var turn: SIMD4<Float>
    var velocity: SIMD3<Float>
    /// Radians a second around each axis.
    var spin: SIMD3<Float>

    init(position: SIMD3<Float>, orientation: simd_quatf, velocity: SIMD3<Float>, spin: SIMD3<Float>) {
        self.position = position
        turn = orientation.vector
        self.velocity = velocity
        self.spin = spin
    }

    var orientation: simd_quatf { simd_normalize(simd_quatf(vector: turn)) }

    /// A toss from `position` that moves along the floor at `floorVelocity` (x, z),
    /// rises a little and rolls forward, as a die does when it leaves the fingers.
    /// A slow flick still throws at the smallest speed, so every roll tumbles.
    static func thrown(
        from position: SIMD3<Float>,
        orientation: simd_quatf,
        floorVelocity: SIMD2<Float>,
        fallbackDirection: SIMD2<Float>
    ) -> LudoToss {
        let speed = simd_length(floorVelocity)
        let direction = speed > 0.01 ? floorVelocity / speed : simd_normalize(fallbackDirection)
        let clamped = min(max(speed, LudoSceneStyle.tossMinimumSpeed), LudoSceneStyle.tossMaximumSpeed)
        let along = SIMD3(direction.x, 0, direction.y)
        return LudoToss(
            position: position,
            orientation: orientation,
            velocity: along * clamped + SIMD3(0, LudoSceneStyle.tossRise, 0),
            spin: simd_cross(SIMD3(0, 1, 0), along) * clamped * LudoSceneStyle.tossRollPerSpeed
        )
    }

    /// The toss of a tap, picked by `seed` so both phones make the same one. The die
    /// rises from `rest` and leaves toward `target`, give or take a little, turned as
    /// `orientation` or a way the seed picks.
    static func standard(
        seed: UInt64,
        rest: SIMD3<Float>,
        target: SIMD2<Float>,
        orientation: simd_quatf? = nil
    ) -> LudoToss {
        var random = LudoRandom(seed: seed)
        let start = rest + SIMD3(0, LudoSceneStyle.dieHoldLift, 0)
        let aim = target - SIMD2(start.x, start.z)
        let turnAside = random.float(in: -0.5...0.5)
        let direction = simd_float2x2(
            SIMD2(cos(turnAside), sin(turnAside)),
            SIMD2(-sin(turnAside), cos(turnAside))
        ) * simd_normalize(aim)
        let speed = random.float(in: LudoSceneStyle.tossMinimumSpeed...(LudoSceneStyle.tossMinimumSpeed + 2))
        let picked = simd_quatf(angle: random.float(in: 0...(2 * .pi)), axis: SIMD3(0, 1, 0))
            * LudoDieFaces.lift(Int(random.next() % 6) + 1)
        return thrown(
            from: start,
            orientation: orientation ?? picked,
            floorVelocity: direction * speed,
            fallbackDirection: aim
        )
    }

    /// The same toss with a different spin and a slightly different speed. The
    /// fingers set the direction. The spin is the part nobody can see.
    func varied(using random: inout LudoRandom) -> LudoToss {
        var toss = self
        toss.spin += random.vector(length: LudoSceneStyle.tossSpinJitter)
        let change = SIMD3(
            1 + random.float(in: -0.12...0.12),
            1,
            1 + random.float(in: -0.12...0.12)
        )
        toss.velocity *= change
        toss.velocity.y += random.float(in: -0.6...0.6)
        return toss
    }

    /// A number made from every value of the toss, so both phones vary it the same way.
    var seed: UInt64 {
        var hash: UInt64 = 0xCBF2_9CE4_8422_2325
        let values = [position.x, position.y, position.z, turn.x, turn.y, turn.z, turn.w]
            + [velocity.x, velocity.y, velocity.z, spin.x, spin.y, spin.z]
        for value in values {
            hash = (hash ^ UInt64(value.bitPattern)) &* 0x0000_0100_0000_01B3
        }
        return hash
    }
}

/// The part of a yard the die is thrown in, in the frame of the near yard: its
/// floor, the edges it bounces back from, and the waiting pawns it bounces off.
nonisolated struct LudoDieTray: Equatable, Sendable {
    var floor: Float
    /// The smallest and largest x and z the die may reach.
    var minimum: SIMD2<Float>
    var maximum: SIMD2<Float>
    /// The pawns waiting in the yard, as (x, z) of their middle.
    var pawns: [SIMD2<Float>] = []
}

/// The path of a thrown die, as poses one frame apart. The first pose is the toss
/// and the last one rests flat on the floor.
nonisolated struct LudoDieFlight: Equatable, Sendable {
    static let frameTime = 1.0 / 60

    var positions: [SIMD3<Float>]
    var orientations: [simd_quatf]
    /// Seconds into the flight when the die hits something hard enough to feel.
    var knocks: [Double]

    var duration: Double { Double(max(positions.count - 1, 0)) * Self.frameTime }

    /// The face on top at the end.
    var face: Int { LudoDiePhysics.face(of: orientations.last ?? simd_quatf(angle: 0, axis: SIMD3(0, 1, 0))) }

    func pose(at time: Double) -> (position: SIMD3<Float>, orientation: simd_quatf) {
        guard positions.count > 1 else {
            return (positions.first ?? .zero, orientations.first ?? simd_quatf(angle: 0, axis: SIMD3(0, 1, 0)))
        }
        let place = min(max(time / Self.frameTime, 0), Double(positions.count - 1))
        let index = min(Int(place), positions.count - 2)
        let fraction = Float(place - Double(index))
        return (
            simd_mix(positions[index], positions[index + 1], SIMD3(repeating: fraction)),
            simd_slerp(orientations[index], orientations[index + 1], fraction)
        )
    }

    /// The same flight with the die's faces swapped round, so `value` lands on top.
    /// The die is a cube, so the swap only shows in the pips.
    func relabeled(showing value: Int) -> LudoDieFlight {
        let landed = LudoDieFaces.face(face).normal
        let wanted = LudoDieFaces.face(value).normal
        let swap: simd_quatf
        if simd_dot(landed, wanted) < -0.5 {
            let axis = abs(wanted.x) > 0.5 ? SIMD3<Float>(0, 0, 1) : SIMD3<Float>(1, 0, 0)
            swap = simd_quatf(angle: .pi, axis: axis)
        } else {
            swap = simd_quatf(from: wanted, to: landed)
        }
        var flight = self
        flight.orientations = orientations.map { simd_normalize($0 * swap) }
        return flight
    }
}

/// A small rigid-body simulation of the die: gravity, bounces off the floor, the
/// yard's edges and the waiting pawns, and friction. It runs a whole throw ahead
/// in one go and is pure math, so both phones get the same flight and it is testable.
///
/// The number is picked before the throw, as the rules need. The simulation tries
/// the throw with slightly different spins until one lands on that number, so the
/// die really rolls there. If none does, the faces are swapped round under the throw.
nonisolated enum LudoDiePhysics {
    static func flight(for toss: LudoToss, showing value: Int, in tray: LudoDieTray) -> LudoDieFlight {
        var random = LudoRandom(seed: toss.seed)
        var first: LudoDieFlight?
        for attempt in 0..<LudoSceneStyle.tossAttempts {
            let candidate = attempt == 0 ? toss : toss.varied(using: &random)
            let result = simulate(candidate, in: tray)
            guard result.settled else { continue }
            if result.flight.face == value { return result.flight }
            if first == nil { first = result.flight }
        }
        return (first ?? simulate(toss, in: tray).flight).relabeled(showing: value)
    }

    /// The face whose side points most nearly up.
    static func face(of orientation: simd_quatf) -> Int {
        let up = orientation.inverse.act(SIMD3(0, 1, 0))
        return (1...6).max { simd_dot(LudoDieFaces.face($0).normal, up) < simd_dot(LudoDieFaces.face($1).normal, up) }
            ?? 1
    }

    // MARK: Simulation

    private static let stepsPerFrame = 2
    private static let step = Float(LudoDieFlight.frameTime) / Float(stepsPerFrame)
    /// The die is eight balls in its rounded corners, so it rests on a face at its full height.
    private static var cornerRadius: Float { LudoSceneStyle.dieCornerRadius }
    private static var halfSize: Float { LudoSceneStyle.dieSize / 2 }
    private static var corners: [SIMD3<Float>] {
        let inset = halfSize - cornerRadius
        let signs: [Float] = [-1, 1]
        return signs.flatMap { across in
            signs.flatMap { up in signs.map { deep in SIMD3(across, up, deep) * inset } }
        }
    }

    /// A cube's resistance to turning, for a mass of 1.
    private static var inverseInertia: Float { 6 / (LudoSceneStyle.dieSize * LudoSceneStyle.dieSize) }

    private struct Body {
        var position: SIMD3<Float>
        var orientation: simd_quatf
        var velocity: SIMD3<Float>
        var spin: SIMD3<Float>
    }

    /// Runs the throw. `settled` is false when the die was still moving at the time
    /// limit, and the flight then ends by setting it down flat.
    static func simulate(_ toss: LudoToss, in tray: LudoDieTray) -> (flight: LudoDieFlight, settled: Bool) {
        var body = Body(
            position: toss.position,
            orientation: toss.orientation,
            velocity: toss.velocity,
            spin: toss.spin
        )
        var flight = LudoDieFlight(positions: [body.position], orientations: [body.orientation], knocks: [])
        let frameLimit = Int(LudoSceneStyle.tossSettleLimit / LudoDieFlight.frameTime)
        var calm: Float = 0
        var lastKnock = -1.0
        var settled = false
        frames: for frame in 1...frameLimit {
            for substep in 0..<stepsPerFrame {
                let time = (Double(frame - 1) + Double(substep) / Double(stepsPerFrame)) * LudoDieFlight.frameTime
                let contact = advance(&body, in: tray)
                if contact.impact > LudoSceneStyle.tossKnockSpeed, time - lastKnock > 0.08 {
                    flight.knocks.append(time)
                    lastKnock = time
                }
                let isFlat = simd_dot(upFace(of: body.orientation), SIMD3(0, 1, 0)) > 0.985
                let isCalm = simd_length(body.velocity) < 0.3 && simd_length(body.spin) < 1
                calm = contact.touchesFloor && isCalm && isFlat ? calm + step : 0
            }
            flight.positions.append(body.position)
            flight.orientations.append(body.orientation)
            if calm >= 0.1 {
                settled = true
                break frames
            }
        }
        setDown(&flight, floor: tray.floor)
        return (flight, settled)
    }

    /// The direction of the face on top, in the world.
    private static func upFace(of orientation: simd_quatf) -> SIMD3<Float> {
        orientation.act(LudoDieFaces.face(face(of: orientation)).normal)
    }

    /// Eases the die from its last pose to resting exactly flat on the floor.
    private static func setDown(_ flight: inout LudoDieFlight, floor: Float) {
        guard let position = flight.positions.last, let orientation = flight.orientations.last else { return }
        let level = simd_normalize(simd_quatf(from: upFace(of: orientation), to: SIMD3(0, 1, 0)) * orientation)
        let rest = SIMD3(position.x, floor + halfSize, position.z)
        let frames = max(Int(LudoSceneStyle.tossSetDownTime / LudoDieFlight.frameTime), 1)
        for frame in 1...frames {
            let amount = Float(LudoMotion.smooth(Double(frame) / Double(frames)))
            flight.positions.append(simd_mix(position, rest, SIMD3(repeating: amount)))
            flight.orientations.append(simd_slerp(orientation, level, amount))
        }
    }

    /// One small step of time. Returns whether a corner touched the floor and the
    /// hardest hit, as the speed into the surface.
    private static func advance(_ body: inout Body, in tray: LudoDieTray) -> (touchesFloor: Bool, impact: Float) {
        body.velocity.y -= LudoSceneStyle.tossGravity * step
        body.position += body.velocity * step
        let turn = simd_quatf(real: 0, imag: body.spin) * body.orientation
        body.orientation = simd_normalize(simd_quatf(vector: body.orientation.vector + turn.vector * (0.5 * step)))

        var touchesFloor = false
        var impact: Float = 0
        var push = SIMD3<Float>.zero
        for corner in corners {
            let center = body.position + body.orientation.act(corner)
            for (normal, depth) in surfaces(touching: center, in: tray) {
                let point = center - normal * cornerRadius
                impact = max(impact, collide(&body, at: point, normal: normal))
                push = deepest(push, normal * depth)
                if normal.y > 0.5 { touchesFloor = true }
            }
        }
        body.position += push

        let linear = touchesFloor ? LudoSceneStyle.tossFloorDrag : LudoSceneStyle.tossAirDrag
        let angular = touchesFloor ? LudoSceneStyle.tossFloorSpinDrag : LudoSceneStyle.tossAirSpinDrag
        body.velocity *= exp(-linear * step)
        body.spin *= exp(-angular * step)
        return (touchesFloor, impact)
    }

    /// The surfaces a corner ball pokes into, with the direction out of each and how deep.
    private static func surfaces(touching center: SIMD3<Float>, in tray: LudoDieTray) -> [(SIMD3<Float>, Float)] {
        var found: [(SIMD3<Float>, Float)] = []
        let radius = cornerRadius
        let floorDepth = tray.floor - (center.y - radius)
        if floorDepth > 0 { found.append((SIMD3(0, 1, 0), floorDepth)) }
        let walls: [(SIMD3<Float>, Float)] = [
            (SIMD3(1, 0, 0), tray.minimum.x - (center.x - radius)),
            (SIMD3(-1, 0, 0), (center.x + radius) - tray.maximum.x),
            (SIMD3(0, 0, 1), tray.minimum.y - (center.z - radius)),
            (SIMD3(0, 0, -1), (center.z + radius) - tray.maximum.y)
        ]
        found += walls.filter { $0.1 > 0 }
        let pawnTop = tray.floor + LudoSceneStyle.pawnHeight
        guard center.y - radius < pawnTop else { return found }
        for pawn in tray.pawns {
            let away = SIMD2(center.x, center.z) - pawn
            let distance = simd_length(away)
            let depth = LudoSceneStyle.pawnBaseRadius + LudoSceneStyle.tossPawnClearance + radius - distance
            guard depth > 0, distance > 0.0001 else { continue }
            found.append((SIMD3(away.x / distance, 0, away.y / distance), depth))
        }
        return found
    }

    /// The larger of two pushes along each axis, so four corners on the floor lift the die once, not four times.
    private static func deepest(_ first: SIMD3<Float>, _ second: SIMD3<Float>) -> SIMD3<Float> {
        func pick(_ one: Float, _ other: Float) -> Float { abs(one) >= abs(other) ? one : other }
        return SIMD3(pick(first.x, second.x), pick(first.y, second.y), pick(first.z, second.z))
    }

    /// A bounce with friction at `point`. Returns the speed into the surface before it.
    private static func collide(_ body: inout Body, at point: SIMD3<Float>, normal: SIMD3<Float>) -> Float {
        let arm = point - body.position
        let pointVelocity = body.velocity + simd_cross(body.spin, arm)
        let into = simd_dot(pointVelocity, normal)
        guard into < 0 else { return 0 }
        let bounce = -into > LudoSceneStyle.tossBounceSpeed ? LudoSceneStyle.tossRestitution : 0
        let resistance = 1 + inverseInertia * simd_length_squared(simd_cross(arm, normal))
        let push = -(1 + bounce) * into / resistance
        apply(&body, impulse: normal * push, at: arm)

        let after = body.velocity + simd_cross(body.spin, arm)
        let sliding = after - normal * simd_dot(after, normal)
        let slide = simd_length(sliding)
        if slide > 0.0001 {
            let along = sliding / slide
            let grip = 1 + inverseInertia * simd_length_squared(simd_cross(arm, along))
            let friction = min(slide / grip, LudoSceneStyle.tossFriction * push)
            apply(&body, impulse: -along * friction, at: arm)
        }
        return -into
    }

    private static func apply(_ body: inout Body, impulse: SIMD3<Float>, at arm: SIMD3<Float>) {
        body.velocity += impulse
        body.spin += simd_cross(arm, impulse) * inverseInertia
    }
}

/// A small random number maker that gives the same numbers for the same seed on
/// every phone (SplitMix64).
nonisolated struct LudoRandom: Sendable {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var value = state
        value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
        value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
        return value ^ (value >> 31)
    }

    mutating func float(in range: ClosedRange<Float>) -> Float {
        let unit = Float(next() >> 40) / Float(1 << 24)
        return range.lowerBound + (range.upperBound - range.lowerBound) * unit
    }

    /// A direction picked evenly, `length` long.
    mutating func vector(length: Float) -> SIMD3<Float> {
        let height = float(in: -1...1)
        let angle = float(in: 0...(2 * .pi))
        let across = (1 - height * height).squareRoot()
        return SIMD3(across * cos(angle), height, across * sin(angle)) * length
    }
}
