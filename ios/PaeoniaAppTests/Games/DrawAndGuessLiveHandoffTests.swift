import PencilKit
import Testing
@testable import PaeoniaApp

/// Feeds the strokes a drawing partner's snapshot carries into a live room, as the
/// relay would when the guesser watched the drawing happen.
@MainActor
func sendPartnerCanvasSnapshot(on connection: WidgetLiveConnection) {
    connection.onMessage?(WidgetLiveMessage(
        type: .ops,
        side: Double(DrawAndGuessCanvas.canonicalSide),
        upserts: GameFixture.umbrella().dataRepresentation().base64EncodedString(),
        snapshot: true
    ))
}

/// What the guesser looks at once the drawer has sent the drawing: the live
/// canvas when it holds the drawing, and otherwise the replay of the file.
@MainActor
struct DrawAndGuessLiveHandoffTests {
    private var partnerDrawing: RemoteDrawAndGuessState {
        GameFixture.state(
            settings: GameFixture.settings(),
            game: GameFixture.game(state: .drawing, turn: GameFixture.me),
            round: GameFixture.round(state: .drawing, drawer: GameFixture.partner)
        )
    }

    private var drawingSent: RemoteDrawAndGuessState {
        GameFixture.state(
            settings: GameFixture.settings(),
            game: GameFixture.game(state: .guessing, turn: GameFixture.me),
            round: GameFixture.round(state: .guessing, drawer: GameFixture.partner, hasDrawing: true)
        )
    }

    /// The guesser is on the watching screen, with the drawer in the room.
    private func watchingLive(
        canvasArrives: Bool
    ) async -> (env: GamesTestEnvironment, viewModel: DrawAndGuessViewModel, connection: WidgetLiveConnection) {
        let env = GamesTestEnvironment(state: partnerDrawing)
        let (room, connection) = makeOfflineLiveRoom()
        let viewModel = env.viewModel(live: room)
        viewModel.configure(participants: GameFixture.participants)
        await viewModel.reload()
        connection.onMessage?(WidgetLiveMessage(type: .welcome, id: "me", peers: 1))
        connection.onMessage?(WidgetLiveMessage(type: .hello, from: "partner", role: "drawing"))
        if canvasArrives {
            sendPartnerCanvasSnapshot(on: connection)
        }
        viewModel.recompute()
        return (env, viewModel, connection)
    }

    /// A push opens the game while the cache still shows the round without a
    /// drawing. The drawer has pressed Done but is still in the room as drawing,
    /// with no canvas left to send a snapshot. The live canvas stays empty, so the
    /// guesser has to get the sent file. Before the fix the square stayed blank.
    @Test func aGuesserWhoJoinedAnEmptyRoomGetsTheSentDrawing() async throws {
        let (env, viewModel, _) = await watchingLive(canvasArrives: false)
        #expect(viewModel.phase == .watchingLive)

        await env.cache.saveState(drawingSent, ownerUserID: GameFixture.me)
        await viewModel.reload()

        #expect(viewModel.phase == .guessing)
        #expect(viewModel.guessSource == .replay)
        let ready = await waitUntil { viewModel.isReplayReady }
        #expect(ready)
        #expect(env.transfer.downloads == [GameFixture.assetID])
    }

    @Test func aGuesserWhoSeesTheDrawingLiveKeepsTheLiveCanvasAndSkipsTheDownload() async throws {
        let (env, viewModel, _) = await watchingLive(canvasArrives: true)

        await env.cache.saveState(drawingSent, ownerUserID: GameFixture.me)
        await viewModel.reload()

        #expect(viewModel.phase == .guessing)
        #expect(viewModel.guessSource == .live)
        #expect(!viewModel.isReplayReady)
        #expect(env.transfer.downloads.isEmpty)
    }

    @Test func aReplayThatIsPlayingStaysWhenTheDrawerComesBackWithACanvas() async throws {
        let (env, viewModel, connection) = await watchingLive(canvasArrives: true)
        await env.cache.saveState(drawingSent, ownerUserID: GameFixture.me)
        await viewModel.reload()
        connection.onMessage?(WidgetLiveMessage(type: .left, id: "partner"))
        viewModel.recompute()
        let ready = await waitUntil { viewModel.isReplayReady }
        #expect(ready)

        connection.onMessage?(WidgetLiveMessage(type: .joined))
        connection.onMessage?(WidgetLiveMessage(type: .hello, from: "partner", role: "drawing"))
        sendPartnerCanvasSnapshot(on: connection)
        viewModel.recompute()

        #expect(viewModel.guessSource == .replay)
        #expect(viewModel.isReplayReady)
    }
}
