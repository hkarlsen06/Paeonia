import MapLibre
import SwiftUI
import UIKit.UIGestureRecognizerSubclass

/// PROTOTYPE. Lets the person drag and pinch Home's map to look around, and brings it back
/// to the couple. While they explore, the map stops following the couple's framing.
@MainActor @Observable
final class HomeMapExplorer {
    private(set) var isExploring = false
    /// The map's zoom and direction when the person started moving it.
    @ObservationIgnored private(set) var start: (zoom: Double, direction: Double)?
    /// Set by the map once its intro has played. Gestures do nothing without it.
    @ObservationIgnored private(set) weak var map: MLNMapView?
    /// Moves the map back to the couple's framing.
    @ObservationIgnored private var reframe: () -> Void = {}
    /// The parts of the screen over the map, in window points, by name.
    @ObservationIgnored private var areas: [String: CGRect] = [:]

    /// Street level.
    private static let closestZoom: Double = 17
    /// How far a fling carries on, in seconds of its speed at release.
    private static let flingReach: CGFloat = 0.25
    private static let flingDuration: TimeInterval = 0.6

    func attach(_ map: MLNMapView, reframe: @escaping () -> Void) {
        self.map = map
        self.reframe = reframe
        isExploring = false
        start = nil
    }

    /// Keeps the place under the fingers' last midpoint under their new one, and zooms and
    /// turns the map around it as the fingers spread, close or twist. `turn` is in radians,
    /// clockwise on screen.
    func move(from previous: CGPoint, to point: CGPoint, scale: CGFloat, turn: CGFloat) {
        guard let map, scale > 0 else { return }
        let widest = log2(max(512, Double(map.bounds.height)) / 512)
        let zoom = min(max(map.zoomLevel + log2(Double(scale)), widest), Self.closestZoom)
        let direction = map.direction - Double(turn) * 180 / .pi
        place(map.convert(previous, toCoordinateFrom: map), at: point, zoom: zoom, direction: direction, on: map)
    }

    /// Glides on in the direction of a fast release, slowing to a stop.
    func fling(velocity: CGPoint) {
        guard let map, hypot(velocity.x, velocity.y) > 200 else { return }
        let middle = CGPoint(x: map.bounds.midX, y: map.bounds.midY)
        let camera = map.camera
        camera.centerCoordinate = map.convert(
            CGPoint(x: middle.x - velocity.x * Self.flingReach, y: middle.y - velocity.y * Self.flingReach),
            toCoordinateFrom: map
        )
        map.setCamera(
            camera,
            withDuration: Self.flingDuration,
            animationTimingFunction: HomeMapLibreTimingFunction(controlPoints: 0.22, 1, 0.36, 1)
        )
    }

    func setArea(_ name: String, _ frame: CGRect?) {
        areas[name] = frame
    }

    /// Whether a finger landing at `point`, in window points, lands on the map.
    func isOverMap(_ point: CGPoint) -> Bool {
        map != nil && areas.values.contains { $0.contains(point) }
    }

    func showBoth() {
        isExploring = false
        start = nil
        reframe()
    }

    private func place(
        _ coordinate: CLLocationCoordinate2D, at point: CGPoint, zoom: Double, direction: Double, on map: MLNMapView
    ) {
        if !isExploring {
            start = (map.zoomLevel, map.direction)
            isExploring = true
        }
        map.tileLodZoomShift = HomeMapLibreView.tileDetailShift(zoom: zoom)
        let center = HomeMapLibreView.mapCenter(
            putting: HomeMapLibreView.mercator(coordinate),
            at: point,
            worldSize: 512 * pow(2, zoom),
            turn: direction * .pi / 180,
            viewSize: map.bounds.size
        )
        map.setCenter(
            HomeMapLibreView.coordinate(center),
            zoomLevel: zoom,
            direction: HomeMapLibreView.heading(direction),
            animated: false
        )
    }
}

extension EnvironmentValues {
    /// PROTOTYPE. Home's map, for views over it that pass a drag or a pinch on to it.
    @Entry var homeMapExplorer: HomeMapExplorer?
}

