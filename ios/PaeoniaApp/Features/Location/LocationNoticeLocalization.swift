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

    /// Takes the partner's name so the permission-denied notice names the partner
    /// ("…share it with Oda."); other notices ignore it.
    func message(partnerName: String) -> LocalizedStringResource {
        switch self {
        case .saveFailed:
            .settingsLocationSaveErrorMessage
        case .permissionDenied:
            .settingsLocationPermissionDeniedMessage(partnerName)
        case .locationUnavailable:
            .settingsLocationUnavailableMessage
        }
    }
}
