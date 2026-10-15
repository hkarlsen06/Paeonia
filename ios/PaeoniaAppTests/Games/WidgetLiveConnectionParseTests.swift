import Foundation
import PencilKit
import Testing
@testable import PaeoniaApp

/// One parse tells a game message from a drawing message and decodes the strokes.
struct WidgetLiveConnectionParseTests {
    @Test func aGameMessageKeepsItsJSONForTheChannel() async throws {
        let envelope = GameLiveEnvelope(
            game: ExquisiteCorpseLiveMessage.game,
            message: ExquisiteCorpseLiveMessage.done(partID: UUID())
        )
        let data = try JSONEncoder().encode(envelope)
        let text = try #require(String(data: data, encoding: .utf8))

        guard case let .game(kept) = await WidgetLiveConnection.parse(text) else {
            Issue.record("Expected a game message")
            return
        }
        #expect(kept == data)
    }

    @Test func aDrawingMessageDecodes() async throws {
        let message = WidgetLiveMessage(type: .hello, needsCanvas: true, from: "me", role: "drawing")
        let text = try #require(String(data: try JSONEncoder().encode(message), encoding: .utf8))

        guard case let .live(decoded) = await WidgetLiveConnection.parse(text) else {
            Issue.record("Expected a drawing message")
            return
        }
        #expect(decoded.type == .hello)
        #expect(decoded.from == "me")
        #expect(decoded.preparedUpserts == nil)
    }

    @Test func theStrokesOfAnOpsMessageAreDecodedAhead() async throws {
        let drawing = makeNonEmptyDrawing()
        let message = WidgetLiveMessage(
            type: .ops,
            side: 320,
            upserts: drawing.dataRepresentation().base64EncodedString()
        )
        let text = try #require(String(data: try JSONEncoder().encode(message), encoding: .utf8))

        guard case let .live(decoded) = await WidgetLiveConnection.parse(text) else {
            Issue.record("Expected a drawing message")
            return
        }
        #expect(decoded.preparedUpserts?.strokes.count == 1)
    }

    @Test func theWireFormatDoesNotCarryTheDecodedStrokes() throws {
        var message = WidgetLiveMessage(type: .ops, side: 320, upserts: "AAAA")
        message.preparedUpserts = makeNonEmptyDrawing()

        let object = try #require(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(message)) as? [String: Any]
        )

        #expect(object["preparedUpserts"] == nil)
        #expect(object["upserts"] as? String == "AAAA")
    }

    @Test func textThatIsNoMessageGivesNothing() async {
        #expect(await WidgetLiveConnection.parse("not json") == nil)
        #expect(await WidgetLiveConnection.parse(#"{"unknown":1}"#) == nil)
    }
}
