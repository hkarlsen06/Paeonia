import Foundation
import Testing
@testable import PaeoniaApp

struct ExquisiteCorpseLiveMessageTests {
    private let part = UUID(uuidString: "AAAAAAAA-0000-4000-8000-000000000001") ?? UUID()

    private func json(_ message: ExquisiteCorpseLiveMessage) throws -> [String: Any] {
        let data = try JSONEncoder().encode(message)
        return try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func roundTrip(_ message: ExquisiteCorpseLiveMessage) throws -> ExquisiteCorpseLiveMessage {
        try JSONDecoder().decode(ExquisiteCorpseLiveMessage.self, from: JSONEncoder().encode(message))
    }

    @Test func theGameNamesItselfOnTheWire() {
        #expect(ExquisiteCorpseLiveMessage.game == "exquisite_corpse")
    }

    @Test func aPenMessageIsOneFlatObjectWithATypeField() throws {
        let object = try json(.pen(partID: part, x: 0.25, y: 0.5))

        #expect(object["type"] as? String == "pen")
        #expect(object["part"] as? String == part.uuidString)
        #expect(object["x"] as? Double == 0.25)
        #expect(object["y"] as? Double == 0.5)
        #expect(object.count == 4)
    }

    @Test func aLiftedPenCarriesNoPosition() throws {
        let object = try json(.pen(partID: part, x: nil, y: nil))

        #expect(object["type"] as? String == "pen")
        #expect(object["x"] == nil && object["y"] == nil)
        #expect(try roundTrip(.pen(partID: part, x: nil, y: nil)) == .pen(partID: part, x: nil, y: nil))
    }

    @Test func aStripMessageCarriesTheDrawingAsText() throws {
        let object = try json(.strip(partID: part, drawing: "AQID"))

        #expect(object["type"] as? String == "strip")
        #expect(object["drawing"] as? String == "AQID")
        #expect(object["part"] as? String == part.uuidString)
    }

    @Test func aDoneMessageHasOnlyTheTypeAndThePart() throws {
        let object = try json(.done(partID: part))

        #expect(object["type"] as? String == "done")
        #expect(object.count == 2)
    }

    @Test func everyMessageSurvivesTheTrip() throws {
        let messages: [ExquisiteCorpseLiveMessage] = [
            .pen(partID: part, x: 0.975, y: 0.025),
            .pen(partID: part, x: nil, y: nil),
            .strip(partID: part, drawing: "AQID"),
            .done(partID: part),
        ]

        for message in messages {
            #expect(try roundTrip(message) == message)
            #expect(message.partID == part)
        }
    }

    @Test func aMessageTravelsInsideTheGameEnvelope() throws {
        let envelope = GameLiveEnvelope(
            game: ExquisiteCorpseLiveMessage.game,
            message: ExquisiteCorpseLiveMessage.done(partID: part)
        )

        let data = try JSONEncoder().encode(envelope)
        let decoded = try JSONDecoder().decode(GameLiveEnvelope<ExquisiteCorpseLiveMessage>.self, from: data)

        #expect(decoded.game == "exquisite_corpse")
        #expect(decoded.message == .done(partID: part))
        #expect(GameLiveEnvelopeTag.isGameMessage(data, decoder: JSONDecoder()))
    }

    @Test func aMessageOfAnUnknownTypeDoesNotDecode() {
        let data = Data(#"{"type":"erase","part":"AAAAAAAA-0000-4000-8000-000000000001"}"#.utf8)

        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(ExquisiteCorpseLiveMessage.self, from: data)
        }
    }

    @Test func aMessageWithoutAPartDoesNotDecode() {
        let data = Data(#"{"type":"done"}"#.utf8)

        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(ExquisiteCorpseLiveMessage.self, from: data)
        }
    }
}

struct ExquisiteCorpsePenSamplerTests {
    private typealias Sample = ExquisiteCorpsePenSampler.Sample

    @Test func aPositionIsTheCenterOfItsCellOnA20By20Grid() {
        var sampler = ExquisiteCorpsePenSampler()

        // 0.51 is in column 10 and 0.26 in row 5.
        #expect(sampler.move(x: 0.51, y: 0.26, at: 0) == Sample(x: 0.525, y: 0.275))
    }

    @Test func theEdgesStayInsideTheGrid() {
        var sampler = ExquisiteCorpsePenSampler()

        #expect(sampler.move(x: 1, y: 1, at: 0) == Sample(x: 0.975, y: 0.975))
        #expect(sampler.move(x: -0.3, y: 7, at: 1) == Sample(x: 0.025, y: 0.975))
        #expect(sampler.move(x: .nan, y: .infinity, at: 2) == Sample(x: 0.025, y: 0.025))
    }

    @Test func theSameCellIsNeverSentTwice() {
        var sampler = ExquisiteCorpsePenSampler()

        #expect(sampler.move(x: 0.51, y: 0.26, at: 0) != nil)
        #expect(sampler.move(x: 0.52, y: 0.27, at: 1) == nil)
        #expect(sampler.move(x: 0.54, y: 0.29, at: 10) == nil)
        #expect(sampler.move(x: 0.56, y: 0.29, at: 11) != nil)
    }

    @Test func atMostEightPositionsGoOutEachSecond() {
        var sampler = ExquisiteCorpsePenSampler()

        #expect(sampler.move(x: 0.1, y: 0.1, at: 0) != nil)
        #expect(sampler.move(x: 0.3, y: 0.3, at: 0.05) == nil)
        #expect(sampler.move(x: 0.3, y: 0.3, at: 0.124) == nil)
        #expect(sampler.move(x: 0.3, y: 0.3, at: 0.125) != nil)
    }

    @Test func aPenSweepingForASecondSendsNoMoreThanEightPositions() {
        var sampler = ExquisiteCorpsePenSampler()
        var sent = 0

        // 60 moves in a second, each into a new cell.
        for frame in 0..<60 {
            let fraction = Double(frame) / 60
            if sampler.move(x: fraction, y: 1 - fraction, at: fraction) != nil {
                sent += 1
            }
        }

        #expect(sent == 8)
    }

    @Test func aMoveHeldBackByTheRateLimitGoesOutLater() {
        var sampler = ExquisiteCorpsePenSampler()
        _ = sampler.move(x: 0.1, y: 0.1, at: 0)

        // The pen is in a new cell, but too soon. The cell was not sent, so it goes out later.
        #expect(sampler.move(x: 0.5, y: 0.5, at: 0.05) == nil)
        #expect(sampler.move(x: 0.5, y: 0.5, at: 0.2) == Sample(x: 0.525, y: 0.525))
    }

    @Test func theLiftAlwaysGoesOutAndIsNotHeldBack() {
        var sampler = ExquisiteCorpsePenSampler()

        #expect(sampler.lift() == .lift)
        _ = sampler.move(x: 0.1, y: 0.1, at: 0)
        #expect(sampler.lift() == .lift)
        #expect(sampler.lift() == .lift)
        #expect(Sample.lift == Sample(x: nil, y: nil))
    }

    @Test func afterALiftTheSameCellGoesOutAgain() {
        var sampler = ExquisiteCorpsePenSampler()
        let first = sampler.move(x: 0.51, y: 0.26, at: 0)
        _ = sampler.lift()

        #expect(sampler.move(x: 0.51, y: 0.26, at: 1) == first)
    }
}
