import Foundation

/// Where the person is in the game right now. Each case is one screen state.
nonisolated enum ExquisiteCorpsePhase: Equatable, Sendable {
    /// Nothing is cached yet and the first read has not finished.
    case loading
    /// The couple has not picked a game language yet.
    case needsSetup
    /// The couple's game does not exist yet and is being created.
    case preparing
    /// It is this person's turn to draw a part.
    case drawing
    /// It is the partner's turn, and they are not drawing in the live room.
    case waiting
    /// It is the partner's turn, and the live room says they are drawing. This
    /// person watches the folded paper.
    case watching
    /// A finished figure this person has not moved past. Shows the unfolding.
    case reveal
    /// This person's legs are queued on the phone. The figure is finished here,
    /// and the reveal waits for the server.
    case waitingToSync

    /// What this phone tells the partner's phone through the relay room.
    static func liveRole(phase: ExquisiteCorpsePhase) -> WidgetLivePresence.Role {
        switch phase {
        case .drawing: .drawing
        case .watching, .waiting: .watching
        case .reveal: .result
        default: .present
        }
    }
}

nonisolated struct ExquisiteCorpseResolution: Equatable, Sendable {
    let phase: ExquisiteCorpsePhase
    /// The part the turn is about. It is this person's part when `turnPhase` is
    /// `.drawing` and the partner's part when it is `.waiting` or `.watching`.
    /// In a reveal it is the part after the reveal, such as the next head. Nil in
    /// the other phases.
    let part: ExquisiteCorpsePartKind?
    /// The figure the phase is about. With a queued part applied it is the figure
    /// in progress, and during a reveal it is the unseen finished figure. A queued
    /// part has no media ids yet, so the screen finds its drawing in the pending
    /// work by part id. Nil when no figure is in progress.
    let figure: RemoteExquisiteCorpseFigure?
    /// A part is saved on this phone and not on the server yet.
    let isWaitingToSend: Bool
    /// The phase once the person moves on from the reveal, or `phase` when there
    /// is no reveal. Whose turn the hub shows comes from this. It is never `.reveal`.
    let turnPhase: ExquisiteCorpsePhase

    init(
        phase: ExquisiteCorpsePhase,
        part: ExquisiteCorpsePartKind?,
        figure: RemoteExquisiteCorpseFigure?,
        isWaitingToSend: Bool,
        turnPhase: ExquisiteCorpsePhase? = nil
    ) {
        self.phase = phase
        self.part = part
        self.figure = figure
        self.isWaitingToSend = isWaitingToSend
        self.turnPhase = turnPhase ?? phase
    }
}

