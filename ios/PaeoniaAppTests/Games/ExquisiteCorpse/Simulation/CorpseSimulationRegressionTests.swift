import Foundation
import PencilKit
import Testing
@testable import PaeoniaApp

/// Scripted plays on the two-phone simulation, with no random faults. Each one
/// plays the moves of a situation the seeded runs also reach, so a failure here
/// is easy to read.
@MainActor
@Suite(.serialized)
struct CorpseSimulationRegressionTests {
    /// Runs `body` on a fresh pair of phones, with a watchdog, the invariants at the end, and the log on failure.
    private func scenario(_ body: @escaping @MainActor (CorpseSimDriver) async throws -> Void) async {
        let driver = CorpseSimDriver(seed: 1, config: CorpseSimDriver.Config(faultScale: 0))
        do {
            try await SimReport.run(timeout: .seconds(90)) {
                try await driver.setUp()
                try await body(driver)
                await driver.settle()
                try await driver.checkSettled()
            }
        } catch {
            Issue.record("\(error)\n\(driver.log.tail())")
        }
        driver.shutDown()
    }

    private func drawing(_ data: Data?) -> PKDrawing {
        data.flatMap { try? PKDrawing(data: $0) } ?? PKDrawing()
    }

    /// A whole figure with both phones in the room: the watcher sees the strip while the head is drawn,
    /// the strip carries over to the body, and both phones open the reveal after the legs.
    @Test func aFigureGoesFromHeadToRevealLiveWithTheHandOff() async {
        await scenario { driver in
            let starter = driver.turnPhone
            let other = driver.partner(of: starter)

            // The head. The watcher sees the strokes below the fold, and nothing else.
            try driver.require(other, in: .watching)
            try await driver.scriptDraw(starter, zones: [.above, .crossing, .below])
            let watcher = try driver.require(other, in: .watching)
            #expect(watcher.partnerStrip?.strokes.isEmpty == false)
            #expect(starter.stripsSent > 0)
            try await driver.scriptDone(starter)
            await driver.settle()

            // The hand-off: the body drawer has the strip of the head above the canvas.
            let body = try driver.require(other, in: .drawing)
            let head = try #require(driver.server.parts.first)
            let headDrawing = self.drawing(driver.server.assets[head.drawingAssetID]?.data)
            let headStrip = ExquisiteCorpseFold.strip(of: headDrawing)
            #expect(body.strip?.paeoniaContentSignature == headStrip.paeoniaContentSignature)
            try driver.require(starter, in: .watching)
            try await driver.scriptTurn(other)

            try await self.finishFigure(driver, starter: starter, other: other)
        }
    }

    /// The legs, the reveal on both phones, and the next figure starting with the body drawer.
    private func finishFigure(_ driver: CorpseSimDriver, starter: CorpseSimPhone, other: CorpseSimPhone) async throws {
        try await driver.scriptTurn(starter)
        let revealStarter = try driver.require(starter, in: .reveal)
        let revealOther = try driver.require(other, in: .reveal)
        #expect(revealStarter.revealContent?.isReady == true)
        #expect(revealOther.revealContent?.isReady == true)
        #expect(driver.server.figures.first?.finishedAt != nil)

        // Nothing hidden went to the partner before the figure was finished.
        let early = driver.server.downloads.filter { $0.purpose == "exquisite_corpse_drawing" && !$0.figureFinished }
        #expect(early.allSatisfy { $0.user == $0.drawer })
        #expect(starter.leaks.isEmpty && other.leaks.isEmpty)

        await revealStarter.continueFromReveal()
        await revealOther.continueFromReveal()
        await driver.settle()
        try driver.require(other, in: .drawing)
        try driver.require(starter, in: .watching)
    }

    /// The drawer's socket dropped in the middle of the part. Done still goes through, and the partner
    /// gets the strip from the file.
    @Test func doneStillGoesThroughAfterTheDrawersSocketDrops() async {
        await scenario { driver in
            let drawer = driver.turnPhone
            let other = driver.partner(of: drawer)
            try await driver.scriptDraw(drawer, zones: [.crossing, .above])
            drawer.socket?.dropSilently()
            await driver.pump()
            try await driver.scriptDraw(drawer, zones: [.below])
            try await driver.scriptDone(drawer)
            await driver.settle()

            let head = try #require(driver.server.parts.first)
            #expect(self.drawing(driver.server.assets[head.drawingAssetID]?.data).strokes.count == 3)
            let next = try driver.require(other, in: .drawing)
            let expected = ExquisiteCorpseFold.strip(of: self.drawing(driver.server.assets[head.drawingAssetID]?.data))
            #expect(next.strip?.paeoniaContentSignature == expected.paeoniaContentSignature)
        }
    }

