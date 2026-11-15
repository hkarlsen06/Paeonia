import CoreLocation
import SwiftUI

/// "Sammen" or "306 km" in the bar's title position, with how old the partner's place is
/// centered under it.
struct HomeMapDistanceLine: View {
    let current: LocationPoint
    let partner: LocationPoint
    let partnerCoordinate: CLLocationCoordinate2D
    let partnerWasStaleAtLastRefresh: Bool
    let compass: PartnerCompass
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
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
            line(isTogether: isTogether, at: context.date)
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

    private func line(isTogether: Bool, at date: Date) -> some View {
        let meters = CoupleMapSnapshot.distanceMeters(current.coordinate, partnerCoordinate)
        let distance = isTogether
            ? String(localized: .homeMapTogether)
            : CoupleMapSnapshot.formattedDistance(from: current.coordinate, to: partnerCoordinate)
        let age = PartnerLocationRecordedStatus.shortAge(capturedAt: partner.capturedAt, now: date)
        // The icon sits beside both lines, centered on them like the info button.
        return HStack(spacing: PaeoniaSpacing.space4) {
            // Apart, the arrow points up until the first compass reading.
            Image(systemName: isTogether ? "person.2.fill" : "location.north.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.paeoniaAccentPrimary)
                .contentTransition(.symbolEffect(.replace))
                .rotationEffect(.degrees(isTogether ? 0 : rotation ?? 0))
                .animation(reduceMotion ? nil : PaeoniaMotion.buttonPress, value: rotation)
                .accessibilityHidden(true)
            VStack(spacing: 0) {
                // Rolls up when the partner moves away and down when they come closer.
                Text(distance)
                    .contentTransition(.numericText(value: isTogether ? 0 : meters))
                Text(verbatim: age)
                    .contentTransition(.numericText())
                    .font(PaeoniaTypography.caption)
                    .foregroundStyle(.paeoniaTextSecondary)
            }
        }
        .animation(reduceMotion ? nil : PaeoniaMotion.stateChange, value: age)
        .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
        .fixedSize(horizontal: false, vertical: true)
        .font(PaeoniaTypography.bodyEmphasis)
        .foregroundStyle(.paeoniaTextPrimary)
        .shadow(color: .black.opacity(0.5), radius: 3, y: 1)
    }

    private var direction: Double? {
        guard let heading = compass.heading, let origin = compass.coordinate,
              let bearing = PartnerCompassDirection.bearing(from: origin, to: partnerCoordinate) else { return nil }
        return bearing - heading
    }
}
