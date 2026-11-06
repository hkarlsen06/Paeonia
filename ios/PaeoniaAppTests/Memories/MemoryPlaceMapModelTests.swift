import CoreLocation
import Foundation
import Testing
@testable import PaeoniaApp

@MainActor
struct MemoryPlaceMapModelTests {
    @Test func retryUsesTheSelectedCoordinateWithoutMovingTheMap() async throws {
        var shouldFail = true
        let model = MemoryPlaceMapModel { coordinate in
            if shouldFail { throw URLError(.notConnectedToInternet) }
            return MemoryPlace(
                name: "Bergen", latitude: coordinate.latitude, longitude: coordinate.longitude,
                city: nil, countryCode: nil
            )
        }
        let coordinate = CLLocationCoordinate2D(latitude: 60.39, longitude: 5.32)
        model.select(coordinate)
        await waitForMemoryTestCondition { !model.isLoading }
        #expect(model.failure == .offline)
        #expect(model.place == nil)

        shouldFail = false
        model.retry()
        await waitForMemoryTestCondition { !model.isLoading }
        let place = try #require(model.place)
        #expect(place.latitude == coordinate.latitude)
        #expect(place.longitude == coordinate.longitude)
        #expect(model.failure == nil)
    }

    @Test func unnamedPointHasACompletedLookupState() async {
        let model = MemoryPlaceMapModel { _ in nil }
        model.select(CLLocationCoordinate2D(latitude: 0, longitude: 0))
        await waitForMemoryTestCondition { !model.isLoading }
        #expect(model.hasNoName)
        #expect(model.failure == nil)
        #expect(model.place == nil)
    }

    @Test func anOlderLookupCannotReplaceTheNewlySelectedPoint() async throws {
        var held: CheckedContinuation<MemoryPlace?, Never>?
        let model = MemoryPlaceMapModel { coordinate in
            if coordinate.latitude == 1 {
                return await withCheckedContinuation { held = $0 }
            }
            return MemoryPlace(
                name: "New spot", latitude: coordinate.latitude, longitude: coordinate.longitude,
                city: nil, countryCode: nil
            )
        }
        model.select(CLLocationCoordinate2D(latitude: 1, longitude: 1))
        await waitForMemoryTestCondition { held != nil }
        model.select(CLLocationCoordinate2D(latitude: 2, longitude: 2))
        await waitForMemoryTestCondition { !model.isLoading }
        held?.resume(returning: MemoryPlace(name: "Old spot", latitude: 1, longitude: 1, city: nil, countryCode: nil))
        await Task.yield()
        #expect(model.place?.name == "New spot")
        #expect(model.place?.latitude == 2)
    }
}
