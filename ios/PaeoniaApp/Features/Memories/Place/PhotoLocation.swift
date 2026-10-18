import CoreLocation
import Foundation
import ImageIO

/// Reads where a photo was taken from its own metadata, before upload. Nothing here is
/// stored or sent: the editor only offers the spot as a suggestion, and the upload
/// re-encodes the photo without its metadata.
nonisolated enum PhotoLocation {
    static func coordinate(in data: Data) -> CLLocationCoordinate2D? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let gps = properties[kCGImagePropertyGPSDictionary] as? [CFString: Any]
        else { return nil }
        return coordinate(fromGPS: gps)
    }

    /// EXIF stores both values as positive numbers with N/S and E/W letters beside them.
    static func coordinate(fromGPS gps: [CFString: Any]) -> CLLocationCoordinate2D? {
        guard let latitude = (gps[kCGImagePropertyGPSLatitude] as? NSNumber)?.doubleValue,
              let longitude = (gps[kCGImagePropertyGPSLongitude] as? NSNumber)?.doubleValue
        else { return nil }
        let isSouth = (gps[kCGImagePropertyGPSLatitudeRef] as? String)?.uppercased() == "S"
        let isWest = (gps[kCGImagePropertyGPSLongitudeRef] as? String)?.uppercased() == "W"
        let coordinate = CLLocationCoordinate2D(
            latitude: isSouth ? -latitude : latitude,
            longitude: isWest ? -longitude : longitude
        )
        // Some apps write 0, 0 when they have no fix.
        guard CLLocationCoordinate2DIsValid(coordinate), latitude != 0 || longitude != 0 else { return nil }
        return coordinate
    }
}

extension PhotoLocation {
    /// The distinct spots the photos were taken at, in photo order. Photos taken within
    /// about 100 meters of each other count as one spot.
    @concurrent
    static func spots(in photos: [Data]) async -> [CLLocationCoordinate2D] {
        var spots: [CLLocationCoordinate2D] = []
        for data in photos {
            guard let coordinate = coordinate(in: data) else { continue }
            let isNew = !spots.contains {
                abs($0.latitude - coordinate.latitude) < 0.001 && abs($0.longitude - coordinate.longitude) < 0.001
            }
            if isNew { spots.append(coordinate) }
        }
        return spots
    }
}
