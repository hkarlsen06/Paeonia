import CoreLocation
import SwiftUI

/// "Sammen · 2 t" or "306 km · 2 t", in the bar's title position.
struct HomeMapDistanceLine: View {
    let current: LocationPoint
    let partner: LocationPoint
    let partnerCoordinate: CLLocationCoordinate2D
    let partnerWasStaleAtLastRefresh: Bool
    let compass: PartnerCompass
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var rotation: Double?

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
                    .rotationEffect(.degrees(isTogether ? 0 : rotation ?? 0))
                    .opacity(isTogether || direction != nil ? 1 : 0)
                    .animation(reduceMotion ? nil : PaeoniaMotion.buttonPress, value: rotation)
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
            .task(id: scenePhase == .active && !isTogether) {
                if scenePhase == .active && !isTogether { compass.start() } else { compass.stop() }
            }
        }
        .onChange(of: direction, initial: true) { _, direction in
            let previous = rotation
            var transaction = Transaction()
            // The first reliable reading appears in place, without turning from an invented north.
            transaction.disablesAnimations = previous == nil || direction == nil
            withTransaction(transaction) {
                rotation = direction.map { PartnerCompassDirection.rotation(angle: $0, previous: previous) }
            }
        }
        .onDisappear { compass.stop() }
    }

    private var direction: Double? {
        guard let heading = compass.heading, let origin = compass.coordinate,
              let bearing = PartnerCompassDirection.bearing(from: origin, to: partnerCoordinate) else { return nil }
        return bearing - heading
    }
}
