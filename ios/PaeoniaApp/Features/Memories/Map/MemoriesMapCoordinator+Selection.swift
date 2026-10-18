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
            markSelection(on: mapView)
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

    /// Draws which memory's card shows: its own pin grows and turns pink, or, when it
    /// shares a cluster, the cluster does with that memory's photo on top. MapKit's own
    /// selection is never used for this, because a selected annotation leaves its
    /// cluster and would hide its neighbour and the count.
    func markSelection(on _: MKMapView) {
        let id = parent?.selectedID
        for view in pinViews.allObjects {
            let memoryID = (view.annotation as? MemoryMapAnnotation)?.memoryID
            view.setShowsSelection(memoryID != nil && memoryID == id, animated: true)
        }
        for view in clusterViews.allObjects where view.annotation is MKClusterAnnotation {
            view.showSelectedMemory(id, animated: true)
        }
    }

    func mapView(_ mapView: MKMapView, didSelect annotation: any MKAnnotation) {
        // MapKit's selection is cleared straight away. See `markSelection`.
        mapView.deselectAnnotation(annotation, animated: false)
        if let cluster = annotation as? MKClusterAnnotation {
            openCluster(cluster, on: mapView)
            return
        }
        guard let memory = annotation as? MemoryMapAnnotation else { return }
        // The person tapped the pin, so it is already on screen: no camera move.
        revealedID = memory.memoryID
        if parent?.selectedID != memory.memoryID {
            PaeoniaHaptics.selection()
            parent?.selectedID = memory.memoryID
        }
        markSelection(on: mapView)
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
