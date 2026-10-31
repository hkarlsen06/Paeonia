import CoreLocation
import MapKit
import SwiftUI

struct LocationMapDetails: View {
    let current: LocationPoint
    let partner: LocationPoint
    let partnerName: String
    let partnerWasStaleAtLastRefresh: Bool

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(CoupleMapSnapshot.formattedDistance(from: current.coordinate, to: partner.coordinate))
                    Text(PartnerLocationRecordedStatus.accessibilityText(
                        partnerName: partnerName, capturedAt: partner.capturedAt,
                        wasStaleAtLastRefresh: partnerWasStaleAtLastRefresh
                    ))
                }
                Section {
                    coordinates(current)
                } header: {
                    Text(.homeMapYourLocation)
                }
                Section(partnerName) {
                    coordinates(partner)
                }
                Button(.homeMapOpenLocations, action: openMaps)
            }
            .paeoniaGroupedList()
            .navigationTitle(Text(.homeMapLocationDetails))
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(.commonDone) { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private func coordinates(_ location: LocationPoint) -> some View {
        VStack(alignment: .leading, spacing: PaeoniaSpacing.space8) {
            LabeledContent(.homeMapLatitude, value: location.latitude.formatted(.number.precision(.fractionLength(4))))
            LabeledContent(
                .homeMapLongitude, value: location.longitude.formatted(.number.precision(.fractionLength(4)))
            )
            Text(location.capturedAt, format: .dateTime.year().month(.wide).day().hour().minute())
        }
        .textSelection(.enabled)
    }

    private func openMaps() {
        let own = MKMapItem(
            location: CLLocation(latitude: current.latitude, longitude: current.longitude), address: nil
        )
        own.name = String(localized: .homeMapYourLocation)
        let other = MKMapItem(
            location: CLLocation(latitude: partner.latitude, longitude: partner.longitude), address: nil
        )
        other.name = partnerName
        MKMapItem.openMaps(with: [own, other])
    }
}
