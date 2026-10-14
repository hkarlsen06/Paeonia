import Foundation

/// The high-level destinations shown in the paired tab bar.
///
/// `home` holds what is happening between the couple right now, and `us` is the
/// couple's page: both partners, their relationship, and the settings. Countdown is
/// intentionally not a tab — for MVP it is a derived value (anniversary/monthly
/// milestone) that lives on Home, not a feature with its own surface.
///
/// Tab selection is owned by `RootViewModel` so that navigation intent — such as
/// opening the widget drawing screen from the Home Screen widget — can select the
/// correct tab and present its destination as a single, atomic state change.
enum MainTab: String, CaseIterable, Identifiable {
    case home
    case questions
    case games
    case memories
    case us

    var id: String { rawValue }

    var title: LocalizedStringResource {
        switch self {
        case .home: .mainTabHome
        case .questions: .mainTabQuestions
        case .games: .mainTabGames
        case .memories: .mainTabMemories
        case .us: .mainTabUs
        }
    }

    var systemImage: String {
        switch self {
        case .home: "house.fill"
        case .questions: "bubble.left.and.bubble.right.fill"
        case .games: "gamecontroller.fill"
        case .memories: "memories"
        case .us: "heart.fill"
        }
    }
}
