#if WIDGET_EXTENSION
import Foundation

/// Deep links the Lock Screen widgets open. They match `PaeoniaDeepLink` in the
/// app. A widget with no link opens the app on its last screen.
enum LockScreenURL {
    static let streak = URL(string: "paeonia://streak")
    static let dailyQuestion = URL(string: "paeonia://daily/today")

    /// `gamePath` is the path `LockScreenYourMove` returns, such as `draw-and-guess`.
    static func game(path: String?) -> URL? {
        path.flatMap { URL(string: "paeonia://games/\($0)") }
    }
}
#endif
