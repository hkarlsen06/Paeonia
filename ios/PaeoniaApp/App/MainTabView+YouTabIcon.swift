import SwiftUI
import UIKit

extension MainTabView {
    /// Loads the user's profile photo as a round icon the size of a tab bar symbol.
    /// Returns nil when there is no photo, so the tab keeps its system symbol.
    static func youTabIcon(for assetID: UUID?) async -> UIImage? {
        guard let assetID else { return nil }

        if let cached = PaeoniaImageMemoryCache.image(for: assetID) {
            return roundTabIcon(from: cached)
        }

        guard let data = await ProfilePhotoImageProviderFactory.shared?.profilePhotoData(for: assetID),
              let image = UIImage(data: data),
              !Task.isCancelled
        else {
            return nil
        }

        PaeoniaImageMemoryCache.store(image, for: assetID)
        return roundTabIcon(from: image)
    }

    /// Crops a photo to a circle, keeping its colors instead of the tab tint.
    private static func roundTabIcon(from image: UIImage) -> UIImage {
        let side: CGFloat = 26
        let bounds = CGRect(x: 0, y: 0, width: side, height: side)
        let scale = max(side / image.size.width, side / image.size.height)
        let drawSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let drawRect = CGRect(
            x: (side - drawSize.width) / 2,
            y: (side - drawSize.height) / 2,
            width: drawSize.width,
            height: drawSize.height
        )
        return UIGraphicsImageRenderer(bounds: bounds).image { _ in
            UIBezierPath(ovalIn: bounds).addClip()
            image.draw(in: drawRect)
        }
        .withRenderingMode(.alwaysOriginal)
    }
}
