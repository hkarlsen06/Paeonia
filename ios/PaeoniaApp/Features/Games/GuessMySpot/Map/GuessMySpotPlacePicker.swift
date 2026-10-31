import MapKit
import SwiftUI

/// Inputs come only from the person searching. Never seed these from a round or photo.
struct GuessMySpotPlacePicker: View {
    let select: (GuessMySpotCoordinate) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var latitude = ""
    @State private var longitude = ""
    @State private var results: [MKMapItem] = []
    @State private var isSearching = false
    @State private var searchFailed = false

    var body: some View {
        NavigationStack {
            Form {
                searchSection
                coordinateSection
            }
            .navigationTitle(Text(.guessMySpotChoosePlace))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(.commonDone) { dismiss() }
                }
            }
        }
    }

    private var searchSection: some View {
        Section {
            TextField(.guessMySpotPlaceSearch, text: $query)
                .onSubmit { Task { await search() } }
                .accessibilityIdentifier("guessMySpot.place.query")
            Button(.guessMySpotPlaceSearch) { Task { await search() } }
                .disabled(query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSearching)
            if isSearching { ProgressView() }
            if searchFailed { Text(.guessMySpotPlaceSearchFailed) }
            ForEach(results.indices, id: \.self) { index in
                let item = results[index]
                Button {
                    choose(GuessMySpotCoordinate(item.location.coordinate))
                } label: {
                    VStack(alignment: .leading) {
                        Text(item.name ?? "")
                        Text(item.location.coordinate.latitude.formatted() + ", "
                            + item.location.coordinate.longitude.formatted())
                            .font(.caption)
                    }
                }
            }
        }
    }

    private var coordinateSection: some View {
        Section {
            TextField(.guessMySpotLatitude, text: $latitude)
                .keyboardType(.numbersAndPunctuation)
                .accessibilityIdentifier("guessMySpot.place.latitude")
            TextField(.guessMySpotLongitude, text: $longitude)
                .keyboardType(.numbersAndPunctuation)
                .accessibilityIdentifier("guessMySpot.place.longitude")
            Button(.guessMySpotChoosePlace) {
                if let coordinate { choose(coordinate) }
            }
            .disabled(coordinate == nil)
            .accessibilityIdentifier("guessMySpot.place.select")
        } footer: {
            Text(.guessMySpotCoordinateHelp)
        }
    }

    private var coordinate: GuessMySpotCoordinate? {
        GuessMySpotCoordinateInput.parse(latitude: latitude, longitude: longitude)
    }

    private func choose(_ coordinate: GuessMySpotCoordinate) {
        guard GuessMySpotRules.isValid(coordinate) else { return }
        select(coordinate)
        dismiss()
    }

    private func search() async {
        guard !isSearching else { return }
        isSearching = true
        searchFailed = false
        results = []
        defer { isSearching = false }
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        do {
            results = try await MKLocalSearch(request: request).start().mapItems
            searchFailed = results.isEmpty
        } catch {
            searchFailed = true
        }
    }
}

nonisolated enum GuessMySpotCoordinateInput {
    static func parse(latitude: String, longitude: String) -> GuessMySpotCoordinate? {
        func number(_ text: String) -> Double? {
            Double(text.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: ",", with: "."))
        }
        guard let latitude = number(latitude), let longitude = number(longitude) else { return nil }
        let coordinate = GuessMySpotCoordinate(latitude: latitude, longitude: longitude)
        return GuessMySpotRules.isValid(coordinate) ? coordinate : nil
    }
}
