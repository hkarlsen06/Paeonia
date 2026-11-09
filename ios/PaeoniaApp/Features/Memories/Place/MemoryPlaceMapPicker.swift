import CoreLocation
import MapKit
import SwiftUI

/// "Choose on the map": the person moves the map under a fixed pin. When the map stops,
/// the spot is named after its city, which is what the place is saved as.
struct MemoryPlaceMapPicker: View {
    /// Where the map starts. Nil starts on the phone's region setting.
    let start: CLLocationCoordinate2D?
    let onPick: (MemoryPlace) -> Void

    @State private var position: MapCameraPosition = .automatic
    @State private var lookup = MemoryPlaceMapModel()

    var body: some View {
        Map(position: $position, interactionModes: [.pan, .zoom])
            .mapStyle(MemoriesMapStyle.swiftUI)
            .environment(\.colorScheme, .dark)
            .onMapCameraChange(frequency: .onEnd) { context in
                lookup.select(context.region.center)
            }
            .overlay {
                pin.allowsHitTesting(false)
            }
            .safeAreaInset(edge: .bottom) { footer.paeoniaBannerBottomEdge() }
            .onDisappear { lookup.cancel() }
            .navigationTitle(Text(.memoriesPlaceChooseOnMap))
            .navigationBarTitleDisplayMode(.inline)
            .task {
                if let start {
                    position = .region(MKCoordinateRegion(
                        center: start,
                        latitudinalMeters: 2_000,
                        longitudinalMeters: 2_000
                    ))
                } else if let region = await MemoriesMapRegion.home() {
                    position = .region(region)
                }
            }
    }

    /// The tip sits on the map's center.
    private var pin: some View {
        Image(systemName: "mappin")
            .font(.system(size: 36, weight: .semibold))
            .foregroundStyle(.paeoniaAccentPrimary)
            .shadow(color: .black.opacity(0.4), radius: 4, y: 2)
            .offset(y: -18)
            .accessibilityHidden(true)
    }

    private var footer: some View {
        VStack(spacing: PaeoniaSpacing.space12) {
            Group {
                if let failure = lookup.failure {
                    Text(failure == .offline ? .memoriesPlaceOffline : .memoriesPlaceSearchFailed)
                } else if let place = lookup.place {
                    Text(place.nameAndCity)
                } else if lookup.isLoading {
                    ProgressView()
                } else if lookup.hasNoName {
                    Text(.memoriesPlaceNoName)
                } else {
                    Text(.memoriesPlacePickerHint)
                }
            }
            .font(PaeoniaTypography.body)
            .foregroundStyle(.paeoniaTextPrimary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)

            if lookup.failure != nil || lookup.hasNoName {
                Button { lookup.retry() } label: { Text(.commonTryAgain) }
                    .buttonStyle(PaeoniaSecondaryButtonStyle())
            }

            Button {
                if let place = lookup.place { onPick(place) }
            } label: {
                Text(.memoriesPlacePickerUse)
            }
            .buttonStyle(PaeoniaPrimaryButtonStyle())
            .disabled(lookup.place == nil)
        }
        .padding(PaeoniaSpacing.space16)
        .background(.paeoniaBackgroundElevated)
        .clipShape(RoundedRectangle(cornerRadius: PaeoniaRadius.radius20, style: .continuous))
        .padding(.horizontal, PaeoniaSpacing.screenHorizontalPadding)
        .padding(.bottom, PaeoniaSpacing.space8)
    }
}
