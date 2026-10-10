import Foundation
import Testing
@testable import PaeoniaApp

struct LiveJSONTests {
    private struct Payload: Decodable, Equatable {
        let streak: Int
        let ratio: Double
        let note: String?
        let flags: [Bool]
        let startedOn: Date

        enum CodingKeys: String, CodingKey {
            case streak
            case ratio
            case note
            case flags
            case startedOn = "started_on"
        }
    }

    private func text(_ data: Data) throws -> String {
        try #require(String(bytes: data, encoding: .utf8))
    }

    private func normalized(_ json: String) throws -> Data {
        try JSONDecoder().decode(LiveJSON.self, from: Data(json.utf8)).normalizedData()
    }

    @Test func plainDecoderBehaviorForWholeNumberDoublesInIntFields() throws {
        let decoder = JSONDecoder()

        // ConvexMobile's Rust layer may print a JS number as `5.0`. Document
        // what the plain decoder does with that, since DTOs use `Int` fields.
        let whole = try? decoder.decode([Int].self, from: Data("[5.0]".utf8))
        let fractional = try? decoder.decode([Int].self, from: Data("[5.5]".utf8))

        #expect(whole == [5])
        #expect(fractional == nil)
    }

    @Test func normalizedTextWritesWholeNumbersWithoutAFraction() throws {
        let data = try normalized(#"{"a":5.0,"b":2.5,"c":-3.0,"d":[1.0,0.0]}"#)
        let text = try #require(String(data: data, encoding: .utf8))

        #expect(!text.contains("5.0"))
        #expect(!text.contains("-3.0"))
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(object["a"] as? Int == 5)
        #expect(object["b"] as? Double == 2.5)
        #expect(object["c"] as? Int == -3)
        #expect(object["d"] as? [Int] == [1, 0])
    }

    @Test func normalizedResultDecodesWithTheAppDecoder() throws {
        let data = try normalized(
            #"{"streak":12.0,"ratio":0.25,"note":null,"flags":[true,false],"started_on":"2026-03-04T05:06:07.890Z"}"#
        )

        let payload = try PaeoniaConvexClient.decoder.decode(Payload.self, from: data)

        #expect(payload.streak == 12)
        #expect(payload.ratio == 0.25)
        #expect(payload.note == nil)
        #expect(payload.flags == [true, false])
        #expect(abs(payload.startedOn.timeIntervalSince1970 - 1_772_600_767.890) < 0.001)
    }

    @Test func booleansStayBooleansAndNumbersStayNumbers() throws {
        let data = try normalized(#"[true,1,0,false]"#)
        let text = try #require(String(data: data, encoding: .utf8))

        #expect(text == "[true,1,0,false]")
    }

    @Test func topLevelScalarsAndNullPassThrough() throws {
        #expect(try text(normalized("7.0")) == "7")
        #expect(try text(normalized("null")) == "null")
        #expect(try text(normalized(#""hi""#)) == #""hi""#)
        #expect(try text(normalized("[]")) == "[]")
    }

    @Test func taggedInt64ValuesBecomeNumbers() throws {
        // 1 as a little-endian int64, base64 encoded.
        let data = try normalized(#"{"n":{"$integer":"AQAAAAAAAAA="}}"#)
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])

        #expect(object["n"] as? Int == 1)
    }

    @Test func stringsKeepEscapesAndUnicode() throws {
        let data = try normalized(#"{"text":"line\nbreak \"quoted\" æøå"}"#)
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])

        #expect(object["text"] as? String == "line\nbreak \"quoted\" æøå")
    }
}
