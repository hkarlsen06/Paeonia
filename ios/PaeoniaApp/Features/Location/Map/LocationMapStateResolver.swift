import Foundation

extension LocationMapViewModel {
    /// Picks what the map card shows. The partner's location only appears when
    /// you share, iOS lets Paeonia read your location, and the server reports
    /// the partner as visible, so the map is never one-sided.
    static func resolveMapState(
        visibility: LocationVisibilitySnapshot?,
        ownLocation: OwnLocationSnapshot?,
        authorization: ForegroundLocationAuthorizationState = .authorized,
        isLocating: Bool = false,
        now: Date = Date()
    ) -> CoupleMapState {
        // Nothing can be shared while iOS location access is off, so that is
        // the one thing worth telling the user, whatever else is stored.
        if authorization == .denied {
            return .locationAccessOff
        }
        // No snapshot means the server has not answered yet: a first pairing,
        // or a return from the paywall, which clears the cached location. The
        // server always answers with a snapshot, so asking the person to share
        // here would flash the wrong card for a moment.
        guard let visibility, visibility.viewerSharingEnabled else {
            return isLocating ? .locatingCurrent : visibility == nil ? .loading : .currentUnknown
        }
        guard let current = ownLocation?.location else {
            return ownLocationMissingState(authorization: authorization, isLocating: isLocating)
        }

        switch visibility.visibilityState {
        case .visible:
            guard let partner = visibility.partnerLocation else {
                return .waitingForPartnerLocation
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
        case .notSharing where visibility.partnerSharingEnabled:
            return .waitingForPartnerLocation
        case .unknown("local"):
            // The repositories write "local" when you just turned sharing on
            // and the server has not answered yet.
            // The partner's own switch is still known from the last answer.
            return visibility.partnerSharingEnabled
                ? .waitingForPartnerLocation
                : .partnerUnknown(.notSharing)
        default:
            return .partnerUnknown(visibility.visibilityState)
        }
    }

    /// Sharing is on but this phone has no location yet. When iOS has not
    /// asked this phone yet, as after a fresh install, the card asks to share,
    /// which leads to that question.
    private static func ownLocationMissingState(
        authorization: ForegroundLocationAuthorizationState,
        isLocating: Bool
    ) -> CoupleMapState {
        if isLocating {
            return .locatingCurrent
        }
        return authorization == .notDetermined ? .currentUnknown : .currentLocationMissing
    }
}
