import Foundation
import Observation

/// The user's reactions that the server has not confirmed yet. Every place that takes a
/// reaction owns one: the question chat and `ReactionStore`, which serves everything else.
///
/// A change shows at once. If the server turns it down, the earlier reaction comes back and
/// the caller gets the failure, to say so. The saved reactions stay with the caller, because
/// the chat reads them with its messages and the other places read them from the feed.
@MainActor
@Observable
final class ReactionEditor {
    /// A reaction the user just chose and the server has not confirmed. A nil emoji means the
    /// user took their reaction back.
    struct Pending: Equatable {
        let emoji: String?
        /// Tells this change apart from a later one on the same thing.
        let id = UUID()
    }

    private(set) var pending: [ReactionTarget: Pending] = [:]

    @ObservationIgnored private let gateway: any ReactionGateway
    @ObservationIgnored private let palette: ReactionPalette

    init(gateway: any ReactionGateway = LiveReactionGateway(), palette: ReactionPalette = .shared) {
        self.gateway = gateway
        self.palette = palette
    }

    /// `saved` with the user's unconfirmed change in place of their saved reaction.
    func reactions(on target: ReactionTarget, saved: [EmojiReaction], userID: UUID?) -> [EmojiReaction] {
        guard let userID, let pending = pending[target] else { return saved }
        var list = saved.filter { $0.userID != userID }
        if let emoji = pending.emoji { list.append(EmojiReaction(userID: userID, emoji: emoji)) }
        return list
    }

    /// The user's own reaction, counting what they just chose.
    func ownReaction(on target: ReactionTarget, saved: [EmojiReaction], userID: UUID?) -> String? {
        if let pending = pending[target] { return pending.emoji }
        return saved.first { $0.userID == userID }?.emoji
    }

    /// Puts `emoji` on `target`. Choosing the reaction already there takes it back. Returns nil
    /// when the server took it, otherwise the failure, and the earlier reaction shows again.
    /// A chosen emoji moves to the front of the reaction row.
    func toggle(
        _ emoji: String,
        on target: ReactionTarget,
        saved: [EmojiReaction],
        userID: UUID?
    ) async -> PaeoniaFailure? {
        await toggle(emoji, on: target, saved: saved, userID: userID) { [gateway] next in
            try await gateway.setReaction(next, on: target)
        }
    }

    /// Like `toggle`, with the caller sending the change. The question chat reads its messages
    /// again when the server has taken it.
    func toggle(
        _ emoji: String,
        on target: ReactionTarget,
        saved: [EmojiReaction],
        userID: UUID?,
        send: (String?) async throws -> Void
    ) async -> PaeoniaFailure? {
        let next = ownReaction(on: target, saved: saved, userID: userID) == emoji ? nil : emoji
        let change = Pending(emoji: next)
        pending[target] = change
        PaeoniaHaptics.selection()
        if let next { palette.recordSelection(next) }
        do {
            try await send(next)
            return nil
        } catch {
            if pending[target] == change { pending[target] = nil }
            return PaeoniaFailure(error)
        }
    }

    /// Forgets the changes the saved reactions now show, once a read brings them. `saved`
    /// returns the saved reactions on a target.
    func settle(userID: UUID?, saved: (ReactionTarget) -> [EmojiReaction]) {
        for (target, change) in pending {
            let own = saved(target).first { $0.userID == userID }?.emoji
            if own == change.emoji { pending[target] = nil }
        }
    }

    /// Forgets everything, for sign-out and a new account.
    func reset() {
        pending = [:]
    }
}
