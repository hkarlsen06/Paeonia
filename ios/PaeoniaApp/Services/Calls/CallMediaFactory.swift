@preconcurrency import LiveKitWebRTC

/// One factory for the app's lifetime, with WebRTC's `AVAudioEngine` audio (`CallAudio`).
/// `CallAudio.queue` reaches its audio module, so it is not tied to the main actor.
nonisolated enum CallMediaFactory {
    nonisolated(unsafe) static let shared: LKRTCPeerConnectionFactory = {
        LKRTCInitializeSSL()
        return LKRTCPeerConnectionFactory(
            audioDeviceModuleType: .audioEngine,
            bypassVoiceProcessing: false,
            encoderFactory: CallVideoEncoderFactory(),
            decoderFactory: LKRTCDefaultVideoDecoderFactory(),
            audioProcessingModule: nil
        )
    }()
}
