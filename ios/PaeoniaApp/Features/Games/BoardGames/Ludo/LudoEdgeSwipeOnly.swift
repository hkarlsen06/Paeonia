import SwiftUI
import UIKit

/// Turns off the full-width back swipe while the Ludo board is open, so a drag
/// that throws the die never leaves the screen. The swipe from the left edge
/// still goes back. The full-width swipe comes back when the screen closes.
struct LudoEdgeSwipeOnly: UIViewRepresentable {
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
                  let navigationController = view.ludoNavigationController(),
                  let contentPop = navigationController.interactiveContentPopGestureRecognizer
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
    func ludoNavigationController() -> UINavigationController? {
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
