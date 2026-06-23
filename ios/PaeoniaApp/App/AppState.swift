nonisolated enum AppState: CaseIterable, Equatable {
    case launching
    case unauthenticated
    case onboarding
    case limitedAuthenticated
    case reviewAccess
    case unpaired
    case invitePending
    case paired
    case pairedPaywalled
    case entitlementLost
    case entitlementRestored
    case relationshipEndedNotice
    case deletingAccount
}