extension View {
    /// A drag or a pinch that starts on one of the explorer's areas moves Home's map. Taps
    /// still reach the views here.
    func homeMapGestures(_ explorer: HomeMapExplorer) -> some View {
        gesture(HomeMapGesture(explorer: explorer))
    }

    /// Marks this view as lying over Home's map, so a drag or a pinch on it moves the map.
    func homeMapArea(_ name: String, _ explorer: HomeMapExplorer?) -> some View {
        onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frame in
            explorer?.setArea(name, frame)
        }
        .onDisappear { explorer?.setArea(name, nil) }
    }
}

/// One finger drags the map. Two drag it by their midpoint, zoom it by their spread and
/// turn it by their twist.
private struct HomeMapGesture: UIGestureRecognizerRepresentable {
    let explorer: HomeMapExplorer

    func makeCoordinator(converter: CoordinateSpaceConverter) -> HomeMapGestureTracker {
        HomeMapGestureTracker(explorer: explorer)
    }

    func makeUIGestureRecognizer(context: Context) -> HomeMapPanRecognizer {
        let pan = HomeMapPanRecognizer()
        pan.maximumNumberOfTouches = 2
        pan.delegate = context.coordinator
        return pan
    }

    func handleUIGestureRecognizerAction(_ pan: HomeMapPanRecognizer, context: Context) {
        guard let map = explorer.map else { return }
        let tracker = context.coordinator
        let point = pan.location(in: map)
        let fingers = pan.fingers
        switch pan.state {
        case .began:
            // The fingers have already moved a little before the drag is recognized, so the
            // first step catches up from where they went down.
            let moved = pan.translation(in: map)
            tracker.begin(at: CGPoint(x: point.x - moved.x, y: point.y - moved.y), fingers: pan.firstFingers ?? fingers)
        case .changed:
            guard let step = tracker.step(to: point, fingers: fingers) else { return }
            explorer.move(from: step.from, to: point, scale: step.scale, turn: step.turn)
        case .ended where !tracker.hadTwoFingers:
            explorer.fling(velocity: pan.velocity(in: map))
        default:
            break
        }
    }
}

/// How two fingers sit: how far apart, in points, and the angle of the line between them.
struct HomeMapFingers {
    let spread: CGFloat
    let angle: CGFloat

    /// How far the line between the fingers has turned since `earlier`, clockwise on
    /// screen. The line has no direction, so the turn is under a quarter turn either way,
    /// and the two fingers swapping places does not count.
    func twist(since earlier: Self) -> CGFloat {
        var twist = (angle - earlier.angle).truncatingRemainder(dividingBy: .pi)
        if twist > .pi / 2 { twist -= .pi }
        if twist < -.pi / 2 { twist += .pi }
        return twist
    }
}

/// A pan that also starts when two fingers spread, close or twist with their midpoint
/// still, which a plain pan never notices.
final class HomeMapPanRecognizer: UIPanGestureRecognizer {
    private static let pinchStart: CGFloat = 10
    /// Where two fingers were as they went down.
    private(set) var firstFingers: HomeMapFingers?
    /// Whether a finger of this gesture landed on the map.
    var touchedMap = false

    /// Nil for one finger.
    var fingers: HomeMapFingers? {
        guard numberOfTouches == 2 else { return nil }
        let first = location(ofTouch: 0, in: view)
        let second = location(ofTouch: 1, in: view)
        return HomeMapFingers(
            spread: hypot(first.x - second.x, first.y - second.y),
            angle: atan2(second.y - first.y, second.x - first.x)
        )
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesBegan(touches, with: event)
        if state == .possible, firstFingers == nil { firstFingers = fingers }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesMoved(touches, with: event)
        guard state == .possible, let fingers else { return }
        guard let firstFingers else {
            firstFingers = fingers
            return
        }
        if abs(fingers.spread - firstFingers.spread) > Self.pinchStart
            || abs(fingers.twist(since: firstFingers)) > HomeMapGestureTracker.turnStart {
            state = .began
        }
    }

