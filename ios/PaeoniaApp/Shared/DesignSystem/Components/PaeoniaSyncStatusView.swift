import SwiftUI

enum PaeoniaSyncStatus: Equatable {
    case savedLocally
    case syncing
    case synced
    case failed
    case offline

    var title: LocalizedStringResource {
        switch self {
        case .savedLocally:
            .syncStatusSavedLocally
        case .syncing:
            .syncStatusSyncing
        case .synced:
            .syncStatusSynced
        case .failed:
            .syncStatusFailed
        case .offline:
            .syncStatusOffline
        }
    }

    var systemImage: String {
        switch self {
        case .savedLocally:
            "checkmark.circle"
        case .syncing:
            "arrow.triangle.2.circlepath"
        case .synced:
            "checkmark.icloud"
        case .failed:
            "exclamationmark.triangle"
        case .offline:
            "wifi.slash"
        }
    }

    var tint: Color {
        switch self {
        case .savedLocally, .synced:
            .paeoniaSuccess
        case .syncing:
            .paeoniaSyncPending
        case .failed:
            .paeoniaSyncError
        case .offline:
            .paeoniaTextTertiary
        }
    }
}

struct PaeoniaSyncStatusView: View {
    let status: PaeoniaSyncStatus

    var body: some View {
        Label {
            Text(status.title)
                .font(PaeoniaTypography.caption)
                .foregroundStyle(.paeoniaTextSecondary)
        } icon: {
            Image(systemName: status.systemImage)
                .foregroundStyle(status.tint)
                .accessibilityHidden(true)
        }
        .labelStyle(.titleAndIcon)
    }
}
