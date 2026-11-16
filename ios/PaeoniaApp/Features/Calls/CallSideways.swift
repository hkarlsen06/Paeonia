import Observation
import SwiftUI
import UIKit

/// How far the phone is turned from the way the screen is drawn, in quarter turns. The app stays
/// upright on an iPhone, so a phone held on its side is a quarter turn from it. An iPad turns its
/// screen itself, so it stays at none.
nonisolated enum CallTurn: Int, Equatable, Sendable {
    /// The top of the phone to the left. Pictures turn clockwise to stand upright.
    case left = 1
    case none = 0
    /// The top of the phone to the right. Pictures turn counterclockwise.
    case right = -1

    var angle: Angle {
        .degrees(Double(rawValue) * 90)
    }

    var isSideways: Bool {
        self != .none
    }

    /// Where `point`, given from the middle of what the person sees, shows on the screen, measured
    /// from the screen's middle.
    func onScreen(_ point: CGPoint) -> CGPoint {
        switch self {
        case .none: point
        case .left: CGPoint(x: -point.y, y: point.x)
        case .right: CGPoint(x: point.y, y: -point.x)
        }
    }

    /// The other way round from `onScreen(_:)`.
    func asSeen(_ point: CGPoint) -> CGPoint {
        switch self {
        case .none: point
        case .left: CGPoint(x: point.y, y: -point.x)
        case .right: CGPoint(x: -point.y, y: point.x)
        }
    }

    /// The screen's margins, as the person sees them with the phone turned.
    func asSeen(_ insets: EdgeInsets) -> EdgeInsets {
        switch self {
        case .none: insets
        case .left:
            EdgeInsets(top: insets.trailing, leading: insets.top, bottom: insets.leading, trailing: insets.bottom)
        case .right:
            EdgeInsets(top: insets.leading, leading: insets.bottom, bottom: insets.trailing, trailing: insets.top)
        }
    }

    /// The screen's size, as the person sees it.
    func asSeen(_ size: CGSize) -> CGSize {
        isSideways ? CGSize(width: size.height, height: size.width) : size
    }
}

/// Follows how the person holds the phone, like the Camera app does while the screen stays upright.
/// Face up and face down keep the last turn. iOS stops reporting turns while Portrait Orientation
/// Lock is on, so the call then stays upright, which is what the person asked for.
@MainActor
@Observable
final class CallDeviceTurn {
    private(set) var turn = CallTurn.none
    @ObservationIgnored private var observer: NSObjectProtocol?

    func start() {
        guard observer == nil else { return }
        UIDevice.current.beginGeneratingDeviceOrientationNotifications()
        observer = NotificationCenter.default.addObserver(
            forName: UIDevice.orientationDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.update() }
        }
        update()
    }

    func stop() {
        guard let observer else { return }
        NotificationCenter.default.removeObserver(observer)
        self.observer = nil
        UIDevice.current.endGeneratingDeviceOrientationNotifications()
        turn = .none
    }

    private func update() {
        let device: CallTurn
        switch UIDevice.current.orientation {
        case .portrait: device = .none
        case .landscapeLeft: device = .left
        case .landscapeRight: device = .right
        // Upside down, face up and face down keep the last turn.
        default: return
        }
        // An iPad turns its own screen, so only the difference to it counts.
        let screen: CallTurn = switch Self.interfaceOrientation {
        case .landscapeLeft: .right
        case .landscapeRight: .left
        default: .none
        }
        let next = CallTurn(rawValue: max(-1, min(1, device.rawValue - screen.rawValue))) ?? .none
        guard next != turn else { return }
        turn = next
    }

    private static var interfaceOrientation: UIInterfaceOrientation {
        UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first?
            .effectiveGeometry.interfaceOrientation ?? .portrait
    }
}

extension EnvironmentValues {
    /// Pins how the phone is held, for a developer scenario's screenshot.
    @Entry var callTurnOverride: CallTurn?
    /// How the person holds the phone during a video call on the full call screen.
    @Entry var callTurn = CallTurn.none
}

extension View {
    /// Turns this control's symbol or short text to stand upright the way the phone is held.
    func callTurned() -> some View {
        modifier(CallTurnedModifier())
    }
}

private struct CallTurnedModifier: ViewModifier {
    @Environment(\.callTurn) private var turn
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .rotationEffect(turn.angle)
            .animation(reduceMotion ? nil : PaeoniaMotion.stateChange, value: turn)
    }
}
