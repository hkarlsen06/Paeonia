import Combine
import RealityKit
import UIKit

/// Owns the 3D scene of the Ludo board. The board view gives it the screen's
/// state through `receive(_:)`, and RealityKit calls `tick(_:)` every frame.
///
/// The stage keeps the board it shows. When the newest move is one it has not
/// seen and it follows from that board, the stage animates it. Any other change
/// of the board shows at once. All motion comes from clips (see `LudoClip`) that
/// are pure functions of time, so a pawn always lands on its square.
@MainActor
final class LudoStage {
    /// What the board view knows. The stage compares it with the last one.
    struct Input: Equatable {
        let board: LudoBoard
        let lastMove: BoardMoveEvent?
        let styles: BoardPieceStyles
        /// The colors the two players picked.
        let colors: LudoColorPair
        let me: BoardPlayer
        let die: LudoDieState
        let movableChoices: [LudoChoice]
        let showsOutcome: Bool
        let reduceMotion: Bool
    }

    /// A move the stage started to show, for the VoiceOver announcement.
    struct PresentedMove: Equatable {
        let transition: LudoTransition
        let isMine: Bool
    }

    /// What `receive(_:)` found out.
    struct Update: Equatable {
        var presentedMove: PresentedMove?
        /// Seconds until the result starts to play, when it was asked for just now.
        var outcomeStartsIn: Double?
    }

    enum Target: Equatable {
        case die
        case pawn(Int)
    }

    // MARK: Scene

    // Made on first use, because SwiftUI creates the stage with every new copy of the board view.
    private(set) lazy var sceneRoot = Entity()
    private(set) lazy var camera = PerspectiveCamera()
    private(set) var isBuilt = false
    var viewer = BoardPlayer.one
    var pawns: [LudoPawnNode] = []
    var dieNode: LudoDieNode?
    var homeGlows: [ModelEntity] = []
    var capMaterials: [PhysicallyBasedMaterial] = []
    /// The board pieces that take the players' colors.
    var paint = LudoPaintTargets()
    /// Goes up with each new look, so a slow mark texture of an earlier one never lands over a later one.
    private var lookGeneration = 0
    private var targets: [Entity.ID: Target] = [:]
    private var updateSubscription: Cancellable?

    // MARK: Camera

    /// How far the camera stands for the view's shape, nil until the shape is known.
    var fit: LudoCameraFit?
    /// What the person's hands have done to the camera.
    var pose = LudoCameraPose.home
    /// The pose when two fingers went down. A pinch and a twist both start from it.
    var zoomStart: LudoCameraPose?
    /// The board point (x, z) under the fingers when the pinch began.
    var zoomAnchor: SIMD2<Double>?
    var glide: CameraGlide?
    var cameraNeedsUpdate = true
    /// Called when the camera stops moving, so VoiceOver can follow it.
    var onCameraSettled: ((LudoCameraRig) -> Void)?
    /// Called once the built scene has drawn a few frames, so the loading view can fade.
    var onReady: (() -> Void)?
    /// Called when my thrown die comes to rest, so my pawns can light up at once.
    var onDieLanded: (() -> Void)?
    private var framesSinceBuilt = 0

    struct CameraGlide {
        let from: LudoCameraPose
        let start: Double
    }

    /// Where the camera is now. Nil until the view's shape is known.
    var rig: LudoCameraRig? { fit?.rig(for: pose) }

    // MARK: State

    var input: Input?
    var clock: Double = 0
    var clips: [LudoClip] = []
    var shownBoard = LudoBoard.initial
    var presentedNumber: Int?
    var hasShownBoard = false
    var reduceMotion = false
    var lastTumbleToken: Int?
    /// My partner's roll that tumbled live, before their move arrived, and when
    /// that tumble ends. Their move then skips its own tumble.
    var partnerLiveRoll: (die: Int, endsAt: Double)?
    var diePlaced = false
    /// Where the die in the hand goes, while a drag holds it.
    var heldDie: SIMD3<Float>?
    /// When the finger let the held die go, and how it threw it. The die flies on
    /// with that throw until its roll arrives, which should be at once.
    var releasedAt: Double?
    var releasedToss: LudoToss?
    var outcomeWinner: BoardPlayer?
    var outcomeSchedule: OutcomeSchedule?
    var glowLevels: [Float] = [0, 0]
    var glowTargets: [Float] = [0, 0]
    var glowPulses: [Float] = [0, 0]
    var appliedGlows: [Float] = [-1, -1]

