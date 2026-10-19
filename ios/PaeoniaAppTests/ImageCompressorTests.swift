import CoreGraphics
import Foundation
import Testing
import UIKit
@testable import PaeoniaApp

private let sidewaysOrientations: [UIImage.Orientation] = [
    .left, .right, .leftMirrored, .rightMirrored
]
private let allOrientations: [UIImage.Orientation] = [
    .up, .down, .upMirrored, .downMirrored
] + sidewaysOrientations

struct ImageCompressorTests {
    @Test(arguments: allOrientations)
    func smallImageKeepsDisplayedSizeForEveryOrientation(orientation: UIImage.Orientation) throws {
        let rawImage = Self.solidImage(width: 200, height: 100)
        let rawCGImage = try #require(rawImage.cgImage)
        let image = UIImage(cgImage: rawCGImage, scale: 1, orientation: orientation)
        let isSideways = sidewaysOrientations.contains(orientation)

        let result = try #require(ImageCompressor.compress(image))

        #expect(result.width == (isSideways ? 100 : 200))
        #expect(result.height == (isSideways ? 200 : 100))

        // The reported size matches what the encoded JPEG displays.
        let decoded = try #require(UIImage(data: result.data))
        #expect(Int(decoded.size.width * decoded.scale) == result.width)
        #expect(Int(decoded.size.height * decoded.scale) == result.height)
    }

    @Test func largeNoisyImageStaysWithinByteAndSizeLimits() throws {
        let image = try Self.noiseImage(width: 2_400, height: 1_800)

        let result = try #require(ImageCompressor.compress(image))

        #expect(result.mediaType == "image/jpeg")
        #expect(result.fileExtension == "jpg")
        #expect(result.data.count <= ImageCompressor.maxUploadBytes)
        #expect(CGFloat(max(result.width, result.height)) <= ImageCompressor.maxDimension)

        // The 4:3 shape survives downscaling, and the metadata matches the JPEG.
        let aspectRatio = Double(result.width) / Double(result.height)
        #expect(abs(aspectRatio - 4.0 / 3.0) < 0.02)
        let decoded = try #require(UIImage(data: result.data))
        #expect(Int(decoded.size.width * decoded.scale) == result.width)
        #expect(Int(decoded.size.height * decoded.scale) == result.height)
    }

    // MARK: - Fixtures

    private static func solidImage(width: Int, height: Int) -> UIImage {
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let size = CGSize(width: width, height: height)
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIColor.systemTeal.setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
    }

    /// Pseudo-random pixels, so the JPEG stays large and the compressor has to lower
    /// the quality and size to fit the byte budget.
    private static func noiseImage(width: Int, height: Int) throws -> UIImage {
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        var state: UInt32 = 0x1234_5678
        for index in bytes.indices {
            state = state &* 1_664_525 &+ 1_013_904_223
            bytes[index] = UInt8(truncatingIfNeeded: state >> 24)
        }

        let provider = try #require(CGDataProvider(data: Data(bytes) as CFData))
        let cgImage = try #require(
            CGImage(
                width: width,
                height: height,
                bitsPerComponent: 8,
                bitsPerPixel: 32,
                bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                provider: provider,
                decode: nil,
                shouldInterpolate: false,
                intent: .defaultIntent
            )
        )
        return UIImage(cgImage: cgImage, scale: 1, orientation: .up)
    }
}
