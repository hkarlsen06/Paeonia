import MapKit
import SwiftUI
import UIKit

extension CoupleMapSnapshot {
    /// Renders the map and both avatar points, trying again after each wait in
    /// `retryDelays` while the task is alive. Returns nil when every attempt failed or
    /// the task was cancelled.
    func renderMap(size: CGSize) async -> SnapshotResult? {
        await Self.renderMap(size: size, current: currentCoordinate, partner: partnerCoordinate)
    }

    /// Runs off the main thread. Building the map configuration and snapshot options
    /// cost about 30 ms of the first Home build while they ran on it.
    @concurrent
    private static func renderMap(
        size: CGSize,
        current currentCoordinate: CLLocationCoordinate2D,
        partner partnerCoordinate: CLLocationCoordinate2D
    ) async -> SnapshotResult? {
        // Muted standard config plays down roads, borders, and labels so the map
        // reads as a calm backdrop rather than a navigation map.
        let configuration = MKStandardMapConfiguration(elevationStyle: .flat, emphasisStyle: .muted)
        configuration.pointOfInterestFilter = .excludingAll

        let options = MKMapSnapshotter.Options()
        options.region = CoupleMapFraming.region(
            current: currentCoordinate,
            partner: partnerCoordinate,
            aspectRatio: size.width / size.height
        )
        options.size = size
        options.traitCollection = UITraitCollection(userInterfaceStyle: .dark)
        options.preferredConfiguration = configuration

        for attempt in 0...retryDelays.count {
            if attempt > 0 {
                do {
                    try await Task.sleep(for: retryDelays[attempt - 1])
                } catch {
                    return nil
                }
            }

            let snapshotter = MKMapSnapshotter(options: options)
            let result = try? await snapshotter.start()
            guard !Task.isCancelled else {
                return nil
            }
            if let result {
                return SnapshotResult(
                    image: result.image,
                    currentPoint: result.point(for: currentCoordinate),
                    partnerPoint: result.point(for: partnerCoordinate)
                )
            }
        }
        return nil
    }
}
