import CoreLocation
import Foundation

nonisolated enum ForegroundLocationCaptureError: Error, Equatable {
    case authorizationDenied
    case unavailable
    case alreadyRequesting
}

nonisolated enum ForegroundLocationAuthorizationState: Equatable, Sendable {
    case notDetermined
    case authorized
    case denied
}

@MainActor
protocol ForegroundLocationCapturing: AnyObject {
    var authorizationState: ForegroundLocationAuthorizationState { get }
    func captureCurrentLocation() async throws -> LocationPoint
}

extension ForegroundLocationCapturing {
    /// Test and scenario captures opt out of silent restoration unless they
    /// deliberately provide an authorization state.
    var authorizationState: ForegroundLocationAuthorizationState { .notDetermined }
}

@MainActor
final class ForegroundLocationCaptureService: NSObject, ForegroundLocationCapturing {
    private let manager = CLLocationManager()
    private var continuation: CheckedContinuation<LocationPoint, Error>?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    var authorizationState: ForegroundLocationAuthorizationState {
        switch manager.authorizationStatus {
        case .notDetermined:
            .notDetermined
        case .authorizedAlways, .authorizedWhenInUse:
            .authorized
        case .denied, .restricted:
            .denied
        @unknown default:
            .denied
        }
    }

    func captureCurrentLocation() async throws -> LocationPoint {
        guard continuation == nil else {
            throw ForegroundLocationCaptureError.alreadyRequesting
        }

        let authorizationStatus = manager.authorizationStatus
        switch authorizationStatus {
        case .notDetermined:
            break
        case .authorizedAlways, .authorizedWhenInUse:
            break
        case .denied, .restricted:
            throw ForegroundLocationCaptureError.authorizationDenied
        @unknown default:
            throw ForegroundLocationCaptureError.unavailable
        }

        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            if authorizationStatus == .notDetermined {
                manager.requestWhenInUseAuthorization()
            } else {
                manager.requestLocation()
            }
        }
    }

    private func finish(_ result: Result<LocationPoint, Error>) {
        guard let continuation else {
            return
        }
        self.continuation = nil
        continuation.resume(with: result)
    }
}

extension ForegroundLocationCaptureService: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_: CLLocationManager) {
        Task { @MainActor in
            switch self.manager.authorizationStatus {
            case .authorizedAlways, .authorizedWhenInUse:
                guard continuation != nil else {
                    return
                }
                self.manager.requestLocation()
            case .denied, .restricted:
                finish(.failure(ForegroundLocationCaptureError.authorizationDenied))
            case .notDetermined:
                break
            @unknown default:
                finish(.failure(ForegroundLocationCaptureError.unavailable))
            }
        }
    }

    nonisolated func locationManager(
        _: CLLocationManager,
        didUpdateLocations locations: [CLLocation]
    ) {
        guard let location = locations.last else {
            Task { @MainActor in
                finish(.failure(ForegroundLocationCaptureError.unavailable))
            }
            return
        }

        let point = LocationPoint(
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude,
            accuracyMeters: location.horizontalAccuracy >= 0 ? location.horizontalAccuracy : nil,
            capturedAt: location.timestamp,
            updatedAt: nil
        )
        Task { @MainActor in
            finish(.success(point))
        }
    }

    nonisolated func locationManager(_: CLLocationManager, didFailWithError _: any Error) {
        Task { @MainActor in
            finish(.failure(ForegroundLocationCaptureError.unavailable))
        }
    }
}
