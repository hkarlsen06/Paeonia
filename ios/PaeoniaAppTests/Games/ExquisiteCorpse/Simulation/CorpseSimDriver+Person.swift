import Foundation
import PencilKit
@testable import PaeoniaApp

// What a person does with the game: draws above and below the fold, clears, asks
// for an idea, taps Done, continues from the reveal, invites, leaves the screen.
extension CorpseSimDriver {
    /// Gets the phone to the game screen, or does the one thing it needs first. Nil until it is there.
    private func readyScreen(of phone: CorpseSimPhone) -> ExquisiteCorpseViewModel? {
        guard phone.isAlive else {
            phone.launch()
            return nil
        }
        guard phone.isForeground else {
            phone.moveToForeground()
            return nil
        }
        guard phone.isScreenOpen, let viewModel = phone.viewModel else {
            phone.openScreen()
            return nil
        }
        return viewModel
    }

    func act(as phone: CorpseSimPhone) async {
        guard let viewModel = readyScreen(of: phone) else { return }
        switch viewModel.phase {
        case .drawing:
            await draw(phone, viewModel)
        case .reveal:
            await reveal(phone, viewModel)
        case .waiting, .watching:
            wait(phone, viewModel)
        case .waitingToSync:
            log.add("\(phone.name) try again")
            Task { await viewModel.retrySending() }
        case .loading, .preparing, .needsSetup:
            if viewModel.startFailed {
                Task { await viewModel.retryStart() }
            }
        }
    }

    private func wait(_ phone: CorpseSimPhone, _ viewModel: ExquisiteCorpseViewModel) {
        if viewModel.invite == .available, random.chance(0.15) {
            log.add("\(phone.name) invite")
            Task { await viewModel.sendInvite() }
        } else if viewModel.isSendFailing, random.chance(0.5) {
            log.add("\(phone.name) try again")
            Task { await viewModel.retrySending() }
        } else if random.chance(0.2) {
            phone.closeScreen()
        }
    }

    private func ledgerCount(_ phone: CorpseSimPhone, _ kind: SyncPendingOperationKind) async -> Int {
        await phone.pending.ledger.filter { $0.kind == kind }.count
    }

    private func failNow(_ message: String) {
        if pendingFailure == nil {
            pendingFailure = SimFailure(message: message)
        }
    }

    private func draw(_ phone: CorpseSimPhone, _ viewModel: ExquisiteCorpseViewModel) async {
        phone.updateScreens()
        guard let part = viewModel.part, let partID = viewModel.ownPartID else { return }
        let board = viewModel.board
        let roll = random.unit()
        if !board.isEmpty, viewModel.canFinishDrawing, roll < 0.3 {
            await finish(phone, viewModel, part: part)
            return
        }
        if !board.isEmpty, roll < 0.36 {
            log.add("\(phone.name) erase a stroke")
            phone.erase(strokeAt: random.int(0...(board.drawing.strokes.count - 1)))
        } else if !board.isEmpty, roll < 0.40 {
            log.add("\(phone.name) clear")
            board.clear()
        } else if roll < 0.52, viewModel.hasIdeas {
            changeIdea(phone, viewModel)
        } else {
            drawStrokes(phone, part: part)
        }
        drawn[phone.name] = CorpseSimDrawing(
            partID: partID,
            strokes: board.drawing.strokes.count,
            ideaID: viewModel.idea?.id
        )
    }

    private func changeIdea(_ phone: CorpseSimPhone, _ viewModel: ExquisiteCorpseViewModel) {
        if viewModel.idea == nil {
            log.add("\(phone.name) asks for an idea")
            viewModel.askIdea()
        } else if random.chance(0.6) {
            log.add("\(phone.name) shuffles the idea")
            viewModel.shuffleIdea()
        } else {
            log.add("\(phone.name) removes the idea")
            viewModel.removeIdea()
        }
    }

    private func drawStrokes(_ phone: CorpseSimPhone, part: ExquisiteCorpsePartKind) {
        let count = random.int(1...3)
        for _ in 0..<count {
            let zone = random.weighted([
                (CorpseSimStrokes.Zone.above, 3), (.crossing, 2), (.below, 2), (.anywhere, 2),
            ])
            phone.draw(CorpseSimStrokes.stroke(seed: &random, side: phone.canvasSide, zone: zone))
        }
        log.add("\(phone.name) draw \(count) strokes on the \(part)")
    }

    private func finish(
        _ phone: CorpseSimPhone,
        _ viewModel: ExquisiteCorpseViewModel,
        part: ExquisiteCorpsePartKind
    ) async {
        log.add("\(phone.name) done with the \(part) (\(viewModel.board.drawing.strokes.count) strokes)")
        let kind = SyncPendingOperationKind.exquisiteCorpseSubmitPart
        let before = await ledgerCount(phone, kind)
        let noticesBefore = phone.notices.count
        await viewModel.finishDrawing()
        drawn[phone.name] = nil
        guard !isBurst else { return }
        await pump()
        if await ledgerCount(phone, kind) == before {
            let refused: [GamesNotice] = [.drawingTooBig, .couldNotSaveMove]
            if !phone.notices.dropFirst(noticesBefore).contains(where: { refused.contains($0) }) {
                failNow("\(phone.name) done made no move and showed no notice")
            }
            return
        }
        // Local first: the screen shows the move at once, online or not.
        let expected: Set<ExquisiteCorpsePhase> = part.next == nil ? [.waitingToSync, .reveal] : [.waiting, .watching]
        if phone.notices.count == noticesBefore, let phase = phone.activeViewModel?.phase, !expected.contains(phase) {
            failNow("\(phone.name) done left the screen in \(phase), expected \(expected)")
        }
    }

    private func reveal(_ phone: CorpseSimPhone, _ viewModel: ExquisiteCorpseViewModel) async {
        guard let figureID = viewModel.figure?.id else { return }
        log.add("\(phone.name) continue")
        let kind = SyncPendingOperationKind.exquisiteCorpseRevealSeen
        let before = await ledgerCount(phone, kind)
        await viewModel.continueFromReveal()
        if await ledgerCount(phone, kind) > before {
            continued[phone.name, default: []].insert(figureID)
        }
        guard !isBurst else { return }
        await pump()
        if phone.activeViewModel === viewModel, viewModel.phase == .reveal, viewModel.figure?.id == figureID {
            failNow("\(phone.name) continue did not leave the reveal")
        }
    }
}
