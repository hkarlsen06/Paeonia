import CoreGraphics
import Foundation
import ImageIO
import MapKit
import Testing
import UniformTypeIdentifiers
@testable import PaeoniaApp

/// The photo the phone sends has no location, time or camera in it, and the spot
/// and day are read from the original before that.
struct GuessMySpotPhotoTests {
    /// A small JPEG with the metadata a phone camera writes.
    private func cameraPhoto(gps: [CFString: Any]?, date: String? = "2024:06:12 18:30:05") throws -> Data {
        let width = 64, height = 48
        let context = try #require(CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ))
        context.setFillColor(CGColor(red: 0.2, green: 0.5, blue: 0.8, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let image = try #require(context.makeImage())
        let data = NSMutableData()
        let destination = try #require(
            CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil)
        )
        var properties: [CFString: Any] = [
            kCGImagePropertyTIFFDictionary: [kCGImagePropertyTIFFMake: "Apple", kCGImagePropertyTIFFModel: "iPhone"],
        ]
        if let date {
            properties[kCGImagePropertyExifDictionary] = [kCGImagePropertyExifDateTimeOriginal: date]
        }
        if let gps {
            properties[kCGImagePropertyGPSDictionary] = gps
        }
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        #expect(CGImageDestinationFinalize(destination))
        return data as Data
    }

    private func properties(of data: Data) throws -> [CFString: Any] {
        let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
        return CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] ?? [:]
    }

    @Test func theSpotAndDayComeFromThePhoto() throws {
        let data = try cameraPhoto(gps: [
            kCGImagePropertyGPSLatitude: 33.8688, kCGImagePropertyGPSLatitudeRef: "S",
            kCGImagePropertyGPSLongitude: 151.2093, kCGImagePropertyGPSLongitudeRef: "E",
        ])
        let prepared = try #require(GuessMySpotPhotoReader.prepare(data))
        let spot = try #require(prepared.spot)
        #expect(abs(spot.latitude + 33.8688) < 0.0001)
        #expect(abs(spot.longitude - 151.2093) < 0.0001)
        #expect(prepared.takenOn == "2024-06-12")
        #expect(prepared.width == 64 && prepared.height == 48)
    }

    @Test func theSentPhotoHasNoLocationTimeOrCamera() throws {
        let data = try cameraPhoto(gps: [
            kCGImagePropertyGPSLatitude: 60.39, kCGImagePropertyGPSLatitudeRef: "N",
            kCGImagePropertyGPSLongitude: 5.32, kCGImagePropertyGPSLongitudeRef: "E",
        ])
        #expect(try properties(of: data)[kCGImagePropertyGPSDictionary] != nil)
        let prepared = try #require(GuessMySpotPhotoReader.prepare(data))
        let sent = try properties(of: prepared.jpeg)
        #expect(sent[kCGImagePropertyGPSDictionary] == nil)
        let exif = sent[kCGImagePropertyExifDictionary] as? [CFString: Any]
        #expect(exif?[kCGImagePropertyExifDateTimeOriginal] == nil)
        let tiff = sent[kCGImagePropertyTIFFDictionary] as? [CFString: Any]
        #expect(tiff?[kCGImagePropertyTIFFMake] == nil)
        #expect(tiff?[kCGImagePropertyTIFFModel] == nil)
    }

    @Test func aPhotoWithoutALocationHasNoSpot() throws {
        let prepared = try #require(GuessMySpotPhotoReader.prepare(try cameraPhoto(gps: nil, date: nil)))
        #expect(prepared.spot == nil)
        #expect(prepared.takenOn == nil)
    }

    @Test func aDayInTheFutureCountsAsNone() throws {
        let photo = try cameraPhoto(gps: nil, date: "2999:01:01 12:00:00")
        let prepared = try #require(GuessMySpotPhotoReader.prepare(photo))
        #expect(prepared.takenOn == nil)
    }

    @Test func aBrokenZeroLocationCountsAsNone() throws {
        let data = try cameraPhoto(gps: [
            kCGImagePropertyGPSLatitude: 0.0, kCGImagePropertyGPSLatitudeRef: "N",
            kCGImagePropertyGPSLongitude: 0.0, kCGImagePropertyGPSLongitudeRef: "E",
        ])
        #expect(try #require(GuessMySpotPhotoReader.prepare(data)).spot == nil)
    }

    @Test func somethingThatIsNotAPhotoIsRefused() {
        #expect(GuessMySpotPhotoReader.prepare(Data("not a photo".utf8)) == nil)
    }

    @Test func theLiveMessageCannotCarryAPinOrTheRealSpot() throws {
        let view = GuessMySpotLiveMapView(MKMapRect(x: 1, y: 2, width: 3, height: 4), satellite: false)
        let messages: [GuessMySpotLiveMessage] = [
            .guessMap(roundID: UUID(), view: view),
            .photoPreview(roundID: UUID(), jpeg: Data([1, 2])),
            .photoPreviewCleared,
        ]
        let fields = try messages.map { message in
            let data = try JSONEncoder().encode(message)
            let json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
            let body = try #require(json.values.first as? [String: Any])
            return Set(body.keys)
        }
        #expect(fields == [["roundID", "view"], ["roundID", "jpeg"], []])
        let viewJSON = try #require(
            try JSONSerialization.jsonObject(with: JSONEncoder().encode(view)) as? [String: Any]
        )
        #expect(Set(viewJSON.keys) == ["x", "y", "width", "height", "satellite"])
    }

    @MainActor @Test func thePreviewIsAFewPixelsWithoutLocation() async throws {
        let original = try cameraPhoto(gps: [
            kCGImagePropertyGPSLatitude: 60.39, kCGImagePropertyGPSLatitudeRef: "N",
            kCGImagePropertyGPSLongitude: 5.32, kCGImagePropertyGPSLongitudeRef: "E",
        ])
        let prepared = try #require(GuessMySpotPhotoReader.prepare(original))
        let jpeg = try #require(await GuessMySpotPhotoPreview.jpeg(from: prepared.jpeg))
        #expect(try properties(of: jpeg)[kCGImagePropertyGPSDictionary] == nil)
        let preview = try #require(GuessMySpotPhotoPreview(roundID: UUID(), jpeg: jpeg))
        #expect(max(preview.image.size.width, preview.image.size.height) <= 32)
        // A whole photo is not a preview, so the guesser's phone drops it.
        #expect(GuessMySpotPhotoPreview(roundID: UUID(), jpeg: original) == nil)
    }
}
