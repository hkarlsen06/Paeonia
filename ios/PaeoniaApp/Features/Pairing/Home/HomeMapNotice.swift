import SwiftUI

/// Why Home has no map, in the map card's words, and the one thing to do about it.
struct HomeMapNotice {
    /// Which situation this is, so a "Not now" covers only this one.
    var id = ""
    let title: LocalizedStringResource
    let message: LocalizedStringResource
    let systemImage: String
    var actionTitle: LocalizedStringResource?
    var actionSystemImage: String?
    var action: Action?
    var showsProgress = false

    enum Action {
        case promptCurrentLocation(() -> Void)
        case openSettings
    }

    /// Nil while the map loads, so nothing flashes before it arrives.
    init?(state: CoupleMapState, partnerName: String, onPromptCurrentLocation: @escaping () -> Void) {
        self.init(matching: state, partnerName: partnerName, onPromptCurrentLocation: onPromptCurrentLocation)
        id = Self.id(for: state)
    }

    private static func id(for state: CoupleMapState) -> String {
        switch state {
        case .loading: "loading"
        case .currentUnknown: "currentUnknown"
        case .locatingCurrent: "locatingCurrent"
        case .currentLocationMissing: "currentLocationMissing"
        case .sharingPaused: "sharingPaused"
        case .locationAccessOff: "locationAccessOff"
        case .waitingForPartnerLocation: "waitingForPartnerLocation"
        case let .partnerUnknown(reason): "partnerUnknown.\(reason)"
        case .ready: "ready"
        }
    }

    private init?(matching state: CoupleMapState, partnerName: String, onPromptCurrentLocation: @escaping () -> Void) {
        switch state {
        case .loading, .ready:
            return nil
        case .currentUnknown:
            self.init(
                title: .homeMapCurrentUnknownTitle,
                message: .homeMapCurrentUnknownMessage,
                systemImage: "location.slash.fill",
                actionTitle: .homeMapCurrentUnknownButton,
                actionSystemImage: "location.fill",
                action: .promptCurrentLocation(onPromptCurrentLocation)
            )
        case .locatingCurrent:
            self.init(
                title: .homeMapLocatingTitle,
                message: .homeMapLocatingMessage,
                systemImage: "location.fill",
                showsProgress: true
            )
        case .currentLocationMissing:
            self.init(
                title: .homeMapCurrentMissingTitle,
                message: .homeMapCurrentMissingMessage,
                systemImage: "location.slash.fill",
                actionTitle: .homeMapCurrentMissingButton,
                actionSystemImage: "arrow.clockwise",
                action: .promptCurrentLocation(onPromptCurrentLocation)
            )
        case let .sharingPaused(until):
            self.init(
                title: .homeMapPausedTitle,
                message: .homeMapPausedMessage(LocationPauseEndText.text(for: until)),
                systemImage: "pause.circle.fill",
                actionTitle: .homeMapPausedButton,
                actionSystemImage: "play.fill",
                action: .promptCurrentLocation(onPromptCurrentLocation)
            )
        case .locationAccessOff:
            self.init(
                title: .homeMapAccessOffTitle,
                message: .homeMapAccessOffMessage(partnerName),
                systemImage: "location.slash.fill",
                actionTitle: .commonOpenSettings,
                actionSystemImage: "gear",
                action: .openSettings
            )
        case .waitingForPartnerLocation:
            self.init(
                title: .homeMapPartnerWaitingTitle(partnerName),
                message: .homeMapPartnerWaitingMessage(partnerName),
                systemImage: "location.fill"
            )
        case .partnerUnknown(.relationshipEnded):
            self.init(
                title: .homeMapRelationshipEndedTitle,
                message: .homeMapRelationshipEndedMessage,
                systemImage: "location.slash.fill"
            )
        case .partnerUnknown(.unknown):
            self.init(title: .homeMapUnavailableTitle, message: .homeMapUnavailableMessage, systemImage: "map")
        case .partnerUnknown:
            self.init(
                title: .homeMapPartnerUnknownTitle(partnerName),
                message: .homeMapPartnerUnknownMessage(partnerName),
                systemImage: "location.slash.fill"
            )
        }
    }

    private init(
        title: LocalizedStringResource,
        message: LocalizedStringResource,
        systemImage: String,
        actionTitle: LocalizedStringResource? = nil,
        actionSystemImage: String? = nil,
        action: Action? = nil,
        showsProgress: Bool = false
    ) {
        self.title = title
        self.message = message
        self.systemImage = systemImage
        self.actionTitle = actionTitle
        self.actionSystemImage = actionSystemImage
        self.action = action
        self.showsProgress = showsProgress
    }
}

/// The notice centered on the page: an icon, the title, the explanation, and a small
/// button or a spinner.
struct HomeMapNoticeView: View {
    let notice: HomeMapNotice
    let onDismiss: () -> Void

    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(spacing: PaeoniaSpacing.space8) {
            Image(systemName: notice.systemImage)
                .font(.title3.weight(.semibold))
                .foregroundStyle(.paeoniaAccentPrimary)
                .accessibilityHidden(true)
            Text(notice.title)
                .font(PaeoniaTypography.bodyEmphasis)
                .foregroundStyle(.paeoniaTextPrimary)
            Text(notice.message)
                .font(PaeoniaTypography.caption)
                .foregroundStyle(.paeoniaTextSecondary)
                .frame(maxWidth: 300)
            if notice.showsProgress {
                ProgressView()
                    .tint(.paeoniaAccentPrimary)
                    .padding(.top, PaeoniaSpacing.space4)
            } else if let title = notice.actionTitle, let action = notice.action {
                Button {
                    perform(action)
                } label: {
                    Label {
                        Text(title)
                    } icon: {
                        if let image = notice.actionSystemImage {
                            Image(systemName: image)
                                .accessibilityHidden(true)
                        }
                    }
                    .font(PaeoniaTypography.caption.weight(.semibold))
                    .foregroundStyle(.paeoniaTextInverse)
                    .padding(.horizontal, PaeoniaSpacing.space16)
                    .frame(minHeight: 40)
                    .background(.paeoniaAccentPrimary, in: Capsule())
                }
                .buttonStyle(.plain)
                .padding(.top, PaeoniaSpacing.space8)
            }
            Button(action: onDismiss) {
                Text(.gamesHubNotNow)
                    .font(PaeoniaTypography.caption.weight(.semibold))
                    .foregroundStyle(.paeoniaTextSecondary)
                    .frame(minHeight: 44)
                    .padding(.horizontal, PaeoniaSpacing.space16)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
    }

    private func perform(_ action: HomeMapNotice.Action) {
        switch action {
        case let .promptCurrentLocation(prompt):
            prompt()
        case .openSettings:
            if let url = URL(string: UIApplication.openSettingsURLString) {
                openURL(url)
            }
        }
    }
}
