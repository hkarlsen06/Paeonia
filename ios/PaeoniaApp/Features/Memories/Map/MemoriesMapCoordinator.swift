import MapKit
import SwiftUI

/// Keeps the `MKMapView` in step with `MemoriesMapView`: pins, framing, selection (in
/// `+Selection`), and the pop-in animations. State is internal so the extensions in
/// other files can use it.
@MainActor
final class MemoriesMapCoordinator: NSObject, MKMapViewDelegate, UIGestureRecognizerDelegate {
    var parent: MemoriesMapView?
    weak var mapView: MemoriesMKMapView?

    var annotations: [UUID: MemoryMapAnnotation] = [:]
    var hasSize = false
    var hasFitted = false
    var appliedFitRequest = 0
    var appliedEmptyRegion = false
    /// Once the person pans or zooms, a size change no longer refits the map.
    var userMovedMap = false
    /// Pins added after the first fit pop in when they appear.
    var bloomIDs: Set<UUID> = []
    var entranceViews: [MKAnnotationView] = []
    var isCollectingEntrance = false
    /// The memory whose card shows. The camera moves only when it changes.
    var revealedID: UUID?
    /// The second half of a long glide: after zooming out over both places, zoom in here.
    var pendingCameraRect: MKMapRect?
    /// The cluster views on the map. `MKMapView.annotations` doesn't list MapKit's
    /// cluster annotations, so the coordinator keeps its own list to light them up.
    let clusterViews = NSHashTable<MemoryClusterAnnotationView>.weakObjects()
    /// The single pins on the map, to draw which one's card shows.
    let pinViews = NSHashTable<MemoryPinAnnotationView>.weakObjects()

    func mapDidChangeSize() {
        guard let parent else { return }
        let isFirstSize = !hasSize
        hasSize = true
        if isFirstSize {
            update()
        } else if !userMovedMap, hasFitted, parent.selectedID == nil {
            // The first layout can be smaller than the final one (the safe area arrives
            // later). Fit again so the pins fill the final frame.
            fitAll(animated: false)
        } else if !userMovedMap, !hasFitted, let region = parent.emptyRegion {
            show(Self.mapRect(for: region), animated: false)
        }
    }

    func update() {
        guard let parent, let mapView else { return }
        // The Maps logo and Legal link must stay visible, so they sit above the
        // screen's own controls.
        let margins = UIEdgeInsets(
            top: parent.overlayInsets.top,
            left: 8,
            bottom: parent.overlayInsets.bottom,
            right: 8
        )
        if mapView.layoutMargins != margins {
            mapView.layoutMargins = margins
        }
        guard hasSize else { return }
        let wasEmpty = annotations.isEmpty
        syncAnnotations(parent.entries, on: mapView)

        if parent.entries.isEmpty {
            if !appliedEmptyRegion, let region = parent.emptyRegion {
                appliedEmptyRegion = true
                show(Self.mapRect(for: region), animated: hasFitted)
            }
        } else if !hasFitted {
            fitFirstTime(on: mapView)
            return
        } else if wasEmpty || appliedFitRequest != parent.fitRequest {
            appliedFitRequest = parent.fitRequest
            fitAll(animated: true)
        }
        syncSelection(on: mapView)
    }

    private func fitFirstTime(on mapView: MKMapView) {
        hasFitted = true
        appliedFitRequest = parent?.fitRequest ?? 0
        if appliedEmptyRegion {
            // The first place was just added on this screen: fly to it and pop it in.
            bloomIDs.formUnion(annotations.keys)
            mapView.addAnnotations(Array(annotations.values))
            fitAll(animated: true)
        } else {
            // The first fit happens before the pins are added, so the ones that
            // land on screen can pop in together.
            isCollectingEntrance = true
            fitAll(animated: false, only: parent?.initialFocusIDs)
            mapView.addAnnotations(Array(annotations.values))
        }
        // A selection made before the map had a size, such as a card opened by a
        // scenario, waits for the pins.
        DispatchQueue.main.async { [weak self, weak mapView] in
            guard let self, let mapView else { return }
            self.syncSelection(on: mapView)
        }
    }

    // MARK: - Gestures

