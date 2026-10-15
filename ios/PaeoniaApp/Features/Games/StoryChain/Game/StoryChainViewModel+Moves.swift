import Foundation

/// The opening the starter picked.
nonisolated enum StoryChainOpeningChoice: Equatable, Sendable {
    case opening(RemoteStoryOpening)
    /// The starter writes the first sentence themselves.
    case own
}

/// The word this person gives the partner with the line they are writing.
nonisolated struct StoryChainDare: Equatable, Sendable {
    let word: String
    /// The suggested word's id. Nil for a word the person typed.
    let wordID: String?
}

/// A finished story as the reveal shows it.
nonisolated struct StoryChainFinishedStory: Equatable, Sendable {
    let storyID: UUID
    let storyNumber: Int
    let title: String
    let finishedAt: Date
    let lineCount: Int
    /// Dare words that the next line used.
    let dareCount: Int
    /// This person gave the story its title, so their button starts the next story.
    let isNamer: Bool
}

// The moves. Each one is written to the pending operations first and sent in the
// background, so it works offline. The screen reacts to the saved move at once
// through `recompute()`.
extension StoryChainViewModel {
    // MARK: - What the composer knows

    /// The number the line being written will get.
    var nextLineNumber: Int {
        guard let story, story.story.state == .writing else { return 1 }
        return story.story.lines.count + 1
    }

    /// The word the partner dared this person to use in this line.
    var dareForMe: String? {
        phase == .writing ? story?.story.lines.last?.dareWord : nil
    }

    var lineCheck: StoryChainLineCheck {
        StoryChainLineCheck(draft: draft, dare: dareForMe)
    }

    /// The writer may make this line the last one.
    var canEndHere: Bool {
        phase == .writing && StoryChainRules.canEnd(lineNumber: nextLineNumber)
    }

    /// This line is the last one whatever the switch says.
    var mustEndHere: Bool {
        phase == .writing && StoryChainRules.mustEnd(lineNumber: nextLineNumber)
    }

    /// The line is the last one: the switch is on, or the story ends here anyway.
    /// Turning it on takes the dare away, because nobody writes after it.
    var isLastLine: Bool {
        get { mustEndHere || (canEndHere && wantsLastLine) }
        set {
            guard canEndHere else { return }
            wantsLastLine = newValue
            if newValue {
                dareToGive = nil
            }
            sendDraftLive()
        }
    }

    /// "Give [Name] a word" is available.
    var canGiveDare: Bool {
        phase == .writing && !isLastLine
    }

    var canSend: Bool {
        phase == .writing && !isSavingMove && lineCheck.canSend
    }

    var canName: Bool {
        phase == .naming && !isSavingMove && StoryChainRules.normalizedTitle(titleDraft) != nil
    }

    // MARK: - Starting a story

    /// Starts the story with the picked opening, or with no opening for the
    /// person's own first line. The screen moves to writing at once.
    func startStory() async {
        guard phase == .chooseOpening, !isSavingMove, let userID = currentUserID, let gameID = state?.game?.id,
              let choice = selectedOpening
        else { return }
        var start = StoryChainQueuedStart(storyID: UUID(), gameID: gameID, createdAt: dependencies.now())
        if case let .opening(opening) = choice {
            start.openingID = opening.openingID
            start.openingText = opening.text
        }
        isSavingMove = true
        defer { isSavingMove = false }
        PaeoniaHaptics.drawingSent()
        GameSound.send.play()
        do {
            try await moveQueue.start(start, ownerUserID: userID)
        } catch {
            notice = .couldNotSaveMove
            return
        }
        selectedOpening = nil
        await afterLocalChange()
    }

    // MARK: - The dare

    func giveDare(_ word: RemoteStoryDareWord) {
        guard canGiveDare else { return }
        dareToGive = StoryChainDare(word: word.word, wordID: word.wordID)
    }

    /// Gives the partner a word the person typed. False when it is not one word
    /// of 2 to 20 letters.
    func giveOwnDare(_ text: String) -> Bool {
        guard canGiveDare, let word = StoryChainRules.normalizedDareWord(text) else { return false }
        dareToGive = StoryChainDare(word: word, wordID: nil)
        return true
    }

    func removeDare() {
        dareToGive = nil
    }

    // MARK: - Writing a line

