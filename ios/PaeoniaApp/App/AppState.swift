enum AppState: CaseIterable, Equatable {
    case launching
    case unauthenticated
    case onboarding
    case unpaired
    case paired
    case paywalled
}
