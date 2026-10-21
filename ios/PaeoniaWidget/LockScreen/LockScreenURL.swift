#if WIDGET_EXTENSION
import Foundation

/// Deep links the Lock Screen and Home Screen widgets open. They match
/// `PaeoniaDeepLink` in the app. A widget with no link opens the app on its last screen.
enum LockScreenURL {
    static let streak = URL(string: "paeonia://streak")
    static let dailyQuestion = URL(string: "paeonia://daily/today")
    /// The dates screen: days together, milestones, countdowns and birthdays.
    static let dates = URL(string: "paeonia://dates")

    /// `gamePath` is the path `LockScreenYourMove` returns, such as `draw-and-guess`.
    static func game(path: String?) -> URL? {
        path.flatMap { URL(string: "paeonia://games/\($0)") }
    }
}
#endif
