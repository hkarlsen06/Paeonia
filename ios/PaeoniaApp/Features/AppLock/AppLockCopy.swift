import Foundation

extension AppLockBiometry {
    /// How the phone's own unlock is named in the labels. Face ID, Touch ID and
    /// Optic ID are Apple's names. A phone without any of them says passcode.
    var name: String {
        switch self {
        case .faceID: String(localized: .appLockBiometryFaceId)
        case .touchID: String(localized: .appLockBiometryTouchId)
        case .opticID: String(localized: .appLockBiometryOpticId)
        case .passcode: String(localized: .appLockBiometryPasscode)
        }
    }

    var systemImage: String {
        switch self {
        case .faceID: "faceid"
        case .touchID: "touchid"
        case .opticID: "opticid"
        case .passcode: "lock.fill"
        }
    }
}

extension AppLockTimeout {
    var title: LocalizedStringResource {
        switch self {
        case .immediately: .appLockTimeoutImmediately
        case .afterOneMinute: .appLockTimeoutOneMinute
        case .afterFifteenMinutes: .appLockTimeoutFifteenMinutes
        }
    }
}

extension AppLockModel.Notice {
    var title: LocalizedStringResource {
        switch self {
        case .turnedOffNoPasscode: .appLockTurnedOffTitle
        }
    }

    var message: LocalizedStringResource {
        switch self {
        case .turnedOffNoPasscode: .appLockTurnedOffMessage
        }
    }
}
