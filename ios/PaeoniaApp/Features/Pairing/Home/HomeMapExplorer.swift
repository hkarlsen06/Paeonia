import MapLibre
import SwiftUI
import UIKit.UIGestureRecognizerSubclass

/// PROTOTYPE. Lets the person drag and pinch Home's map to look around, and brings it back
/// to the couple. While they explore, the map stops following the couple's framing.
@MainActor @Observable
final class HomeMapExplorer {
    private(set) var isExploring = false
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
    }

    /// Keeps the place under the fingers' last midpoint under their new one, and zooms
    /// around it by how much the fingers spread or close.
    func move(from previous: CGPoint, to point: CGPoint, scale: CGFloat) {
        guard let map, scale > 0 else { return }
        let widest = log2(max(512, Double(map.bounds.height)) / 512)
        let zoom = min(max(map.zoomLevel + log2(Double(scale)), widest), Self.closestZoom)
        place(map.convert(previous, toCoordinateFrom: map), at: point, zoom: zoom, on: map)
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
        reframe()
    }

    private func place(_ coordinate: CLLocationCoordinate2D, at point: CGPoint, zoom: Double, on map: MLNMapView) {
        isExploring = true
        let center = HomeMapLibreView.mapCenter(
            putting: HomeMapLibreView.mercator(coordinate),
            at: point,
            worldSize: 512 * pow(2, zoom),
            turn: map.direction * .pi / 180,
            viewSize: map.bounds.size
        )
        map.setCenter(
            HomeMapLibreView.coordinate(center), zoomLevel: zoom, direction: map.direction, animated: false
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

/// One finger drags the map. Two drag it by their midpoint and zoom it by their spread.
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
        let spread = pan.spread
        switch pan.state {
        case .began:
            // The finger has already moved a little before the drag is recognized.
            let moved = pan.translation(in: map)
            tracker.start(at: CGPoint(x: point.x - moved.x, y: point.y - moved.y), spread: spread)
        case .changed:
            // A finger landing or lifting moves the midpoint without moving the map.
            guard (spread == nil) == (tracker.spread == nil) else {
                tracker.start(at: point, spread: spread)
                return
            }
            let scale = spread.flatMap { now in tracker.spread.map { now / max($0, 1) } } ?? 1
            explorer.move(from: tracker.point, to: point, scale: scale)
            tracker.start(at: point, spread: spread)
        case .ended where tracker.spread == nil:
            explorer.fling(velocity: pan.velocity(in: map))
        default:
            break
        }
    }
}

/// A pan that also starts when two fingers spread or close with their midpoint still,
/// which a plain pan never notices.
final class HomeMapPanRecognizer: UIPanGestureRecognizer {
    private static let pinchStart: CGFloat = 10
    private var firstSpread: CGFloat?

    /// How far apart two fingers are, in points. Nil for one finger.
    var spread: CGFloat? {
        guard numberOfTouches == 2 else { return nil }
        let first = location(ofTouch: 0, in: view)
        let second = location(ofTouch: 1, in: view)
        return hypot(first.x - second.x, first.y - second.y)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesMoved(touches, with: event)
        guard state == .possible, let spread else { return }
        guard let firstSpread else {
            firstSpread = spread
            return
        }
        if abs(spread - firstSpread) > Self.pinchStart {
            state = .began
        }
    }

    override func reset() {
        super.reset()
        firstSpread = nil
    }
}

/// The last midpoint and spread of the fingers. Takes only fingers that land on the map,
/// and Home's scroll view waits until they stop moving it.
final class HomeMapGestureTracker: NSObject, UIGestureRecognizerDelegate {
    private let explorer: HomeMapExplorer
    private(set) var point = CGPoint.zero
    private(set) var spread: CGFloat?

    init(explorer: HomeMapExplorer) {
        self.explorer = explorer
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        explorer.isOverMap(touch.location(in: nil))
    }

    func start(at point: CGPoint, spread: CGFloat?) {
        self.point = point
        self.spread = spread
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldBeRequiredToFailBy other: UIGestureRecognizer
    ) -> Bool {
        (other.view as? UIScrollView)?.panGestureRecognizer === other
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
