import MapKit
import UIKit

// MARK: - Selection

/// A card picked in the carousel moves the camera to its city (about 8 km across).
/// Places far apart glide: the map zooms out over both, then in. With Reduce Motion it
/// cuts straight there. A memory whose pin is still inside a cluster at that zoom lights
/// up its cluster instead.
extension MemoriesMapCoordinator {
    static let cityMeters: CLLocationDistance = 8_000
    /// Farther than this, the camera zooms out over both places before zooming in.
    static let glideMeters: CLLocationDistance = 40_000

    func syncSelection(on mapView: MKMapView) {
        let wantedID = parent?.selectedID
        guard wantedID != revealedID else { return }
        revealedID = wantedID
        guard let wantedID, let annotation = annotations[wantedID] else {
            deselectAll(on: mapView)
            highlightClusters(on: mapView)
            return
        }
        moveCamera(to: annotation.coordinate, on: mapView)
        markSelection(on: mapView)
    }

    private func moveCamera(to coordinate: CLLocationCoordinate2D, on mapView: MKMapView) {
        let target = Self.mapRect(for: MKCoordinateRegion(
            center: coordinate,
            latitudinalMeters: Self.cityMeters,
            longitudinalMeters: Self.cityMeters
        ))
        pendingCameraRect = nil
        guard !UIAccessibility.isReduceMotionEnabled else {
            show(target, animated: false, padding: 24)
            return
        }
        let current = mapView.centerCoordinate
        let distance = CLLocation(latitude: current.latitude, longitude: current.longitude)
            .distance(from: CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude))
        let isFarAway = distance > Self.glideMeters
        let isZoomedIn = mapView.region.span.latitudeDelta < 2
        if isFarAway, isZoomedIn {
            pendingCameraRect = target
            let overview = MKMapRect(origin: MKMapPoint(current), size: MKMapSize(width: 0, height: 0))
                .union(MKMapRect(origin: MKMapPoint(coordinate), size: MKMapSize(width: 0, height: 0)))
            show(overview, animated: true)
        } else {
            show(target, animated: true, padding: 24)
        }
    }

    /// Selects the memory's own pin, or lights up the cluster it is in.
    func markSelection(on mapView: MKMapView) {
        guard let id = parent?.selectedID, let annotation = annotations[id] else { return }
        if mapView.view(for: annotation) is MemoryPinAnnotationView {
            if !mapView.selectedAnnotations.contains(where: { $0 === annotation }) {
                isChangingSelection = true
                mapView.selectAnnotation(annotation, animated: true)
                isChangingSelection = false
            }
        } else {
            deselectAll(on: mapView)
        }
        highlightClusters(on: mapView)
    }

    func highlightClusters(on mapView: MKMapView) {
        let id = parent?.selectedID
        for case let cluster as MKClusterAnnotation in mapView.annotations {
            guard let view = mapView.view(for: cluster) as? MemoryClusterAnnotationView else { continue }
            view.setHoldsSelection(cluster.memoryEntries.contains { $0.id == id }, animated: true)
        }
    }

    private func deselectAll(on mapView: MKMapView) {
        isChangingSelection = true
        for annotation in mapView.selectedAnnotations {
            mapView.deselectAnnotation(annotation, animated: true)
        }
        isChangingSelection = false
    }

    func mapView(_ mapView: MKMapView, didSelect annotation: any MKAnnotation) {
        if let cluster = annotation as? MKClusterAnnotation {
            isChangingSelection = true
            mapView.deselectAnnotation(cluster, animated: false)
            isChangingSelection = false
            openCluster(cluster, on: mapView)
            return
        }
        guard !isChangingSelection, let memory = annotation as? MemoryMapAnnotation else { return }
        // The person tapped the pin, so it is already on screen: no camera move.
        revealedID = memory.memoryID
        if parent?.selectedID != memory.memoryID {
            PaeoniaHaptics.selection()
            parent?.selectedID = memory.memoryID
        }
        highlightClusters(on: mapView)
    }

    func mapView(_ mapView: MKMapView, didDeselect annotation: any MKAnnotation) {
        guard !isChangingSelection, annotation is MemoryMapAnnotation else { return }
        // Tapping another pin deselects this one first. Only an empty selection
        // afterwards means the person tapped the map.
        DispatchQueue.main.async { [weak self, weak mapView] in
            guard let self, let mapView, mapView.selectedAnnotations.isEmpty else { return }
            self.revealedID = nil
            self.parent?.selectedID = nil
            self.highlightClusters(on: mapView)
        }
    }

    /// Zooms in when the cluster's memories are at different spots. Memories at
    /// about the same spot can't be separated by zooming, so they open as a list of
    /// exactly the memories the badge counts.
    private func openCluster(_ cluster: MKClusterAnnotation, on mapView: MKMapView) {
        var rect = MKMapRect.null
        for member in cluster.memberAnnotations {
            let point = MKMapPoint(member.coordinate)
            rect = rect.union(MKMapRect(x: point.x, y: point.y, width: 0, height: 0))
        }
        let metersPerPoint = 1 / MKMapPointsPerMeterAtLatitude(cluster.coordinate.latitude)
        let spreadMeters = max(rect.width, rect.height) * metersPerPoint
        let viewMeters = mapView.visibleMapRect.width * metersPerPoint
        if spreadMeters < 150 || viewMeters < 1_000 {
            PaeoniaHaptics.selection()
            parent?.onOpenCluster(cluster.memoryEntries)
        } else {
            userMovedMap = true
            show(rect, animated: true, padding: 64)
        }
    }

    func mapView(_ mapView: MKMapView, regionDidChangeAnimated _: Bool) {
        if let next = pendingCameraRect {
            pendingCameraRect = nil
            show(next, animated: true, padding: 24)
            return
        }
        let visible = mapView.visibleMapRect
        let allVisible = annotations.values.allSatisfy { visible.contains(MKMapPoint($0.coordinate)) }
        if parent?.isShowingAll != allVisible {
            parent?.isShowingAll = allVisible
        }
        markSelection(on: mapView)
    }
}
