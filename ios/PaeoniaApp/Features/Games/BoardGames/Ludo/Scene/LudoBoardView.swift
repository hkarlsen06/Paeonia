import RealityKit
import SwiftUI
import UIKit

/// The Ludo board: a real 3D scene made in code with RealityKit. The board is a
/// rounded slab seen from above at an angle, with raised tiles, a pair of pawns
/// for each player and a die in the base of whoever rolls. My base is always at the
/// bottom left, nearest me.
///
/// When `lastMove.number` changes and the move follows from the board the scene
/// shows, the scene animates it: for the partner's move their die tumbles first
/// (the scene does that itself), then the pawn hops. Any other change of the
/// board shows at once. The screen around the board owns my die, the choices,
/// the status line and the timing of `showsOutcome`.
///
/// The view fills the space it is given and fits the board inside the middle
/// `boardFitHeight` of it. One finger plays and never moves the camera: a tap picks a
/// pawn, and while my die waits for its throw a drag anywhere picks it up and letting
/// go throws it. A tap on the die does nothing. Two fingers pinch to zoom and slide
/// the board, and a double tap goes back to the default view.
struct LudoBoardView: View {
    let board: LudoBoard
    /// The newest move. The board animates it when `number` changes.
    let lastMove: BoardMoveEvent?
    let styles: BoardPieceStyles
    /// The colors the two players picked. Pink and lavender until they pick.
    var colors = LudoColorPair.standard
    /// The player this phone plays as.
    let me: BoardPlayer
    let die: LudoDieState
    /// My pawns that glow and accept a tap. Empty while I can't choose.
    let movableChoices: [LudoChoice]
    /// Turns true when the result should play: the winner's home glows, the
    /// other pawns dim and the petals bloom.
    let showsOutcome: Bool
    /// Seeds the petal bloom, for example "<game id>:<game number>".
    let bloomSeed: String
    /// The partner's name for the VoiceOver announcements.
    let partnerName: String
    /// Rolls the die. Carries the throw when the person threw the die by hand.
    let onRoll: (LudoToss?) -> Void
    let onChoose: (LudoChoice) -> Void

    /// How long the die tumbles. The screen keeps the die rolling for this long.
    nonisolated static let tumbleDuration: Duration = .seconds(LudoSceneStyle.tumbleDuration)

    var body: some View {
        // The scene is built for one player, so a different player starts a new one.
        LudoBoardScene(inputs: self)
            .id(me)
    }
}

