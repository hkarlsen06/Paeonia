import CoreGraphics
import Foundation

/// Coordinates use the displayed UIImage size, just like TOCropView's imageCropFrame.
/// Rotation and mirrored camera metadata stay with the original UIImage and cropper.
nonisolated struct ProfilePhotoFraming {
    let imageSize: CGSize
    var horizontalPosition: Double
    var verticalPosition: Double
    var zoom: Double
    let maximumZoom: Double

    init(imageSize: CGSize, crop: CGRect) {
        self.imageSize = imageSize
        let side = min(imageSize.width, imageSize.height)
        let cropSide = min(crop.width, crop.height)
        let validCrop = cropSide > 0 && cropSide.isFinite && cropSide <= side
        zoom = validCrop ? Double(side / cropSide) : 1
        maximumZoom = max(15, zoom)
        let widthRemaining = imageSize.width - (validCrop ? cropSide : side)
        let heightRemaining = imageSize.height - (validCrop ? cropSide : side)
        horizontalPosition = validCrop && widthRemaining > 0 ? Double(crop.minX / widthRemaining) : 0.5
        verticalPosition = validCrop && heightRemaining > 0 ? Double(crop.minY / heightRemaining) : 0.5
        horizontalPosition = min(1, max(0, horizontalPosition))
        verticalPosition = min(1, max(0, verticalPosition))
    }

    var crop: CGRect {
        let side = min(imageSize.width, imageSize.height) / min(maximumZoom, max(1, zoom))
        return CGRect(
            x: (imageSize.width - side) * min(1, max(0, horizontalPosition)),
            y: (imageSize.height - side) * min(1, max(0, verticalPosition)),
            width: side,
            height: side
        )
    }

    mutating func reset() {
        horizontalPosition = 0.5
        verticalPosition = 0.5
        zoom = 1
    }
}
