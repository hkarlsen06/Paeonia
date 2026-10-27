import CoreLocation
import SwiftUI

/// "Sammen · 2 t" or "306 km · 2 t", in the bar's title position.
struct HomeMapDistanceLine: View {
    let current: LocationPoint
    let partner: LocationPoint
    let partnerCoordinate: CLLocationCoordinate2D
    let partnerWasStaleAtLastRefresh: Bool
    /// How far the map is turned. The arrow turns back by as much, so it points north.
    var mapDirection: Double = 0

    var body: some View {
        TimelineView(.everyMinute) { context in
            // A place from a day ago or more says nothing about now, so it never reads as together.
            let isTogether = CoupleMapFraming.areTogether(
                current: current.coordinate,
                partner: partnerCoordinate,
                partnerIsStale: LocationDisplayRecency.resolve(
                    capturedAt: partner.capturedAt,
                    now: context.date,
                    wasStaleAtLastRefresh: partnerWasStaleAtLastRefresh
                ) == .stale
            )
            HStack(spacing: PaeoniaSpacing.space4) {
                Image(systemName: isTogether ? "person.2.fill" : "location.north.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.paeoniaAccentPrimary)
                    .rotationEffect(.degrees(isTogether ? 0 : -mapDirection))
                    .accessibilityHidden(true)
                Text(isTogether
                    ? String(localized: .homeMapTogether)
                    : CoupleMapSnapshot.formattedDistance(from: current.coordinate, to: partnerCoordinate))
                Text(verbatim: "· " + PartnerLocationRecordedStatus.shortAge(
                    capturedAt: partner.capturedAt, now: context.date
                ))
            }
            .font(PaeoniaTypography.bodyEmphasis)
            .foregroundStyle(.paeoniaTextPrimary)
            .shadow(color: .black.opacity(0.5), radius: 3, y: 1)
        }
    }
}
