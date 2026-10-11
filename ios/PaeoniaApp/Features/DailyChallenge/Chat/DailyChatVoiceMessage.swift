import Foundation

/// The file a chat voice message sends. The composer records with the same recorder
/// as voice answers, which writes .m4a.
nonisolated enum DailyChatVoiceRecording {
    static let fileExtension = "m4a"
    static let mimeType = "audio/mp4"
}
