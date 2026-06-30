import Foundation

/// The high-level destinations shown in the paired tab bar.
///
/// The first and last tabs use relationship-aware names: `home` is the shared
/// couple space ("Us") and `you` is the personal corner ("You"). Countdown is
/// intentionally not a tab — for MVP it is a derived value (anniversary/monthly
/// milestone) that lives on Home, not a feature with its own surface.
///
/// Tab selection is owned by `RootViewModel` so that navigation intent — such as
/// opening the widget drawing screen from the Home Screen widget — can select the
/// correct tab and present its destination as a single, atomic state change.
enum MainTab: String, CaseIterable, Identifiable {
    case home
    case questions
    case memories
    case you

    var id: String { rawValue }

    func tab(offsetBy offset: Int) -> MainTab? {
        guard let currentIndex = Self.allCases.firstIndex(of: self) else { return nil }

        let destinationIndex = currentIndex + offset
        guard Self.allCases.indices.contains(destinationIndex) else { return nil }

        return Self.allCases[destinationIndex]
    }

    var title: LocalizedStringResource {
        switch self {
        case .home: .mainTabHomeUs
        case .questions: .mainTabQuestions
        case .memories: .mainTabMemories
        case .you: .mainTabYou
        }
    }

    var systemImage: String {
        switch self {
        case .home: "heart.fill"
        case .questions: "bubble.left.and.bubble.right.fill"
        case .memories: "memories"
        case .you: "person.crop.circle"
        }
    }
}
