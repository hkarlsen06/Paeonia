@preconcurrency import LiveKitWebRTC

/// The shared screens in a call's media, both on the third transceiver: this phone's screen,
/// which sends while the person shares it, and the partner's, which shows in `partnerFeed`. The
/// partner's screen shows on the simulator too, where this phone cannot share.
final class CallScreenMedia {
    /// Each change to this phone's share (`CallScreenCapture.onShareChange`), after `isSharing`
    /// follows it.
    var onShareChange: ((CallScreenShare) -> Void)?
    /// This phone's screen sends.
    private(set) var isSharing = false

    private let track: LKRTCVideoTrack
    private let capture: CallScreenCapture
    private let partnerFeed: CallVideoFeed
    private var transceiver: LKRTCRtpTransceiver?
    private var partnerTrack: LKRTCVideoTrack?

    init(factory: LKRTCPeerConnectionFactory, partnerFeed: CallVideoFeed) {
        let source = CallCodecs.screenSource(from: factory)
        track = factory.videoTrack(with: source, trackId: "screen")
        capture = CallScreenCapture(source: source)
        self.partnerFeed = partnerFeed
        capture.onShareChange = { [weak self] share in self?.shareChanged(share) }
    }

    func use(_ transceiver: LKRTCRtpTransceiver, limits: CallVideoLimits) {
        self.transceiver = transceiver
        transceiver.sender.track = isSharing ? track : nil
        limit(to: limits)
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
        capture.setMaxFramesPerSecond(limits.maxFramesPerSecond)
        if let sender = transceiver?.sender {
            CallCodecs.limitScreen(sender, to: limits)
        }
    }

    func close() {
        capture.stop()
        partnerTrack?.remove(partnerFeed)
    }

    private func shareChanged(_ share: CallScreenShare) {
        if isSharing != (share == .on) {
            isSharing = share == .on
            transceiver?.sender.track = isSharing ? track : nil
        }
        onShareChange?(share)
    }
}
