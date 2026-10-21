import SwiftUI
import UIKit

/// Turns the system's full-width back swipe on for the chat, but lets a reply swipe on
/// a partner bubble win when both move right. A swipe right on the empty table also
/// goes back.
struct ThreadChatNavigationGestureBridge: UIViewRepresentable {
    let onNavigateBack: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onNavigateBack: onNavigateBack)
    }

    func makeUIView(context _: Context) -> UIView {
        let view = UIView(frame: .zero)
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.onNavigateBack = onNavigateBack
        DispatchQueue.main.async {
            context.coordinator.configure(from: uiView)
        }
    }

    static func dismantleUIView(_: UIView, coordinator: Coordinator) {
        coordinator.restore()
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var onNavigateBack: () -> Void
        private weak var contentPopGestureRecognizer: UIGestureRecognizer?
        private weak var originalDelegate: UIGestureRecognizerDelegate?
        private weak var navigationView: UIView?
        private var backgroundBackPanGestureRecognizer: UIPanGestureRecognizer?

        init(onNavigateBack: @escaping () -> Void) {
            self.onNavigateBack = onNavigateBack
        }

        func configure(from view: UIView) {
            guard let navigationController = view.threadChatNavigationController() else { return }
            guard let recognizer = navigationController.interactiveContentPopGestureRecognizer else {
                installBackgroundBackRecognizerIfNeeded(on: navigationController.view)
                return
            }
            guard contentPopGestureRecognizer !== recognizer else { return }

            restore()
            originalDelegate = recognizer.delegate
            recognizer.delegate = self
            recognizer.isEnabled = true
            contentPopGestureRecognizer = recognizer
            installBackgroundBackRecognizerIfNeeded(on: navigationController.view)
        }

        func restore() {
            if let backgroundBackPanGestureRecognizer, let navigationView {
                navigationView.removeGestureRecognizer(backgroundBackPanGestureRecognizer)
            }
            backgroundBackPanGestureRecognizer = nil
            navigationView = nil

            guard let recognizer = contentPopGestureRecognizer else { return }
            if recognizer.delegate === self {
                recognizer.delegate = originalDelegate
            }
            contentPopGestureRecognizer = nil
            originalDelegate = nil
        }

        private func installBackgroundBackRecognizerIfNeeded(on view: UIView) {
            guard navigationView !== view else { return }
            if let backgroundBackPanGestureRecognizer, let navigationView {
                navigationView.removeGestureRecognizer(backgroundBackPanGestureRecognizer)
            }
            let recognizer = backgroundBackPanGestureRecognizer ?? UIPanGestureRecognizer(
                target: self,
                action: #selector(handleBackgroundBackPan(_:))
            )
            recognizer.cancelsTouchesInView = false
            recognizer.delaysTouchesBegan = false
            recognizer.delaysTouchesEnded = false
            recognizer.delegate = self
            view.addGestureRecognizer(recognizer)
            backgroundBackPanGestureRecognizer = recognizer
            navigationView = view
        }

        @objc private func handleBackgroundBackPan(_ recognizer: UIPanGestureRecognizer) {
            guard recognizer.state == .ended else { return }
            let translation = recognizer.translation(in: recognizer.view)
            let velocity = recognizer.velocity(in: recognizer.view)
            guard ThreadChatPanGestureResolver.shouldTriggerNavigationBack(
                translation: CGSize(width: translation.x, height: translation.y),
                velocity: CGSize(width: velocity.x, height: velocity.y)
            ) else { return }
            onNavigateBack()
        }

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            if gestureRecognizer === backgroundBackPanGestureRecognizer {
                guard let recognizer = gestureRecognizer as? UIPanGestureRecognizer else { return true }
                guard movesRight(recognizer) else { return false }
                return startsInChatTableBackground(gestureRecognizer)
            }

            guard gestureRecognizer === contentPopGestureRecognizer else {
                return originalDelegate?.gestureRecognizerShouldBegin?(gestureRecognizer) ?? true
            }
            if originalDelegate?.gestureRecognizerShouldBegin?(gestureRecognizer) == false {
                return false
            }
            if let recognizer = gestureRecognizer as? UIPanGestureRecognizer, !movesRight(recognizer) {
                return false
            }
            return !startsInNavigationBackExcludedTarget(gestureRecognizer)
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            if isBackNavigationRecognizer(gestureRecognizer, competingWith: otherGestureRecognizer) {
                return false
            }
            if gestureRecognizer === backgroundBackPanGestureRecognizer
                || otherGestureRecognizer === backgroundBackPanGestureRecognizer {
                return true
            }
            guard gestureRecognizer === contentPopGestureRecognizer else {
                return originalDelegate?.gestureRecognizer?(
                    gestureRecognizer,
                    shouldRecognizeSimultaneouslyWith: otherGestureRecognizer
                ) ?? true
            }
            return true
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRequireFailureOf otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            if isBackNavigationRecognizer(gestureRecognizer, competingWith: otherGestureRecognizer) {
                return true
            }
            guard gestureRecognizer === contentPopGestureRecognizer else {
                return originalDelegate?.gestureRecognizer?(
                    gestureRecognizer,
                    shouldRequireFailureOf: otherGestureRecognizer
                ) ?? false
            }
            return false
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldBeRequiredToFailBy otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            if isRightReplyGesture(gestureRecognizer),
               otherGestureRecognizer === contentPopGestureRecognizer
               || otherGestureRecognizer === backgroundBackPanGestureRecognizer {
                return false
            }
            guard gestureRecognizer === contentPopGestureRecognizer else {
                return originalDelegate?.gestureRecognizer?(
                    gestureRecognizer,
                    shouldBeRequiredToFailBy: otherGestureRecognizer
                ) ?? false
            }
            return false
        }

        private func movesRight(_ recognizer: UIPanGestureRecognizer) -> Bool {
            let velocity = recognizer.velocity(in: recognizer.view)
            return ThreadChatPanGestureResolver.hasDirectionalHorizontalIntent(
                velocity: CGSize(width: velocity.x, height: velocity.y),
                direction: .right
            )
        }

        private func isBackNavigationRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            competingWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            (gestureRecognizer === contentPopGestureRecognizer
                || gestureRecognizer === backgroundBackPanGestureRecognizer)
                && isRightReplyGesture(otherGestureRecognizer)
        }

        private func isRightReplyGesture(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard let recognizer = gestureRecognizer as? ThreadChatDirectionalPanRecognizer,
                  case .replyPayload(direction: .right) = recognizer.targetKind
            else { return false }
            return recognizer.direction == .right
        }

        private func startsInChatTableBackground(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard let rootView = gestureRecognizer.view else { return false }
            let location = gestureRecognizer.location(in: rootView)
            guard let tableView = rootView.threadChatTableView(at: location) else { return false }
            guard tableView.bounds.contains(gestureRecognizer.location(in: tableView)) else { return false }
            return !isNavigationBackExcludedTarget(rootView.threadChatGestureTargetKind(at: location))
        }

        private func startsInNavigationBackExcludedTarget(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard let rootView = gestureRecognizer.view else { return false }
            let location = gestureRecognizer.location(in: rootView)
            return isNavigationBackExcludedTarget(rootView.threadChatGestureTargetKind(at: location))
        }

        private func isNavigationBackExcludedTarget(_ targetKind: ThreadChatGestureTargetKind?) -> Bool {
            if case .replyPayload(direction: .right) = targetKind { return true }
            return false
        }
    }
}