/// Holds the scene and its state for one player.
private struct LudoBoardScene: View {
    let inputs: LudoBoardView

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.boardFitHeight) private var fitHeight
    @State private var stage = LudoStage()
    @State private var bloomStart: Date?
    /// Where the camera last came to rest, so VoiceOver follows it.
    @State private var settledRig: LudoCameraRig?
    /// False until the scene has loaded and drawn. The loading view shows until then.
    @State private var isSceneReady = false
    /// When the loading view first showed, so it stays long enough to read as calm.
    @State private var loadingShownAt = Date()
    /// Whether this phone has ever zoomed the board. The zoom hint stays until it has.
    @AppStorage("paeonia.games.ludo.hasZoomedBoard.v2") private var hasZoomedBoard = false

    var body: some View {
        // Fills the space it is given. The shell decides how much that is.
        GeometryReader { proxy in
            let size = proxy.size
            let aspect = size.height > 0 ? Double(size.width / size.height) : LudoSceneStyle.viewAspect
            let rig = currentRig(aspect: aspect)
            let fit = [aspect, Double(fitHeight)]
            ZStack {
                sceneView
                    .accessibilityHidden(true)
                // It stays in place and fades. A removed view in a stack over the 3D view
                // vanishes at once instead of fading.
                LudoLoadingView()
                    .opacity(isSceneReady ? 0 : 1)
                    .allowsHitTesting(!isSceneReady)
                    .accessibilityHidden(isSceneReady)
                if isSceneReady, !hasZoomedBoard {
                    LudoGestureHints()
                }
                bloom(size: size, rig: rig)
                LudoAccessibilityLayer(
                    board: inputs.board,
                    me: inputs.me,
                    die: inputs.die,
                    movableChoices: inputs.movableChoices,
                    rig: rig,
                    size: size,
                    onRoll: { inputs.onRoll(stage.tapToss()) },
                    onChoose: inputs.onChoose
                )
            }
            .frame(width: size.width, height: size.height)
            .onChange(of: fit, initial: true) {
                stage.setAspect(aspect, fitHeight: Double(fitHeight))
            }
        }
        .onChange(of: stageInput, initial: true) { sync() }
        .onChange(of: inputs.showsOutcome) {
            if !inputs.showsOutcome { bloomStart = nil }
        }
    }

    private var sceneView: some View {
        LudoSceneView(
            stage: stage,
            input: stageInput,
            onUpdate: handle,
            onTarget: handleTap,
            onToss: handleToss,
            onSettled: { settledRig = $0 },
            onZoom: handleZoom,
            onReady: revealScene
        )
    }

    /// The first zoom on this phone hides the zoom hint for good.
    private func handleZoom() {
        guard !hasZoomedBoard else { return }
        withAnimation(reduceMotion ? nil : PaeoniaMotion.stateChange) {
            hasZoomedBoard = true
        }
    }

    /// Fades the loading view away once the scene has drawn. A fast load still shows the
    /// loading view for a moment, so it never flashes.
    private func revealScene() {
        let shown = Date().timeIntervalSince(loadingShownAt)
        let wait = max(0, LudoLoadingView.minimumShowTime - shown)
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(wait))
            withAnimation(reduceMotion ? nil : PaeoniaMotion.standardCurve(duration: LudoLoadingView.fadeDuration)) {
                isSceneReady = true
            }
        }
    }

    /// The camera the person has left, or the default one while the view's shape is new.
    private func currentRig(aspect: Double) -> LudoCameraRig {
        if let settledRig, abs(settledRig.aspect - aspect) < 0.001 { return settledRig }
        return LudoCameraRig.fitting(aspect: aspect, fitHeight: Double(fitHeight))
    }

    private var stageInput: LudoStage.Input {
        LudoStage.Input(
            board: inputs.board,
            lastMove: inputs.lastMove,
            styles: inputs.styles,
            colors: inputs.colors,
            me: inputs.me,
            die: inputs.die,
            movableChoices: inputs.movableChoices,
            showsOutcome: inputs.showsOutcome,
            reduceMotion: reduceMotion
        )
    }

    // MARK: Updates

    private func sync() {
        handle(stage.receive(stageInput))
    }

    private func handle(_ update: LudoStage.Update) {
        if let move = update.presentedMove {
            announce(move)
        }
        if let delay = update.outcomeStartsIn {
            bloomStart = Date().addingTimeInterval(delay + LudoSceneStyle.bloomDelay)
        }
    }

    /// Tells VoiceOver what a move was. A move of mine needs no announcement,
    /// except that nothing could move.
    private func announce(_ move: LudoStage.PresentedMove) {
        let transition = move.transition
        let partnerName = inputs.partnerName
        let text: String
        if transition.pawn == nil {
            text = String(localized: .ludoHintNoMove(transition.die))
        } else if move.isMine || partnerName.isEmpty {
            return
        } else if transition.sentHome.isEmpty {
            text = String(localized: .ludoAnnouncePartnerMoved(partnerName, transition.die))
        } else {
            text = String(localized: .ludoAnnouncePartnerSentHome(partnerName))
        }
        AccessibilityNotification.Announcement(text).post()
    }

    // MARK: Taps

    private func handleTap(_ target: LudoStage.Target) {
        switch target {
        case .die:
            // The die rolls only when thrown. A tap would roll it by accident.
            break
        case let .pawn(index):
            let owner: BoardPlayer = index < LudoBoard.pawnsPerPlayer ? .one : .two
            guard owner == inputs.me else { return }
            let number = index % LudoBoard.pawnsPerPlayer
            if let choice = inputs.movableChoices.first(where: { $0 != .pass && $0.rawValue == number }) {
                inputs.onChoose(choice)
            } else {
                stage.shake(pawn: index)
            }
        }
    }

    /// The person let go of the die they picked up.
    private func handleToss(_ toss: LudoToss) {
        if inputs.die == .ready {
            inputs.onRoll(toss)
        } else {
            stage.dropHeldDie()
        }
    }

    // MARK: Result

    /// The petal bloom rises from the middle of the board.
    @ViewBuilder
    private func bloom(size: CGSize, rig: LudoCameraRig) -> some View {
        if inputs.showsOutcome, inputs.board.outcome?.winner != nil, let bloomStart {
            let margin = size.width * 0.1
            let middle = rig.project(.zero) ?? CGPoint(x: 0.5, y: 0.5)
            GamePetalBloom(
                start: bloomStart,
                seed: inputs.bloomSeed,
                origin: UnitPoint(
                    x: (middle.x * size.width + margin) / (size.width + 2 * margin),
                    y: (middle.y * size.height + margin) / (size.height + 2 * margin)
                ),
                intensity: 0.9
            )
            .padding(-margin)
        }
    }
}

