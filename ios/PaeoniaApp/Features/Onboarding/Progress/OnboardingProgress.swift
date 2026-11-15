import Foundation

/// How a person came into Paeonia, which decides the steps of their onboarding.
nonisolated enum OnboardingPath: Equatable, Sendable {
    /// Started the couple: set the start date, made the first drawing, then signed in.
    case starting
    /// Came with a partner's code: entered the code, then signed in.
    case joining
}

/// A screen that shows the onboarding progress bar.
nonisolated enum OnboardingStage: Equatable, Sendable {
    /// Profile setup.
    case profile
    /// The paywall for someone who starts the couple, the join screen for someone who joins.
    case access
    /// The invite screen. Only someone who starts the couple sees it.
    case invite
    /// The first day sequence after pairing: the steps moved past out of the steps planned.
    case firstDay(finished: Int, total: Int)
}

/// How far through onboarding a screen is. The steps before sign-in show no bar, but
/// they count as done once the person moved past them, so the bar starts partly full.
nonisolated enum OnboardingProgress {
    private enum Step: Equatable {
        case startDate
        case firstDrawing
        case partnerCode
        case signIn
        case profile
        case access
        case invite
        case firstDay
    }

    /// The steps of each path in order. The first day sequence counts as two steps,
    /// because it is the longest part.
    private static func steps(for path: OnboardingPath) -> [Step] {
        switch path {
        case .starting:
            [.startDate, .firstDrawing, .signIn, .profile, .access, .invite, .firstDay, .firstDay]
        case .joining:
            [.partnerCode, .signIn, .profile, .access, .firstDay, .firstDay]
        }
    }

    /// The part of `path` done when `stage` shows, from 0 to 1. Nil when the path
    /// has no such stage, such as the invite screen for someone who joins.
    static func fraction(path: OnboardingPath, stage: OnboardingStage) -> Double? {
        let steps = steps(for: path)
        guard let index = steps.firstIndex(of: step(for: stage)) else {
            return nil
        }
        var done = Double(index)
        if case let .firstDay(finished, total) = stage, total > 0 {
            let firstDaySteps = steps.count(where: { $0 == .firstDay })
            done += Double(firstDaySteps * min(finished, total)) / Double(total)
        }
        return done / Double(steps.count)
    }

    private static func step(for stage: OnboardingStage) -> Step {
        switch stage {
        case .profile: .profile
        case .access: .access
        case .invite: .invite
        case .firstDay: .firstDay
        }
    }
}
