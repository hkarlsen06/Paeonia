import PencilKit

/// What the share sheet offers for a finished Draw & Guess drawing.
enum DrawAndGuessShare {
    /// The drawing on its plum canvas, with the word and who drew it under it.
    /// `drawing` is at the canonical canvas size, as the game keeps it.
    static func shareable(drawing: PKDrawing, word: String, drawer: GamePlayer) -> PaeoniaShareable {
        let game = String(localized: .gamesDrawAndGuessName)
        let subtitle = drawer.sharedName.map { String(localized: .shareDrawnBy($0, game)) } ?? game
        return PaeoniaShareable(title: word) {
            guard let ink = PaeoniaShareRenderer.inkImage(of: drawing, canvasSide: GameCanvas.canonicalSide) else {
                return nil
            }
            return PaeoniaShareCards.drawing(ink: ink, title: word, subtitle: subtitle)
        }
    }
}

extension DrawAndGuessViewModel {
    /// The finished drawing, once the round has ended. Nil before that, so a
    /// guesser never shares the answer early.
    var shareable: PaeoniaShareable? {
        guard phase == .reveal, let drawing = finalDrawing?.drawing, !drawing.strokes.isEmpty,
              let round, let userID = currentUserID
        else { return nil }
        return DrawAndGuessShare.shareable(
            drawing: drawing,
            word: DrawAndGuessAnswer.display(round.word),
            drawer: round.isDrawer(userID) ? me : partner
        )
    }
}
