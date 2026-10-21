import Foundation
import Observation

/// The couple's reactions on stories, memories, widget drawings and game creations, and the
/// one place the screens that show or take them go through. The question chat keeps its
/// reactions with its messages and answers and uses a `ReactionEditor` of its own.
///
/// `saved` is the cached server list, so every screen shows it offline and a reaction from the
/// partner arrives through the live feed (`ReactionsLiveFeed`). The user's own change shows at
/// once through the editor and waits for the server.
@MainActor
@Observable
final class ReactionStore {
    private(set) var participants = ReactionParticipants(currentUserID: nil, partnerName: "")
    private(set) var saved: [ReactionTarget: [EmojiReaction]] = [:]
    let editor: ReactionEditor

    @ObservationIgnored private let cache: any ReactionsCaching
    /// Drops a reload that finished after a newer one started or the account changed.
    @ObservationIgnored private var reloadGeneration = 0

    init(cache: (any ReactionsCaching)? = nil, gateway: (any ReactionGateway)? = nil) {
        self.cache = cache ?? FileReactionsCache.shared
        editor = ReactionEditor(gateway: gateway ?? LiveReactionGateway())
    }

    /// Reads the cache for the signed-in person. Names arrive after launch, so the partner's
    /// name has its own update.
    func configure(ownerUserID: UUID?, partnerName: String) async {
        if participants.currentUserID != ownerUserID {
            saved = [:]
            editor.reset()
        }
        participants = ReactionParticipants(currentUserID: ownerUserID, partnerName: partnerName)
        await reload()
    }

    func updatePartnerName(_ partnerName: String) {
        participants = ReactionParticipants(currentUserID: participants.currentUserID, partnerName: partnerName)
    }

    func observeStoreChanges() async {
        for await change in LocalStoreChanges.changes(in: .reactions) {
            guard !Task.isCancelled else { return }
            guard change.ownerUserID == nil || change.ownerUserID == participants.currentUserID else { continue }
            await reload()
        }
    }

    func reload() async {
        reloadGeneration &+= 1
        let generation = reloadGeneration
        guard let ownerUserID = participants.currentUserID else {
            saved = [:]
            return
        }
        let rows = await cache.rows(ownerUserID: ownerUserID)
        guard generation == reloadGeneration, participants.currentUserID == ownerUserID else { return }
        saved = Dictionary(grouping: rows, by: \.target).mapValues { $0.map(\.reaction) }
        editor.settle(userID: ownerUserID) { [saved] target in saved[target] ?? [] }
    }

    /// Everyone's reaction to `target`, with the user's own change in place.
    func reactions(on target: ReactionTarget) -> [EmojiReaction] {
        editor.reactions(on: target, saved: saved[target] ?? [], userID: participants.currentUserID)
    }

    /// The user's own reaction to `target`.
    func ownReaction(on target: ReactionTarget) -> String? {
        editor.ownReaction(on: target, saved: saved[target] ?? [], userID: participants.currentUserID)
    }

    /// The partner's reaction to `target`.
    func partnerReaction(on target: ReactionTarget) -> String? {
        reactions(on: target).first { $0.userID != participants.currentUserID }?.emoji
    }

    /// Puts `emoji` on `target`, or takes the user's reaction back when it is the one already
    /// there. Returns nil when the server took it, otherwise the failure.
    func toggle(_ emoji: String, on target: ReactionTarget) async -> PaeoniaFailure? {
        await editor.toggle(
            emoji,
            on: target,
            saved: saved[target] ?? [],
            userID: participants.currentUserID
        )
    }
}