    /// Watches the person's own pans, pinches and taps without taking them from the map.
    func watchGestures(on mapView: MKMapView) {
        for recognizer in [UIPanGestureRecognizer(), UIPinchGestureRecognizer()] {
            recognizer.addTarget(self, action: #selector(userGesture(_:)))
            recognizer.delegate = self
            recognizer.cancelsTouchesInView = false
            mapView.addGestureRecognizer(recognizer)
        }
        let tap = UITapGestureRecognizer(target: self, action: #selector(mapTapped(_:)))
        tap.delegate = self
        tap.cancelsTouchesInView = false
        mapView.addGestureRecognizer(tap)
    }

    /// A tap on the map itself, not on a pin, closes the card.
    @objc private func mapTapped(_ recognizer: UITapGestureRecognizer) {
        guard let mapView, parent?.selectedID != nil else { return }
        var view = mapView.hitTest(recognizer.location(in: mapView), with: nil)
        while let current = view {
            if current is MKAnnotationView { return }
            view = current.superview
        }
        revealedID = nil
        parent?.selectedID = nil
        markSelection(on: mapView)
    }

    @objc private func userGesture(_ recognizer: UIGestureRecognizer) {
        if recognizer.state == .began {
            userMovedMap = true
            pendingCameraRect = nil
        }
    }

    nonisolated func gestureRecognizer(
        _: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith _: UIGestureRecognizer
    ) -> Bool {
        true
    }

    // MARK: - Annotations

    private func syncAnnotations(_ entries: [MemoryMapEntry], on mapView: MKMapView) {
        let wanted = Dictionary(entries.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var removed: [MemoryMapAnnotation] = []
        var added: [MemoryMapAnnotation] = []
        for (id, annotation) in annotations where wanted[id] != annotation.entry {
            removed.append(annotation)
            annotations[id] = nil
        }
        for (id, entry) in wanted where annotations[id] == nil {
            let annotation = MemoryMapAnnotation(entry: entry)
            annotations[id] = annotation
            added.append(annotation)
            // A changed pin is replaced, not new, so it doesn't pop.
            if hasFitted, !removed.contains(where: { $0.memoryID == id }) {
                bloomIDs.insert(id)
            }
        }
        mapView.removeAnnotations(removed)
        // Before the first fit the pins wait, so they appear after the camera moves.
        if hasFitted {
            mapView.addAnnotations(added)
        }
    }

    // MARK: - Framing

    /// Fits every pin (or only `ids`) into the clear part of the map.
    func fitAll(animated: Bool, only ids: Set<UUID>? = nil) {
        let fitted = annotations.values.filter { ids?.contains($0.memoryID) ?? true }
        guard !fitted.isEmpty else { return }
        var rect = MKMapRect.null
        for annotation in fitted {
            let point = MKMapPoint(annotation.coordinate)
            rect = rect.union(MKMapRect(x: point.x, y: point.y, width: 0, height: 0))
        }
        // One pin, or pins in one street, still shows the neighborhood around them.
        let minimumSide = 3_000 * MKMapPointsPerMeterAtLatitude(rect.origin.coordinate.latitude)
        if rect.width < minimumSide || rect.height < minimumSide {
            let center = MKMapPoint(x: rect.midX, y: rect.midY)
            let side = max(minimumSide, rect.width, rect.height)
            rect = MKMapRect(x: center.x - side / 2, y: center.y - side / 2, width: side, height: side)
        }
        show(rect.intersection(.world), animated: animated)
    }

    /// Shows `rect` in the part of the map the screen's controls leave clear, with the
    /// same padding on every side. A pin's photo sits above its point, so the top gets
    /// the pin's height on top of that. The region is worked out here because
    /// `setVisibleMapRect(_:edgePadding:)` rounds to a coarser zoom and left a third of
    /// the screen empty.
    func show(_ rect: MKMapRect, animated: Bool, padding: CGFloat = 40) {
        guard let mapView, let parent, !mapView.bounds.isEmpty else { return }
        let insets = parent.overlayInsets
        let top = insets.top + padding + MemoryPinStyle.tileSize
        let left = insets.left + padding
        let clearWidth = max(mapView.bounds.width - left - insets.right - padding, 1)
        // The Maps logo and Legal link sit at the bottom margin and must stay readable.
        let bottom = insets.bottom + Self.attributionHeight + padding
        let clearHeight = max(mapView.bounds.height - top - bottom, 1)
        // Map points per screen point, so the rect just fills the clear area.
        let scale = max(rect.width / clearWidth, rect.height / clearHeight)
        let visible = MKMapRect(
            x: rect.midX - (left + clearWidth / 2) * scale,
            y: rect.midY - (top + clearHeight / 2) * scale,
            width: mapView.bounds.width * scale,
            height: mapView.bounds.height * scale
        )
        mapView.setRegion(MKCoordinateRegion(visible), animated: animated)
    }

    private func pinView(for annotation: MemoryMapAnnotation, on mapView: MKMapView) -> MKAnnotationView {
        let view = mapView.dequeueReusableAnnotationView(
            withIdentifier: MemoryPinAnnotationView.reuseIdentifier,
            for: annotation
        )
        if let pinView = view as? MemoryPinAnnotationView {
            pinView.setShowsSelection(annotation.memoryID == parent?.selectedID, animated: false)
            pinViews.add(pinView)
        }
        return view
    }

    private func clusterView(for annotation: any MKAnnotation, on mapView: MKMapView) -> MKAnnotationView {
        let view = mapView.dequeueReusableAnnotationView(
            withIdentifier: MemoryClusterAnnotationView.reuseIdentifier,
            for: annotation
        )
        if let clusterView = view as? MemoryClusterAnnotationView {
            clusterView.selectedMemoryID = parent?.selectedID
            clusterViews.add(clusterView)
        }
        return view
    }

    /// Room for MapKit's attribution strip (the Maps logo and Legal link), so a fit
    /// never places a pin over it.
    static let attributionHeight: CGFloat = 28

    static func mapRect(for region: MKCoordinateRegion) -> MKMapRect {
        let center = region.center
        let topLeft = MKMapPoint(CLLocationCoordinate2D(
            latitude: min(center.latitude + region.span.latitudeDelta / 2, 85),
            longitude: center.longitude - region.span.longitudeDelta / 2
        ))
        let bottomRight = MKMapPoint(CLLocationCoordinate2D(
            latitude: max(center.latitude - region.span.latitudeDelta / 2, -85),
            longitude: center.longitude + region.span.longitudeDelta / 2
        ))
        return MKMapRect(
            x: min(topLeft.x, bottomRight.x),
            y: min(topLeft.y, bottomRight.y),
            width: abs(bottomRight.x - topLeft.x),
            height: abs(bottomRight.y - topLeft.y)
        )
    }

    func mapView(_ mapView: MKMapView, viewFor annotation: any MKAnnotation) -> MKAnnotationView? {
        switch annotation {
        case is MKClusterAnnotation:
            clusterView(for: annotation, on: mapView)
        case let memory as MemoryMapAnnotation:
            pinView(for: memory, on: mapView)
        default:
            nil
        }
    }
}

// MARK: - Entrance

extension MemoriesMapCoordinator {
    func mapView(_ mapView: MKMapView, didAdd views: [MKAnnotationView]) {
        if isCollectingEntrance {
            let visible = mapView.visibleMapRect
            let onScreen = views.filter { visible.contains(MKMapPoint($0.annotation?.coordinate ?? .init())) }
            onScreen.forEach { $0.alpha = 0 }
            let isFirstBatch = entranceViews.isEmpty
            entranceViews += onScreen
            if isFirstBatch {
                // MapKit adds the first views over a few calls. Wait for the batch.
                DispatchQueue.main.async { [weak self] in self?.playEntrance() }
            }
            return
        }
        for view in views where shouldBloom(view) {
            pop(view, delay: 0)
        }
        // A pin or cluster that just appeared may hold the memory whose card shows.
        markSelection(on: mapView)
    }

    private func shouldBloom(_ view: MKAnnotationView) -> Bool {
        let ids: [UUID] = if let cluster = view.annotation as? MKClusterAnnotation {
            cluster.memoryEntries.map(\.id)
        } else if let memory = view.annotation as? MemoryMapAnnotation {
            [memory.memoryID]
        } else {
            []
        }
        let blooming = ids.filter(bloomIDs.contains)
        bloomIDs.subtract(blooming)
        return !blooming.isEmpty
    }

    /// Pops the pins in, left to right, within `MemoryPinEntrance.totalDuration`.
    private func playEntrance() {
        isCollectingEntrance = false
        let views = entranceViews.sorted { $0.frame.minX < $1.frame.minX }
        entranceViews = []
        let delays = MemoryPinEntrance.delays(count: views.count)
        for (view, delay) in zip(views, delays) {
            pop(view, delay: delay)
        }
    }

    private func pop(_ view: MKAnnotationView, delay: TimeInterval) {
        guard !UIAccessibility.isReduceMotionEnabled else {
            view.alpha = 0
            UIView.animate(withDuration: 0.25) { view.alpha = 1 }
            return
        }
        view.alpha = 0
        view.transform = CGAffineTransform(scaleX: 0.4, y: 0.4)
        UIView.animate(
            springDuration: MemoryPinEntrance.pinDuration,
            bounce: 0.3,
            delay: delay,
            animations: {
                view.alpha = 1
                view.transform = .identity
            }
        )
    }
}