/// A swipe left on the chat table where no row is, for example between two days. The
/// rows have their own surfaces for the same gesture.
struct ThreadChatTimestampRevealGestureBridge: UIViewRepresentable {
    let isEnabled: Bool
    let onChanged: (ThreadChatDragValue) -> Void
    let onEnded: (ThreadChatDragValue) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onChanged: onChanged, onEnded: onEnded)
    }

    func makeUIView(context _: Context) -> UIView {
        let view = UIView(frame: .zero)
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.isEnabled = isEnabled
        context.coordinator.onChanged = onChanged
        context.coordinator.onEnded = onEnded
        DispatchQueue.main.async {
            context.coordinator.configure(from: uiView)
        }
    }

    static func dismantleUIView(_: UIView, coordinator: Coordinator) {
        coordinator.restore()
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var isEnabled = true
        var onChanged: (ThreadChatDragValue) -> Void
        var onEnded: (ThreadChatDragValue) -> Void
        private weak var tableView: UITableView?
        private var recognizer: UIPanGestureRecognizer?
        private var hasPassedMinimumDistance = false

        init(
            onChanged: @escaping (ThreadChatDragValue) -> Void,
            onEnded: @escaping (ThreadChatDragValue) -> Void
        ) {
            self.onChanged = onChanged
            self.onEnded = onEnded
        }

        func configure(from view: UIView) {
            guard isEnabled else {
                restore()
                return
            }
            guard let tableView = view.threadChatListTableView(), tableView !== self.tableView else { return }
            restore()
            let recognizer = ThreadChatDirectionalPanRecognizer(target: self, action: #selector(handlePan(_:)))
            recognizer.targetKind = .timestampRevealGutter
            recognizer.direction = .left
            recognizer.cancelsTouchesInView = false
            recognizer.delaysTouchesBegan = false
            recognizer.delaysTouchesEnded = false
            recognizer.delegate = self
            tableView.addGestureRecognizer(recognizer)
            self.tableView = tableView
            self.recognizer = recognizer
        }

        func restore() {
            if let recognizer, let tableView {
                tableView.removeGestureRecognizer(recognizer)
            }
            recognizer = nil
            tableView = nil
            hasPassedMinimumDistance = false
        }

        @objc private func handlePan(_ recognizer: UIPanGestureRecognizer) {
            guard let tableView else { return }
            let value = ThreadChatDragValue(recognizer: recognizer, in: tableView)
            switch recognizer.state {
            case .began:
                hasPassedMinimumDistance = false
                handleChangedIfReady(value)
            case .changed:
                handleChangedIfReady(value)
            case .ended:
                handleChangedIfReady(value)
                finish(value)
            case .possible:
                break
            default:
                finish(value)
            }
        }

        private func finish(_ value: ThreadChatDragValue) {
            if hasPassedMinimumDistance { onEnded(value) }
            hasPassedMinimumDistance = false
        }

        private func handleChangedIfReady(_ value: ThreadChatDragValue) {
            if !hasPassedMinimumDistance {
                guard ThreadChatPanGestureResolver.hasPassedMinimumDistance(
                    translation: value.translation,
                    minimumDistance: ThreadChatTimestampRevealResolver.minimumDistance
                ) else { return }
                hasPassedMinimumDistance = true
            }
            onChanged(value)
        }

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard isEnabled, let recognizer = gestureRecognizer as? UIPanGestureRecognizer, let tableView else {
                return false
            }
            let location = recognizer.location(in: tableView)
            guard tableView.bounds.contains(location), tableView.indexPathForRow(at: location) == nil else {
                return false
            }
            let velocity = recognizer.velocity(in: tableView.window ?? tableView)
            return ThreadChatPanGestureResolver.hasDirectionalHorizontalIntent(
                velocity: CGSize(width: velocity.x, height: velocity.y),
                direction: .left
            )
        }

        func gestureRecognizer(
            _: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith _: UIGestureRecognizer
        ) -> Bool {
            true
        }
    }
}

