import MapKit
import UIKit

/// The reveal's camera flights. MapKit's own animation ignores the duration it is
/// given, takes about a second and shrinks the view at an even pace in metres, so a
/// long flight crosses most zoom levels in its last tenth of a second, faster than
/// the map can draw them. These flights zoom at an even pace in zoom levels instead,
/// about the one point that stays put on the screen, and the reveal steps the camera
/// along them itself.
nonisolated enum GuessMySpotFlight {
    /// Where a flight from `start` to `end` is at `fraction`, 0 to 1, before easing.
    /// Both rects must have the same shape, as `GuessMySpotCamera.filling` makes them.
    static func view(from start: MKMapRect, to end: MKMapRect, at fraction: Double) -> MKMapRect {
        let end = unwrapped(end, near: start)
        let ratio = end.width / max(1, start.width)
        let scale = pow(ratio, fraction)
        let width = start.width * scale, height = start.height * scale
        let center: MKMapPoint
        if abs(log2(ratio)) < 0.01 {
            // About the same size: a plain pan.
            center = MKMapPoint(
                x: start.midX + (end.midX - start.midX) * fraction,
                y: start.midY + (end.midY - start.midY) * fraction
            )
        } else {
            // The point that sits at the same place on screen in both views.
            let fixed = MKMapPoint(
                x: (start.midX * ratio - end.midX) / (ratio - 1),
                y: (start.midY * ratio - end.midY) / (ratio - 1)
            )
            center = MKMapPoint(
                x: fixed.x + (start.midX - fixed.x) * scale,
                y: fixed.y + (start.midY - fixed.y) * scale
            )
        }
        return MKMapRect(x: center.x - width / 2, y: center.y - height / 2, width: width, height: height)
    }

    /// The views to draw ahead of a flight: its start, its end, and one every two
    /// zoom levels between them. The map shows a view from the images one or two
    /// levels up while its own load, so it never has nothing to draw.
    static func stops(from start: MKMapRect, to end: MKMapRect) -> [MKMapRect] {
        let levels = abs(log2(end.width / max(1, start.width)))
        let count = max(1, Int((levels / 2).rounded(.up)))
        return (0...count).map { view(from: start, to: end, at: Double($0) / Double(count)) }
    }

    /// Slow at both ends, even in the middle.
    static func eased(_ fraction: Double) -> Double {
        let clamped = min(1, max(0, fraction))
        return clamped * clamped * (3 - 2 * clamped)
    }

    /// Slow at both ends, but done with most of the zoom by the middle, so the
    /// closest views, whose images the map loads last, get the most time.
    static func easedDown(_ fraction: Double) -> Double {
        pow(eased(fraction), 0.6)
    }

    /// `rect` moved by a whole world width if that brings it closer to `other`, so a
    /// flight across the 180th meridian goes the short way.
    private static func unwrapped(_ rect: MKMapRect, near other: MKMapRect) -> MKMapRect {
        let world = MKMapSize.world.width
        var rect = rect
        if rect.midX - other.midX > world / 2 {
            rect.origin.x -= world
        } else if other.midX - rect.midX > world / 2 {
            rect.origin.x += world
        }
        return rect
    }
}

/// Draws map views off screen before the camera gets to them (`MKMapSnapshotter`),
/// so their images are on the phone when it does and the map doesn't show gray
/// squares on the way.
@MainActor
final class GuessMySpotMapPreloader {
    typealias Stage = GuessMySpotRevealTimeline.Camera

    private var loading: [Stage: Int] = [:]
    private var snapshotters: [MKMapSnapshotter] = []
    private var isCancelled = false

    struct Picture {
        let rect: MKMapRect
        let image: UIImage
    }

    /// Each stage's views as they finish drawing.
    private(set) var pictures: [Stage: [Picture]] = [:]

    /// Starts drawing `rects` for `stage`, each over a whole map of `size` points.
    func load(_ rects: [MKMapRect], size: CGSize, satellite: Bool, for stage: Stage) {
        guard !isCancelled, size.width > 0, size.height > 0 else { return }
        for rect in rects {
            let options = MKMapSnapshotter.Options()
            let configuration: MKMapConfiguration = satellite
                ? MKHybridMapConfiguration(elevationStyle: .flat)
                : MKStandardMapConfiguration(elevationStyle: .flat, emphasisStyle: .muted)
            options.preferredConfiguration = configuration
            options.mapRect = rect
            options.size = size
            // The map's dark look, so the picture of the last view can stand in for it.
            options.traitCollection = UITraitCollection(userInterfaceStyle: .dark)
            let snapshotter = MKMapSnapshotter(options: options)
            loading[stage, default: 0] += 1
            snapshotters.append(snapshotter)
            // On the main queue.
            snapshotter.start { [weak self] snapshot, _ in
                guard let self else { return }
                snapshotters.removeAll { $0 === snapshotter }
                loading[stage, default: 1] -= 1
                guard let snapshot else { return }
                pictures[stage, default: []].append(Picture(rect: rect, image: snapshot.image))
            }
        }
    }

    /// Stops every view still drawing, and any later `load`, once the reveal has gone.
    func cancel() {
        isCancelled = true
        snapshotters.forEach { $0.cancel() }
        snapshotters = []
        loading = [:]
    }

    /// Returns once every view for `stage` has drawn, or after `limit`.
    func wait(for stage: Stage, atMost limit: Duration) async {
        let deadline = ContinuousClock.now + limit
        while loading[stage, default: 0] > 0, ContinuousClock.now < deadline, !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(50))
        }
    }
}
