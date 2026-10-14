import Foundation
import UIKit

// What the person does: start the game, move, write a stake, play again, invite
// the partner, and draw a mark.
extension BoardGameViewModel {
    /// Creates the couple's game of this kind. Needs a connection.
    func startGame() async {
        guard !isStarting else { return }
        isStarting = true
        defer { isStarting = false }
        do {
            let game = try await dependencies.boardGamesGateway.ensureGame(kind)
            if let userID = currentUserID {
                await dependencies.boardGamesCache.saveGame(game, ownerUserID: userID)
            }
            await refresh()
        } catch {
            phase = .unavailable
        }
    }

    /// Plays a move on the board at once and saves it on this phone. The sync
    /// sends it.
    func play(_ move: Int) async {
        guard canPlay, let snapshot, board.isLegal(move) else { return }
        let isFirstMove = displayedMoves.isEmpty
        let stake = isFirstMove ? BoardGameStake.committed(BoardGameStake.clamp(stakeDraft).text) : nil
        let payload = BoardGameMovePayload(
            kind: kind,
            gameID: snapshot.id,
            gameNumber: snapshot.gameNumber,
            expectedVersion: snapshot.version,
            move: move,
            stake: stake,
            createdAt: dependencies.now()
        )
        localActionRevision += 1
        guard let event = step(move) else { return }
        // A Dots and Boxes box gives the mover another turn.
        if board.outcome == nil, board.next == me {
            extraTurnCount += 1
        }
        hasDisplay = true
        updateScreen()
        guard await enqueue(.move(payload)) else {
            // The move never left the screen, so the board goes back to the game.
            hasDisplay = false
            recompute()
            return
        }
        // After the save, so the result reads the tallies with this move in them.
        if board.outcome != nil {
            stageOutcome(animated: true, after: moveDuration(event))
        }
    }

    /// "Play again": the next game, started by the partner who did not start
    /// this one.
    func rematch() async {
        guard let snapshot, snapshot.isFinished, !isShowingMissedEnding else { return }
        let payload = BoardGameRematchPayload(
            kind: kind,
            gameID: snapshot.id,
            expectedVersion: snapshot.version,
            createdAt: dependencies.now()
        )
        PaeoniaHaptics.selection()
        localActionRevision += 1
        outcomeTask?.cancel()
        showsOutcome = false
        result = nil
        isResultCollapsed = false
        stakeDraft = ""
        extraTurnCount = 0
        // The new game shows from its start, not as an ending of the old one.
        hasDisplay = false
        if await !enqueue(.rematch(payload)) {
            // Nothing was saved, so the result and "Play again" come back.
            hasDisplay = true
            showsOutcome = true
            result = makeResult()
        }
    }

    /// "Try again" next to "We couldn't send your move yet".
    func retrySending() async {
        await localChangeSyncHandler?()
        await refresh()
    }

    /// Saves an action on this phone, shows its effect, and nudges the sync to
    /// send it now.
    @discardableResult
    func enqueue(_ action: BoardGamePendingAction) async -> Bool {
        guard let userID = currentUserID else { return false }
        do {
            try await dependencies.pendingOperationStore.enqueue(
                BoardGamePendingWork.request(
                    for: action,
                    ownerUserID: userID,
                    operation: dependencies.operationProvider.makeOperation()
                )
            )
        } catch {
            notice = .couldNotSaveMove
            return false
        }
        await reload()
        if let sync = localChangeSyncHandler {
            Task { await sync() }
        }
        return true
    }

    // MARK: - Invite

    /// "Tell [Name] you want to play". One invite every 15 minutes.
    func sendInvite() async {
        now = dependencies.now()
        updatePresence()
        guard invite == .available else { return }
        localInviteSentAt = dependencies.now()
        updatePresence()
        do {
            let result = try await dependencies.gateway.sendInvite(kind)
            localInviteSentAt = result.sentAt
        } catch let error as PaeoniaConvexError {
            if case .server(code: "53300", message: _) = error {
                // The server already counted an invite in the last 15 minutes.
                return
            }
            localInviteSentAt = nil
            notice = .couldNotSendInvite
        } catch {
            localInviteSentAt = nil
            notice = .couldNotSendInvite
        }
        updatePresence()
    }

    // MARK: - Marks

    func openMarkEditor() {
        markEditor = .live(
            savedMark: document.marks?.mine,
            initial: meInfo.style.initial,
            userID: currentUserID,
            dependencies: dependencies
        )
    }

