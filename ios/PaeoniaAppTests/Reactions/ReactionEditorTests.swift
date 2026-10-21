import Foundation
import Testing
@testable import PaeoniaApp

/// The user's unconfirmed reactions: shown at once, taken back when the server refuses, and
/// forgotten once the saved copy shows them.
@MainActor
struct ReactionEditorTests {
    private struct Refused: Error {}

    private actor RecordingGateway: ReactionGateway {
        private(set) var sent: [String?] = []
        var error: (any Error)?

        func setReaction(_ emoji: String?, on _: ReactionTarget) throws {
            if let error { throw error }
            sent.append(emoji)
        }

        func refuse() {
            error = Refused()
        }
    }

    private let me = UUID()
    private let partner = UUID()
    private let target = ReactionTarget.story(UUID())

    private func makeEditor(_ gateway: RecordingGateway = RecordingGateway()) -> ReactionEditor {
        let defaults = UserDefaults(suiteName: "ReactionEditorTests.\(UUID().uuidString)") ?? .standard
        return ReactionEditor(gateway: gateway, palette: ReactionPalette(userDefaults: defaults))
    }

    @Test func aChosenEmojiShowsWhileItIsBeingSent() async {
        let editor = makeEditor()
        var shownWhileSending: String?

        let failure = await editor.toggle("❤️", on: target, saved: [], userID: me) { _ in
            shownWhileSending = editor.ownReaction(on: target, saved: [], userID: me)
        }

        #expect(failure == nil)
        #expect(shownWhileSending == "❤️")
    }

    @Test func choosingTheOwnReactionAgainTakesItBack() async {
        let gateway = RecordingGateway()
        let editor = makeEditor(gateway)
        let saved = [EmojiReaction(userID: me, emoji: "😂")]

        _ = await editor.toggle("😂", on: target, saved: saved, userID: me)
        _ = await editor.toggle("🥰", on: target, saved: saved, userID: me)

        #expect(await gateway.sent == [nil, "🥰"])
    }

    @Test func aRefusalPutsTheEarlierReactionBack() async {
        let gateway = RecordingGateway()
        await gateway.refuse()
        let editor = makeEditor(gateway)
        let saved = [EmojiReaction(userID: me, emoji: "😂")]

        let failure = await editor.toggle("❤️", on: target, saved: saved, userID: me)

        #expect(failure == .other)
        #expect(editor.ownReaction(on: target, saved: saved, userID: me) == "😂")
        #expect(editor.pending.isEmpty)
    }

    @Test func theUsersChangeReplacesOnlyTheirOwnReaction() async {
        let editor = makeEditor()
        let saved = [
            EmojiReaction(userID: me, emoji: "😂"),
            EmojiReaction(userID: partner, emoji: "🥰"),
        ]

        _ = await editor.toggle("❤️", on: target, saved: saved, userID: me) { _ in }

        let shown = editor.reactions(on: target, saved: saved, userID: me)
        #expect(Set(shown) == [
            EmojiReaction(userID: me, emoji: "❤️"),
            EmojiReaction(userID: partner, emoji: "🥰"),
        ])
    }

    @Test func aChangeStaysUntilTheSavedCopyShowsIt() async {
        let editor = makeEditor()
        _ = await editor.toggle("❤️", on: target, saved: [], userID: me) { _ in }

        editor.settle(userID: me) { _ in [] }
        #expect(editor.pending.count == 1)

        editor.settle(userID: me) { _ in [EmojiReaction(userID: me, emoji: "❤️")] }
        #expect(editor.pending.isEmpty)
    }
}
