import UIKit

/// Tells whether the person stayed in the app across a stretch of work. iOS pauses the app in
/// the background while clocks keep running, so work that times itself needs to know.
@MainActor
enum AppForeground {
    private static var leaves = 0
    private static var observer: (any NSObjectProtocol)?

    /// A number that changes each time the app leaves the front, or nil while it is not in
    /// front. Two equal readings mean the app stayed in front between them.
    static func stint() -> Int? {
        if observer == nil {
            observer = NotificationCenter.default.addObserver(
                forName: UIApplication.willResignActiveNotification, object: nil, queue: .main
            ) { _ in
                MainActor.assumeIsolated { leaves += 1 }
            }
        }
        return UIApplication.shared.applicationState == .active ? leaves : nil
    }
}