    struct OutcomeSchedule {
        let start: Double
        let winner: BoardPlayer
        var hasStarted = false
        var hasTapped = false
    }

    // MARK: Building

    /// Builds the scene into the view. Call it once, after the view exists.
    /// Returns what showing the first state found out, for example a result that is already on.
    @discardableResult
    func build(into arView: ARView, input: Input) async -> Update {
        // The screen may already have sent newer state than the view was made with.
        let input = self.input ?? input
        viewer = input.me
        self.input = input
        reduceMotion = input.reduceMotion
        async let environment = LudoBackdrop.environment()
        let parts = await LudoSceneBuilder.build(viewer: input.me, styles: input.styles, colors: input.colors)
        sceneRoot.addChild(parts.root)
        pawns = parts.pawns
        dieNode = parts.die
        homeGlows = parts.homeGlows
        capMaterials = parts.capMaterials
        paint = parts.paint
        targets[parts.die.root.id] = .die
        for pawn in parts.pawns { targets[pawn.root.id] = .pawn(pawn.index) }

        // The floor fills the view, so this color shows only before the scene draws.
        // The sky picture only lights the pieces.
        arView.environment.background = .color(LudoSceneStyle.color(LudoSceneStyle.roomHex))
        if let environment = await environment {
            arView.environment.lighting.resource = environment
            arView.environment.lighting.intensityExponent = LudoSceneStyle.environmentExposure
        }
        camera.camera = PerspectiveCameraComponent(
            near: LudoSceneStyle.cameraNear,
            far: LudoSceneStyle.cameraFar,
            fieldOfViewInDegrees: Float(LudoSceneStyle.cameraFieldOfViewDegrees),
            fieldOfViewOrientation: .vertical
        )
        let anchor = AnchorEntity(world: .zero)
        anchor.addChild(sceneRoot)
        anchor.addChild(camera)
        arView.scene.addAnchor(anchor)
        cameraNeedsUpdate = true
        applyCamera()
        updateSubscription = arView.scene.subscribe(to: SceneEvents.Update.self) { [weak self] event in
            MainActor.assumeIsolated { self?.tick(event.deltaTime) }
        }
        isBuilt = true
        // The screen may have sent newer state while the scene was building. Compare
        // it with what the scene was built from, so new marks still reach the pawns.
        let latest = self.input ?? input
        self.input = input
        return receive(latest)
    }

    // MARK: Input

    /// Takes the screen's state. Safe to call again with the same state.
    @discardableResult
    func receive(_ new: Input) -> Update {
        let old = input
        input = new
        reduceMotion = new.reduceMotion
        guard isBuilt, pawns.count == LudoBoard.pawnsPerPlayer * 2, dieNode != nil else { return Update() }
        var update = Update()
        if let old, old.styles != new.styles || old.colors != new.colors {
            refreshLook(new)
        }
        update.presentedMove = syncBoard(new)
        syncMovable(new)
        // The die state can still carry the roll of a partner move this update just
        // played. That roll must not tumble again or mark a later move as rolled.
        syncDie(new.die, afterPartnerMove: update.presentedMove?.isMine == false)
        update.outcomeStartsIn = syncOutcome(new)
        return update
    }

    private func syncMovable(_ new: Input) {
        for pawn in pawns {
            let own = pawn.player == viewer
            let pawnNumber = pawn.index % LudoBoard.pawnsPerPlayer
            pawn.isMovable = own && new.movableChoices.contains { $0 != .pass && $0.rawValue == pawnNumber }
        }
    }

