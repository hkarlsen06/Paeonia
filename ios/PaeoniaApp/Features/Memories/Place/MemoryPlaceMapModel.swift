import CoreLocation
import Foundation
import Observation

@Observable
final class MemoryPlaceMapModel {
    private(set) var center: CLLocationCoordinate2D?
    private(set) var place: MemoryPlace?
    private(set) var failure: PaeoniaFailure?
    private(set) var isLoading = false
    private(set) var hasNoName = false
    @ObservationIgnored private var task: Task<Void, Never>?
    private let lookup: (CLLocationCoordinate2D) async throws -> MemoryPlace?

    init(lookup: @escaping (CLLocationCoordinate2D) async throws -> MemoryPlace? = MemoryPlaceLookup.cityPlace) {
        self.lookup = lookup
    }

    func select(_ coordinate: CLLocationCoordinate2D) {
        center = coordinate
        retry()
    }

    func retry() {
        guard let center else { return }
        task?.cancel()
        place = nil
        failure = nil
        hasNoName = false
        isLoading = true
        task = Task {
            do {
                let found = try await lookup(center)
                guard !Task.isCancelled else { return }
                place = found
                hasNoName = found == nil
            } catch {
                guard !Task.isCancelled else { return }
                failure = PaeoniaFailure(error)
            }
            isLoading = false
        }
    }

    func cancel() {
        task?.cancel()
    }
}
