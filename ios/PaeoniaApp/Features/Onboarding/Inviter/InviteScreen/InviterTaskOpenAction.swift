import SwiftUI

extension EnvironmentValues {
    /// Told true when the invite screen's first questions open, and false when they
    /// close. The root keeps the invite screen up while they are open, so a partner who
    /// joins meanwhile doesn't pull the person out of them.
    @Entry var inviterTaskOpenChanged = InviterTaskOpenAction { _ in }
}

/// Wraps the closure so the environment can compare it. The root sets it once, so every
/// copy counts as equal and a new closure on each root update doesn't redraw the screen.
struct InviterTaskOpenAction: Equatable {
    let action: (Bool) -> Void

    func callAsFunction(_ isOpen: Bool) {
        action(isOpen)
    }

    static func == (lhs: Self, rhs: Self) -> Bool { true }
}