    /// The drawn marks as template images, by owner. A mark rendered before
    /// for the same update is reused. Each render is cached by owner and update
    /// time.
    func renderedMarks(
        _ marks: RemoteBoardGameMarks?,
        userID: UUID,
        partnerID: UUID?
    ) async -> [UUID: (key: String, image: UIImage)] {
        var images: [UUID: (key: String, image: UIImage)] = [:]
        let owners: [(UUID?, RemoteBoardGameMark?)] = [(userID, marks?.mine), (partnerID, marks?.partner)]
        for case let (owner?, mark?) in owners {
            let key = "\(owner.uuidString):\(mark.updatedAt.timeIntervalSince1970)"
            if let kept = markImages[owner], kept.key == key {
                images[owner] = kept
                continue
            }
            guard let data = BoardMarkRenderer.data(fromBase64: mark.drawing),
                  let image = await BoardMarkRenderer.image(from: data, cacheKey: key)
            else { continue }
            images[owner] = (key, image)
        }
        return images
    }

    // MARK: - Derived screen state

    /// The players' names, photos, colors and marks.
    func updatePeople() {
        let myInitial = BoardPieceStyle.initial(of: participants.currentName)
        let theirInitial = BoardPieceStyle.initial(of: participants.partnerName)
        let mine = BoardPieceStyle(
            color: .boardGameMine,
            mark: currentUserID.flatMap { markImages[$0]?.image },
            initial: myInitial
        )
        let theirs = BoardPieceStyle(
            color: .boardGamePartner,
            mark: partnerUserID.flatMap { markImages[$0]?.image },
            initial: theirInitial
        )
        styles = me == .one ? BoardPieceStyles(one: mine, two: theirs) : BoardPieceStyles(one: theirs, two: mine)
        meInfo = BoardGamePlayerInfo(
            name: participants.currentName,
            photoAssetID: participants.currentPhotoAssetID,
            style: mine
        )
        partnerInfo = BoardGamePlayerInfo(
            name: participants.partnerName,
            photoAssetID: participants.partnerPhotoAssetID,
            style: theirs
        )
    }

    /// Whether the partner has this game open, and the invite button.
    func updatePresence() {
        let presence = overview?.presence(for: kind)
        let isHere = presence?.partnerPresent == true
        partnerStatus = isHere ? .here : .away
        invite = GameInviteState.make(
            lastInviteAt: presence?.lastInviteAt,
            localSentAt: localInviteSentAt,
            partnerIsHere: isHere,
            now: now
        )
    }

    /// The turn line, the stake, the score and the photo, from the board on
    /// screen.
    func updateScreen() {
        guard let snapshot, let userID = currentUserID else { return }
        updatePeople()
        if let outcome = board.outcome {
            if let winner = outcome.winner {
                turnLabel = winner == me ? .youWon : .partnerWon
            } else {
                turnLabel = .draw
            }
        } else {
            turnLabel = board.next == me ? .yourTurn : .partnerTurn
        }
        if isShowingMissedEnding {
            stakeState = missedEnding?.stake.map { .fixed($0) } ?? .hidden
        } else if snapshot.moves.isEmpty, snapshot.player(for: userID) == .one {
            stakeState = .writable
        } else {
            stakeState = snapshot.stake.map { .fixed($0) } ?? .hidden
        }
        // The capsule keeps the old tally while the board celebrates, so the
        // result panel is the first to count it up.
        let isCelebrating = snapshot.isFinished && result == nil && !isShowingMissedEnding
        if !isCelebrating || score == nil {
            score = Self.score(snapshot, playStyle: overview?.settings?.playStyle ?? .against)
        }
        loadPhoto(isShowingMissedEnding ? missedEnding?.photoMediaAssetID : snapshot.photoMediaAssetID)
    }

    nonisolated static func score(_ snapshot: BoardGameSnapshot<Board>, playStyle: GamePlayStyle) -> BoardGameScore {
        switch playStyle {
        case .against: .against(mine: snapshot.myWins, partner: snapshot.partnerWins)
        case .together: .together(games: snapshot.gamesFinished)
        }
    }

    func updateSummary(_ snapshot: BoardGameSnapshot<Board>, userID: UUID) {
        let me = snapshot.player(for: userID)
        let status: BoardGameHubSummary.Status = if let outcome = snapshot.board.outcome {
            if let winner = outcome.winner {
                winner == me ? .youWon : .partnerWon
            } else {
                .draw
            }
        } else {
            snapshot.board.next == me ? .yourTurn : .partnerTurn
        }
        summary = BoardGameHubSummary(
            status: status,
            score: Self.score(snapshot, playStyle: overview?.settings?.playStyle ?? .against)
        )
    }

    /// Loads the hidden photo of a Dots and Boxes game. A photo that can't load
    /// leaves plain boxes.
    private func loadPhoto(_ assetID: UUID?) {
        guard assetID != photoAssetID else { return }
        photoAssetID = assetID
        photoTask?.cancel()
        photo = nil
        guard let assetID, let provider = dependencies.memoryPhotos else { return }
        photoTask = Task { [weak self] in
            guard let data = await provider.imageData(for: assetID), !Task.isCancelled else { return }
            let image = await MemoryImageDecoding.downsample(data, maxPixelSize: 1_200)
            guard let self, !Task.isCancelled, photoAssetID == assetID else { return }
            photo = image
        }
    }
}
