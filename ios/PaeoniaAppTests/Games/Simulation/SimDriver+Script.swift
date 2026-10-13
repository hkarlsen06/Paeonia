import Foundation
import PencilKit
@testable import PaeoniaApp

// Scripted moves for the focused regression tests, on the same two phones and
// server the seeded runs use. Each one waits until the phones are quiet.
extension SimDriver {
    /// The phone whose turn it is on the server.
    var turnPhone: SimPhone {
        phones.first { $0.userID == server.game?.turnUser } ?? phones[0]
    }

    func scriptPick(_ phone: SimPhone) async throws {
        let viewModel = try require(phone, in: .chooseWord)
        await viewModel.chooseWord(viewModel.choices[0])
        await pump()
    }

    func scriptDraw(_ phone: SimPhone, strokes: Int = 2) async throws {
        _ = try require(phone, in: .drawing)
        phone.updateScreens()
        guard let canvas = phone.canvas else { throw SimFailure(message: "\(phone.name) has no canvas") }
        var random = SimRandom(seed: 7)
        for _ in 0..<strokes {
            canvas.draw(SimStrokes.stroke(seed: &random, side: canvas.side))
        }
        await pump()
    }

    func scriptDone(_ phone: SimPhone) async throws {
        let viewModel = try require(phone, in: .drawing)
        await viewModel.finishDrawing()
        await pump()
    }

    /// Fills the slots with the answer, or with the tiles in order for a wrong word.
    func scriptGuess(_ phone: SimPhone, right: Bool) async throws {
        guard let viewModel = phone.activeViewModel, viewModel.phase.allowsGuessing else {
            throw SimFailure(message: "\(phone.name) cannot guess in \(phone.viewModel?.phase as Any)")
        }
        var used = Set<Int>()
        let answer = Array(viewModel.slots.answer)
        for slot in viewModel.slots.slots where !slot.isGap {
            let tile = right
                ? viewModel.tiles.first { $0.letter == answer[slot.id] && !used.contains($0.id) }
                : viewModel.tiles.first { $0.letter != answer[slot.id] && !used.contains($0.id) }
            guard let tile else { throw SimFailure(message: "no tile for slot \(slot.id)") }
            used.insert(tile.id)
            viewModel.placeTile(tile)
        }
        await pump()
    }

    /// Plays a round to the guesser's reveal with no faults. Returns the drawer and the guesser.
    func scriptRoundToReveal() async throws -> (drawer: SimPhone, guesser: SimPhone) {
        let drawer = turnPhone
        let guesser = partner(of: drawer)
        try await scriptPick(drawer)
        try await scriptDraw(drawer)
        try await scriptDone(drawer)
        await settle()
        try await scriptGuess(guesser, right: true)
        await settle()
        return (drawer, guesser)
    }

    @discardableResult
    func require(_ phone: SimPhone, in phase: DrawAndGuessPhase) throws -> DrawAndGuessViewModel {
        guard let viewModel = phone.activeViewModel, viewModel.phase == phase else {
            throw SimFailure(message: "\(phone.name) is in \(phone.viewModel?.phase as Any), expected \(phase)")
        }
        return viewModel
    }
}
