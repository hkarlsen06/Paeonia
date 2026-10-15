import Foundation

/// What the Games hub shows for Exquisite corpse.
nonisolated struct ExquisiteCorpseHubSummary: Equatable, Sendable {
    enum Status: Equatable, Sendable {
        /// The couple has not played yet.
        case notStarted
        /// This person draws the part.
        case yourTurn(ExquisiteCorpsePartKind)
        case partnerDrawing(ExquisiteCorpsePartKind)
        /// A finished creature this person has not looked at. It comes before the next turn.
        case revealReady
        /// This person's legs are saved on the phone and the creature is not finished
        /// on the server yet. The partner starts the next one.
        case partnerStarting
    }

    let status: Status
    /// How many creatures the couple has finished.
    let figuresFinished: Int

    init(status: Status, figuresFinished: Int = 0) {
        self.status = status
        self.figuresFinished = figuresFinished
    }

    /// Who is here comes from the shared overview (`GamesViewModel.partnerIsHere(in:)`).
    init(state: RemoteExquisiteCorpseState, resolution: ExquisiteCorpseResolution) {
        self.init(
            status: Self.status(for: resolution),
            figuresFinished: state.game?.figuresFinished ?? 0
        )
    }

    /// "Our creatures" has something to show.
    var hasCreatures: Bool {
        figuresFinished > 0
    }

    /// A reveal comes first, and the hub shows it as the thing waiting for this
    /// person. Any other phase is the turn itself.
    private static func status(for resolution: ExquisiteCorpseResolution) -> Status {
        if resolution.phase == .reveal {
            return .revealReady
        }
        let part = resolution.part ?? .head
        switch resolution.turnPhase {
        case .loading, .needsSetup, .preparing, .reveal:
            return .notStarted
        case .drawing:
            return .yourTurn(part)
        case .waiting, .watching:
            return .partnerDrawing(part)
        case .waitingToSync:
            return .partnerStarting
        }
    }
}