/// The 3D view. RealityKit's `ARView` in its non-AR mode, because it hands out the
/// touches as plain UIKit gestures. The room round the board fills it to its edges.
private struct LudoSceneView: UIViewRepresentable {
    let stage: LudoStage
    let input: LudoStage.Input
    let onUpdate: (LudoStage.Update) -> Void
    let onTarget: (LudoStage.Target) -> Void
    let onToss: (LudoToss) -> Void
    let onSettled: (LudoCameraRig) -> Void
    /// The person started zooming the board.
    let onZoom: () -> Void
    let onReady: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(stage: stage)
    }

    func makeUIView(context: Context) -> ARView {
        let view = ARView(frame: .zero, cameraMode: .nonAR, automaticallyConfigureSession: false)
        let room = LudoSceneStyle.color(LudoSceneStyle.roomHex)
        view.backgroundColor = room
        view.environment.background = .color(room)
        // The pawns carry each player's drawn mark, and replays record a 3D view as pixels.
        view.accessibilityIdentifier = PaeoniaAnalytics.hiddenFromReplaysAccessibilityToken
        // The key light draws the shadows. ARView would also put a soft blob under every
        // model, and the camera effects meant to match a real camera's picture only blur the board.
        view.renderOptions.formUnion([
            .disableGroundingShadows, .disableMotionBlur, .disableDepthOfField, .disableCameraGrain
        ])
        context.coordinator.parent = self
        context.coordinator.attach(to: view)
        stage.onCameraSettled = onSettled
        stage.onReady = onReady
        let stage = stage
        let input = input
        let onUpdate = onUpdate
        Task { @MainActor in
            let update = await stage.build(into: view, input: input)
            onUpdate(update)
        }
        return view
    }

    func updateUIView(_ view: ARView, context: Context) {
        context.coordinator.parent = self
        stage.onCameraSettled = onSettled
    }

    /// Turns touches into play and camera moves. One finger plays: a tap picks a pawn,
    /// and a drag carries the ready die and throws it. Two fingers pinch and twist the
    /// camera as one move, and a double tap resets it.
    @MainActor
    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var parent: LudoSceneView?
        private let stage: LudoStage
        private weak var view: ARView?
        private weak var pan: UIPanGestureRecognizer?
        private weak var doubleTap: UITapGestureRecognizer?
        /// The pinch's scale and the twist's angle in radians so far, and how many of
        /// the two recognizers run. Either one starts the camera move and both end it.
        private var pinchScale = 1.0
        private var twist = 0.0
        private var cameraGestures = 0

        init(stage: LudoStage) {
            self.stage = stage
        }

        func attach(to view: ARView) {
            self.view = view
            let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
            pan.maximumNumberOfTouches = 1
            pan.delegate = self
            self.pan = pan
            let pinch = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:)))
            pinch.delegate = self
            let rotation = UIRotationGestureRecognizer(target: self, action: #selector(handleRotation(_:)))
            rotation.delegate = self
            let doubleTap = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap(_:)))
            doubleTap.numberOfTapsRequired = 2
            doubleTap.delegate = self
            self.doubleTap = doubleTap
            let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
            tap.delegate = self
            for recognizer in [pan, pinch, rotation, doubleTap, tap] {
                view.addGestureRecognizer(recognizer)
            }
        }

        @objc private func handlePan(_ recognizer: UIPanGestureRecognizer) {
            switch recognizer.state {
            case .began:
                stage.pickUpDie(at: unitLocation(of: recognizer))
            case .changed:
                stage.moveHeldDie(to: unitLocation(of: recognizer))
            case .ended:
                throwDie(recognizer)
            case .cancelled, .failed:
                stage.dropHeldDie()
            default:
                break
            }
        }

        private func throwDie(_ recognizer: UIPanGestureRecognizer) {
            guard let view, view.bounds.width > 0, view.bounds.height > 0 else {
                stage.dropHeldDie()
                return
            }
            let speed = recognizer.velocity(in: view)
            let velocity = CGPoint(x: speed.x / view.bounds.width, y: speed.y / view.bounds.height)
            if let toss = stage.releaseDie(at: unitLocation(of: recognizer), velocity: velocity) {
                parent?.onToss(toss)
            }
        }

        @objc private func handlePinch(_ recognizer: UIPinchGestureRecognizer) {
            if recognizer.state == .changed { pinchScale = Double(recognizer.scale) }
            handleCameraGesture(recognizer)
        }

        @objc private func handleRotation(_ recognizer: UIRotationGestureRecognizer) {
            if recognizer.state == .changed { twist = Double(recognizer.rotation) }
            handleCameraGesture(recognizer)
        }

        private func handleCameraGesture(_ recognizer: UIGestureRecognizer) {
            switch recognizer.state {
            case .began:
                if cameraGestures == 0 {
                    pinchScale = 1
                    twist = 0
                    stage.beginZoom(at: unitLocation(of: recognizer))
                    parent?.onZoom()
                }
                cameraGestures += 1
            case .changed:
                // With one finger lifted the place jumps to the other finger, so hold still until the move ends.
                guard recognizer.numberOfTouches == 2 else { return }
                stage.zoom(scale: pinchScale, twist: twist, at: unitLocation(of: recognizer))
            case .ended, .cancelled, .failed:
                cameraGestures = max(cameraGestures - 1, 0)
                if cameraGestures == 0 { stage.endZoom() }
            default:
                break
            }
        }

        /// Where the gesture is, from 0 to 1 across and down the view.
        private func unitLocation(of recognizer: UIGestureRecognizer) -> CGPoint {
            guard let view, view.bounds.width > 0, view.bounds.height > 0 else { return CGPoint(x: 0.5, y: 0.5) }
            let location = recognizer.location(in: view)
            return CGPoint(x: location.x / view.bounds.width, y: location.y / view.bounds.height)
        }

        @objc private func handleDoubleTap(_ recognizer: UITapGestureRecognizer) {
            guard recognizer.state == .ended else { return }
            stage.resetCamera()
        }

        @objc private func handleTap(_ recognizer: UITapGestureRecognizer) {
            guard recognizer.state == .ended, let view,
                  let entity = view.entity(at: recognizer.location(in: view)),
                  let target = stage.target(of: entity)
            else { return }
            parent?.onTarget(target)
        }

        /// A drag only starts while my die waits for its throw. Otherwise one finger does nothing but tap.
        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            gestureRecognizer !== pan || stage.canPickUpDie
        }

        /// A double tap resets the camera only on the board around the pieces, so
        /// a quick second tap on the die or a pawn never also moves the view.
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            guard gestureRecognizer === doubleTap, let view else { return true }
            guard let entity = view.entity(at: touch.location(in: view)) else { return true }
            return stage.target(of: entity) == nil
        }

        /// A drag and a pinch can run together, so a pinch that starts with one finger down does not stall.
        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            true
        }
    }
}
