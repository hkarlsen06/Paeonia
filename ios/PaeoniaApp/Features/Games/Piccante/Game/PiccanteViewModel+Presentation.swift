import SwiftUI
import Observation

extension PiccanteViewModel {
    func beginReplay(from shown: PiccanteShownPosition?) {
        guard let game else { return }
        let number = game.gameNumber
        let ownLastBite = game.bites.lastIndex { $0.userID == userID }.map { $0 + 1 } ?? 0
        let fallback = min(ownLastBite, max(0, game.bites.count - 1))
        let count = shown?.number == number ? min(shown?.bites ?? 0, game.bites.count) : fallback
        shownBites = count
        revealSettled = game.phase == .finished && shownBites == game.bites.count
        noteRevealed = revealSettled
        burnRevealed = revealSettled
        replayTask = Task { [weak self] in
            guard let self else { return }
            await replayBites(in: game, from: count)
            guard !Task.isCancelled else { return }
            replayTask = nil
            if self.game?.gameNumber != number || self.game?.bites.count != game.bites.count { await reload() }
        }
    }
    private func replayBites(in game: RemotePiccanteGame, from count: Int) async {
        GameSoundPlayer.shared.prepare()
        for index in count..<game.bites.count {
            let plan = PiccantePlayback.plan(
                bite: game.bites[index], clock: playbackClock, reduceMotion: reduceMotion, now: Date())
            await wait(until: plan.startsAt)
            guard !Task.isCancelled, self.game?.gameNumber == game.gameNumber else { return }
            shownBites = index + 1
            if plan.playsSound {
                GameSound.piccanteBite.play(
                    variation: PiccantePlayback.variation(gameNumber: game.gameNumber, biteIndex: index))
                PaeoniaHaptics.selection()
            }
            if game.phase == .finished && index == game.bites.count - 1 {
                if reduceMotion {
                    burnRevealed = true
                    revealSettled = true
                    noteRevealed = true
                } else {
                    await revealBurn(startingAt: plan.startsAt)
                }
            }
            guard !Task.isCancelled else { return }
            await saveShown(number: game.gameNumber)
        }
    }

    private func revealBurn(startingAt start: Date) async {
        // Every reveal stage follows the shared bite deadline.
        await wait(until: start.addingTimeInterval(0.32))
        guard !Task.isCancelled else { return }
        burnRevealed = true
        burnShake += 1
        PaeoniaHaptics.answerRevealed()
        GameSound.piccanteBurn.play(variation: 0)
        await wait(until: start.addingTimeInterval(0.72))
        guard !Task.isCancelled else { return }
        withAnimation(reduceMotion ? nil : PaeoniaMotion.stateChange) { revealSettled = true }
        await wait(until: start.addingTimeInterval(0.96))
        guard !Task.isCancelled else { return }
        withAnimation(reduceMotion ? nil : PaeoniaMotion.meaningfulMoment) { noteRevealed = true }
        if !reduceMotion, let game, Set(game.chilis.map(\.tile)).count == 1 {
            GameSound.piccanteSameOne.play(variation: 0)
        }
    }

    private func wait(until deadline: Date) async {
        let delay = PiccantePlayback.delay(until: deadline, now: Date())
        if delay > 0 { try? await Task.sleep(for: .seconds(delay)) }
    }

    func startPlaybackClock() {
        guard playbackClock == nil, playbackClockTask == nil else { return }
        let gateway = dependencies.piccanteGateway
        playbackClockTask = Task { [weak self] in
            var shortestTrip = TimeInterval.infinity
            for _ in 0..<3 {
                let sent = Date()
                guard let server = try? await gateway.samplePiccanteClock(), !Task.isCancelled else { break }
                let received = Date()
                let trip = received.timeIntervalSince(sent)
                if trip < shortestTrip {
                    shortestTrip = trip
                    self?.playbackClock = PiccantePlaybackClock(serverTime: server, sentAt: sent, receivedAt: received)
                }
            }
            guard !Task.isCancelled else { return }
            self?.playbackClockTask = nil
        }
    }

    private func saveShown(number: Int) async {
        if let userID {
            await dependencies.piccanteCache.saveShown(.init(number: number, bites: shownBites), ownerUserID: userID)
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
        startPlaybackClock()
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
        if partnerSelected != lastHeartbeatLift {
            if partnerSelected != nil, partnerSelected == game.myChili {
                PaeoniaHaptics.revealBuildUp(intensity: 0.35)
            }
            lastHeartbeatLift = partnerSelected
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
        localInviteSentAt = dependencies.now()
        let delivery = await GameInviteDelivery.send(.piccante, through: dependencies.gateway)
        localInviteSentAt = delivery.localSentAt(optimistic: localInviteSentAt)
        if let failure = delivery.failure {
            notice = .couldNotSendInvite(failure)
        }
        await reload()
    }
}
