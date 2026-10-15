import Foundation
import PencilKit
import Testing
@testable import PaeoniaApp

/// Regressions that need the whole two-phone harness, with a drawing still on its way.
extension DrawAndGuessSimulationRegressionTests {
    /// The drawer picked and drew offline while the partner changed the game
    /// language, so the server refused the old word. The drawing is kept for
    /// the next word, and the partner watching live sees it on the canvas.
    @Test func aDrawingKeptAfterARefusedWordReachesThePartnerWatchingLive() async {
        await scenario { driver in
            let drawer = driver.turnPhone
            let guesser = driver.partner(of: drawer)
            drawer.setOnline(false)
            try await driver.scriptPick(drawer)
            try await driver.scriptDraw(drawer, strokes: 3)
            try await driver.scriptDone(drawer)

            let language: GameLanguage = driver.server.settings?.language == .en ? .nb : .en
            _ = await guesser.games?.saveSettings(playStyle: .against, language: language)
            drawer.setOnline(true)
            await driver.settle()
            #expect(drawer.notices.contains(.wordRejectedDrawingKept))

            try await driver.scriptPick(drawer)
            await driver.settle()
            let drawerModel = try driver.require(drawer, in: .drawing)
            #expect(drawerModel.board.drawing.strokes.count == 3)
            let guesserModel = try driver.require(guesser, in: .watchingLive)
            #expect(guesserModel.live?.partnerCanvasDrawing?.strokes.count == 3)
        }
    }

    /// The partner guesses right while the drawer's finger is still down. The
    /// drawing goes out once that stroke ends, with the stroke in it.
    @Test func aSolveDuringAStrokeSendsTheDrawingWithThatStroke() async {
        await scenario { driver in
            let drawer = driver.turnPhone
            let guesser = driver.partner(of: drawer)
            try await driver.scriptPick(drawer)
            try await driver.scriptDraw(drawer, strokes: 2)
            await driver.settle()
            let drawerModel = try driver.require(drawer, in: .drawing)
            let canvas = try #require(drawer.canvas)

            drawerModel.board.setStrokeInProgress(true)
            try await driver.scriptGuess(guesser, right: true)
            #expect(driver.server.currentRound?.state == .solved)
            #expect(driver.server.currentRound?.drawingAssetID == nil)

            var random = SimRandom(seed: 3)
            let stroke = SimStrokes.stroke(seed: &random, side: canvas.side)
            let drawing = PKDrawing(strokes: canvas.view.drawing.strokes + [stroke])
            canvas.view.drawing = drawing
            drawerModel.board.updateDrawing(drawing)
            drawerModel.board.setStrokeInProgress(false)
            await driver.settle()

            let round = try #require(driver.server.currentRound)
            let assetID = try #require(round.drawingAssetID)
            let sent = try PKDrawing(data: try #require(driver.server.assets[assetID]?.data))
            #expect(sent.strokes.count == 3)
        }
    }

    /// The drawer's app died mid-drawing, and the partner guessed it from the
    /// live canvas meanwhile. When the drawer comes back, the saved draft is
    /// the drawing the round keeps, and both reveals show it.
    @Test func aDraftFromBeforeAForceQuitIsSentWhenThePartnerSolvedMeanwhile() async {
        await scenario { driver in
            let drawer = driver.turnPhone
            let guesser = driver.partner(of: drawer)
            try await driver.scriptPick(drawer)
            try await driver.scriptDraw(drawer, strokes: 4)
            await driver.settle()
            _ = try driver.require(guesser, in: .watchingLive)

            drawer.forceQuit(closesSocket: false)
            try await driver.scriptGuess(guesser, right: true)
            await driver.settle()
            #expect(driver.server.currentRound?.state == .solved)

            drawer.launch()
            drawer.openScreen()
            await driver.settle()

            let round = try #require(driver.server.currentRound)
            let assetID = try #require(round.drawingAssetID)
            let sent = try PKDrawing(data: try #require(driver.server.assets[assetID]?.data))
            #expect(sent.strokes.count == 4)
            for phone in [drawer, guesser] {
                let model = try driver.require(phone, in: .reveal)
                #expect(model.finalDrawing?.drawing.strokes.count == 4)
            }
        }
    }

    /// The guesser solved the round live, and the guesser's app was relaunched
    /// before the drawer's drawing was sent. The live snapshot lived only in
    /// memory, so the reveal showed a blank square. It is kept on the phone
    /// now, never goes to Memories, and gives way to the sent drawing.
    @Test func aLiveSolveStillShowsTheDrawingAfterARelaunchBeforeItWasSent() async {
        await scenario { driver in
            let drawer = driver.turnPhone
            let guesser = driver.partner(of: drawer)
            try await driver.scriptPick(drawer)
            try await driver.scriptDraw(drawer, strokes: 4)
            await driver.settle()
            _ = try driver.require(guesser, in: .watchingLive)

            drawer.forceQuit(closesSocket: false)
            try await driver.scriptGuess(guesser, right: true)
            await driver.settle()
            let roundID = try #require(driver.server.currentRound?.id)
            #expect(driver.server.currentRound?.state == .solved)
            #expect(driver.server.currentRound?.drawingAssetID == nil)

            guesser.forceQuit(closesSocket: true)
            guesser.launch()
            guesser.openScreen()
            await driver.settle()

            let relaunched = try driver.require(guesser, in: .reveal)
            #expect(relaunched.finalDrawing?.drawing.strokes.count == 4)
            #expect(relaunched.submittedDrawing == nil)

            drawer.launch()
            drawer.openScreen()
            await driver.settle()

            let revealed = try driver.require(guesser, in: .reveal)
            #expect(revealed.submittedDrawing?.drawing.strokes.count == 4)
            #expect(guesser.drawingStore.liveSnapshot(ownerUserID: guesser.userID, roundID: roundID) == nil)
        }
    }

    /// The drawer left the result and waits for the next word. The guesser's
    /// result screen says the drawer is waiting for them.
    @Test func theGuesserSeesTheDrawerWaitingForThem() async {
        await scenario { driver in
            let (drawer, guesser) = try await driver.scriptRoundToReveal()
            try driver.require(drawer, in: .reveal)
            #expect(try driver.require(guesser, in: .reveal).isPartnerWaitingForMe == false)

            try await driver.require(drawer, in: .reveal).continueFromReveal()
            await driver.settle()

            #expect(try driver.require(drawer, in: .waitingForWord).partnerPresence == .result)
            #expect(try driver.require(guesser, in: .reveal).isPartnerWaitingForMe)
            #expect(try driver.require(drawer, in: .waitingForWord).isPartnerWaitingForMe == false)
        }
    }

    /// The guesser left the result to pick the next word. The drawer's result
    /// screen says so until the guesser starts drawing.
    @Test func theDrawerSeesTheGuesserChoosingTheNextWord() async {
        await scenario { driver in
            let (drawer, guesser) = try await driver.scriptRoundToReveal()
            #expect(try driver.require(drawer, in: .reveal).isPartnerChoosingNextWord == false)

            try await driver.require(guesser, in: .reveal).continueFromReveal()
            await driver.settle()

            try driver.require(guesser, in: .chooseWord)
            #expect(try driver.require(drawer, in: .reveal).isPartnerChoosingNextWord)

            try await driver.scriptPick(guesser)
            await driver.settle()

            let result = try driver.require(drawer, in: .reveal)
            #expect(result.partnerNextRound == .drawing)
            #expect(result.isPartnerChoosingNextWord == false)
        }
    }
}
