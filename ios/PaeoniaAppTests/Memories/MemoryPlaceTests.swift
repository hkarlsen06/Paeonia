import CoreLocation
import Foundation
import ImageIO
import Testing
import UIKit
import UniformTypeIdentifiers
@testable import PaeoniaApp

struct MemoryPlaceTests {
    private let bryggen = MemoryPlace.bryggen

    // MARK: - Photo location

    @Test func readsTheSpotAPhotoWasTakenAt() throws {
        let data = try photo(gps: [
            kCGImagePropertyGPSLatitude: 33.8688,
            kCGImagePropertyGPSLatitudeRef: "S",
            kCGImagePropertyGPSLongitude: 151.2093,
            kCGImagePropertyGPSLongitudeRef: "E",
        ])
        let coordinate = try #require(PhotoLocation.coordinate(in: data))
        #expect(abs(coordinate.latitude + 33.8688) < 0.0001)
        #expect(abs(coordinate.longitude - 151.2093) < 0.0001)
    }

    @Test func aPhotoWithoutLocationHasNoSpot() throws {
        #expect(PhotoLocation.coordinate(in: try photo(gps: nil)) == nil)
        #expect(PhotoLocation.coordinate(in: Data("not a photo".utf8)) == nil)
    }

    /// Some apps write 0, 0 when they have no fix. That is not a real spot.
    @Test func zeroZeroIsNotASpot() {
        let gps: [CFString: Any] = [kCGImagePropertyGPSLatitude: 0.0, kCGImagePropertyGPSLongitude: 0.0]
        #expect(PhotoLocation.coordinate(fromGPS: gps) == nil)
    }

    @Test func photosTakenCloseTogetherCountAsOneSpot() async throws {
        let first = try photo(gps: [kCGImagePropertyGPSLatitude: 60.3975, kCGImagePropertyGPSLongitude: 5.3245])
        let near = try photo(gps: [kCGImagePropertyGPSLatitude: 60.3978, kCGImagePropertyGPSLongitude: 5.3247])
        let far = try photo(gps: [kCGImagePropertyGPSLatitude: 59.9075, kCGImagePropertyGPSLongitude: 10.7531])
        let spots = await PhotoLocation.spots(in: [first, near, try photo(gps: nil), far])
        #expect(spots.count == 2)
        #expect(abs((spots.last?.latitude ?? 0) - 59.9075) < 0.0001)
    }

    // MARK: - Place rules

