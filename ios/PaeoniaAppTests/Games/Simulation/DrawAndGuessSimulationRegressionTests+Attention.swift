import Foundation
import Testing
@testable import PaeoniaApp

/// The taps that tell a person the game needs them, played through the real view
/// models on two phones.
extension DrawAndGuessSimulationRegressionTests {
    /// Each phone's cues, in the order they played.
    @MainActor
    final class CueLog {
        var cues: [String: [String]] = [:]

        /// Gives the phone's open view model a cue that writes here, and lets it read
        /// the game once, so the next change is the first that can play.
        func listen(to phone: SimPhone) {
            guard let viewModel = phone.viewModel else { return }
            let name = phone.name
            viewModel.attentionCue = GameAttentionCue(player: GameAttentionCue.Player(
                turn: { [weak self] in self?.cues[name, default: []].append("turn") },
                step: { [weak self] in self?.cues[name, default: []].append("step") }
            ))
            viewModel.recompute()
        }

        subscript(phone: SimPhone) -> [String] {
            cues[phone.name] ?? []
        }
    }

    /// The guesser hears the drawer start and gets one turn tap for the drawing, also
    /// when it arrived in the background. The drawer hears the wrong guess. Nobody hears
    /// their own moves, the reveal, or a read of the same game again.
    @Test func handoversAndWrongGuessesTapOnceEach() async {
        await scenario { driver in
            let drawer = driver.turnPhone
            let guesser = driver.partner(of: drawer)
            let log = CueLog()
            log.listen(to: drawer)
            log.listen(to: guesser)

            try await driver.scriptPick(drawer)
            await driver.settle()
            #expect(log[guesser] == ["step"])

            try await driver.scriptDraw(drawer)
            guesser.moveToBackground()
            try await driver.scriptDone(drawer)
            await driver.settle()
            #expect(log[guesser] == ["step"])
            guesser.moveToForeground()
            await driver.settle()
            #expect(log[guesser] == ["step", "turn"])

            try await driver.scriptGuess(guesser, right: false)
            await driver.settle()
            #expect(log[drawer] == ["step"])

            try await driver.scriptGuess(guesser, right: true)
            await driver.settle()
            drawer.viewModel?.recompute()
            guesser.viewModel?.recompute()
            #expect(log[drawer] == ["step"])
            #expect(log[guesser] == ["step", "turn"])
        }
    }
}
