import Foundation
import ImageIO
import UniformTypeIdentifiers

/// A picked photo, ready to send: a fresh JPEG with no metadata, and what the
/// original file said about where and when it was taken.
nonisolated struct GuessMySpotPreparedPhoto: Equatable, Sendable {
    let jpeg: Data
    let width: Int
    let height: Int
    /// The photo's own location, or nil when it had none.
    let spot: GuessMySpotCoordinate?
    /// `YYYY-MM-DD`, the day it was taken by the camera's clock, or nil.
    let takenOn: String?
}

/// Reads a photo file with ImageIO and draws a clean copy for upload. The copy is
/// made from the pixels only, so the camera, the time and the location never
/// leave the phone. The game reads the location here, which is why it needs no
/// location or photo library permission.
nonisolated enum GuessMySpotPhotoReader {
    static let maxPixelSize = 2_048
    static let maxBytes = 4_000_000
    private static let qualities: [Double] = [0.82, 0.72, 0.6, 0.5]

    /// Nil when the data is not a photo ImageIO can read.
    static func prepare(_ data: Data) -> GuessMySpotPreparedPhoto? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil), CGImageSourceGetCount(source) > 0 else {
            return nil
        }
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] ?? [:]
        guard let image = uprightImage(from: source), let jpeg = cleanJPEG(image) else { return nil }
        return GuessMySpotPreparedPhoto(
            jpeg: jpeg,
            width: image.width,
            height: image.height,
            spot: spot(in: properties),
            takenOn: takenOn(in: properties)
        )
    }

    /// Off the main actor: decoding and encoding a large photo takes a moment.
    @concurrent
    static func prepareAsync(_ data: Data) async -> GuessMySpotPreparedPhoto? {
        prepare(data)
    }

    // MARK: Reading

    static func spot(in properties: [CFString: Any]) -> GuessMySpotCoordinate? {
        guard let gps = properties[kCGImagePropertyGPSDictionary] as? [CFString: Any],
              let latitude = number(gps[kCGImagePropertyGPSLatitude]),
              let longitude = number(gps[kCGImagePropertyGPSLongitude])
        else { return nil }
        let south = (gps[kCGImagePropertyGPSLatitudeRef] as? String)?.uppercased() == "S"
        let west = (gps[kCGImagePropertyGPSLongitudeRef] as? String)?.uppercased() == "W"
        let coordinate = GuessMySpotCoordinate(
            latitude: south ? -abs(latitude) : latitude,
            longitude: west ? -abs(longitude) : longitude
        )
        // Broken cameras write exactly 0, 0 when they have no fix.
        guard GuessMySpotRules.isValid(coordinate), coordinate.latitude != 0 || coordinate.longitude != 0 else {
            return nil
        }
        return coordinate
    }

    /// The EXIF original date (`yyyy:MM:dd HH:mm:ss`) as `YYYY-MM-DD`, else the digitized
    /// or TIFF date. Nil for a day after tomorrow.
    static func takenOn(in properties: [CFString: Any]) -> String? {
        let exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any]
        let tiff = properties[kCGImagePropertyTIFFDictionary] as? [CFString: Any]
        let raw = (exif?[kCGImagePropertyExifDateTimeOriginal] ?? exif?[kCGImagePropertyExifDateTimeDigitized]
            ?? tiff?[kCGImagePropertyTIFFDateTime]) as? String
        guard let raw else { return nil }
        let parts = raw.prefix(10).split(separator: ":").compactMap { Int($0) }
        guard parts.count == 3, let day = GuessMySpotDay.string(year: parts[0], month: parts[1], day: parts[2]),
              let date = GuessMySpotDay.date(from: day),
              // A camera clock set wrong can write a future day, which the server refuses.
              date <= Date().addingTimeInterval(24 * 3_600)
        else { return nil }
        return day
    }

    private static func number(_ value: Any?) -> Double? {
        (value as? NSNumber)?.doubleValue ?? (value as? Double)
    }

    // MARK: Writing

    /// The photo upright and at most `maxPixelSize` on its long side.
    private static func uprightImage(from source: CGImageSource) -> CGImage? {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    /// A JPEG of the pixels with nothing else: no EXIF, TIFF, GPS or maker notes.
    /// The quality steps down until it fits `maxBytes`.
    static func cleanJPEG(_ image: CGImage) -> Data? {
        for quality in qualities {
            let output = NSMutableData()
            guard let destination = CGImageDestinationCreateWithData(
                output as CFMutableData,
                UTType.jpeg.identifier as CFString,
                1,
                nil
            ) else { return nil }
            let options: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: quality]
            CGImageDestinationAddImage(destination, image, options as CFDictionary)
            guard CGImageDestinationFinalize(destination) else { return nil }
            if output.length <= maxBytes || quality == qualities.last {
                return output as Data
            }
        }
        return nil
    }
}
