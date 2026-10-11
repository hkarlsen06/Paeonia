import Foundation
import SwiftUI
import UIKit

/// One person's profile photo for the pairing celebration and the Home header.
///
/// It fetches and decodes a photo once per asset, so views never decode image
/// data in `body`. A photo that is already shown stays on screen while a new one
/// loads, and loading the same asset again does nothing. The photo only clears
/// when the person no longer has one.
@MainActor
@Observable
final class PairingProfilePhoto {
    private(set) var image: UIImage?
    /// True from the moment a photo is requested until it is shown or the
    /// request ends without one.
    private(set) var isLoading = false

    /// Changes when a different image replaces the shown one. Views use it to
    /// animate photo changes, because `UIImage` is not cheap to compare.
    var imageID: ObjectIdentifier? {
        image.map { ObjectIdentifier($0) }
    }

    /// The asset `image` was decoded from.
    @ObservationIgnored private var shownAssetID: UUID?

    func load(assetID: UUID?, provider: (any ProfilePhotoImageProviding)?) async {
        guard let assetID else {
            image = nil
            shownAssetID = nil
            isLoading = false
            return
        }

        guard assetID != shownAssetID || image == nil else {
            isLoading = false
            return
        }

        isLoading = true
        let decoded = await Self.decodedImage(for: assetID, provider: provider)
        guard !Task.isCancelled else {
            return
        }

        if let decoded {
            image = decoded
            shownAssetID = assetID
        }
        isLoading = false
    }

    /// `byPreparingForDisplay` decodes off the main actor, so the first frame that
    /// shows the photo does not stall on image decoding.
    private static func decodedImage(
        for assetID: UUID,
        provider: (any ProfilePhotoImageProviding)?
    ) async -> UIImage? {
        guard let data = await provider?.profilePhotoData(for: assetID),
              let image = UIImage(data: data) else {
            return nil
        }

        return await image.byPreparingForDisplay() ?? image
    }
}
