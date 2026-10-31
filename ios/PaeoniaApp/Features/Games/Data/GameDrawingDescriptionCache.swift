import Foundation

extension GamesCaching {
    func updateDrawingDescription(_ edit: MediaAlternativeEdit, ownerUserID: UUID,
                                  privacyToken: LocalPrivacyWriteGuard.Token) {
        guard case let .drawAndGuess(roundID) = edit.target else { return }
        try? LocalPrivacyWriteGuard.shared.write(ownerUserID: ownerUserID, token: privacyToken) {
            let document = document(ownerUserID: ownerUserID)
            guard document.state == nil || document.state?.coupleID == edit.coupleID else { return }
            func update(_ round: RemoteDrawAndGuessRound) -> RemoteDrawAndGuessRound {
                var copy = round
                if round.id == roundID && round.drawerUserID == ownerUserID && round.drawingMediaAssetID != nil {
                    copy.drawingAccessibilityText = edit.text.trimmedNonEmpty
                }
                return copy
            }
            if var state = document.state {
                state.currentRound = state.currentRound.map(update)
                state.recentRounds = state.recentRounds.map(update)
                saveState(state, ownerUserID: ownerUserID)
            }
            if let page = document.drawings?.firstPage {
                let rounds = page.rounds.map { round in
                    var copy = round
                    if round.id == roundID && round.drawerUserID == ownerUserID {
                        copy.drawingAccessibilityText = edit.text.trimmedNonEmpty
                    }
                    return copy
                }
                saveHistoryFirstPage(RemoteDrawAndGuessHistoryPage(rounds: rounds,
                    nextBeforeRoundNumber: page.nextBeforeRoundNumber), ownerUserID: ownerUserID)
            }
        }
    }
}

extension ExquisiteCorpseCaching {
    func updateDrawingDescription(_ edit: MediaAlternativeEdit, ownerUserID: UUID,
                                  privacyToken: LocalPrivacyWriteGuard.Token) {
        guard case let .exquisiteCorpse(partID) = edit.target else { return }
        try? LocalPrivacyWriteGuard.shared.write(ownerUserID: ownerUserID, token: privacyToken) {
            let document = document(ownerUserID: ownerUserID)
            guard document.state == nil || document.state?.coupleID == edit.coupleID else { return }
            func update(_ figure: RemoteExquisiteCorpseFigure) -> RemoteExquisiteCorpseFigure {
                // A queued edit must not make a full description appear beside a fold strip.
                guard figure.isFinished else { return figure }
                var copy = figure
                for index in copy.parts.indices where copy.parts[index].id == partID &&
                    copy.parts[index].drawerUserID == ownerUserID {
                    copy.parts[index].drawingAccessibilityText = edit.text.trimmedNonEmpty
                }
                return copy
            }
            if var state = document.state {
                state.currentFigure = state.currentFigure.map(update)
                state.recentFigures = state.recentFigures.map(update)
                saveState(state, ownerUserID: ownerUserID)
            }
            if let page = document.history {
                saveHistoryFirstPage(RemoteExquisiteCorpseHistoryPage(figures: page.figures.map(update),
                    nextBeforeFigureNumber: page.nextBeforeFigureNumber), ownerUserID: ownerUserID)
            }
        }
    }
}
