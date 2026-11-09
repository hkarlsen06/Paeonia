import AppIntents
import Foundation
import Observation
import UIKit

enum PaeoniaBannerStyle: Equatable {
    case error
    /// A neutral, non-error notice used to surface a partner's update in-app
    /// while the app is open, in place of the system notification banner.
    case info
}

/// How long a banner stays before it dismisses itself.
enum PaeoniaBannerTiming: Equatable {
    /// The center's time for the banner's style.
    case standard
    case fixed(Duration)
    /// For an error the user has to deal with somewhere else, or one they must
    /// not miss, such as a report that may not have been sent.
    case untilDismissed
}

struct PaeoniaBannerContent: Equatable, Identifiable {
    let id: UUID
    let style: PaeoniaBannerStyle
    let title: String?
    let message: String
    let gameKind: GameKind?
    /// Optional leading avatar (e.g. the partner's profile photo) shown in place
    /// of the style's icon.
    let imageData: Data?
    /// `imageData` decoded once here, so the banner does not decode it on every render.
    let avatar: UIImage?
    /// When true, tapping the banner invokes the host's tap handler (used to open
    /// the drawing screen from a partner-update notice).
    let isTappable: Bool
    /// SF Symbol shown instead of the style's default icon.
    let systemImage: String?
    /// Runs on tap instead of the host's tap handler. Setting it makes the banner tappable.
    let action: (() -> Void)?
    var appEntityIdentifier: EntityIdentifier?
    let timing: PaeoniaBannerTiming

    init(
        id: UUID = UUID(),
        style: PaeoniaBannerStyle,
        title: String? = nil,
        message: String,
        gameKind: GameKind? = nil,
        imageData: Data? = nil,
        isTappable: Bool = false,
        systemImage: String? = nil,
        action: (() -> Void)? = nil,
        timing: PaeoniaBannerTiming = .standard
    ) {
        self.id = id
        self.style = style
        self.title = title
        self.message = message
        self.gameKind = gameKind
        self.imageData = imageData
        self.avatar = imageData.flatMap { UIImage(data: $0) }
        self.isTappable = isTappable || action != nil
        self.systemImage = systemImage
        self.action = action
        self.appEntityIdentifier = nil
        self.timing = timing
    }

    var titleText: String? { title?.nilIfBlank }

    static func == (lhs: PaeoniaBannerContent, rhs: PaeoniaBannerContent) -> Bool {
        lhs.id == rhs.id
            && lhs.style == rhs.style
            && lhs.title == rhs.title
            && lhs.message == rhs.message
            && lhs.gameKind == rhs.gameKind
            && lhs.imageData == rhs.imageData
            && lhs.isTappable == rhs.isTappable
            && lhs.systemImage == rhs.systemImage
            && lhs.timing == rhs.timing
            && lhs.appEntityIdentifier == rhs.appEntityIdentifier
    }

    /// True when `other` would look the same to the user, even with a different id.
    func hasSameText(as other: PaeoniaBannerContent) -> Bool {
        style == other.style && title == other.title && message == other.message && gameKind == other.gameKind
            && appEntityIdentifier == other.appEntityIdentifier
    }

    static func error(
        title: String? = nil,
        message: String,
        timing: PaeoniaBannerTiming = .standard
    ) -> PaeoniaBannerContent {
        PaeoniaBannerContent(style: .error, title: title, message: message, timing: timing)
    }

    static func info(
        title: String? = nil,
        message: String,
        gameKind: GameKind? = nil,
        imageData: Data? = nil,
        isTappable: Bool = false,
        systemImage: String? = nil,
        action: (() -> Void)? = nil,
        timing: PaeoniaBannerTiming = .standard
    ) -> PaeoniaBannerContent {
        PaeoniaBannerContent(
            style: .info,
            title: title,
            message: message,
            gameKind: gameKind,
            imageData: imageData,
            isTappable: isTappable,
            systemImage: systemImage,
            action: action,
            timing: timing
        )
    }
}

@Observable
final class PaeoniaBannerCenter {
    private(set) var content: PaeoniaBannerContent?
    /// Every place that can draw the banner, with the app root first. Only the newest
    /// draws it: a sheet or cover that mounts `.paeoniaBanner` takes over
    /// from the screen under it, and hands back when it goes away. Nested
    /// attachments therefore never show the same banner twice.
    private(set) var hosts: [UUID] = []

    private let infoDuration: Duration
    private let isVoiceOverRunning: @MainActor () -> Bool
    @ObservationIgnored private var dismissTask: Task<Void, Never>?

    /// Errors and actionable notices stay until dismissed so reading or operating
    /// another control never makes someone miss a problem or an available action.
    init(
        infoDuration: Duration = .seconds(4),
        isVoiceOverRunning: @escaping @MainActor () -> Bool = { UIAccessibility.isVoiceOverRunning }
    ) {
        self.infoDuration = infoDuration
        self.isVoiceOverRunning = isVoiceOverRunning
    }

    func registerHost(_ id: UUID, isRoot: Bool = false) {
        hosts.removeAll { $0 == id }
        if isRoot {
            hosts.insert(id, at: 0)
        } else {
            hosts.append(id)
        }
    }

    func unregisterHost(_ id: UUID) {
        hosts.removeAll { $0 == id }
    }

    /// True for the host that should draw the banner right now.
    func isActiveHost(_ id: UUID) -> Bool {
        hosts.last == id
    }

    /// Shows `content`. If the banner on screen reads the same, it stays as is
    /// (same id, no haptic, no new animation) and only its timer restarts.
    func show(_ content: PaeoniaBannerContent) {
        if let current = self.content, current.hasSameText(as: content) {
            scheduleDismiss(of: current)
            return
        }

        self.content = content

        switch content.style {
        case .error:
            PaeoniaHaptics.validationError()
        case .info:
            PaeoniaHaptics.drawingSent()
        }

        announce(content)
        scheduleDismiss(of: content)
    }

    func dismiss() {
        dismissTask?.cancel()
        dismissTask = nil
        content = nil
    }

    /// Dismisses only if the banner with `id` is still the one on screen, so a
    /// late timer or swipe for an old banner cannot remove a newer one.
    func dismiss(id: UUID) {
        guard content?.id == id else {
            return
        }

        dismiss()
    }

    private func scheduleDismiss(of banner: PaeoniaBannerContent) {
        dismissTask?.cancel()
        dismissTask = nil
        guard banner.style != .error, !banner.isTappable, !isVoiceOverRunning() else { return }

        let duration: Duration
        switch banner.timing {
        case .standard:
            duration = infoDuration
        case let .fixed(fixed):
            duration = fixed
        case .untilDismissed:
            return
        }
        let id = banner.id
        dismissTask = Task { [weak self] in
            try? await Task.sleep(for: duration)
            guard !Task.isCancelled else {
                return
            }

            self?.dismiss(id: id)
        }
    }

    private func announce(_ banner: PaeoniaBannerContent) {
        let text = [banner.title?.nilIfBlank, banner.message.nilIfBlank]
            .compactMap { $0 }
            .joined(separator: ". ")
        AccessibilityNotification.Announcement(text).post()
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