    @Test func normalizedPlaceTrimsAndCutsToTheServersLimits() throws {
        let place = try #require(try MemoryDataService.normalizedPlace(MemoryPlace(
            name: "  " + String(repeating: "a", count: 200),
            latitude: 1,
            longitude: 2,
            city: "  ",
            countryCode: "no"
        )))
        #expect(place.name.count == MemoryDataService.placeNameCharacterLimit)
        #expect(place.city == nil)
        // The server only takes a two capital letter code, so anything else is dropped.
        #expect(place.countryCode == nil)
        #expect(try MemoryDataService.normalizedPlace(bryggen) == bryggen)
        #expect(try MemoryDataService.normalizedPlace(nil) == nil)
    }

    @Test func normalizedPlaceRefusesAPlaceTheServerWouldRefuse() {
        for place in [
            MemoryPlace(name: " ", latitude: 1, longitude: 2, city: nil, countryCode: nil),
            MemoryPlace(name: "North", latitude: 91, longitude: 2, city: nil, countryCode: nil),
            MemoryPlace(name: "East", latitude: 1, longitude: .infinity, city: nil, countryCode: nil),
        ] {
            #expect(throws: MemoryDataServiceError.invalidPlace) {
                try MemoryDataService.normalizedPlace(place)
            }
        }
    }

    @Test func placeText() {
        #expect(bryggen.nameAndCity == "Bryggen, Bergen")
        #expect(bryggen.shortName == "Bergen")
        let city = MemoryPlace(name: "Bergen", latitude: 60, longitude: 5, city: "Bergen", countryCode: nil)
        #expect(city.nameAndCity == "Bergen")
        #expect(city.cityAndCountry == nil)
    }

    // MARK: - Map content

    @Test func totalsCountCitiesWithinTheirCountry() {
        let places = [
            bryggen,
            MemoryPlace(name: "Fløyen", latitude: 60.39, longitude: 5.34, city: "Bergen", countryCode: "NO"),
            MemoryPlace(name: "Opera", latitude: 59.9, longitude: 10.7, city: "Oslo", countryCode: "NO"),
            MemoryPlace(name: "Louvre", latitude: 48.86, longitude: 2.33, city: "Paris", countryCode: "FR"),
            MemoryPlace(name: "Paris", latitude: 33.66, longitude: -95.55, city: "Paris", countryCode: "US"),
            MemoryPlace(name: "At sea", latitude: 58, longitude: 3, city: nil, countryCode: nil),
        ]
        let totals = MemoryPlaceTotals(places: places)
        #expect(totals.countries == 3)
        #expect(totals.cities == 4)
        #expect(totals.isWorthShowing)
    }

    @Test func totalsWaitForASecondCity() {
        let oneCity = MemoryPlaceTotals(places: [bryggen, bryggen])
        #expect(oneCity.cities == 1)
        #expect(!oneCity.isWorthShowing)
        #expect(!MemoryPlaceTotals(places: []).isWorthShowing)
    }

    @Test func clusterBadgeStopsAt99() {
        #expect(MemoryClusterBadge.label(count: 2) == "2")
        #expect(MemoryClusterBadge.label(count: 99) == "99")
        #expect(MemoryClusterBadge.label(count: 100) == "99+")
        #expect(MemoryClusterBadge.label(count: 1_250) == "99+")
    }

    @Test(arguments: [0, 1, 2, 5, 12, 40, 400])
    func pinEntranceNeverRunsLongerThanItsCap(count: Int) {
        let delays = MemoryPinEntrance.delays(count: count)
        #expect(delays.count == count)
        let end = (delays.last ?? 0) + MemoryPinEntrance.pinDuration
        #expect(count == 0 || end <= MemoryPinEntrance.totalDuration + 0.0001)
        #expect(delays == delays.sorted())
    }

    @Test func fewPinsStepApartEvenly() {
        #expect(MemoryPinEntrance.delays(count: 3) == [0, 0.05, 0.1])
    }

    @Test func mapContentSplitsPlacedAndUnplacedInTimelineOrder() {
        let owner = UUID()
        let photo = UUID()
        let records = [
            record(owner: owner, title: "New", date: "2026-07-01", place: bryggen, photo: photo),
            record(owner: owner, title: "No place", date: "2026-06-01", place: nil, photo: nil),
            record(owner: owner, title: "Old", date: "2026-05-01", place: bryggen, photo: nil),
        ]
        let content = MemoriesMapContent(records: records)
        #expect(content.placed.map(\.title) == ["New", "Old"])
        #expect(content.placed.first?.photoAssetID == photo)
        #expect(content.placed.last?.photoAssetID == nil)
        #expect(content.unplaced.map(\.snapshot.title) == ["No place"])
    }

    // MARK: - Helpers

    private func photo(gps: [CFString: Any]?) throws -> Data {
        let image = UIGraphicsImageRenderer(size: CGSize(width: 4, height: 4)).image { context in
            UIColor.systemPink.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 4, height: 4))
        }
        let cgImage = try #require(image.cgImage)
        let output = NSMutableData()
        let destination = try #require(
            CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil)
        )
        let properties = gps.map { [kCGImagePropertyGPSDictionary: $0] as CFDictionary }
        CGImageDestinationAddImage(destination, cgImage, properties)
        #expect(CGImageDestinationFinalize(destination))
        return output as Data
    }

    private func record(owner: UUID, title: String, date: String, place: MemoryPlace?, photo: UUID?) -> MemoryRecord {
        let now = Date(timeIntervalSince1970: 1_000)
        return MemoryRecord(
            snapshot: MemorySnapshot(
                ownerUserID: owner,
                memoryID: UUID(),
                coupleID: UUID(),
                title: title,
                memoryDate: date,
                place: place,
                createdByUserID: owner,
                lastEditedByUserID: owner,
                revision: 1,
                moderationStatus: .visible,
                deletedAt: nil,
                createdAt: now,
                updatedAt: now,
                syncUpdatedAt: now,
                ownNote: nil,
                partnerNote: nil,
                visibleMemoryMediaIDs: [],
                visibleMediaAssetIDs: photo.map { [$0] } ?? [],
                media: [],
                threadID: nil
            )
        )
    }
}

extension MemoryPlace {
    static let bryggen = MemoryPlace(
        name: "Bryggen",
        latitude: 60.3975,
        longitude: 5.3245,
        city: "Bergen",
        countryCode: "NO"
    )
}