    /// A phone that is offline for its whole turn keeps the part on the phone, says so, and sends it when
    /// the network is back. The partner keeps waiting meanwhile.
    @Test func aPartQueuedOfflineIsSentLater() async {
        await scenario { driver in
            let first = driver.turnPhone
            let second = driver.partner(of: first)
            try await driver.scriptTurn(first)

            second.setOnline(false)
            try await driver.scriptDraw(second)
            try await driver.scriptDone(second)
            let offline = try #require(second.activeViewModel)
            #expect(offline.phase == .waiting || offline.phase == .watching)
            #expect(offline.isWaitingToSend)
            #expect(driver.server.parts.count == 1)
            #expect(first.activeViewModel?.phase != .drawing)

            second.setOnline(true)
            await driver.settle()
            #expect(driver.server.parts.count == 2)
            try driver.require(first, in: .drawing)
            #expect(second.activeViewModel?.isWaitingToSend == false)
        }
    }

    /// The legs are queued offline. The drawer waits to sync and then both phones show the reveal.
    @Test func legsQueuedOfflineShowTheRevealOnBothAfterReconnecting() async {
        await scenario { driver in
            let starter = driver.turnPhone
            let other = driver.partner(of: starter)
            try await driver.scriptTurn(starter)
            try await driver.scriptTurn(other)

            starter.setOnline(false)
            try await driver.scriptDraw(starter)
            try await driver.scriptDone(starter)
            try driver.require(starter, in: .waitingToSync)
            #expect(driver.server.figures.first?.finishedAt == nil)

            starter.setOnline(true)
            await driver.settle()
            try driver.require(starter, in: .reveal)
            try driver.require(other, in: .reveal)
            #expect(driver.server.figures.first?.finishedAt != nil)
        }
    }

    /// A force quit in the middle of a part keeps the strokes and the idea on the canvas.
    @Test func aForceQuitMidDrawKeepsTheDraftAndTheIdea() async {
        await scenario { driver in
            let drawer = driver.turnPhone
            let viewModel = try driver.require(drawer, in: .drawing)
            try await driver.scriptDraw(drawer, zones: [.crossing, .above])
            viewModel.askIdea()
            viewModel.shuffleIdea()
            // The draft saves a moment after the last stroke. A slow runner can
            // reach the force quit before that moment.
            await viewModel.draftTask?.value
            await driver.pump()
            let idea = try #require(viewModel.idea?.id)
            let partID = try #require(viewModel.ownPartID)

            drawer.forceQuit(closesSocket: true)
            drawer.launch()
            drawer.openScreen()
            await driver.settle()

            let restored = try driver.require(drawer, in: .drawing)
            #expect(restored.ownPartID == partID)
            #expect(restored.board.drawing.strokes.count == 2)
            #expect(restored.idea?.id == idea)
        }
    }

    /// A reveal this person moved past does not come back, also after the app restarts. The partner who
    /// has not moved past it still sees it.
    @Test func aRevealSeenOnOnePhoneDoesNotShowAgainAfterARelaunch() async {
        await scenario { driver in
            let (starter, other) = try await driver.scriptFigureToReveal()
            let figureID = try #require(driver.server.figures.first?.id)
            let viewModel = try driver.require(starter, in: .reveal)
            await viewModel.continueFromReveal()
            await driver.settle()
            #expect(driver.server.figures.first?.seenAt[starter.userID] != nil)
            #expect(driver.server.figures.first?.seenAt[other.userID] == nil)

            starter.forceQuit(closesSocket: true)
            starter.launch()
            starter.openScreen()
            await driver.settle()
            #expect(starter.activeViewModel?.phase != .reveal)

            other.forceQuit(closesSocket: true)
            other.launch()
            other.openScreen()
            await driver.settle()
            let reveal = try driver.require(other, in: .reveal)
            #expect(reveal.figure?.id == figureID)
        }
    }
}
