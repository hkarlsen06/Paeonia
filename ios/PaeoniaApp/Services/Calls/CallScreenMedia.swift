@preconcurrency import LiveKitWebRTC

/// The shared screens in a call's media, both on the third transceiver: this phone's screen,
/// which sends while the person shares it, and the partner's, which shows in `partnerFeed`. The
/// partner's screen shows on the simulator too, where this phone cannot share.
final class CallScreenMedia {
    /// True once this phone's screen sends, false when the share stops.
    var onSharingChange: ((Bool) -> Void)?
    private(set) var isSharing = false

    private let track: LKRTCVideoTrack
    private let capture: CallScreenCapture
    private let partnerFeed: CallVideoFeed
    private var transceiver: LKRTCRtpTransceiver?
    private var partnerTrack: LKRTCVideoTrack?

    init(factory: LKRTCPeerConnectionFactory, partnerFeed: CallVideoFeed) {
        // A screen source tells the encoder the frames are a screen, which it compresses for text.
        let source = factory.videoSource(forScreenCast: true)
        track = factory.videoTrack(with: source, trackId: "screen")
        capture = CallScreenCapture(source: source)
        self.partnerFeed = partnerFeed
        capture.onSharingChange = { [weak self] isOn in self?.sharingChanged(isOn) }
    }

    func use(_ transceiver: LKRTCRtpTransceiver, limits: CallVideoLimits) {
        self.transceiver = transceiver
        transceiver.sender.track = isSharing ? track : nil
        CallCodecs.limitScreen(transceiver.sender, to: limits)
        partnerTrack = transceiver.receiver.track as? LKRTCVideoTrack
        partnerTrack?.add(partnerFeed)
    }

    /// Shows the system's picker. Sharing starts once the person picks there.
    func start() {
        capture.start()
    }

    func stop() {
        capture.stop()
    }

    func limit(to limits: CallVideoLimits) {
        if let sender = transceiver?.sender {
            CallCodecs.limitScreen(sender, to: limits)
        }
    }

    func close() {
        capture.stop()
        partnerTrack?.remove(partnerFeed)
    }

    private func sharingChanged(_ isOn: Bool) {
        isSharing = isOn
        transceiver?.sender.track = isOn ? track : nil
        onSharingChange?(isOn)
    }
}
