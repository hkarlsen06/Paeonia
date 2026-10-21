import Foundation
import PencilKit
@testable import PaeoniaApp

// The invariants the driver checks. `checkAlways` runs after every step, and
// `checkSettled` once the network is up and the queues have drained. The ledger
// and the screen checks are in the other `CorpseSimDriver+` files.
extension CorpseSimDriver {
    func fail(_ message: String) -> SimFailure {
        SimFailure(message: message)
    }

    func name(of user: UUID) -> String {
        phones.first { $0.userID == user }?.name ?? "?"
    }

    func drawing(of assetID: UUID?) -> PKDrawing? {
        assetID.flatMap { server.assets[$0] }.flatMap { try? PKDrawing(data: $0.data) }
    }

    // MARK: - After every step

    /// Checked also while offline.
    func checkAlways() async throws {
        if let pendingFailure {
            throw pendingFailure
        }
        for phone in phones {
            if let leak = phone.leaks.first {
                throw fail("PRIVACY: \(leak)")
            }
            try await checkNothingHiddenIsHeld(phone)
            if let viewModel = phone.activeViewModel {
                try checkDraft(phone)
                let figureID = viewModel.figure?.id
                if viewModel.phase == .reveal, let id = figureID, continued[phone.name]?.contains(id) == true {
                    throw fail("\(phone.name) shows the reveal of \(id.uuidString.prefix(6)) again after Continue")
                }
            }
        }
        // The server never answers a request for the other person's part before the figure is finished.
        for download in server.downloads where download.purpose == "exquisite_corpse_drawing" {
            if let drawer = download.drawer, drawer != download.user, !download.figureFinished {
                let asker = name(of: download.user)
                throw fail("PRIVACY: \(asker) asked for a part of \(name(of: drawer)) before the figure was finished")
            }
        }
    }

    /// A phone never holds the full part or the idea of a figure that is not finished,
    /// in its cache, its files, or on its screen.
    private func checkNothingHiddenIsHeld(_ phone: CorpseSimPhone) async throws {
        let hidden = server.parts.filter { part in
            let figure = server.figures.first { $0.id == part.figureID }
            return part.drawer != phone.userID && figure?.finishedAt == nil
        }
        for part in hidden where phone.drawingStore.downloadedDrawing(mediaAssetID: part.drawingAssetID) != nil {
            throw fail("PRIVACY: \(phone.name) holds the drawing of part \(part.index) of an unfinished figure")
        }
        let document = await phone.corpseCache.document(ownerUserID: phone.userID)
        var figures = document.state.map { [$0.currentFigure].compactMap(\.self) + $0.recentFigures } ?? []
        figures += [phone.viewModel?.figure].compactMap(\.self)
        for figure in figures where !figure.isFinished {
            for part in figure.parts where part.drawerUserID != phone.userID {
                if part.drawingMediaAssetID != nil || part.idea != nil {
                    throw fail("PRIVACY: \(phone.name) has the drawing or idea of part \(part.partIndex) of the " +
                        "partner before the figure is finished")
                }
            }
        }
    }

    /// The canvas, the draft and the idea chip stay as the person left them, also after a relaunch.
    private func checkDraft(_ phone: CorpseSimPhone) throws {
        guard let record = drawn[phone.name], let now = phone.drawingRecord, now.partID == record.partID else { return }
        guard now.strokes == record.strokes else {
            throw fail("\(phone.name) draft lost: \(now.strokes) strokes, the person drew \(record.strokes)")
        }
        guard now.ideaID == record.ideaID else {
            throw fail("\(phone.name) idea is \(now.ideaID ?? "none"), the person chose \(record.ideaID ?? "none")")
        }
    }

    // MARK: - Once the queues drained

    func checkSettled() async throws {
        try await checkAlways()
        try checkPartOrder()
        try checkFigureShapes()
        try checkStrips()
        for phone in phones {
            try await checkLedger(phone)
        }
        for phone in phones {
            guard let viewModel = phone.activeViewModel else { continue }
            try await checkScreen(phone, viewModel)
        }
        try checkProgress()
    }