    override func reset() {
        super.reset()
        firstFingers = nil
        touchedMap = false
    }
}

/// Follows the fingers from one moment to the next. Sees every finger on the page, so a
/// pinch whose first finger lands on the cards still zooms, and starts only when one of
/// them landed on the map. Home's scroll view waits until they stop moving the map.
final class HomeMapGestureTracker: NSObject, UIGestureRecognizerDelegate {
    /// How far two fingers twist before the map turns, so a pinch does not turn it.
    static let turnStart: CGFloat = 0.15

    private let explorer: HomeMapExplorer
    private var point = CGPoint.zero
    private var fingers: HomeMapFingers?
    /// How far the fingers have twisted since they went down, until the map starts turning.
    private var twist: CGFloat = 0
    private var turns = false
    /// A pinch ends with the fingers lifting one by one, which must not fling the map.
    private(set) var hadTwoFingers = false

    init(explorer: HomeMapExplorer) {
        self.explorer = explorer
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        if explorer.isOverMap(touch.location(in: nil)) {
            (gestureRecognizer as? HomeMapPanRecognizer)?.touchedMap = true
        }
        return true
    }

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        (gestureRecognizer as? HomeMapPanRecognizer)?.touchedMap == true
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldBeRequiredToFailBy other: UIGestureRecognizer
    ) -> Bool {
        (other.view as? UIScrollView)?.panGestureRecognizer === other
    }

    func begin(at point: CGPoint, fingers: HomeMapFingers?) {
        hadTwoFingers = false
        regrip(at: point, fingers: fingers)
    }

    struct Step {
        let from: CGPoint
        let scale: CGFloat
        let turn: CGFloat
    }

    /// Where the map should move from, and how much it should zoom and turn, as the fingers
    /// move to `point`. Nil when a finger lands or lifts, which moves the midpoint without
    /// moving the map.
    func step(to point: CGPoint, fingers: HomeMapFingers?) -> Step? {
        guard let fingers, let last = self.fingers else {
            let lastPoint = self.point
            let sameGrip = (fingers == nil) == (self.fingers == nil)
            regrip(at: point, fingers: fingers)
            return sameGrip ? Step(from: lastPoint, scale: 1, turn: 0) : nil
        }
        defer {
            self.point = point
            self.fingers = fingers
        }
        var turn = fingers.twist(since: last)
        if !turns {
            twist += turn
            turns = abs(twist) > Self.turnStart
            turn = 0
        }
        return Step(from: self.point, scale: fingers.spread / max(last.spread, 1), turn: turn)
    }

    private func regrip(at point: CGPoint, fingers: HomeMapFingers?) {
        self.point = point
        self.fingers = fingers
        twist = 0
        turns = false
        if fingers != nil { hadTwoFingers = true }
    }
}

/// Brings the map back to the couple after the person has moved it. It shows at the
/// trailing edge, just above where the map fades into the cards.
struct HomeMapShowBothButton: View {
    let explorer: HomeMapExplorer
    /// The bottom of the open map, in the map's points.
    let mapBottom: CGFloat

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            if explorer.isExploring {
                Button { explorer.showBoth() } label: {
                    Image(systemName: "location.fill")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.paeoniaAccentPrimary)
                        .frame(width: PaeoniaSpacing.compactButtonHeight, height: PaeoniaSpacing.compactButtonHeight)
                }
                .buttonStyle(.plain)
                .glassEffect(.regular.interactive(), in: Circle())
                .accessibilityLabel(Text(.homeMapShowBoth))
                .transition(.opacity)
            }
        }
        .animation(reduceMotion ? nil : PaeoniaMotion.stateChange, value: explorer.isExploring)
        .padding(.trailing, PaeoniaSpacing.screenHorizontalPadding)
        .frame(maxWidth: .infinity, alignment: .trailing)
        .offset(y: mapBottom - PaeoniaSpacing.compactButtonHeight - PaeoniaSpacing.space8)
    }
}
