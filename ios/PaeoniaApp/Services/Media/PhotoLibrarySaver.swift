import Foundation
import Photos

/// The outcome of trying to add an image or a video to the device's photo library.
enum PhotoLibrarySaveResult: Equatable, Sendable {
    /// The image or video was added to the photo library.
    case saved
    /// The person has turned off permission for Paeonia to add to their photos.
    /// They need to change it in the system Settings before we can save.
    case permissionDenied
    /// Something else went wrong while saving (e.g. out of storage).
    case failed
}

/// Adds an image or a video to the device's photo library, asking for add-only access
/// the first time. Abstracted behind a protocol so the save flow can be unit-tested
/// without touching the real photo library.
nonisolated protocol PhotoLibrarySaving: Sendable {
    /// `data` is encoded image data, such as PNG or JPEG.
    func saveImage(_ data: Data) async -> PhotoLibrarySaveResult
    /// `fileURL` is a video file, such as an mp4. Photos copies it, so the file stays.
    func saveVideo(fileURL: URL) async -> PhotoLibrarySaveResult
}

/// Live implementation backed by the Photos framework. Uses add-only access,
/// which is the least the feature needs: it never reads the user's existing
/// photos, it only writes new ones.
struct PhotoLibrarySaver: PhotoLibrarySaving {
    func saveImage(_ data: Data) async -> PhotoLibrarySaveResult {
        await save { $0.addResource(with: .photo, data: data, options: nil) }
    }

    func saveVideo(fileURL: URL) async -> PhotoLibrarySaveResult {
        await save { $0.addResource(with: .video, fileURL: fileURL, options: nil) }
    }

    private func save(
        _ addResource: @escaping @Sendable (PHAssetCreationRequest) -> Void
    ) async -> PhotoLibrarySaveResult {
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
                addResource(PHAssetCreationRequest.forAsset())
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
