import Foundation
import UIKit

/// The phone's heat, Low Power Mode and battery, which decide how much video a call sends
/// (`CallHeat`) and whether the call screen offers to turn the camera off.
nonisolated struct CallPowerState: Equatable, Sendable {
    /// Where iOS warns that the battery is low and offers Low Power Mode.
    static let lowBattery: Float = 0.2

    var thermalState: ProcessInfo.ThermalState
    var isLowPowerMode: Bool
    /// From 0 to 1, or nil when iOS does not know, such as on the simulator.
    var batteryLevel: Float?
    /// Plugged in, charging or full.
    var isPluggedIn: Bool

    var heat: CallHeat {
        CallHeat(thermalState, isLowPowerMode: isLowPowerMode)
    }

    /// Why to offer turning the camera off, or nil. Heat comes first, because a phone at
    /// `critical` slows down and may stop the camera itself. A reason the person dismissed stays
    /// away for the rest of the call.
    func cameraOffSuggestion(
        isCameraOn: Bool,
        dismissed: Set<CallCameraOffSuggestion>
    ) -> CallCameraOffSuggestion? {
        guard isCameraOn else { return nil }
        if heat == .hot, !dismissed.contains(.hot) {
            return .hot
        }
        if let batteryLevel, batteryLevel <= Self.lowBattery, !isPluggedIn, !dismissed.contains(.lowBattery) {
            return .lowBattery
        }
        return nil
    }
}

/// Watches the phone's heat, Low Power Mode and battery during one call.
final class CallDevicePower {
    private(set) var state: CallPowerState
    private var observers: [any NSObjectProtocol] = []

    /// `onChange` runs on the main thread with each new state.
    init(onChange: @escaping @MainActor (CallPowerState) -> Void) {
        UIDevice.current.isBatteryMonitoringEnabled = true
        state = Self.read()
        observers = [
            ProcessInfo.thermalStateDidChangeNotification,
            Notification.Name.NSProcessInfoPowerStateDidChange,
            UIDevice.batteryLevelDidChangeNotification,
            UIDevice.batteryStateDidChangeNotification,
        ].map { name in
            NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    let state = Self.read()
                    guard state != self.state else { return }
                    self.state = state
                    onChange(state)
                }
            }
        }
    }

    func stop() {
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
        }
        observers = []
        UIDevice.current.isBatteryMonitoringEnabled = false
    }

    private static func read() -> CallPowerState {
        let device = UIDevice.current
        let info = ProcessInfo.processInfo
        return CallPowerState(
            thermalState: info.thermalState,
            isLowPowerMode: info.isLowPowerModeEnabled,
            batteryLevel: device.batteryLevel < 0 ? nil : device.batteryLevel,
            isPluggedIn: device.batteryState == .charging || device.batteryState == .full
        )
    }
}
