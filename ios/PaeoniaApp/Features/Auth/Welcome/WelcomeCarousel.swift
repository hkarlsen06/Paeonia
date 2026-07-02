import Foundation

/// Which shared-artifact hero a welcome page shows. The order of the cases is not
/// the carousel order — `WelcomeCarousel.standard` owns that.
enum WelcomePageKind: Hashable, CaseIterable, Sendable {
    case doodle
    case dailyQuestions
    case countdown
}

/// One pre-auth welcome page: a hero artifact plus the copy that sells it.
struct WelcomePage: Identifiable {
    let kind: WelcomePageKind
    let title: LocalizedStringResource
    let subtitle: LocalizedStringResource

    var id: WelcomePageKind { kind }
}

/// The pre-auth welcome carousel — the ordered set of shared-artifact screens shown
/// before the sign-in screen. Kept pure and view-free so the order and per-page copy
/// can be unit-tested without SwiftUI.
struct WelcomeCarousel {
    let pages: [WelcomePage]

    /// The canonical order. The doodle leads on purpose: "draw on your partner's home
    /// screen" is the most distinctive, least-expected feature, so it makes the
    /// strongest first hook. Daily questions and the countdown follow.
    static let standard = WelcomeCarousel(pages: [
        WelcomePage(
            kind: .doodle,
            title: .welcomeDoodleTitle,
            subtitle: .welcomeDoodleSubtitle
        ),
        WelcomePage(
            kind: .dailyQuestions,
            title: .welcomeDailyQuestionsTitle,
            subtitle: .welcomeDailyQuestionsSubtitle
        ),
        WelcomePage(
            kind: .countdown,
            title: .welcomeCountdownTitle,
            subtitle: .welcomeCountdownSubtitle
        ),
    ])

    var count: Int { pages.count }

    var lastIndex: Int { max(0, count - 1) }

    /// True when `index` is the final page — the point where the primary button reads
    /// "Get started" and leads into the sign-in screen rather than advancing.
    func isLast(_ index: Int) -> Bool {
        index >= lastIndex
    }

    func page(at index: Int) -> WelcomePage? {
        pages.indices.contains(index) ? pages[index] : nil
    }
}
