import Intents
import UserNotifications

/// Upgrades the widget update alert into a communication notification so it
/// shows the partner's avatar and name, styled like a Messages alert. The push
/// carries the sender details (`mutable-content: 1`); the avatar is read from the
/// shared App Group, where the app stages it while paired (the extension has no
/// time to fetch it over the network).
final class NotificationService: UNNotificationServiceExtension {
    // The extension cannot import the app target, so these mirror
    // `PaeoniaAppGroup.identifier` / `.communicationPartnerAvatarPath`.
    private static let appGroupIdentifier = "group.no.paeonia.app"
    private static let partnerAvatarPath = "Notifications/partner-avatar"

    private var contentHandler: ((UNNotificationContent) -> Void)?
    private var bestAttemptContent: UNMutableNotificationContent?

    override func didReceive(
        _ request: UNNotificationRequest,
        withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void
    ) {
        self.contentHandler = contentHandler

        guard let content = request.content.mutableCopy() as? UNMutableNotificationContent else {
            contentHandler(request.content)
            return
        }
        bestAttemptContent = content

        guard let enriched = Self.communicationContent(from: content) else {
            contentHandler(content)
            return
        }
        contentHandler(enriched)
    }

    override func serviceExtensionTimeWillExpire() {
        if let contentHandler, let bestAttemptContent {
            contentHandler(bestAttemptContent)
        }
    }

    private static func communicationContent(
        from content: UNMutableNotificationContent
    ) -> UNNotificationContent? {
        let userInfo = content.userInfo
        guard (userInfo["type"] as? String) == "widget_updated" else {
            return nil
        }

        let senderID = (userInfo["sender_user_id"] as? String)?.nonEmpty ?? "partner"
        let senderName = (userInfo["sender_name"] as? String)?.nonEmpty
            ?? content.title.nonEmpty
            ?? "Paeonia"
        let intent = sendMessageIntent(senderID: senderID, senderName: senderName, body: content.body)

        let interaction = INInteraction(intent: intent, response: nil)
        interaction.direction = .incoming
        interaction.donate(completion: nil)

        do {
            let updated = try content.updating(from: intent)
            guard let mutable = updated.mutableCopy() as? UNMutableNotificationContent else {
                return updated
            }
            // Group repeated widget alerts from the same partner together.
            mutable.threadIdentifier = "widget:\(senderID)"
            // `updating(from:)` may replace the content object and drop the
            // APNs custom payload. Put the original routing hints back so taps
            // can still open the drawing screen.
            var mergedUserInfo = mutable.userInfo
            for (key, value) in content.userInfo {
                mergedUserInfo[key] = value
            }
            mergedUserInfo["type"] = "widget_updated"
            mergedUserInfo["route"] = "widget"
            mutable.userInfo = mergedUserInfo
            return mutable
        } catch {
            return nil
        }
    }

    private static func sendMessageIntent(
        senderID: String,
        senderName: String,
        body: String
    ) -> INSendMessageIntent {
        let avatar = partnerAvatarImage()
        let sender = INPerson(
            personHandle: INPersonHandle(value: senderID, type: .unknown),
            nameComponents: nil,
            displayName: senderName,
            image: avatar,
            contactIdentifier: nil,
            customIdentifier: senderID
        )

        let intent = INSendMessageIntent(
            recipients: nil,
            outgoingMessageType: .outgoingMessageText,
            content: body,
            speakableGroupName: nil,
            conversationIdentifier: "widget:\(senderID)",
            serviceName: "Paeonia",
            sender: sender,
            attachments: nil
        )
        intent.setImage(avatar, forParameterNamed: \.sender)
        return intent
    }

    private static func partnerAvatarImage() -> INImage? {
        guard let container = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupIdentifier
        ) else {
            return nil
        }

        let url = container.appendingPathComponent(partnerAvatarPath)
        guard let data = try? Data(contentsOf: url), !data.isEmpty else {
            return nil
        }
        return INImage(imageData: data)
    }
}

private extension String {
    var nonEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