    /// Sends the line. It is saved on the phone first and goes out when the phone
    /// is online. The partner's page gets it at once when they have the game open.
    func sendLine() async {
        let check = lineCheck
        guard canSend, let userID = currentUserID, let storyID = story?.id else { return }
        let sentDraft = draft
        let number = nextLineNumber
        let isLast = isLastLine
        let dare = isLast ? nil : dareToGive
        let line = StoryChainQueuedLine(
            storyID: storyID,
            lineID: UUID(),
            text: check.text,
            isLast: isLast,
            dareWord: dare?.word,
            dareWordID: dare?.wordID,
            createdAt: dependencies.now()
        )
        isSavingMove = true
        defer { isSavingMove = false }
        PaeoniaHaptics.drawingSent()
        GameSound.send.play()
        // Before the queue reads the line back, so the first page that has it
        // already writes it in.
        beginArrival(of: line.lineID, isMine: true)
        do {
            try await moveQueue.addLine(line, ownerUserID: userID)
        } catch {
            arrivingLineID = nil
            animatedLineIDs.remove(line.lineID)
            notice = .couldNotSaveMove
            return
        }
        sendLineLive(line, number: number)
        // Words typed while the line was being saved were not part of it, so they
        // stay. A composer that changed in another way keeps everything.
        let remainder = draft == sentDraft ? "" :
            draft.hasPrefix(sentDraft) ? String(draft.dropFirst(sentDraft.count)) : draft
        dareToGive = nil
        wantsLastLine = false
        draft = remainder.trimmingCharacters(in: .whitespacesAndNewlines)
        // Written now and whatever the phase, so the sent words never come back.
        writeDraftNow(draft, ownerUserID: userID)
        await afterLocalChange()
    }

    // MARK: - Naming

    /// Gives the finished story its title. The reveal shows at once.
    func nameStory() async {
        guard canName, let userID = currentUserID, let storyID = story?.id,
              let title = StoryChainRules.normalizedTitle(titleDraft)
        else { return }
        isSavingMove = true
        isNamingInFlight = true
        // The queued name moves the resolver on to choosing an opening. This keeps
        // the reveal on screen instead.
        revealedStoryID = storyID
        defer {
            isSavingMove = false
            isNamingInFlight = false
        }
        do {
            try await moveQueue.name(StoryChainQueuedName(storyID: storyID, title: title), ownerUserID: userID)
        } catch {
            revealedStoryID = nil
            notice = .couldNotSaveMove
            return
        }
        await afterLocalChange()
    }

    // MARK: - The finished story

    /// Leaves the reveal. The person who named the story goes on to choosing the
    /// next opening. The other partner's "I have seen this story" mark is saved on
    /// the phone first, so the screen moves on without the network.
    func continueFromFinished() async {
        guard case let .finished(storyID) = phase, !isSavingMove, let userID = currentUserID else { return }
        if revealedStoryID == storyID {
            // The name already marked the story as seen.
            revealedStoryID = nil
            titleDraft = ""
            recompute()
            return
        }
        isSavingMove = true
        defer { isSavingMove = false }
        do {
            try await moveQueue.markSeen(storyID: storyID, ownerUserID: userID)
        } catch {
            notice = .couldNotSaveMove
            return
        }
        await afterLocalChange()
    }

    /// The finished story the phase names, with what the reveal counts.
    func makeFinished() -> StoryChainFinishedStory? {
        guard case let .finished(storyID) = phase, let story, story.id == storyID else { return nil }
        let remote = story.story
        let dareCount = zip(remote.lines, remote.lines.dropFirst()).count { line, next in
            line.dareWord.map { StoryChainRules.lineUses(next.text, dare: $0) } == true
        }
        return StoryChainFinishedStory(
            storyID: storyID,
            storyNumber: remote.storyNumber,
            title: remote.title ?? "",
            finishedAt: remote.finishedAt ?? localFinishedDate(of: storyID),
            lineCount: remote.lines.count,
            dareCount: dareCount,
            isNamer: remote.titledByUserID == currentUserID
        )
    }

    /// The time a story was named on this phone, before the server has its own.
    /// It stays the same, so the byline does not change on every tick.
    private func localFinishedDate(of storyID: UUID) -> Date {
        if let date = localFinishedDates[storyID] {
            return date
        }
        localFinishedDates[storyID] = now
        return now
    }

    // MARK: - Resetting

    /// A new line or a new story to name starts with an empty composer.
    func resetComposerForNewTurn() {
        if phase != .writing {
            // The line that went out live is on its way. A refused line can come back.
            liveSentKey = nil
        }
        let key = phase == .writing ? story.map { StoryChainWritingKey(storyID: $0.id, number: nextLineNumber) } : nil
        if let key, key != writingKey {
            // A new line to write. Words still in the composer were never sent,
            // such as when another phone of this person moved the story on, so
            // they stay. A sent line has already emptied it.
            dareToGive = nil
            wantsLastLine = false
            writingKey = key
        }
        if phase == .naming, let storyID = story?.id, storyID != namingStoryID {
            titleDraft = ""
            namingStoryID = storyID
        }
    }

