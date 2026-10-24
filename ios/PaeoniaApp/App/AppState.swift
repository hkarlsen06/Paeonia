nonisolated enum AppState: CaseIterable, Equatable {
    case launching
    case unauthenticated
    case onboarding
    case limitedAuthenticated
    case unpaired
    case invitePending
    case paired
    case pairedPaywalled
    case relationshipEndedNotice
    case accountClosed
    case deletingAccount
}
