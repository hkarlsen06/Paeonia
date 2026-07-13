import Foundation

nonisolated enum PaeoniaDeepLink: Equatable, Sendable, Hashable {
    case widgetDrawing
    case dailyReveal(instanceID: UUID, coupleDayID: UUID?)
    case dailyToday(coupleDayID: UUID?)
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

    static var streakURL: URL {
        var components = URLComponents()
        components.scheme = scheme
        components.host = "streak"

        guard let url = components.url else {
            preconditionFailure("Invalid Paeonia streak URL")
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

    init?(notificationUserInfo userInfo: [AnyHashable: Any]) {
        let type = userInfo.nonEmptyString(for: "type")
        let route = userInfo.nonEmptyString(for: "route")
        let coupleDayID = userInfo.uuidValue(for: "couple_day_id")
        let deeplink = userInfo.deepLink

        switch type {
        case "widget_updated":
            self = .widgetDrawing
        case "partner_answered":
            if case let .some(.dailyReveal(instanceID, deeplinkCoupleDayID)) = deeplink {
                self = .dailyReveal(instanceID: instanceID, coupleDayID: deeplinkCoupleDayID)
                return
            }
            guard let instanceID = userInfo.uuidValue(for: "instance_id") else {
                self = .dailyToday(coupleDayID: coupleDayID)
                return
            }
            self = .dailyReveal(instanceID: instanceID, coupleDayID: coupleDayID)
        case "daily_challenge_completed":
            if case let .some(.dailyToday(deeplinkCoupleDayID)) = deeplink {
                self = .dailyToday(coupleDayID: deeplinkCoupleDayID)
                return
            }
            self = .dailyToday(coupleDayID: coupleDayID)
        case "streak_reminder":
            self = .streak
        case "subscription_trial_reminder":
            self = .subscription
        default:
            if let deeplink {
                self = deeplink
                return
            }

            switch route {
            case "widget":
                self = .widgetDrawing
            case "daily":
                self = .dailyToday(coupleDayID: coupleDayID)
            case "streak":
                self = .streak
            case "subscription":
                self = .subscription
            default:
                return nil
            }
        }
    }

    init?(notificationThreadIdentifier threadIdentifier: String) {
        let trimmed = threadIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("widget:") else {
            return nil
        }

        self = .widgetDrawing
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

private extension Dictionary where Key == AnyHashable, Value == Any {
    nonisolated var deepLink: PaeoniaDeepLink? {
        guard let deeplink = nonEmptyString(for: "deeplink"),
              let url = URL(string: deeplink)
        else {
            return nil
        }
        return PaeoniaDeepLink(url)
    }

    nonisolated func nonEmptyString(for key: String) -> String? {
        guard let raw = self[key] else {
            return nil
        }

        if let string = raw as? String {
            let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }

        if let uuid = raw as? UUID {
            return uuid.uuidString
        }

        return nil
    }

    nonisolated func uuidValue(for key: String) -> UUID? {
        if let uuid = self[key] as? UUID {
            return uuid
        }

        guard let value = nonEmptyString(for: key) else {
            return nil
        }
        return UUID(uuidString: value)
    }
}
