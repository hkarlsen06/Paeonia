import CoreLocation
import MapKit
import Observation

/// State for the place sheet: search suggestions as the person types, and before that,
/// places near where their photos were taken. A failed search is classified with
/// `PaeoniaFailure`, so only a phone with no connection is told it is offline.
@MainActor
@Observable
final class MemoryPlaceSearchModel: NSObject {
    var query = "" {
        didSet { search() }
    }

    private(set) var completions: [MKLocalSearchCompletion] = []
    private(set) var isSearching = false
    private(set) var failure: PaeoniaFailure?
    /// Named places near the photos' spots, and the city each photo was taken in.
    private(set) var photoPlaces: [MemoryPlace] = []
    /// True while a picked suggestion is being looked up.
    private(set) var isResolving = false

    @ObservationIgnored private let completer = MKLocalSearchCompleter()

    override init() {
        super.init()
        completer.delegate = self
        completer.resultTypes = [.pointOfInterest, .address]
    }

    var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var hasNoResults: Bool {
        !trimmedQuery.isEmpty && !isSearching && failure == nil && completions.isEmpty
    }

    /// The suggestions for each distinct photo spot (see `MemoryPlaceLookup.photoSuggestions`).
    /// Failures leave the list empty: search still works.
    func loadPhotoPlaces(from coordinates: [CLLocationCoordinate2D]) async {
        var places: [MemoryPlace] = []
        for coordinate in coordinates.prefix(2) {
            for place in await MemoryPlaceLookup.photoSuggestions(around: coordinate)
            where !places.contains(where: { $0.isSameSpot(as: place) }) {
                places.append(place)
            }
        }
        photoPlaces = places
    }

    /// The place behind a search suggestion, or nil after a failure (shown in the list).
    func resolve(_ completion: MKLocalSearchCompletion) async -> MemoryPlace? {
        isResolving = true
        defer { isResolving = false }
        do {
            failure = nil
            return try await MemoryPlaceLookup.place(for: completion)
        } catch {
            failure = PaeoniaFailure(error)
            return nil
        }
    }

    private func search() {
        failure = nil
        guard !trimmedQuery.isEmpty else {
            completer.cancel()
            completions = []
            isSearching = false
            return
        }
        isSearching = true
        completer.queryFragment = trimmedQuery
    }
}

/// MapKit calls the completer's delegate on the main thread.
extension MemoryPlaceSearchModel: MKLocalSearchCompleterDelegate {
    func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        completions = completer.results
        isSearching = false
    }

    func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: any Error) {
        completions = []
        isSearching = false
        failure = PaeoniaFailure(error)
    }
}
