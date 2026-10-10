import Foundation

extension LocationMapViewModel {
    static func resolveMapState(
        visibility: LocationVisibilitySnapshot?,
        ownLocation: OwnLocationSnapshot?,
        now: Date = Date()
    ) -> CoupleMapState {
        guard let visibility else {
            return .partnerUnknown(.unknown("missing_visibility"))
        }
        guard visibility.viewerSharingEnabled else {
            return .currentUnknown
        }
        guard let current = ownLocation?.location else {
            return .currentUnknown
        }
        guard visibility.visibilityState == .visible,
              let partner = visibility.partnerLocation
        else {
            return .partnerUnknown(visibility.visibilityState)
        }

        return .ready(
            current: current,
            partner: partner,
            // The server's stale flag only changes when a row is written, so
            // age comes from the capture time. The map views re-check it on a timer.
            partnerWasStaleAtLastRefresh: LocationDisplayRecency.resolve(
                capturedAt: partner.capturedAt,
                now: now
            ) == .stale
        )
    }
}
