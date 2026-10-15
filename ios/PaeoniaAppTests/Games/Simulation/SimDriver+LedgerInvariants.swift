import Foundation
@testable import PaeoniaApp

// Every write a phone queued either landed once, still waits for a reason, or was dropped
// with a notice.
extension SimDriver {
    /// One phone and the notices its screens showed or its cache kept.
    private struct LedgerContext {
        let phone: SimPhone
        let notices: [GamesNotice]

        func noticed(_ kinds: [GamesNotice]) -> Bool {
            notices.contains { kinds.contains($0) }
        }
    }

    /// The guesses of one round the server holds or still waits to receive, by their text.
    private struct GuessTally {
        var landed: [String] = []
        var waiting: [String] = []
    }

    func checkLedger(_ phone: SimPhone) async throws {
        let ledger = await phone.pending.ledger
        let storedNotices = await phone.cache.document(ownerUserID: phone.userID).notices.map(GamesNotice.init)
        let context = LedgerContext(phone: phone, notices: phone.notices + storedNotices)
        try checkNoticesHaveDroppedMoves(context, ledger: ledger)
        let guessesByRound = try checkEntries(ledger, context)
        try checkNoGuessLostOrDoubled(guessesByRound, phone: phone)
        // Once online with nothing held, nothing may stay in the queue.
        guard phone.isAlive, phone.isForeground else { return }
        for entry in ledger where entry.outcome == .inFlight {
            throw fail("\(phone.name) \(entry.kind.rawValue) is stuck in the queue after settling")
        }
    }

    /// Checks each queued write against what the server holds and what the screens said.
    private func checkEntries(
        _ ledger: [SimPendingStore.Entry],
        _ context: LedgerContext
    ) throws -> [UUID: GuessTally] {
        var guessesByRound: [UUID: GuessTally] = [:]
        for entry in ledger {
            guard let data = entry.requestData else { continue }
            switch entry.kind {
            case .pickDrawWord: try checkPick(entry, data, context)
            case .submitGameDrawing: try checkDrawing(entry, data, context)
            case .submitGameGuess: try checkGuess(entry, data, context, tallies: &guessesByRound)
            case .giveUpGameRound: try checkGiveUp(entry, data, context)
            case .markGameRoundResultSeen: try checkResultSeen(entry, data, context)
            default: break
            }
        }
        return guessesByRound
    }

    /// A notice about a dropped move needs a dropped move behind it.
    private func checkNoticesHaveDroppedMoves(
        _ context: LedgerContext,
        ledger: [SimPendingStore.Entry]
    ) throws {
        let dropped = Set(ledger.compactMap { entry -> SyncPendingOperationKind? in
            if case .terminal = entry.outcome { entry.kind } else { nil }
        })
        let explains: [GamesNotice: [SyncPendingOperationKind]] = [
            .moveRejected: [.submitGameGuess, .giveUpGameRound],
            .wordRejected: [.pickDrawWord],
            .wordRejectedDrawingKept: [.pickDrawWord],
            .drawingRejected: [.submitGameDrawing],
        ]
        for notice in Set(context.notices) {
            if let kinds = explains[notice], dropped.isDisjoint(with: kinds) {
                throw fail("\(context.phone.name) showed \(notice) with no dropped move behind it")
            }
        }
    }

    private func checkPick(_ entry: SimPendingStore.Entry, _ data: Data, _ context: LedgerContext) throws {
        let name = context.phone.name
        guard let pick = try? JSONDecoder().decode(GamePickWordPayload.self, from: data) else { return }
        switch entry.outcome {
        case .succeeded:
            guard server.round(pick.roundID)?.drawer == context.phone.userID else {
                throw fail("\(name) pick for \(tag(pick.roundID)) succeeded but the server has no such round")
            }
        case .terminal:
            guard context.noticed([.wordRejected, .wordRejectedDrawingKept]) else {
                throw fail("\(name) pick dropped without a notice")
            }
        case .inFlight:
            break
        }
    }

