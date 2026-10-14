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
/// The view fills the space it is given. A one-finger drag orbits the board, a
/// pinch zooms and a double tap goes back to the default view.
struct LudoBoardView: View {
    let board: LudoBoard
    /// The newest move. The board animates it when `number` changes.
    let lastMove: BoardMoveEvent?
    let styles: BoardPieceStyles
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
    let onRoll: () -> Void
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
    @State private var stage = LudoStage()
    @State private var bloomStart: Date?
    /// Where the camera last came to rest, so VoiceOver follows it.
    @State private var settledRig: LudoCameraRig?

    var body: some View {
        // Fills the space it is given. The shell decides how much that is.
        GeometryReader { proxy in
            let size = proxy.size
            let aspect = size.height > 0 ? Double(size.width / size.height) : LudoSceneStyle.viewAspect
            let overshoot = LudoSceneStyle.cameraOvershoot(forViewWidth: Double(size.width))
            let rig = currentRig(aspect: aspect, overshoot: overshoot)
            ZStack {
                LudoSceneView(
                    stage: stage,
                    input: stageInput,
                    onUpdate: handle,
                    onTarget: handleTap,
                    onSettled: { settledRig = $0 }
                )
                .accessibilityHidden(true)
                bloom(size: size, rig: rig)
                LudoAccessibilityLayer(
                    board: inputs.board,
                    me: inputs.me,
                    die: inputs.die,
                    movableChoices: inputs.movableChoices,
                    rig: rig,
                    size: size,
                    onRoll: inputs.onRoll,
                    onChoose: inputs.onChoose
                )
            }
            .frame(width: size.width, height: size.height)
            .onChange(of: [aspect, overshoot], initial: true) { stage.setAspect(aspect, overshoot: overshoot) }
        }
        .onChange(of: stageInput, initial: true) { sync() }
        .onChange(of: inputs.showsOutcome) {
            if !inputs.showsOutcome { bloomStart = nil }
        }
    }

    /// The camera the person has left, or the default one while the view's shape is new.
    private func currentRig(aspect: Double, overshoot: Double) -> LudoCameraRig {
        if let settledRig, abs(settledRig.aspect - aspect) < 0.001 { return settledRig }
        return LudoCameraRig.fitting(aspect: aspect, overshoot: overshoot)
    }

    private var stageInput: LudoStage.Input {
        LudoStage.Input(
            board: inputs.board,
            lastMove: inputs.lastMove,
            styles: inputs.styles,
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
            if inputs.die == .ready { inputs.onRoll() }
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

/// The 3D view. RealityKit's `ARView` in its non-AR mode, because it can draw
/// with a clear background, so the screen shows through around the board, and it
/// hands out the touches as plain UIKit gestures.
private struct LudoSceneView: UIViewRepresentable {
    let stage: LudoStage
    let input: LudoStage.Input
    let onUpdate: (LudoStage.Update) -> Void
    let onTarget: (LudoStage.Target) -> Void
    let onSettled: (LudoCameraRig) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(stage: stage)
    }

    func makeUIView(context: Context) -> ARView {
        let view = ARView(frame: .zero, cameraMode: .nonAR, automaticallyConfigureSession: false)
        view.backgroundColor = .clear
        view.isOpaque = false
        view.environment.background = .color(.clear)
        context.coordinator.parent = self
        context.coordinator.attach(to: view)
        stage.onCameraSettled = onSettled
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

    /// Turns touches into camera moves and taps on pieces. One finger orbits, two
    /// fingers pinch, a double tap resets, and a tap that does not move picks a piece.
    @MainActor
    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var parent: LudoSceneView?
        private let stage: LudoStage
        private weak var view: ARView?
        private weak var doubleTap: UITapGestureRecognizer?

        init(stage: LudoStage) {
            self.stage = stage
        }

        func attach(to view: ARView) {
            self.view = view
            let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
            pan.maximumNumberOfTouches = 1
            pan.delegate = self
            let pinch = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:)))
            pinch.delegate = self
            let doubleTap = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap(_:)))
            doubleTap.numberOfTapsRequired = 2
            doubleTap.delegate = self
            self.doubleTap = doubleTap
            let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
            tap.delegate = self
            for recognizer in [pan, pinch, doubleTap, tap] {
                view.addGestureRecognizer(recognizer)
            }
        }

        @objc private func handlePan(_ recognizer: UIPanGestureRecognizer) {
            switch recognizer.state {
            case .began:
                stage.beginOrbit()
                recognizer.setTranslation(.zero, in: recognizer.view)
            case .changed:
                let move = recognizer.translation(in: recognizer.view)
                recognizer.setTranslation(.zero, in: recognizer.view)
                stage.orbit(byX: Double(move.x), y: Double(move.y))
            case .ended:
                let speed = recognizer.velocity(in: recognizer.view)
                stage.endOrbit(velocityX: Double(speed.x), velocityY: Double(speed.y))
            case .cancelled, .failed:
                stage.endOrbit(velocityX: 0, velocityY: 0)
            default:
                break
            }
        }

        @objc private func handlePinch(_ recognizer: UIPinchGestureRecognizer) {
            switch recognizer.state {
            case .began:
                stage.beginZoom(at: unitLocation(of: recognizer))
            case .changed:
                // With one finger lifted the place jumps to the other finger, so hold still until the pinch ends.
                guard recognizer.numberOfTouches == 2 else { return }
                stage.zoom(scale: Double(recognizer.scale), at: unitLocation(of: recognizer))
            case .ended, .cancelled, .failed:
                stage.endZoom()
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
