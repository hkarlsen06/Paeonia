import Foundation
import Observation

extension PiccanteViewModel {
    func beginReplay(from shown: PiccanteShownPosition?) {
        guard let game else { return }
        let number = game.gameNumber
        let ownLastBite = game.bites.lastIndex { $0.userID == userID }.map { $0 + 1 } ?? 0
        let fallback = game.phase == .finished ? min(ownLastBite, max(0, game.bites.count - 1)) : ownLastBite
        let count = shown?.number == number ? min(shown?.bites ?? 0, game.bites.count) : fallback
        shownBites = count
        revealSettled = game.phase == .finished && count == game.bites.count
        replayTask = Task { [weak self] in
            guard let self else { return }
            for index in count..<game.bites.count {
                guard !Task.isCancelled, self.game?.gameNumber == number else { break }
                if !reduceMotion { try? await Task.sleep(for: .seconds(0.32)) }
                guard !Task.isCancelled else { break }
                shownBites = index + 1
                GameSound.piccanteBite.play(volume: 0.55)
                PaeoniaHaptics.selection()
                if game.phase == .finished && index == game.bites.count - 1 {
                    if !reduceMotion { try? await Task.sleep(for: .seconds(0.5)) }
                    guard !Task.isCancelled else { break }
                    revealSettled = true
                    PaeoniaHaptics.answerRevealed()
                    GameSound.piccanteBurn.play(volume: 0.55)
                }
                if let userID {
                    await dependencies.piccanteCache.saveShown(
                        .init(number: number, bites: shownBites), ownerUserID: userID)
                }
            }
            if game.bites.isEmpty { revealSettled = false }
            replayTask = nil
            if self.game?.bites.count != game.bites.count { await reload() }
        }
    }
    func queueSeenOnExit(_ game: RemotePiccanteGame, userID: UUID) {
        let dependencies = dependencies
        let sync = sync
        let move = PiccanteMove(
            action: .seen, gameID: game.id, gameNumber: game.gameNumber, expectedVersion: game.version)
        let operation = dependencies.operationProvider.makeOperation()
        Task {
            do {
                try await dependencies.pendingOperationStore.enqueue(
                    PendingSyncOperationRequest(
                        ownerUserID: userID,
                        operation: operation, operationKind: .piccanteSeen,
                        idempotencyScope: "piccante-seen:\(game.id):\(game.gameNumber)",
                        requestData: try JSONEncoder().encode(move)))
                LocalStoreChanges.post(.games, ownerUserID: userID)
                await sync?()
            } catch {
                await dependencies.piccanteCache.refuse(move, ownerUserID: userID)
            }
        }
    }
    func startLive() {
        if live == nil, let coupleID = participants.coupleID {
            live = dependencies.makePiccanteLive(coupleID)
            if let live {
                let channel = GameLiveChannel<PiccanteLiveMessage>(connection: live.connection)
                channel.onMessage = { [weak self] in self?.receive($0) }
                self.channel = channel
                live.onPartnerArrived = { [weak self] in self?.sendSelection() }
            }
        }
        live?.start()
        liveObservation?.cancel()
        if let live {
            liveObservation = Task { [weak self] in
                for await _ in Observations({ live.partnerActivity }) {
                    guard !Task.isCancelled else { return }
                    await self?.reload()
                }
            }
        }
    }
    func sendSelection() {
        guard let game, game.phase == .biting, isMyTurn else { return }
        channel?.send(.init(gameNumber: game.gameNumber, version: game.version, selection: selected, reaction: nil))
    }
    func receive(_ message: PiccanteLiveMessage) {
        guard let game, game.phase == .biting, message.gameNumber == game.gameNumber,
            message.version == game.version, partnerHere
        else { return }
        if let reaction = message.reaction {
            reactions.show(reaction)
            return
        }
        guard !isMyTurn else { return }
        partnerSelected = message.selection.flatMap { tile in
            tile >= 0 && tile < (game.size ?? 0) * (game.size ?? 0) && !game.bites.contains(where: { $0.tile == tile })
                ? tile : nil
        }
    }
    func react(_ reaction: GameLiveReaction) {
        guard let game, game.phase == .biting, partnerHere else { return }
        reactions.show(reaction)
        channel?.send(
            .init(gameNumber: game.gameNumber, version: game.version, selection: selected, reaction: reaction))
    }
    func sendInvite() async {
        guard invite == .available else { return }
        do { localInviteSentAt = try await dependencies.gateway.sendInvite(.piccante).sentAt } catch {
            notice = .couldNotSendInvite(PaeoniaFailure(error))
        }
        await reload()
    }
}
