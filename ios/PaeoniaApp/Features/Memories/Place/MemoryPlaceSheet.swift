import CoreLocation
import MapKit
import SwiftUI

/// The place picker. Before the person types it lists places near where their photos
/// were taken and places either partner used before. Typing replaces both lists with
/// search suggestions. "Choose on the map" covers spots that search can't find.
struct MemoryPlaceSheet: View {
    /// Where the memory's photos were taken, read from the photos on this phone.
    let photoCoordinates: [CLLocationCoordinate2D]
    /// Places on the couple's other memories, newest first.
    let knownPlaces: [MemoryPlace]
    let isChanging: Bool
    let onPick: (MemoryPlace) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var model = MemoryPlaceSearchModel()
    @State private var isChoosingOnMap = false

    var body: some View {
        NavigationStack {
            list
                .paeoniaGroupedList()
                .disabled(model.isResolving)
                .overlay {
                    if model.isResolving {
                        ProgressView().tint(.paeoniaAccentPrimary)
                    }
                }
                .searchable(
                    text: $model.query,
                    placement: .navigationBarDrawer(displayMode: .always),
                    prompt: Text(.memoriesPlaceSearchPrompt)
                )
                .navigationTitle(Text(isChanging ? .memoriesPlaceSheetChangeTitle : .memoriesPlaceSheetTitle))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(role: .cancel) { dismiss() } label: { Text(.commonCancel) }
                    }
                }
                .navigationDestination(isPresented: $isChoosingOnMap) {
                    MemoryPlaceMapPicker(start: photoCoordinates.first ?? knownPlaces.first?.coordinate) { place in
                        pick(place)
                    }
                }
        }
        .presentationBackground(.paeoniaBackgroundPrimary)
        .task {
            await model.loadPhotoPlaces(from: photoCoordinates)
        }
    }

    private var list: some View {
        List {
            if model.trimmedQuery.isEmpty {
                suggestions
            } else {
                results
            }
            chooseOnMap
        }
    }

    private var chooseOnMap: some View {
        Section {
            Button {
                isChoosingOnMap = true
            } label: {
                Label {
                    Text(.memoriesPlaceChooseOnMap)
                } icon: {
                    Image(systemName: "mappin.and.ellipse").accessibilityHidden(true)
                }
            }
            .foregroundStyle(.paeoniaAccentPrimary)
            .listRowBackground(Color.paeoniaSurfacePrimary)
        }
    }

    @ViewBuilder
    private var suggestions: some View {
        if !model.photoPlaces.isEmpty {
            Section {
                ForEach(model.photoPlaces, id: \.self) { place in
                    placeRow(place, icon: "photo")
                }
            } header: {
                Text(.memoriesPlaceSectionPhotos)
            }
        }
        if !knownPlaces.isEmpty {
            Section {
                ForEach(knownPlaces, id: \.self) { place in
                    placeRow(place, icon: "heart.fill")
                }
            } header: {
                Text(.memoriesPlaceSectionUsed)
            }
        }
    }

    @ViewBuilder
    private var results: some View {
        Section {
            if let failure = model.failure {
                messageRow(failure == .offline ? .memoriesPlaceOffline : .memoriesPlaceSearchFailed)
            } else if model.hasNoResults {
                messageRow(.memoriesPlaceNoResults(model.trimmedQuery))
            }
            ForEach(model.completions, id: \.self) { completion in
                Button {
                    Task {
                        if let place = await model.resolve(completion) { pick(place) }
                    }
                } label: {
                    row(title: completion.title, subtitle: completion.subtitle, icon: "mappin")
                }
                .listRowBackground(Color.paeoniaSurfacePrimary)
            }
        }
    }

    private func placeRow(_ place: MemoryPlace, icon: String) -> some View {
        Button {
            pick(place)
        } label: {
            row(title: place.name, subtitle: place.cityAndCountry ?? "", icon: icon)
        }
        .listRowBackground(Color.paeoniaSurfacePrimary)
    }

    private func row(title: String, subtitle: String, icon: String) -> some View {
        HStack(spacing: PaeoniaSpacing.space12) {
            Image(systemName: icon)
                .font(.body)
                .foregroundStyle(.paeoniaAccentPrimary)
                .frame(width: 28)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: PaeoniaSpacing.space2) {
                Text(title)
                    .font(PaeoniaTypography.body)
                    .foregroundStyle(.paeoniaTextPrimary)
                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(PaeoniaTypography.caption)
                        .foregroundStyle(.paeoniaTextSecondary)
                }
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private func messageRow(_ message: LocalizedStringResource) -> some View {
        Text(message)
            .font(PaeoniaTypography.body)
            .foregroundStyle(.paeoniaTextSecondary)
            .listRowBackground(Color.paeoniaSurfacePrimary)
    }

    private func pick(_ place: MemoryPlace) {
        PaeoniaHaptics.selection()
        onPick(place)
        dismiss()
    }
}
