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
        return VStack(alignment: .leading, spacing: PaeoniaSpacing.space4) {
            HStack(spacing: PaeoniaSpacing.space4) {
                // Without a compass reading the icon fades out as it was, instead of turning
                // into an arrow that points nowhere.
                Image(systemName: !isTogether && direction != nil ? "location.north.fill" : "person.2.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.paeoniaAccentPrimary)
                    .contentTransition(.symbolEffect(.replace))
                    .rotationEffect(.degrees(isTogether ? 0 : rotation ?? 0))
                    .opacity(isTogether || direction != nil ? 1 : 0)
                    .animation(reduceMotion ? nil : PaeoniaMotion.buttonPress, value: rotation)
                    .accessibilityHidden(true)
                // Rolls up when the partner moves away and down when they come closer.
                Text(distance)
                    .contentTransition(.numericText(value: isTogether ? 0 : meters))
                if !dynamicTypeSize.isAccessibilitySize {
                    Text(verbatim: "· " + age)
                        .contentTransition(.numericText())
                }
            }
            if dynamicTypeSize.isAccessibilitySize {
                Text(verbatim: age)
                    .contentTransition(.numericText())
                    .font(PaeoniaTypography.caption)
                    .foregroundStyle(.paeoniaTextSecondary)
            }
        }
        .animation(reduceMotion ? nil : PaeoniaMotion.stateChange, value: age)
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
