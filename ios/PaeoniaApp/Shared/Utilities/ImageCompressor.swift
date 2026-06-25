import Foundation
import UIKit

/// Utility for compressing images before upload.
/// This follows Tidex's JPEG path: downscale large images, then reduce quality
/// only as much as needed to stay within a predictable byte budget.
enum ImageCompressor {
    struct CompressedImage: Equatable, Sendable {
        let data: Data
        let mediaType: String
        let fileExtension: String
        let width: Int
        let height: Int
    }

    private struct JPEGCompressionResult {
        let data: Data
        let pixelSize: PixelSize
    }

    private struct PixelSize {
        let width: Int
        let height: Int
    }

    private static let maxDimension: CGFloat = 1_568
    private static let defaultQuality: CGFloat = 0.8
    private static let maxUploadBytes = 1_500_000
    private static let minimumQuality: CGFloat = 0.45
    private static let iterativeDownscaleFactor: CGFloat = 0.85
    private static let minimumDimension: CGFloat = 512

    static func compress(_ imageData: Data, quality: CGFloat = defaultQuality) -> CompressedImage? {
        guard let image = UIImage(data: imageData) else {
            return nil
        }

        return compress(image, quality: quality)
    }

    static func compress(_ image: UIImage, quality: CGFloat = defaultQuality) -> CompressedImage? {
        guard let result = compressedJPEGData(for: image, preferredQuality: quality) else {
            return nil
        }

        return CompressedImage(
            data: result.data,
            mediaType: "image/jpeg",
            fileExtension: "jpg",
            width: result.pixelSize.width,
            height: result.pixelSize.height
        )
    }

    private static func compressedJPEGData(
        for image: UIImage,
        preferredQuality: CGFloat
    ) -> JPEGCompressionResult? {
        let maxSide = max(image.size.width, image.size.height)
        guard maxSide > 0 else {
            return nil
        }

        var currentMaxDimension = min(maxSide, maxDimension)
        var bestAttempt: JPEGCompressionResult?

        while true {
            let scaledImage = resize(image, maxDimension: currentMaxDimension)
            let pixelSize = pixelSize(for: scaledImage)

            for quality in compressionQualities(startingAt: preferredQuality) {
                guard let data = scaledImage.jpegData(compressionQuality: quality) else {
                    continue
                }

                bestAttempt = JPEGCompressionResult(data: data, pixelSize: pixelSize)
                if data.count <= maxUploadBytes {
                    return JPEGCompressionResult(data: data, pixelSize: pixelSize)
                }
            }

            guard currentMaxDimension > minimumDimension else {
                break
            }

            let nextDimension = floor(currentMaxDimension * iterativeDownscaleFactor)
            guard nextDimension < currentMaxDimension else {
                break
            }
            currentMaxDimension = max(minimumDimension, nextDimension)
        }

        guard let bestAttempt, bestAttempt.data.count <= maxUploadBytes else {
            return nil
        }

        return bestAttempt
    }

    private static func compressionQualities(startingAt preferredQuality: CGFloat) -> [CGFloat] {
        let initialQuality = min(max(preferredQuality, minimumQuality), 1)
        var qualities = [initialQuality]
        var currentQuality = initialQuality

        while currentQuality > minimumQuality {
            let nextQuality = max(minimumQuality, currentQuality - 0.1)
            guard nextQuality < currentQuality else {
                break
            }
            qualities.append(nextQuality)
            currentQuality = nextQuality
        }

        return qualities
    }

    private static func resize(_ image: UIImage, maxDimension: CGFloat) -> UIImage {
        let size = image.size
        let maxSide = max(size.width, size.height)

        guard maxSide > maxDimension else {
            return image
        }

        let scale = maxDimension / maxSide
        let newSize = CGSize(
            width: size.width * scale,
            height: size.height * scale
        )

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = false

        let renderer = UIGraphicsImageRenderer(size: newSize, format: format)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }

    private static func pixelSize(for image: UIImage) -> PixelSize {
        if let cgImage = image.cgImage {
            return PixelSize(width: cgImage.width, height: cgImage.height)
        }

        return PixelSize(
            width: max(Int((image.size.width * image.scale).rounded()), 1),
            height: max(Int((image.size.height * image.scale).rounded()), 1)
        )
    }
}
