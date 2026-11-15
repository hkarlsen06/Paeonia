import UIKit

/// The app's own window and what is presented over its screens.
@MainActor
enum PaeoniaAppWindow {
    /// The app's window is the one at the normal level. The call overlay and the app lock's cover
    /// sit above it, and either may be the key window.
    static var rootViewController: UIViewController? {
        UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.windows.first { $0.windowLevel == .normal }?.rootViewController }
            .first
    }

    /// The sheets, covers and alerts over the app's screens, the lowest first.
    static var presentedControllers: some Sequence<UIViewController> {
        sequence(state: rootViewController) { controller in
            controller = controller?.presentedViewController
            return controller
        }
    }

    /// A sheet, cover or alert is over the app's screens.
    static var isCovered: Bool {
        rootViewController?.presentedViewController != nil
    }
}
