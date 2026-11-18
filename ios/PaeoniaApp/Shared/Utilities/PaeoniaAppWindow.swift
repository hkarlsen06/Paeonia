import UIKit

/// The app's own window and what is presented over its screens.
@MainActor
enum PaeoniaAppWindow {
    /// The app's window is the one at the normal level. The call overlay and the app lock's cover
    /// sit above it, and either may be the key window.
    static var window: UIWindow? {
        UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.windows.first { $0.windowLevel == .normal } }
            .first
    }

    static var rootViewController: UIViewController? {
        window?.rootViewController
    }

    /// The app's screens as they are on screen now within `frame`, in window coordinates, or nil
    /// when the window could not be drawn whole.
    static func snapshot(of frame: CGRect) -> UIImage? {
        guard frame.width > 0, frame.height > 0, let window else { return nil }
        var drewWhole = false
        let image = UIGraphicsImageRenderer(bounds: frame).image { _ in
            drewWhole = window.drawHierarchy(in: window.bounds, afterScreenUpdates: false)
        }
        return drewWhole ? image : nil
    }

    /// The radius of the window's corners: the screen's own on an iPhone, and the window's on an
    /// iPad. A view that fills the window with container-concentric corners reports it.
    static var cornerRadius: CGFloat {
        guard let window else { return 0 }
        let probe = UIView(frame: window.bounds)
        probe.cornerConfiguration = .corners(radius: .containerConcentric())
        window.addSubview(probe)
        defer { probe.removeFromSuperview() }
        probe.layoutIfNeeded()
        return probe.effectiveRadius(corner: .topLeft)
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
