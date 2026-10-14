import Foundation

// Ludo only: the piece colors of the two players. Each player picks one for the
// game before their first move, and the pick goes to the server with that move.
// Until then this phone shows the pick on its own.
extension BoardGameViewModel {
    /// Whether this person has a move in `moves` of the game on screen.
    private func hasMoved(in moves: [Int], as player: BoardPlayer) -> Bool {
        Board.movers(moves)?.contains(player) ?? true
    }

    /// The color circles show until this person makes their first move of the
    /// game. Games without colors, a finished game and an ending from before
    /// have none.
    var canPickColor: Bool {
        guard let snapshot, let userID = currentUserID, snapshot.myColor != nil, snapshot.partnerColor != nil,
              snapshot.board.outcome == nil, !isShowingMissedEnding
        else { return false }
        let player = snapshot.player(for: userID)
        if hasMoved(in: snapshot.moves, as: player) {
            return false
        }
        // The move this phone just made shows before it is saved.
        return displayedGameNumber != snapshot.gameNumber || !hasMoved(in: displayedMoves, as: player)
    }

    /// The color this person tapped for this game, when it still counts: they have
    /// not moved yet, it is not their partner's color and it is not the color they
    /// already have. It goes with their first move.
    var pendingColorPick: LudoColor? {
        guard let snapshot, let userID = currentUserID, let draft = colorDraft,
              draft.gameNumber == snapshot.gameNumber,
              draft.color != snapshot.partnerColor, draft.color != snapshot.myColor,
              !hasMoved(in: snapshot.moves, as: snapshot.player(for: userID))
        else { return nil }
        return draft.color
    }

    /// The two colors the screen shows. Everything that has a piece color, such
    /// as the avatars, the pawns and the result, takes them from here.
    func currentColors() -> LudoColorPair {
        guard let snapshot, let mine = snapshot.myColor, let partner = snapshot.partnerColor else {
            return .standard
        }
        return LudoColorPair(mine: pendingColorPick ?? mine, partner: partner)
    }

    /// Updates the colors and the color circles from the game on screen.
    func updateColors() {
        let colors = currentColors()
        if ludoColors != colors {
            ludoColors = colors
        }
        let choice = canPickColor
            ? BoardGameColorChoice(colors: colors, partnerName: partnerName, partnerInitial: partnerInfo.style.initial)
            : nil
        if colorChoice != choice {
            colorChoice = choice
        }
    }

    /// A tap on a color circle. The color shows at once on both the screen and
    /// the board, and goes to the server with the first move.
    func pickColor(_ color: LudoColor) {
        guard canPickColor, let snapshot, color != snapshot.partnerColor, color != ludoColors.mine else { return }
        colorDraft = (snapshot.gameNumber, color)
        PaeoniaHaptics.selection()
        updatePeople()
        updateColors()
    }
}
