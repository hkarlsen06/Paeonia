import CoreLocation
import MapKit
import SwiftUI

/// The memory form's place row, under the date. Empty, it reads "Add". When a picked
/// photo carries the spot it was taken at, a suggestion offers that city, and only a tap
/// adds it. Set, it shows a small map, the name, the city and country, and a remove button.
struct MemoryPlaceField: View {
    @Binding var place: MemoryPlace?
    let photos: [MemoryDraftPhoto]
    let knownPlaces: [MemoryPlace]

    @State private var photoSpots: [CLLocationCoordinate2D] = []
    @State private var suggestion: MemoryPlace?
    @State private var isPicking = false

    var body: some View {
        VStack(alignment: .leading, spacing: PaeoniaSpacing.space12) {
            if let place {
                chosenRow(place)
            } else {
                addRow
                if let suggestion {
                    suggestionRow(suggestion)
                        .transition(.opacity)
                }
            }
        }
        .animation(PaeoniaMotion.stateChange, value: place)
        .animation(PaeoniaMotion.stateChange, value: suggestion)
        .sheet(isPresented: $isPicking) {
            MemoryPlaceSheet(
                photoCoordinates: photoSpots,
                knownPlaces: knownPlaces,
                isChanging: place != nil
            ) { picked in
                place = picked
            }
        }
        .task(id: photos.map(\.id)) {
            await readPhotoSpots()
        }
    }

    private var addRow: some View {
        Button {
            isPicking = true
        } label: {
            HStack {
                Text(.memoriesPlaceLabel)
                    .font(PaeoniaTypography.body)
                    .foregroundStyle(.paeoniaTextPrimary)
                Spacer(minLength: PaeoniaSpacing.space16)
                Text(.memoriesPlaceAdd)
                    .font(PaeoniaTypography.body)
                    .foregroundStyle(.paeoniaAccentPrimary)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.paeoniaAccentPrimary)
                    .accessibilityHidden(true)
            }
            .frame(minHeight: PaeoniaSpacing.compactButtonHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func suggestionRow(_ suggestion: MemoryPlace) -> some View {
        HStack(spacing: PaeoniaSpacing.space12) {
            Image(systemName: "photo")
                .foregroundStyle(.paeoniaAccentPrimary)
                .accessibilityHidden(true)
            Text(.memoriesPlaceSuggestion(suggestion.name))
                .font(PaeoniaTypography.body)
                .foregroundStyle(.paeoniaTextPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button {
                PaeoniaHaptics.selection()
                place = suggestion
            } label: {
                Text(.memoriesPlaceAdd)
                    .font(PaeoniaTypography.bodyEmphasis)
                    .foregroundStyle(.paeoniaTextInverse)
                    .padding(.horizontal, PaeoniaSpacing.space12)
                    .padding(.vertical, PaeoniaSpacing.space8)
                    .background(.paeoniaAccentPrimary, in: Capsule())
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(PaeoniaSpacing.space12)
        .overlay {
            RoundedRectangle(cornerRadius: PaeoniaRadius.radius16, style: .continuous)
                .strokeBorder(Color.paeoniaMemory.opacity(0.35), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
        }
        .accessibilityElement(children: .combine)
    }

    private func chosenRow(_ place: MemoryPlace) -> some View {
        HStack(spacing: PaeoniaSpacing.space12) {
            Button {
                isPicking = true
            } label: {
                chosenLabel(place)
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityHint(Text(.memoriesPlaceSheetChangeTitle))

            Button {
                self.place = nil
            } label: {
                Image(systemName: "xmark")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.paeoniaTextSecondary)
                    .frame(width: PaeoniaSpacing.compactButtonHeight, height: PaeoniaSpacing.compactButtonHeight)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(.memoriesPlaceRemove))
        }
        .padding(PaeoniaSpacing.space8)
        .background(
            .paeoniaSurfaceSecondary,
            in: RoundedRectangle(cornerRadius: PaeoniaRadius.radius16, style: .continuous)
        )
    }

    private func chosenLabel(_ place: MemoryPlace) -> some View {
        HStack(spacing: PaeoniaSpacing.space12) {
            MemoryPlaceMapThumbnail(coordinate: place.coordinate)
            VStack(alignment: .leading, spacing: PaeoniaSpacing.space2) {
                Text(place.name)
                    .font(PaeoniaTypography.bodyEmphasis)
                    .foregroundStyle(.paeoniaTextPrimary)
                if let detail = place.cityAndCountry {
                    Text(detail)
                        .font(PaeoniaTypography.caption)
                        .foregroundStyle(.paeoniaTextSecondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .contentShape(Rectangle())
    }

    /// Reads the photos' spots off the main actor, then names the first one's city for
    /// the suggestion. Camera shots and photos shared without their location have no spot.
    private func readPhotoSpots() async {
        let spots = await PhotoLocation.spots(in: photos.map(\.data))
        guard !Task.isCancelled else { return }
        photoSpots = spots
        guard let first = spots.first else {
            suggestion = nil
            return
        }
        let city = try? await MemoryPlaceLookup.cityPlace(at: first)
        guard !Task.isCancelled else { return }
        suggestion = city
    }
}

/// A small dark map around the place, drawn once as an image.
struct MemoryPlaceMapThumbnail: View {
    let coordinate: CLLocationCoordinate2D
    var size: CGFloat = 48

    @State private var image: UIImage?

    var body: some View {
        ZStack {
            Color.paeoniaBackgroundSecondary
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .transition(.opacity)
            }
            Circle()
                .fill(.paeoniaAccentPrimary)
                .frame(width: 10, height: 10)
                .overlay(Circle().stroke(Color.paeoniaMemory, lineWidth: 2))
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: PaeoniaRadius.radius12, style: .continuous))
        .accessibilityHidden(true)
        .task(id: "\(coordinate.latitude),\(coordinate.longitude)") {
            let options = MKMapSnapshotter.Options()
            options.region = MKCoordinateRegion(center: coordinate, latitudinalMeters: 1_500, longitudinalMeters: 1_500)
            options.size = CGSize(width: size, height: size)
            options.traitCollection = UITraitCollection(userInterfaceStyle: .dark)
            options.preferredConfiguration = MemoriesMapStyle.configuration()
            let snapshot = try? await MKMapSnapshotter(options: options).start()
            guard !Task.isCancelled else { return }
            withAnimation(PaeoniaMotion.stateChange) { image = snapshot?.image }
        }
    }
}
