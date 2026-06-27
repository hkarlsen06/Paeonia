import Foundation

extension LocationMapViewModel.Notice {
    var title: LocalizedStringResource {
        switch self {
        case .saveFailed:
            .settingsLocationSaveErrorTitle
        case .permissionDenied:
            .settingsLocationPermissionDeniedTitle
        case .locationUnavailable:
            .settingsLocationUnavailableTitle
        }
    }

    var message: LocalizedStringResource {
        switch self {
        case .saveFailed:
            .settingsLocationSaveErrorMessage
        case .permissionDenied:
            .settingsLocationPermissionDeniedMessage
        case .locationUnavailable:
            .settingsLocationUnavailableMessage
        }
    }
}
