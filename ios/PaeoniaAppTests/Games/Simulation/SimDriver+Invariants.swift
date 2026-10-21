import Foundation
import PencilKit
@testable import PaeoniaApp

// The invariants the driver checks. `checkAlways` runs after every step, and
// `checkSettled` once the network is up and the queues have drained.
extension SimDriver {
    // MARK: - Invariants

    /// Checked after every step, also while offline.
    func checkAlways() throws {
        if let pendingFailure {
            throw pendingFailure
        }
        // A drawer looking at their own sent drawing never sees a blank square, even offline.
        for phone in phones {
            guard let viewModel = phone.activeViewModel, let round = viewModel.round,
                  viewModel.phase == .waitingForGuess || viewModel.phase == .reveal,
                  round.isDrawer(phone.userID), drawnHere.contains(round.id), !viewModel.isLoadingDrawing
            else { continue }
            if viewModel.finalDrawing?.drawing.strokes.isEmpty != false {
                throw SimFailure(
                    message: "\(phone.name) shows a blank square for its own drawing of \(tag(round.id)) "
                        + "in \(viewModel.phase) (load failed \(viewModel.drawingLoadFailed))"
                )
            }
        }
        for phone in phones {
            guard let viewModel = phone.activeViewModel, let record = boardStrokes[phone.name] else { continue }
            if viewModel.phase == .drawing, viewModel.round?.id == record.roundID, phone.canvas != nil,
               viewModel.board.drawing.strokes.count != record.count {
                throw SimFailure(
                    message: "\(phone.name) draft lost: board has \(viewModel.board.drawing.strokes.count) "
                        + "strokes, drew \(record.count)"
                )
            }
        }
    }

    func fail(_ message: String) -> SimFailure {
        SimFailure(message: message)
    }

    /// The first six characters of an id, which is how the log names rounds and moves.
    func tag(_ id: UUID) -> String {
        String(id.uuidString.prefix(6))
    }

    func checkSettled() async throws {
        try checkAlways()
        try checkServerTotals()
        for phone in phones {
            try await checkLedger(phone)
        }
        for phone in phones {
            guard let viewModel = phone.activeViewModel else { continue }
            try await checkScreen(phone, viewModel)
            try checkUnsentDrawingWentOut(phone)
        }
        try checkProgress()
    }

    private func checkServerTotals() throws {
        guard let game = server.game else { return }
        for round in server.rounds where round.state == .solved {
            try checkBonuses(of: round)
        }
        let solved = server.rounds.filter { $0.state == .solved }
        let shared = solved.reduce(0) { $0 + $1.points }
        guard game.shared == shared else { throw fail("server shared points \(game.shared) != \(shared)") }
        for user in server.users {
            let expected = solved.reduce(0) { total, round in
                let asDrawer = round.drawer == user ? round.points : 0
                let asGuesser = round.guesser == user ? round.points + round.speedBonus + round.firstTryBonus : 0
                return total + asDrawer + asGuesser
            }
            guard (game.points[user] ?? 0) == expected else {
                throw fail("server points for a player \(game.points[user] ?? 0) != \(expected)")
            }
        }
    }

    private func checkBonuses(of round: SimServer.Round) throws {
        if let promised = promisedBonus[round.id], round.speedBonus != promised {
            throw fail("round \(tag(round.id)) has speed bonus \(round.speedBonus), the screen promised \(promised)")
        }
        if let promised = promisedHints[round.id], round.hintsUsed != promised {
            throw fail("round \(tag(round.id)) has \(round.hintsUsed) hints, the screen showed \(promised)")
        }
        // Any hint takes both bonuses away. The first try is the round's first attempt.
        if round.hintsUsed > 0, round.speedBonus != 0 || round.firstTryBonus != 0 {
            throw fail("round \(tag(round.id)) has bonuses after \(round.hintsUsed) hints")
        }
        let expectedFirstTry = round.hintsUsed == 0 && round.attempts.count == 1 ? 1 : 0
        if round.firstTryBonus != expectedFirstTry {
            throw fail(
                "round \(tag(round.id)) has first try bonus \(round.firstTryBonus), expected \(expectedFirstTry)"
            )
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
        let actor = phones.first { $0.userID == game.turnUser }
        if actor?.activeViewModel != nil {
            settlesWithoutProgress += 1
        }
        if settlesWithoutProgress > 30 {
            throw fail("no progress for 30 settles with the turn's player in the game")
        }
    }
}
