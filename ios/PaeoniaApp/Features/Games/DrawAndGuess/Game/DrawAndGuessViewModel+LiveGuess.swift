import PencilKit
import QuartzCore

/// The guesser's screen as the drawer sees it on the result screen: the letters
/// in the slots, and the replay at the point the guesser is watching.
struct DrawAndGuessPartnerGuess: Equatable {
    let roundID: UUID
    let slots: DrawAndGuessSlots
    /// The full word was wrong, and the tiles are going back.
    let isWrong: Bool
    /// Goes up with each wrong word, to shake the slots.
    let wrongCount: Int
    /// Nil while the guesser looks at the live canvas, which already shows the
    /// whole drawing, or their drawing is still loading.
    let replayClock: DrawAndGuessReplayClock?
}

/// The partner's latest guess screen, as it arrived on the drawer's phone.
struct DrawAndGuessReceivedGuessScreen {
    let message: DrawAndGuessLiveMessage
    /// `monotonicNow()` on arrival, where the message's replay time was current.
    let receivedAt: TimeInterval
    /// Wrong words seen this round, to shake the slots once each.
    let wrongCount: Int
}

/// What the guesser's phone last sent, so the same screen is not sent twice.
struct DrawAndGuessSentGuessScreen: Equatable {
    let round: UUID
    let letters: [String?]
    let isWrong: Bool
    let clock: DrawAndGuessReplayClock?
}

// The guess screen over the live room. The guesser's phone sends it with
// `DrawAndGuessLiveMessage`, and the drawer's result screen shows it.
extension DrawAndGuessViewModel {
    // MARK: - Guesser

    /// Sends the guess screen when it changed since the last send. Called when the
    /// slots or the replay change, and after every recompute.
    func sendGuessScreen() {
        guard let channel = liveGuessChannel else { return }
        guard let message = guessScreenMessage() else {
            lastSentGuessScreen = nil
            return
        }
        let sent = DrawAndGuessSentGuessScreen(
            round: message.round,
            letters: message.letters,
            isWrong: message.isWrong,
            clock: message.replay == nil ? nil : replayClock
        )
        guard sent != lastSentGuessScreen else { return }
        lastSentGuessScreen = sent
        channel.send(message)
    }

    /// The partner may have missed the last screen, so it goes again.
    func resendGuessScreen() {
        lastSentGuessScreen = nil
        sendGuessScreen()
    }

    private func guessScreenMessage() -> DrawAndGuessLiveMessage? {
        guard phase.allowsGuessing, let round, let userID = currentUserID,
              round.guesserUserID == userID, tilesRoundID == round.id
        else { return nil }
        let replay = guessSource == .replay
            ? replayClock.map { clock in
                DrawAndGuessLiveMessage.Replay(time: clock.replayTime(at: monotonicNow()), rate: clock.rate)
            }
            : nil
        return DrawAndGuessLiveMessage(
            round: round.id,
            letters: slots.slots.map { slot in slot.tile.map { String($0.letter) } },
            isWrong: isShowingWrongGuess,
            replay: replay
        )
    }

    // MARK: - Drawer

    /// Keeps the partner's latest screen. It may arrive before this phone has
    /// loaded the round or its drawing, so `updatePartnerGuess()` applies it on
    /// every change.
    func receiveGuessScreen(_ message: DrawAndGuessLiveMessage) {
        let previous = receivedGuessScreen?.message.round == message.round ? receivedGuessScreen : nil
        let turnedWrong = message.isWrong && previous?.message.isWrong != true
        receivedGuessScreen = DrawAndGuessReceivedGuessScreen(
            message: message,
            receivedAt: monotonicNow(),
            wrongCount: (previous?.wrongCount ?? 0) + (turnedWrong ? 1 : 0)
        )
        updatePartnerGuess()
    }

    /// Shows the partner's screen only while they are on it, for this round. It
    /// reads the live room, because `partnerPresence` waits for the next recompute.
    func updatePartnerGuess() {
        if live?.partnerActivity != .watching {
            receivedGuessScreen = nil
        }
        guard let received = receivedGuessScreen, let userID = currentUserID, let round,
              round.isDrawer(userID), !round.isFinished, received.message.round == round.id
        else {
            if partnerGuess != nil { partnerGuess = nil }
            return
        }
        let message = received.message
        // Anchored at arrival, so a drawing that loads later picks up where the replay is now.
        let clock = message.replay.flatMap { replay in
            partnerReplayTimeline(for: round).map { timeline in
                DrawAndGuessReplayClock(
                    duration: timeline.duration,
                    replayTime: replay.time,
                    rate: replay.rate,
                    at: received.receivedAt
                )
            }
        }
        let guess = DrawAndGuessPartnerGuess(
            roundID: round.id,
            slots: DrawAndGuessSlots(answer: round.word, letters: message.letters.map { $0?.first }),
            isWrong: message.isWrong,
            wrongCount: received.wrongCount,
            replayClock: clock
        )
        if partnerGuess != guess { partnerGuess = guess }
    }

    /// The drawer's own drawing on the replay's time line. It is the drawing the
    /// guesser downloaded, so both replays take the same time.
    private func partnerReplayTimeline(for round: DrawAndGuessRoundView) -> DrawAndGuessReplayTimeline? {
        if let cached = partnerReplayTimelineCache, cached.roundID == round.id {
            return cached.timeline
        }
        guard let drawing = finalDrawing?.drawing else { return nil }
        let timeline = DrawAndGuessReplayTimeline(drawing: drawing)
        partnerReplayTimelineCache = (round.id, timeline)
        return timeline
    }

    /// The partner's replay for `DrawAndGuessReplaySurface`.
    var partnerReplayFrames: DrawAndGuessReplayFrames {
        DrawAndGuessReplayFrames(
            drawing: { [weak self] wall, side in
                guard let self, let clock = partnerGuess?.replayClock, let round,
                      let timeline = partnerReplayTimeline(for: round)
                else { return nil }
                return DrawAndGuessCanvas.fitted(timeline.drawing(at: clock.replayTime(at: wall)), toSide: side)
            },
            isFinished: { [weak self] wall in
                self?.partnerGuess?.replayClock?.isFinished(at: wall) ?? false
            }
        )
    }
}