    private func checkDrawing(_ entry: SimPendingStore.Entry, _ data: Data, _ context: LedgerContext) throws {
        let name = context.phone.name
        guard let drawing = try? JSONDecoder().decode(GameSubmitDrawingPayload.self, from: data) else { return }
        switch entry.outcome {
        case .succeeded:
            guard let round = server.round(drawing.roundID), let assetID = round.drawingAssetID else {
                throw fail("\(name) drawing for \(tag(drawing.roundID)) succeeded but the round has none")
            }
            if server.assets[assetID]?.data != drawing.drawingData {
                throw fail("\(name) a second drawing for round \(tag(drawing.roundID)) was dropped silently")
            }
        case let .terminal(reason):
            let explained = reason.contains("upload expired") || reason.contains("word pick for this drawing")
            guard explained || context.noticed([.drawingRejected]) else {
                throw fail("\(name) drawing dropped without a notice: \(reason)")
            }
        case .inFlight:
            break
        }
    }

    private func checkGuess(
        _ entry: SimPendingStore.Entry,
        _ data: Data,
        _ context: LedgerContext,
        tallies: inout [UUID: GuessTally]
    ) throws {
        let name = context.phone.name
        guard let guess = try? JSONDecoder().decode(GameGuessPayload.self, from: data) else { return }
        let text = SimServer.normalizeWordText(guess.guess)
        switch entry.outcome {
        case .succeeded:
            tallies[guess.roundID, default: GuessTally()].landed.append(text)
        case let .terminal(reason):
            guard !reason.contains("already finished") else {
                throw fail("\(name) guess \(text) refused silently: \(reason)")
            }
            guard context.noticed([.moveRejected]) else {
                throw fail("\(name) guess dropped without a notice: \(reason)")
            }
        case .inFlight:
            tallies[guess.roundID, default: GuessTally()].waiting.append(text)
        }
    }

    private func checkGiveUp(_ entry: SimPendingStore.Entry, _ data: Data, _ context: LedgerContext) throws {
        let name = context.phone.name
        guard let giveUp = try? JSONDecoder().decode(GameGiveUpPayload.self, from: data) else { return }
        switch entry.outcome {
        case .succeeded:
            guard server.round(giveUp.roundID)?.state.isFinished == true else {
                throw fail("\(name) give up succeeded but the round is open")
            }
        case let .terminal(reason):
            guard !reason.contains("already finished") else {
                throw fail("\(name) give up refused silently: \(reason)")
            }
            guard context.noticed([.moveRejected]) else {
                throw fail("\(name) give up dropped without a notice: \(reason)")
            }
        case .inFlight:
            break
        }
    }

    private func checkResultSeen(_ entry: SimPendingStore.Entry, _ data: Data, _ context: LedgerContext) throws {
        guard let seen = try? JSONDecoder().decode(GameResultSeenPayload.self, from: data) else { return }
        if case .succeeded = entry.outcome, let round = server.round(seen.roundID) {
            let stamp = round.drawer == context.phone.userID ? round.drawerSeenAt : round.guesserSeenAt
            guard stamp != nil else {
                throw fail("\(context.phone.name) result seen succeeded but the server has no time for it")
            }
        }
    }

    /// No guess is lost or doubled: the server holds each landed guess once,
    /// plus at most the ones still waiting that already reached it.
    private func checkNoGuessLostOrDoubled(_ guessesByRound: [UUID: GuessTally], phone: SimPhone) throws {
        for (roundID, guesses) in guessesByRound {
            let onServer = (server.round(roundID)?.attempts ?? []).filter { $0.userID == phone.userID }.map(\.text)
            for text in Set(guesses.landed + onServer) {
                let landed = guesses.landed.filter { $0 == text }.count
                let waiting = guesses.waiting.filter { $0 == text }.count
                let held = onServer.filter { $0 == text }.count
                guard held >= landed, held <= landed + waiting else {
                    throw fail(
                        "\(phone.name) guess \(text) is on the server \(held) times, "
                            + "sent \(landed), waiting \(waiting)"
                    )
                }
            }
        }
    }
}