extension UIView {
    fileprivate func threadChatNavigationController() -> UINavigationController? {
        sequence(first: self as UIResponder?, next: { $0?.next })
            .first { $0 is UINavigationController } as? UINavigationController
    }

    fileprivate func threadChatGestureTargetKind(at point: CGPoint) -> ThreadChatGestureTargetKind? {
        for subview in subviews.reversed() {
            guard !subview.isHidden, subview.alpha > 0.01 else { continue }
            let convertedPoint = subview.convert(point, from: self)
            if let targetView = subview as? ThreadChatGestureTargetView, targetView.bounds.contains(convertedPoint) {
                return targetView.kind
            }
            if subview.bounds.contains(convertedPoint) || !subview.clipsToBounds,
               let kind = subview.threadChatGestureTargetKind(at: convertedPoint) {
                return kind
            }
        }
        return nil
    }

    fileprivate func threadChatTableView(at point: CGPoint) -> UITableView? {
        for subview in subviews.reversed() {
            guard !subview.isHidden, subview.alpha > 0.01 else { continue }
            let convertedPoint = subview.convert(point, from: self)
            if let tableView = subview as? UITableView, tableView.bounds.contains(convertedPoint) {
                return tableView
            }
            if subview.bounds.contains(convertedPoint) || !subview.clipsToBounds,
               let tableView = subview.threadChatTableView(at: convertedPoint) {
                return tableView
            }
        }
        return nil
    }

    /// ExyteChat's message table, found by its delegate's type.
    fileprivate func threadChatListTableView() -> UITableView? {
        var root: UIView = self
        while let superview = root.superview { root = superview }
        let searchRoot = window ?? root
        let tableViews = searchRoot.threadChatDescendantTableViews()
        return tableViews.first { candidate in
            guard let delegate = candidate.delegate else { return false }
            return String(reflecting: type(of: delegate)).contains("UIList")
        } ?? tableViews.first
    }

    private func threadChatDescendantTableViews() -> [UITableView] {
        subviews.flatMap { subview -> [UITableView] in
            let nested = subview.threadChatDescendantTableViews()
            if let tableView = subview as? UITableView { return [tableView] + nested }
            return nested
        }
    }
}
