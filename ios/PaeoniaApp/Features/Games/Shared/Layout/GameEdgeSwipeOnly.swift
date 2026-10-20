import SwiftUI
import UIKit

/// Turns off the full-width back swipe while a game screen is open, so a drag on
/// the board, such as throwing Ludo's die or panning Guess my spot's map, never
/// leaves the screen. The swipe from the left edge still goes back. The
/// full-width swipe comes back when the screen closes.
struct GameEdgeSwipeOnly: UIViewRepresentable {
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context _: Context) -> UIView {
        let view = UIView(frame: .zero)
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        // The navigation controller is found once the view is in a window.
        DispatchQueue.main.async {
            context.coordinator.disableContentPop(from: uiView)
        }
    }

    static func dismantleUIView(_: UIView, coordinator: Coordinator) {
        coordinator.restore()
    }

    @MainActor
    final class Coordinator {
        private weak var recognizer: UIGestureRecognizer?

        func disableContentPop(from view: UIView) {
            guard recognizer == nil,
                  let navigationController = view.gameNavigationController(),
                  let contentPop = navigationController.interactiveContentPopGestureRecognizer,
                  // A screen pushed over another game screen leaves the swipe to that one,
                  // so going back to it doesn't turn the swipe on.
                  contentPop.isEnabled
            else { return }
            contentPop.isEnabled = false
            recognizer = contentPop
        }

        func restore() {
            recognizer?.isEnabled = true
            recognizer = nil
        }
    }
}

private extension UIView {
    func gameNavigationController() -> UINavigationController? {
        var responder: UIResponder? = self
        while let current = responder {
            if let controller = current as? UIViewController, let navigation = controller.navigationController {
                return navigation
            }
            responder = current.next
        }
        return nil
    }
}