    /// Turns strictly alternate, and the parts cycle head, body, legs.
    private func checkPartOrder() throws {
        guard let game = server.game else { return }
        var previous: CorpseSimServer.Part?
        for part in server.parts {
            try checkPart(part, after: previous, game: game)
            previous = part
        }
        if let last = previous {
            guard game.turnUser == server.partner(of: last.drawer), game.partIndex == (last.index + 1) % 3 else {
                throw fail("the game's turn does not follow the last part")
            }
        }
    }

    private func checkPart(
        _ part: CorpseSimServer.Part,
        after previous: CorpseSimServer.Part?,
        game: CorpseSimServer.Game
    ) throws {
        if let previous {
            guard previous.drawer != part.drawer else {
                throw fail("\(name(of: part.drawer)) drew two parts in a row")
            }
            guard part.index == (previous.index + 1) % 3 else {
                throw fail("part \(part.index) follows part \(previous.index)")
            }
        } else {
            guard part.index == 0, part.drawer == game.creator else {
                throw fail("the first part is not the creator's head")
            }
        }
        let expectedID = ExquisiteCorpseIDs.part(
            gameID: game.id, figureNumber: part.figureNumber, partIndex: part.index, drawerID: part.drawer
        )
        guard part.id == expectedID else {
            throw fail("part \(part.index) of figure \(part.figureNumber) has an unexpected id")
        }
    }

    /// A figure is a head, a body and legs, with the head and the legs by its starter. The next figure
    /// starts with the previous body drawer.
    private func checkFigureShapes() throws {
        guard let game = server.game else { return }
        var nextStarter = game.creator
        for figure in server.figures.sorted(by: { $0.number < $1.number }) {
            let own = server.parts.filter { $0.figureID == figure.id }.sorted { $0.index < $1.index }
            guard figure.id == ExquisiteCorpseIDs.figure(gameID: game.id, number: figure.number) else {
                throw fail("figure \(figure.number) has an unexpected id")
            }
            guard figure.starter == nextStarter else {
                throw fail("figure \(figure.number) starts with the wrong person")
            }
            for part in own where (part.drawer == figure.starter) != (part.index != 1) {
                throw fail("part \(part.index) of figure \(figure.number) is by the wrong person")
            }
            guard (figure.finishedAt != nil) == (own.count == 3) else {
                throw fail("figure \(figure.number) is finished wrongly")
            }
            nextStarter = own.first { $0.index == 1 }?.drawer ?? nextStarter
        }
        guard game.figuresFinished == server.figures.filter({ $0.finishedAt != nil }).count else {
            throw fail("the game counts \(game.figuresFinished) finished figures")
        }
    }

    /// A strip file holds exactly what is below the fold of its part.
    private func checkStrips() throws {
        for part in server.parts {
            guard let stripID = part.stripAssetID else {
                guard part.index == 2 else { throw fail("part \(part.index) has no strip") }
                continue
            }
            guard let full = drawing(of: part.drawingAssetID), let strip = drawing(of: stripID) else {
                throw fail("part \(part.index) of figure \(part.figureNumber) has an unreadable file")
            }
            if let leak = CorpseSimFold.leak(in: strip) {
                throw fail("PRIVACY: the strip file of part \(part.index) holds \(leak)")
            }
            let expected = ExquisiteCorpseFold.strip(of: full)
            guard strip.strokes.count == expected.strokes.count,
                  strip.paeoniaContentSignature == expected.paeoniaContentSignature
            else {
                throw fail("the strip of part \(part.index) of figure \(part.figureNumber) is not its bottom")
            }
        }
    }

    /// The game moves on while the person whose turn it is has the game open.
    private func checkProgress() throws {
        guard let game = server.game else { return }
        if game.version != lastProgressVersion {
            lastProgressVersion = game.version
            settlesWithoutProgress = 0
            return
        }
        if phones.first(where: { $0.userID == game.turnUser })?.activeViewModel != nil {
            settlesWithoutProgress += 1
        }
        if settlesWithoutProgress > 30 {
            throw fail("no progress for 30 settles with the turn's player in the game")
        }
    }
}
