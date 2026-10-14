import Foundation
@testable import PaeoniaApp

/// What the server tells a person: the game state, the overview, and the ideas.
extension CorpseSimServer {
    /// `get_exquisite_corpse` for `user`.
    func state(for user: UUID) -> RemoteExquisiteCorpseState {
        let current = figures.first { $0.id == game?.figureID }
        let recent = figures.filter { $0.finishedAt != nil }.sorted { $0.number > $1.number }.prefix(10)
        return RemoteExquisiteCorpseState(
            userID: user,
            partnerUserID: partner(of: user),
            coupleID: coupleID,
            game: game.map(gameJSON),
            currentFigure: current.map { json($0, for: user) },
            recentFigures: recent.map { json($0, for: user) },
            ideas: game.map { $0.turnUser == user ? deck(for: $0) : [] } ?? []
        )
    }

    func overview(for user: UUID) -> RemoteGamesOverview {
        let partnerID = partner(of: user)
        let hasPresence = presence[user] != nil || presence[partnerID] != nil || invites[user] != nil
        return RemoteGamesOverview(
            userID: user,
            partnerUserID: partnerID,
            coupleID: coupleID,
            settings: settings,
            presence: hasPresence ? [
                RemoteGamePresence(
                    kind: .exquisiteCorpse,
                    myPresent: presence[user] != nil,
                    partnerPresent: presence[partnerID] != nil,
                    lastInviteAt: invites[user]
                ),
            ] : []
        )
    }

    private func gameJSON(_ game: Game) -> RemoteExquisiteCorpseGame {
        RemoteExquisiteCorpseGame(
            id: game.id,
            turnUserID: game.turnUser,
            turnStartedAt: game.turnStartedAt,
            figureID: game.figureID,
            figureNumber: game.figureNumber,
            partIndex: game.partIndex,
            figuresFinished: game.figuresFinished,
            version: game.version,
            createdAt: game.createdAt,
            updatedAt: game.updatedAt
        )
    }

    /// `figureJson` and `partJson`: the full drawing and the idea of a part stay
    /// hidden from the partner until the figure is finished. The strip never is.
    private func json(_ figure: Figure, for user: UUID) -> RemoteExquisiteCorpseFigure {
        let isFinished = figure.finishedAt != nil
        let figureParts = parts.filter { $0.figureID == figure.id }.sorted { $0.index < $1.index }
        return RemoteExquisiteCorpseFigure(
            id: figure.id,
            number: figure.number,
            starterUserID: figure.starter,
            createdAt: figure.createdAt,
            finishedAt: figure.finishedAt,
            myRevealSeenAt: figure.seenAt[user],
            starredByMe: figure.starredBy.contains(user),
            parts: figureParts.map { part in
                let isVisible = isFinished || part.drawer == user
                return RemoteExquisiteCorpsePart(
                    id: part.id,
                    partIndex: part.index,
                    drawerUserID: part.drawer,
                    createdAt: part.createdAt,
                    stripMediaAssetID: part.stripAssetID,
                    drawingMediaAssetID: isVisible ? part.drawingAssetID : nil,
                    idea: isVisible ? part.idea : nil
                )
            }
        )
    }

    private func deck(for game: Game) -> [RemoteExquisiteCorpseIdea] {
        let list = Self.ideas[game.partIndex]
        let shift = (game.figureNumber * 3 + game.partIndex) % list.count
        return Array((list[shift...] + list[..<shift]).prefix(12))
    }

    // MARK: - Play together

    func sendInvite(user: UUID) throws -> RemoteInviteResult {
        if let previous = invites[user], previous > now.addingTimeInterval(-15 * 60) {
            throw fail("53300", "you can send one invite every 15 minutes")
        }
        invites[user] = now
        changed()
        return RemoteInviteResult(sentAt: now)
    }

    func setPresence(user: UUID, present: Bool) {
        presence[user] = present ? now : nil
        changed()
    }

    func presenceStamp(of user: UUID) -> Date? {
        presence[user]
    }

    /// Like the presence component, closes a game screen 60 seconds after its
    /// last heartbeat and tells the subscribers.
    func expirePresence() {
        let stale = presence.filter { now.timeIntervalSince($0.value) >= 60 }.map(\.key)
        guard !stale.isEmpty else { return }
        for user in stale {
            presence[user] = nil
        }
        changed()
    }
}