/// Works out the phase from the server's state and this phone's unsent moves.
/// A finished figure's reveal counts as seen when the server has this person's
/// "reveal seen" time for it, or a mark for it waits on this phone. It reads no
/// clock and no network.
nonisolated struct ExquisiteCorpseResolver: Sendable {
    let userID: UUID

    /// - Parameter hasSettings: The couple has picked a game language.
    func resolve(
        state: RemoteExquisiteCorpseState?,
        hasSettings: Bool,
        pending: ExquisiteCorpsePendingWork,
        isPartnerDrawingLive: Bool
    ) -> ExquisiteCorpseResolution {
        let waiting = pending.hasMoveWaiting
        func resolution(_ phase: ExquisiteCorpsePhase) -> ExquisiteCorpseResolution {
            ExquisiteCorpseResolution(phase: phase, part: nil, figure: nil, isWaitingToSend: waiting)
        }
        guard let state else {
            return resolution(.loading)
        }
        guard hasSettings else {
            return resolution(.needsSetup)
        }
        guard let game = state.game, let kind = ExquisiteCorpsePartKind(rawValue: game.partIndex) else {
            return resolution(.preparing)
        }

        let turn = turnToShow(
            state: state,
            game: game,
            kind: kind,
            pending: pending,
            isPartnerDrawingLive: isPartnerDrawingLive
        )
        // The legs drawer, or the partner who drew the body, may not have moved
        // past the last figure's reveal. That comes before the next turn.
        if let unseen = unseenFigure(state: state, pending: pending) {
            return ExquisiteCorpseResolution(
                phase: .reveal,
                part: turn.part,
                figure: unseen,
                isWaitingToSend: waiting,
                turnPhase: turn.phase
            )
        }
        return ExquisiteCorpseResolution(
            phase: turn.phase,
            part: turn.part,
            figure: turn.figure,
            isWaitingToSend: waiting
        )
    }

    private struct Turn {
        let phase: ExquisiteCorpsePhase
        let part: ExquisiteCorpsePartKind?
        let figure: RemoteExquisiteCorpseFigure?
    }

    /// The turn as the screen shows it: the server's, or the next one when a
    /// queued part of this person's has not reached the server yet.
    private func turnToShow(
        state: RemoteExquisiteCorpseState,
        game: RemoteExquisiteCorpseGame,
        kind: ExquisiteCorpsePartKind,
        pending: ExquisiteCorpsePendingWork,
        isPartnerDrawingLive: Bool
    ) -> Turn {
        let partnersPhase: ExquisiteCorpsePhase = isPartnerDrawingLive ? .watching : .waiting
        if let queued = pending.parts.first(where: { isNextPart($0, of: game) }),
           let figure = figure(applying: queued, state: state, game: game) {
            // The legs end the figure on this phone, and the next turn belongs to
            // the server.
            guard let next = kind.next else {
                return Turn(phase: .waitingToSync, part: nil, figure: figure)
            }
            return Turn(phase: partnersPhase, part: next, figure: figure)
        }
        let phase: ExquisiteCorpsePhase = game.turnUserID == userID ? .drawing : partnersPhase
        return Turn(phase: phase, part: kind, figure: state.currentFigure)
    }

    /// The queued part is the one the server is waiting for from this person. A
    /// part the turn has moved past, or from another figure, is stale and ignored.
    private func isNextPart(_ part: ExquisiteCorpseSubmitPartPayload, of game: RemoteExquisiteCorpseGame) -> Bool {
        guard part.gameID == game.id, part.partIndex == game.partIndex, game.turnUserID == userID else {
            return false
        }
        if part.partIndex == ExquisiteCorpsePartKind.head.rawValue {
            return game.figureID == nil
                && part.figureID == ExquisiteCorpseIDs.figure(gameID: game.id, number: game.figureNumber)
        }
        return part.figureID == game.figureID
    }

    /// The figure in progress with the queued part in it. The legs finish it, at
    /// this phone's time until the server's replaces it. Nil when the server's
    /// figure is not the one the part belongs to.
    private func figure(
        applying queued: ExquisiteCorpseSubmitPartPayload,
        state: RemoteExquisiteCorpseState,
        game: RemoteExquisiteCorpseGame
    ) -> RemoteExquisiteCorpseFigure? {
        let base: RemoteExquisiteCorpseFigure
        if queued.partIndex == ExquisiteCorpsePartKind.head.rawValue {
            base = RemoteExquisiteCorpseFigure(
                id: queued.figureID,
                number: game.figureNumber,
                starterUserID: userID,
                createdAt: queued.createdAt,
                finishedAt: nil,
                myRevealSeenAt: nil,
                parts: []
            )
        } else if let current = state.currentFigure, current.id == queued.figureID {
            base = current
        } else {
            return nil
        }
        let part = RemoteExquisiteCorpsePart(
            id: queued.partID,
            partIndex: queued.partIndex,
            drawerUserID: userID,
            createdAt: queued.createdAt,
            stripMediaAssetID: nil,
            drawingMediaAssetID: nil,
            idea: queued.idea
        )
        let parts = (base.parts.filter { $0.partIndex != queued.partIndex } + [part])
            .sorted { $0.partIndex < $1.partIndex }
        let isLegs = ExquisiteCorpsePartKind(rawValue: queued.partIndex)?.next == nil
        return RemoteExquisiteCorpseFigure(
            id: base.id,
            number: base.number,
            starterUserID: base.starterUserID,
            createdAt: base.createdAt,
            finishedAt: isLegs ? queued.createdAt : base.finishedAt,
            myRevealSeenAt: base.myRevealSeenAt,
            parts: parts
        )
    }

    /// It is this person's turn once the partner's part hands it over, also while the
    /// last figure's reveal is still on screen. Every part the server takes moves the
    /// turn to the other partner, so each of this person's parts follows one of the
    /// partner's, except the very first head, which goes to whoever started the game.
    static func attention(
        resolution: ExquisiteCorpseResolution,
        game: RemoteExquisiteCorpseGame?
    ) -> GameAttention {
        guard resolution.turnPhase == .drawing, let game,
              game.figureNumber > 1 || game.partIndex > ExquisiteCorpsePartKind.head.rawValue
        else {
            return GameAttention()
        }
        return GameAttention(turn: "figure \(game.figureNumber) part \(game.partIndex)")
    }

    /// The latest finished figure, when this person has not moved past its reveal.
    /// Only the latest counts, so a person who missed several sees one and not
    /// the whole history.
    private func unseenFigure(
        state: RemoteExquisiteCorpseState,
        pending: ExquisiteCorpsePendingWork
    ) -> RemoteExquisiteCorpseFigure? {
        guard let latest = state.recentFigures.filter(\.isFinished).max(by: { $0.number < $1.number }),
              latest.myRevealSeenAt == nil,
              !pending.hasRevealSeen(figureID: latest.id)
        else {
            return nil
        }
        return latest
    }
}
