import SwiftUI
import UIKit

/// Puts `AppLockCoverView` in its own window above everything the app shows,
/// including sheets and full-screen covers, which an overlay inside the root
/// view could not hide. It also turns the scene's lifecycle notifications into
/// calls on `AppLockModel`. The notifications arrive synchronously, so the
/// cover is up before the system takes the app switcher's snapshot.
@MainActor
final class AppLockCoverController {
    private let model: AppLockModel
    private var window: UIWindow?
    private var observers: [any NSObjectProtocol] = []
    private var isInstalled = false

    private static let fadeDuration: TimeInterval = 0.25

    init(model: AppLockModel) {
        self.model = model
    }

    /// Safe to call more than once. Call it once the first scene exists.
    func install() {
        guard !isInstalled else { return }
        isInstalled = true

        model.onCoverChange = { [weak self] isCovering in
            self?.setCovering(isCovering)
        }
        observe(UIScene.willDeactivateNotification) { $0.sceneWillResignActive() }
        observe(UIScene.didEnterBackgroundNotification) { $0.sceneDidEnterBackground() }
        observe(UIScene.didActivateNotification) { $0.sceneDidBecomeActive() }

        // The window exists before the first lock, so showing it costs no setup.
        prepareWindow()
        setCovering(model.isCovering)
        // A cold launch can be active already by the time the root appears.
        if windowScene?.activationState == .foregroundActive {
            model.sceneDidBecomeActive()
        }
    }

    private func observe(_ name: Notification.Name, _ handler: @escaping @MainActor (AppLockModel) -> Void) {
        let model = model
        let token = NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { handler(model) }
        }
        observers.append(token)
    }

    private var windowScene: UIWindowScene? {
        UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
    }

    @discardableResult
    private func prepareWindow() -> UIWindow? {
        if let window {
            return window
        }
        guard let scene = windowScene else {
            return nil
        }

        let host = UIHostingController(rootView: AppLockCoverView(model: model))
        host.overrideUserInterfaceStyle = .dark
        host.view.backgroundColor = .clear
        // VoiceOver stays on the cover and never reads the screen underneath.
        host.view.accessibilityViewIsModal = true
        host.loadViewIfNeeded()

        let window = UIWindow(windowScene: scene)
        window.windowLevel = .alert + 1
        window.backgroundColor = .clear
        window.rootViewController = host
        window.isHidden = true
        self.window = window
        return window
    }

    private func setCovering(_ isCovering: Bool) {
        guard let window = prepareWindow() else { return }
        window.layer.removeAllAnimations()

        if isCovering {
            // The keyboard sits above every window, so close it before locking.
            UIApplication.shared.sendAction(
                #selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil
            )
            window.alpha = 1
            window.isHidden = false
            return
        }

        guard !window.isHidden else { return }
        guard !UIAccessibility.isReduceMotionEnabled else {
            window.isHidden = true
            return
        }
        UIView.animate(withDuration: Self.fadeDuration) {
            window.alpha = 0
        } completion: { [weak self] _ in
            guard let self, !model.isCovering else { return }
            window.isHidden = true
        }
    }
}
