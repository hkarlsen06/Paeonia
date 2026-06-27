import Foundation
import Testing
@testable import PaeoniaApp

struct DailyAnswerMediaUploadServiceTests {
    @Test func voiceReserveRequestUsesBackendVoiceMediaType() throws {
        let request = ReserveDailyAnswerMediaRequest(
            operation: try Self.operation(),
            answerID: try #require(UUID(uuidString: "F3004A57-760A-4238-8F47-3BC9F06D6699")),
            purpose: .voice,
            fileExtension: "m4a"
        )

        let payload = try Self.payloadDictionary(for: request)

        #expect(payload["p_upload_purpose"] as? String == "voice_note")
        #expect(payload["p_media_type"] as? String == "voice")
        #expect(payload["p_file_extension"] as? String == "m4a")
    }

    @Test func voiceFinalizeRequestUsesBackendVoiceMediaType() throws {
        let mediaAssetID = try #require(UUID(uuidString: "C90D2C5E-A6B9-4564-9B2C-E58896B42C41"))
        let reservation = PendingMediaUploadResponse(
            mediaAssetID: mediaAssetID,
            bucket: "couple-media",
            storagePath: "couple-id/voice/\(mediaAssetID.uuidString).m4a"
        )
        let media = DailyAnswerUploadMedia(
            data: Data([0x01, 0x02, 0x03]),
            purpose: .voice,
            mimeType: "audio/mp4",
            fileExtension: "m4a",
            durationMs: 1_500
        )
        let request = FinalizeDailyAnswerMediaRequest(
            reservation: reservation,
            reservedByClientOperationID: try #require(UUID(uuidString: "3CC4616B-7C22-4B2F-9DA7-6DBF073C5F3D")),
            operation: try Self.operation(),
            answerID: try #require(UUID(uuidString: "8BFA9389-A6F8-4F24-893C-42C881D23633")),
            media: media
        )

        let payload = try Self.payloadDictionary(for: request)

        #expect(payload["p_upload_purpose"] as? String == "voice_note")
        #expect(payload["p_media_type"] as? String == "voice")
        #expect(payload["p_mime_type"] as? String == "audio/mp4")
        #expect(payload["p_duration_ms"] as? Int == 1_500)
    }

    private static func operation() throws -> SyncClientOperation {
        SyncClientOperation(
            id: try #require(UUID(uuidString: "0E350756-6CE9-4373-A3A0-94641C2A7E4D")),
            clientID: try #require(UUID(uuidString: "CF25139E-6B10-4697-9559-0F3278D514C7")),
            clientSequence: 42,
            localCreatedAt: Date(timeIntervalSince1970: 1_710_000_000)
        )
    }

    private static func payloadDictionary<T: Encodable>(for value: T) throws -> [String: Any] {
        let data = try JSONEncoder().encode(value)
        let object = try JSONSerialization.jsonObject(with: data)
        return try #require(object as? [String: Any])
    }
}
