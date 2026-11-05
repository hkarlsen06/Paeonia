import Foundation

extension PiccanteViewModel {
    func act(_ action: PiccanteAction, size: Int? = nil, tile: Int? = nil) async {
        guard let game, let userID, !isSaving else { return }
        let chosen = tile ?? selected
        if action == .seen, !noteRevealed { return }
        if action == .hide, chosen == nil || !PiccanteRules.validNote(note) { return }
        if action == .bite, chosen.map({ PiccanteRules.canBite($0, in: game, userID: userID) }) != true { return }
        if action == .sniff, chosen.map({ PiccanteRules.canSniff($0, in: game, userID: userID) }) != true { return }
        let move = PiccanteMove(
            action: action, gameID: game.id, gameNumber: game.gameNumber,
            expectedVersion: game.version, tile: action == .hide || action == .bite || action == .sniff ? chosen : nil,
            size: size,
            note: action == .hide && !note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? note.trimmingCharacters(in: .whitespacesAndNewlines) : nil)
        if action == .bite {
            PaeoniaHaptics.selection()
        }
        isSaving = true
        defer { isSaving = false }
        let operation = dependencies.operationProvider.makeOperation()
        if action == .sniff {
            do {
                let loaded = try await dependencies.piccanteGateway.sendPiccante(move, operation: operation)
                await dependencies.piccanteCache.saveState(loaded, ownerUserID: userID)
                PaeoniaHaptics.selection()
                GameSound.piccanteSniff.play(volume: 0.2)
                await reload()
            } catch { notice = .piccanteSniffFailed(PaeoniaFailure(error)) }
            return
        }
        do {
            try await dependencies.pendingOperationStore.enqueue(
                PendingSyncOperationRequest(
                    ownerUserID: userID,
                    operation: operation, operationKind: action.pendingKind,
                    idempotencyScope: "piccante:\(game.id):\(game.gameNumber):\(action.rawValue):\(game.version)",
                    requestData: try JSONEncoder().encode(move)))
            lastMove = move
            if action == .seen || action == .rematch { deferredResult = game.gameNumber }
            if action == .hide {
                note = ""
                PaeoniaHaptics.selection()
                GameSound.piccanteHide.play(volume: 0.22)
            }
            await reload()
            LocalStoreChanges.post(.games, ownerUserID: userID)
            if let sync { Task { await sync() } }
        } catch { notice = .couldNotSaveMove }
    }
    func continueResult() async {
        guard let game else { return }
        await act(.seen)
        deferredResult = game.gameNumber
        await reload()
    }
    func retry() async {
        await sync?()
        await refresh()
    }
}
