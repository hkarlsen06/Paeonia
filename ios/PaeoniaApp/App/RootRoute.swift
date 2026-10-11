import Foundation

enum RootNotice: Equatable {
    case sessionLoadFailed
    /// The sign-in expired or was ended on another device while the app ran.
    case sessionEnded
    case signInFailed
    case onboardingFailed
    case signOutFailed
    case deleteAccountFailed
    case relationshipEndedAcknowledgeFailed
}

enum RootPresentedDestination: Equatable {
    case widgetDrawing
}

/// The root's routing state. `RootViewModel` derives the visible `AppState`,
/// the auth route, and the current relationship from it.
enum RootRoute: Equatable {
    case launching
    case signedOut
    case onboarding(AuthSession)
    /// Access is being resolved. `previous` keeps the last stable resolution on
    /// screen during a refresh. Without one, `holding` is the screen that stays
    /// up, so signing in or finishing the profile keeps its own screen (with a
    /// spinner on the button) instead of flashing an empty one.
    case resolvingAccess(AuthSession, previous: AccessRouteResolution?, holding: AppState)
    case access(AuthSession, AccessRouteResolution)
    case deletingAccount(AuthSession?)

    var appState: AppState {
        switch self {
        case .launching:
            .launching
        case .signedOut:
            .unauthenticated
        case .onboarding:
            .onboarding
        case let .resolvingAccess(_, previous, holding):
            previous?.route.appState ?? holding
        case let .access(_, accessResolution):
            accessResolution.route.appState
        case .deletingAccount:
            .deletingAccount
        }
    }

    var authRoute: AuthRoute {
        switch self {
        case .launching, .signedOut:
            .signedOut
        case let .onboarding(session):
            .onboarding(session)
        case let .resolvingAccess(session, _, _),
             let .access(session, _),
             let .deletingAccount(.some(session)):
            .limitedAuthenticated(session)
        case .deletingAccount(nil):
            .signedOut
        }
    }

    var session: AuthSession? {
        authRoute.session
    }

    var accessResolution: AccessRouteResolution? {
        switch self {
        case let .resolvingAccess(_, previous, _):
            previous
        case let .access(_, accessResolution):
            accessResolution
        case .launching,
             .signedOut,
             .onboarding,
             .deletingAccount:
            nil
        }
    }

    /// The same route carrying a newer copy of the signed-in user's session.
    func replacingSession(_ session: AuthSession) -> RootRoute {
        switch self {
        case .onboarding:
            .onboarding(session)
        case let .resolvingAccess(_, previous, holding):
            .resolvingAccess(session, previous: previous, holding: holding)
        case let .access(_, resolution):
            .access(session, resolution)
        case .deletingAccount(.some):
            .deletingAccount(session)
        case .launching, .signedOut, .deletingAccount(nil):
            self
        }
    }

    var isAccessSettled: Bool {
        if case .access = self {
            return true
        }
        return false
    }

    var isResolvingAccess: Bool {
        if case .resolvingAccess = self {
            return true
        }
        return false
    }
}
