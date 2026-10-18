import MapKit
import SwiftUI

/// The memories map: an `MKMapView`, because SwiftUI's `Map` has no clustering. Pins
/// cluster through MapKit. The first fit pops in the pins on screen, and a pin added
/// later (for example by the partner) pops in on its own.
struct MemoriesMapView: UIViewRepresentable {
    let entries: [MemoryMapEntry]
    @Binding var selectedID: UUID?
    /// True while every pin is on screen, so the "show all" button can hide.
    @Binding var isShowingAll: Bool
    /// Bump to fit every pin on screen again.
    let fitRequest: Int
    /// Where the map sits while nothing has a place yet.
    let emptyRegion: MKCoordinateRegion?
    /// Room the screen's own controls take at the top and bottom.
    let overlayInsets: UIEdgeInsets
    /// Several memories at about the same spot, which zooming can't separate.
    let onOpenCluster: ([MemoryMapEntry]) -> Void
    /// When set, the first fit frames only these memories instead of all of them.
    var initialFocusIDs: Set<UUID>?

    func makeCoordinator() -> MemoriesMapCoordinator {
        MemoriesMapCoordinator()
    }

    func makeUIView(context: Context) -> MemoriesMKMapView {
        let mapView = MemoriesMKMapView()
        mapView.preferredConfiguration = MemoriesMapStyle.configuration()
        mapView.overrideUserInterfaceStyle = .dark
        mapView.showsUserLocation = false
        mapView.selectableMapFeatures = []
        mapView.isRotateEnabled = false
        mapView.isPitchEnabled = false
        mapView.showsCompass = false
        // `overlayInsets` already count the safe area.
        mapView.insetsLayoutMarginsFromSafeArea = false
        mapView.register(
            MemoryPinAnnotationView.self,
            forAnnotationViewWithReuseIdentifier: MemoryPinAnnotationView.reuseIdentifier
        )
        mapView.register(
            MemoryClusterAnnotationView.self,
            forAnnotationViewWithReuseIdentifier: MemoryClusterAnnotationView.reuseIdentifier
        )
        mapView.delegate = context.coordinator
        context.coordinator.mapView = mapView
        context.coordinator.watchGestures(on: mapView)
        mapView.onSizeChange = { [weak coordinator = context.coordinator] in
            coordinator?.mapDidChangeSize()
        }
        return mapView
    }

    func updateUIView(_ mapView: MemoriesMKMapView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.update()
    }
}

/// Tells the map's coordinator when its size changes. The first fit needs a size, and
/// the first size can still grow once the safe area arrives.
final class MemoriesMKMapView: MKMapView {
    var onSizeChange: (() -> Void)?
    private var reportedSize: CGSize = .zero

    override func layoutSubviews() {
        super.layoutSubviews()
        guard !bounds.isEmpty, bounds.size != reportedSize else { return }
        reportedSize = bounds.size
        onSizeChange?()
    }
}
