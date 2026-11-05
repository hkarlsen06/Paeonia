import AppIntents
import Foundation

// App Shortcuts titles use literal localization keys for metadata extraction.
// swiftlint:disable no_raw_localization_keys
@available(iOS 27.3, *)
struct PaeoniaChatShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: SendChatMessageIntent(),
            phrases: ["Send a message in \(.applicationName)"],
            shortTitle: LocalizedStringResource("siri.shortcuts.send", table: "Localizable"),
            systemImageName: "paperplane")
        AppShortcut(
            intent: DraftChatMessageIntent(),
            phrases: ["Draft a message in \(.applicationName)", "Write a message in \(.applicationName)"],
            shortTitle: LocalizedStringResource("siri.shortcuts.draft", table: "Localizable"),
            systemImageName: "square.and.pencil")
        AppShortcut(
            intent: EditChatMessageIntent(),
            phrases: ["Edit a message in \(.applicationName)"],
            shortTitle: LocalizedStringResource("siri.shortcuts.edit", table: "Localizable"),
            systemImageName: "pencil")
        AppShortcut(
            intent: UnsendChatMessageIntent(),
            phrases: ["Unsend a message in \(.applicationName)"],
            shortTitle: LocalizedStringResource("siri.shortcuts.unsend", table: "Localizable"),
            systemImageName: "arrow.uturn.backward")
        AppShortcut(
            intent: SendChatMessageReactionIntent(),
            phrases: ["React to a message in \(.applicationName)"],
            shortTitle: LocalizedStringResource("siri.shortcuts.react", table: "Localizable"),
            systemImageName: "face.smiling")
    }
}

// swiftlint:enable no_raw_localization_keys
