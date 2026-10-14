import Foundation

nonisolated enum PaeoniaDeepLink: Equatable, Sendable, Hashable {
    case widgetDrawing
    case dailyReveal(instanceID: UUID, coupleDayID: UUID?)
    /// A question's chat. A couple has one chat per question.
    case dailyChat(questionID: UUID)
    case dailyToday(coupleDayID: UUID?)
    case memories
    /// `paeonia://games/<path>`, for every `GameKind`.
    case game(GameKind)
    case streak
    case subscription

    static let scheme = "paeonia"

    static var widgetDrawingURL: URL {
        PaeoniaWidgetDeepLink.drawingURL
    }

    static func dailyRevealURL(instanceID: UUID, coupleDayID: UUID) -> URL {
        var components = URLComponents()
        components.scheme = scheme
        components.host = "daily"
        components.path = "/reveal"
        components.queryItems = [
            URLQueryItem(name: "instanceId", value: instanceID.uuidString),
            URLQueryItem(name: "coupleDayId", value: coupleDayID.uuidString),
        ]

        guard let url = components.url else {
            preconditionFailure("Invalid Paeonia daily reveal URL")
        }

        return url
    }

    static func dailyTodayURL(coupleDayID: UUID) -> URL {
        var components = URLComponents()
        components.scheme = scheme
        components.host = "daily"
        components.path = "/today"
        components.queryItems = [
            URLQueryItem(name: "coupleDayId", value: coupleDayID.uuidString),
        ]

        guard let url = components.url else {
            preconditionFailure("Invalid Paeonia daily today URL")
        }

        return url
    }

    static func dailyChatURL(questionID: UUID) -> URL {
        var components = URLComponents()
        components.scheme = scheme
        components.host = "daily"
        components.path = "/chat"
        components.queryItems = [
            URLQueryItem(name: "questionId", value: questionID.uuidString),
        ]

        guard let url = components.url else {
            preconditionFailure("Invalid Paeonia daily chat URL")
        }
        return url
    }

    static var streakURL: URL {
        var components = URLComponents()
        components.scheme = scheme
        components.host = "streak"

        guard let url = components.url else {
            preconditionFailure("Invalid Paeonia streak URL")
        }

        return url
    }

    static var memoriesURL: URL {
        var components = URLComponents()
        components.scheme = scheme
        components.host = "memories"

        guard let url = components.url else {
            preconditionFailure("Invalid Paeonia memories URL")
        }

        return url
    }

    static func gameURL(_ kind: GameKind) -> URL {
        var components = URLComponents()
        components.scheme = scheme
        components.host = "games"
        components.path = "/\(kind.path)"

        guard let url = components.url else {
            preconditionFailure("Invalid Paeonia game URL")
        }

        return url
    }

    static var subscriptionURL: URL {
        var components = URLComponents()
        components.scheme = scheme
        components.host = "settings"
        components.path = "/subscription"

        guard let url = components.url else {
            preconditionFailure("Invalid Paeonia subscription URL")
        }

        return url
    }

    static var appStoreSubscriptionsURL: URL {
        guard let url = URL(string: "https://apps.apple.com/account/subscriptions") else {
            preconditionFailure("Invalid App Store subscriptions URL")
        }
        return url
    }

    init?(_ url: URL) {
        if let widgetDeepLink = PaeoniaWidgetDeepLink(url) {
            switch widgetDeepLink {
            case .drawing:
                self = .widgetDrawing
            }
            return
        }

        guard url.scheme?.lowercased() == Self.scheme,
              let host = url.host()?.lowercased()
        else {
            return nil
        }

        let pathComponents = url.pathComponents.filter { $0 != "/" }
        let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []

        switch (host, pathComponents) {
        case ("daily", ["reveal"]):
            guard let instanceID = query.uuidValue(named: "instanceId") else {
                return nil
            }
            self = .dailyReveal(
                instanceID: instanceID,
                coupleDayID: query.uuidValue(named: "coupleDayId")
            )
        case ("daily", ["today"]):
            self = .dailyToday(coupleDayID: query.uuidValue(named: "coupleDayId"))
        case ("daily", ["chat"]):
            guard let questionID = query.uuidValue(named: "questionId") else { return nil }
            self = .dailyChat(questionID: questionID)
        case ("memories", []):
            self = .memories
        case ("games", _) where pathComponents.count == 1:
            guard let kind = GameKind(path: pathComponents[0]) else { return nil }
            self = .game(kind)
        case ("streak", []):
            self = .streak
        case ("settings", ["subscription"]):
            self = .subscription
        default:
            return nil
        }
    }

    init?(_ widgetDeepLink: PaeoniaWidgetDeepLink) {
        switch widgetDeepLink {
        case .drawing:
            self = .widgetDrawing
        }
    }

    /// Every backend push carries a `deeplink` URL. The notification service
    /// extension keeps it when it rewrites a widget alert.
    init?(notificationUserInfo userInfo: [AnyHashable: Any]) {
        guard let deeplink = userInfo["deeplink"] as? String,
              let url = URL(string: deeplink.trimmingCharacters(in: .whitespacesAndNewlines))
        else {
            return nil
        }
        self.init(url)
    }

    static func handles(_ url: URL) -> Bool {
        Self(url) != nil
    }
}

private extension Array where Element == URLQueryItem {
    nonisolated func uuidValue(named name: String) -> UUID? {
        guard let value = first(where: { $0.name == name })?.value else {
            return nil
        }
        return UUID(uuidString: value)
    }
}