    /// Paints the pawns and the glows in the players' colors, then paints the board top
    /// again and puts their marks on the pawn tops.
    private func refreshLook(_ new: Input) {
        let colors = LudoSceneBuilder.CornerColors(viewer: viewer, colors: new.colors)
        LudoSceneBuilder.repaintGlows(paint, colors: colors)
        for pawn in pawns {
            pawn.setColor(colors.pawnColor(of: pawn.player))
        }
        lookGeneration += 1
        let generation = lookGeneration
        let styles = new.styles
        let viewer = viewer
        Task { @MainActor in
            let board = await LudoSceneBuilder.boardTopMaterial(viewer: viewer, colors: colors)
            let materials = await LudoSceneBuilder.makeCapMaterials(styles: styles, colors: colors)
            guard generation == lookGeneration else { return }
            if let board { paint.boardTop?.model?.materials = [board] }
            guard materials.count == 2 else { return }
            capMaterials = materials
            for pawn in pawns {
                pawn.setCapMaterial(materials[pawn.player.rawValue - 1])
            }
        }
    }

    // MARK: Taps

    /// What a tap on this entity means, looking up through its parents.
    func target(of entity: Entity) -> Target? {
        var current: Entity? = entity
        while let candidate = current {
            if let target = targets[candidate.id] { return target }
            current = candidate.parent
        }
        return nil
    }

    // MARK: Frames

    func tick(_ deltaTime: Double) {
        if isBuilt, let onReady {
            framesSinceBuilt += 1
            if framesSinceBuilt >= 3 {
                self.onReady = nil
                onReady()
            }
        }
        let step = min(max(deltaTime, 0), 0.1)
        clock += step
        playClips()
        updateOutcomeSchedule()
        updateCamera()
        for pawn in pawns {
            if hasClip(.pawn(pawn.index)) {
                pawn.updateDim(deltaTime: step)
            } else {
                pawn.updateIdle(deltaTime: step, clock: clock, reduceMotion: reduceMotion)
            }
        }
        if let dieNode, !hasClip(.die), !updateHeldDie(deltaTime: step) {
            dieNode.updateIdle(clock: clock, isReady: input?.die == .ready, reduceMotion: reduceMotion)
        }
        updateGlows(deltaTime: step)
    }

    private func playClips() {
        let now = clock
        let finished = clips.filter { $0.play(at: now) }
        guard !finished.isEmpty else { return }
        clips.removeAll { clip in finished.contains { $0 === clip } }
        for clip in finished { clip.onFinish?() }
    }

    func hasClip(_ owner: LudoClip.Owner) -> Bool {
        clips.contains { $0.owner == owner }
    }

    /// Starts a clip. It replaces a clip of the same owner, which jumps to its end.
    func add(_ clip: LudoClip) {
        if let existing = clips.first(where: { $0.owner == clip.owner }) {
            existing.finishNow()
            clips.removeAll { $0 === existing }
            existing.onFinish?()
        }
        clips.append(clip)
    }

    /// Every clip jumps to its last pose, so a new move starts from a settled board.
    /// Ends every clip at once, except the die's while `keepsDie` is set.
    func finishAllClips(keepsDie: Bool = false) {
        let running = keepsDie ? clips.filter { $0.owner != .die } : clips
        clips = keepsDie ? clips.filter { $0.owner == .die } : []
        for clip in running {
            clip.finishNow()
            clip.onFinish?()
        }
    }

    /// Seconds until every pawn stands still. The die and a home glow may still move.
    var pawnTimeLeft: Double {
        let pawnClips = clips.filter { if case .pawn = $0.owner { true } else { false } }
        return max(0, (pawnClips.map(\.end).max() ?? clock) - clock)
    }

    // MARK: Pawn shake

    /// A pawn that cannot move shakes, and the phone taps twice.
    func shake(pawn index: Int) {
        PaeoniaHaptics.gameWrongGuess()
        GameSound.wrong.play(volume: 0.8)
        guard !reduceMotion, pawns.indices.contains(index), !hasClip(.pawn(index)) else { return }
        let pawn = pawns[index]
        let duration = LudoSceneStyle.shakeDuration
        add(LudoClip(owner: .pawn(index), start: clock, duration: duration) { time in
            let offset = LudoMotion.shake(progress: time / duration)
            pawn.apply(position: pawn.rest + SIMD3(offset, 0, 0), scale: pawn.restScale)
        })
    }
}