    func resetComposer() {
        draft = ""
        dareToGive = nil
        wantsLastLine = false
    }

    // MARK: - The saved draft

    /// How long typing pauses before the draft is written to the phone.
    static let draftSaveDelay: Duration = .milliseconds(500)

    /// Keeps the composer's text on the phone, so leaving the app loses nothing.
    /// An empty composer forgets it.
    func saveDraftSoon() {
        guard phase == .writing, let userID = currentUserID else { return }
        let value = draft.isEmpty ? nil : draft
        guard value != lastDraftWritten else { return }
        lastDraftWritten = value
        draftSaveTask?.cancel()
        draftSaveTask = Task { [weak self, sleep = self.sleep, cache = self.dependencies.storyChainCache] in
            // An empty composer is written at once, so a sent line never comes back.
            if value != nil {
                guard (try? await sleep(Self.draftSaveDelay)) != nil, !Task.isCancelled else { return }
            }
            await cache.saveDraft(value, ownerUserID: userID)
            self?.savedDraft = value
        }
    }

    /// Writes the composer's text at once, or forgets it when empty.
    func writeDraftNow(_ text: String, ownerUserID: UUID) {
        draftSaveTask?.cancel()
        draftSaveTask = nil
        let value = text.isEmpty ? nil : text
        lastDraftWritten = value
        savedDraft = value
        Task { [cache = self.dependencies.storyChainCache] in
            await cache.saveDraft(value, ownerUserID: ownerUserID)
        }
    }

    /// Writes a draft that still waits for the typing pause, such as when the
    /// screen closes.
    func saveDraftNow() {
        guard let task = draftSaveTask, let userID = currentUserID else { return }
        task.cancel()
        draftSaveTask = nil
        let value = lastDraftWritten
        Task { [cache = self.dependencies.storyChainCache] in
            await cache.saveDraft(value, ownerUserID: userID)
        }
    }

    /// Puts the saved text back into an empty composer after a relaunch, and adds
    /// the words of refused lines to the composer, so neither is lost.
    func restoreDraftIfNeeded() {
        guard phase == .writing else { return }
        if mayRestoreSavedDraft {
            mayRestoreSavedDraft = false
            if draft.isEmpty, let saved = savedDraft, saved != lastDraftWritten, !isAlreadyWritten(saved) {
                draft = saved
            }
        }
        takeRescuedLines()
    }

    /// The text is a line of the story already, sent or queued, such as when the
    /// app stopped right after Send and before the draft was forgotten.
    private func isAlreadyWritten(_ text: String) -> Bool {
        let line = StoryChainRules.normalizeText(text)
        let stories = [story?.story, state?.previousStory].compactMap(\.self)
        return stories.contains { $0.lines.contains { $0.text == line } }
    }

    /// Moves the rescued lines into the composer. The cache saves them with the
    /// composer's text as the draft in one step, so a crash right after never
    /// loses them. They then join whatever the composer holds by now, edits made
    /// meanwhile included, and that is written at once.
    private func takeRescuedLines() {
        guard hasRescuedLines, !isTakingRescuedLines, let userID = currentUserID else { return }
        isTakingRescuedLines = true
        hasRescuedLines = false
        // A save of the composer from before must not land over the rescued words.
        draftSaveTask?.cancel()
        draftSaveTask = nil
        let cache = dependencies.storyChainCache
        let composerText = draft
        Task { [weak self] in
            let rescued = await cache.takeRescuedLines(into: composerText, ownerUserID: userID)
            guard let self else { return }
            isTakingRescuedLines = false
            guard let rescued, currentUserID == userID else { return }
            let combined = [draft, rescued].filter { !$0.isEmpty }.joined(separator: " ")
            writeDraftNow(combined, ownerUserID: userID)
            draft = combined
        }
    }

    // MARK: - Queueing

    /// Shows the effect of a saved move and nudges the sync to send it now.
    func afterLocalChange() async {
        await reload()
        if let sync = syncAfterLocalChange {
            Task { await sync() }
        }
    }

    /// "Try again" on the waiting screen: sends what waits now, then reads the
    /// server's state.
    func retrySend() async {
        await syncAfterLocalChange?()
        await refresh()
    }
}
