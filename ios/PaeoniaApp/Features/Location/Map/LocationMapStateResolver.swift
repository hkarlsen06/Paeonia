extension LocationMapViewModel {
    static func resolveMapState(
        visibility: LocationVisibilitySnapshot?,
        ownLocation: OwnLocationSnapshot?
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
            partnerWasStaleAtLastRefresh: visibility.partnerLocationIsStale
        )
    }
}
