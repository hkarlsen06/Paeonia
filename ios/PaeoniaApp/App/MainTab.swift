import Foundation

/// The high-level destinations shown in the paired tab bar.
///
/// `us` holds what is happening between the couple right now. Its screen is
/// `PairedHomeView`, the screen the app opens on. `settings` shows "More" under a
/// gear: the couple at the top, then the settings. Countdown is intentionally not a tab — for MVP it is a
/// derived value (anniversary/monthly milestone) that lives on Us, not a feature
/// with its own surface.
///
/// Tab selection is owned by `RootViewModel` so that navigation intent — such as
/// opening the widget drawing screen from the Home Screen widget — can select the
/// correct tab and present its destination as a single, atomic state change.
enum MainTab: String, CaseIterable, Identifiable {
    case us
    case questions
    case games
    case memories
    case settings

    var id: String { rawValue }

    var title: LocalizedStringResource {
        switch self {
        case .us: .mainTabUs
        case .questions: .mainTabQuestions
        case .games: .mainTabGames
        case .memories: .mainTabMemories
        case .settings: .mainTabSettings
        }
    }

    var systemImage: String {
        switch self {
        case .us: "heart.fill"
        case .questions: "bubble.left.and.bubble.right.fill"
        case .games: "gamecontroller.fill"
        case .memories: "memories"
        case .settings: "gearshape.fill"
        }
    }
}
