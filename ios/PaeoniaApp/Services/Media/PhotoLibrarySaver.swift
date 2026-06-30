import Foundation
import Photos

/// The outcome of trying to add an image to the device's photo library.
enum PhotoLibrarySaveResult: Equatable, Sendable {
    /// The image was added to the photo library.
    case saved
    /// The person has turned off permission for Paeonia to add to their photos.
    /// They need to change it in the system Settings before we can save.
    case permissionDenied
    /// Something else went wrong while saving (e.g. out of storage).
    case failed
}

/// Adds an image to the device's photo library, asking for add-only access the
/// first time. Abstracted behind a protocol so the save flow can be unit-tested
/// without touching the real photo library.
nonisolated protocol PhotoLibrarySaving: Sendable {
    func savePNG(_ data: Data) async -> PhotoLibrarySaveResult
}

/// Live implementation backed by the Photos framework. Uses add-only access,
/// which is the least the feature needs: it never reads the user's existing
/// photos, it only writes new ones.
struct PhotoLibrarySaver: PhotoLibrarySaving {
    func savePNG(_ data: Data) async -> PhotoLibrarySaveResult {
        switch await ensureAddAuthorization() {
        case .authorized, .limited:
            break
        case .denied, .restricted:
            return .permissionDenied
        case .notDetermined:
            return .failed
        @unknown default:
            return .failed
        }

        do {
            try await PHPhotoLibrary.shared().performChanges {
                let request = PHAssetCreationRequest.forAsset()
                request.addResource(with: .photo, data: data, options: nil)
            }
            return .saved
        } catch {
            return .failed
        }
    }

    /// Returns the current add-only status, prompting once if the person hasn't
    /// been asked yet.
    private func ensureAddAuthorization() async -> PHAuthorizationStatus {
        let current = PHPhotoLibrary.authorizationStatus(for: .addOnly)
        guard current == .notDetermined else {
            return current
        }
        return await withCheckedContinuation { continuation in
            PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
                continuation.resume(returning: status)
            }
        }
    }
}
