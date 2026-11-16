import Foundation
import Network
@preconcurrency import LiveKitWebRTC

/// The audio and video connection between the two phones for one call, set up over the relay.
///
/// Audio, the camera and the shared screen are all in the first offer, so turning a camera or a
/// screen share on or off swaps a video sender's track and never needs a new offer. The caller
/// offers whenever the partner's phone is in the relay room and the phones are not connected. A
/// later offer restarts the network path (an ICE restart), which is how the call recovers after a
/// drop or a network change.
///
/// Both phones start the session while the call rings. A ringing phone takes the caller's
/// newest offer but holds its answer, and sends nothing at all, until its person answers on it
/// (`answer()`). So no sound or picture leaves it before then, and only the device that answered
/// ever answers the offer when the partner has several.
final class CallMediaSession {
    nonisolated enum Role: Sendable {
        /// Sends the offers. The phone that started the call.
        case offerer
        case answerer
    }

    /// True when the phones reached each other, false when the connection dropped.
    var onConnectionChange: ((Bool) -> Void)?
    var onPartnerCamera: ((CallCameraState) -> Void)?
    var onPartnerScreen: ((Bool) -> Void)?
    /// True once this phone's screen sends, false when the share stops.
    var onScreenShare: ((Bool) -> Void)?
    /// Whose end of the call is weak, or nil while both are fine (`CallConnectionHealth`).
    var onWeakConnection: ((CallWeakSide?) -> Void)?
    /// The back camera's zoom once it sends, and nil while any other camera or none runs.
    var onBackCameraZoom: ((CallCameraZoom?) -> Void)?
    /// Each `CallStatsLog` sample while the phones are connected.
    var onStatsSample: ((CallStatsSample) -> Void)?

    private let role: Role
    private let relay: CallRelay
    private let peerConnection: LKRTCPeerConnection
    private let observer: PeerConnectionObserver
    private let audioTrack: LKRTCAudioTrack
    private let videoTrack: LKRTCVideoTrack
    private let camera: CallCamera
    private let screen: CallScreenMedia
    private let partnerFeed: CallVideoFeed
    private let localFeed: CallVideoFeed
    private let statsLog = CallStatsLog()
    private var videoTransceiver: LKRTCRtpTransceiver?
    private var remoteVideoTrack: LKRTCVideoTrack?
    private var isCameraOn: Bool
    /// iOS stopped the camera for now, so the partner sees it as paused.
    private var isCameraInterrupted = false
    /// Counts camera starts, so only the newest one ends the wait in `localFeed`.
    private var cameraStarts = 0
    private var isConnected = false
    /// The path the video's limits were last set for. `CallCodecs.configure` starts at TURN's.
    private var videoPath = CallMediaPath.turn
    private var heat: CallHeat
    private var health = CallConnectionHealth()
    /// The number of the newest offer: the one this phone sent, whose answer alone applies, or on
    /// the answering phone the one it took.
    private var offerNumber = 0
    /// A ringing phone whose person has not answered on it. It sends nothing to the relay.
    private var isHeld: Bool
    /// An offer waits in `work`, so another reason to offer needs no second one.
    private var isOfferQueued = false
    /// Candidates that arrived before a session description they belong to.
    private var pendingCandidates: [LKRTCIceCandidate] = []
    /// Every relay message and every reason to offer, handled one at a time in order, so a
    /// candidate never overtakes the description it belongs to.
    private let work: AsyncStream<Work>.Continuation
    private var workTask: Task<Void, Never>?
    private let pathMonitor = NWPathMonitor()
    private var lastInterface: NWInterface.InterfaceType?
    private var pathMonitorHasReported = false

    private enum Work {
        case signal(CallSignal.Message)
        case partnerPresent
        case offer
        case answer
    }

    init(
        callID: UUID,
        role: Role,
        servers: CallIceServers,
        backend: CallBackend,
        partnerFeed: CallVideoFeed,
        localFeed: CallVideoFeed,
        partnerScreenFeed: CallVideoFeed,
        isMuted: Bool,
        isCameraOn: Bool,
        isFrontCamera: Bool,
        heat: CallHeat
    ) throws {
        let factory = CallMediaFactory.shared
        let observer = PeerConnectionObserver()
        self.role = role
        peerConnection = try Self.makePeerConnection(servers: servers, observer: observer)
        self.observer = observer
        self.partnerFeed = partnerFeed
        self.localFeed = localFeed
        self.isCameraOn = isCameraOn
        isHeld = role == .answerer
        self.heat = heat
        relay = CallRelay(callID: callID, backend: backend)
        audioTrack = factory.audioTrack(
            with: factory.audioSource(with: LKRTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil)),
            trackId: "audio"
        )
        audioTrack.isEnabled = !isMuted
        let videoSource = factory.videoSource()
        videoTrack = factory.videoTrack(with: videoSource, trackId: "video")
        camera = CallCamera(source: videoSource)
        screen = CallScreenMedia(factory: factory, partnerFeed: partnerScreenFeed)
        let (stream, continuation) = AsyncStream.makeStream(of: Work.self)
        work = continuation

        videoTrack.add(localFeed)
        if role == .offerer {
            addTransceivers()
        }
        observer.session = self
        camera.onInterruption = { [weak self] in self?.cameraInterrupted($0) }
        camera.setMaxFramesPerSecond(CallVideoLimits(path: videoPath, heat: heat).maxFramesPerSecond)
        screen.onSharingChange = { [weak self] isOn in self?.screenSharingChanged(isOn) }
        if isCameraOn {
            startCamera(front: isFrontCamera)
        }
        relay.onSignal = { continuation.yield(.signal($0)) }
        relay.onPartnerPresent = { continuation.yield(.partnerPresent) }
        workTask = Task { [weak self] in
            for await item in stream {
                await self?.handle(item)
            }
        }
    }

    private static func makePeerConnection(
        servers: CallIceServers,
        observer: PeerConnectionObserver
    ) throws -> LKRTCPeerConnection {
        let configuration = LKRTCConfiguration()
        configuration.iceServers = servers.iceServers.map {
            LKRTCIceServer(urlStrings: $0.urls, username: $0.username, credential: $0.credential)
        }
        configuration.iceTransportPolicy = servers.relayOnly ? .relay : .all
        configuration.sdpSemantics = .unifiedPlan
        configuration.bundlePolicy = .maxBundle
        configuration.rtcpMuxPolicy = .require
        configuration.continualGatheringPolicy = .gatherContinually
        // A ringing phone gathers its candidates before it answers, and they go out at the answer.
        configuration.iceCandidatePoolSize = 1
        guard let peerConnection = CallMediaFactory.shared.peerConnection(
            with: configuration,
            constraints: LKRTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil),
            delegate: observer
        ) else {
            throw CallMediaError.couldNotCreateConnection
        }
        return peerConnection
    }

    func start() {
        relay.start()
        pathMonitor.pathUpdateHandler = { [weak self] path in
            MainActor.assumeIsolated { self?.networkChanged(path) }
        }
        pathMonitor.start(queue: .main)
    }

    func close() {
        screen.close()
        statsLog.stop()
        pathMonitor.cancel()
        work.finish()
        workTask?.cancel()
        relay.stop()
        camera.stop()
        videoTrack.remove(localFeed)
        remoteVideoTrack?.remove(partnerFeed)
        observer.session = nil
        peerConnection.close()
    }

    /// The person answered on this phone. It answers the caller's newest offer, now or when one
    /// arrives, and from here on sends like any phone in the call.
    func answer() {
        work.yield(.answer)
    }

    /// Reconnects the relay now. When the partner is back in the room, the caller offers again.
    func restart() {
        relay.reconnectNow()
    }

    func setMuted(_ isMuted: Bool) {
        audioTrack.isEnabled = !isMuted
    }

    func setCamera(isOn: Bool, front: Bool) {
        isCameraOn = isOn
        if isOn {
            startCamera(front: front)
        } else {
            camera.stop()
            onBackCameraZoom?(nil)
        }
        videoTransceiver?.sender.track = isOn ? videoTrack : nil
        send(.camera(cameraState))
    }

    /// Returns the zoom the back camera took, or nil when it is not running.
    func setBackCameraZoom(_ factor: Double) -> Double? {
        camera.setZoom(factor)
    }

    /// The local video keeps the old camera's last frame and mirroring until the new camera
    /// sends, so flipping never shows the old picture mirrored the new way.
    ///
    /// The start in `init` reports its zoom after the engine has set `onBackCameraZoom`, because
    /// the camera reports from a later turn of the main queue.
    private func startCamera(front: Bool) {
        cameraStarts += 1
        let start = cameraStarts
        localFeed.cameraWillStart()
        onBackCameraZoom?(nil)
        camera.start(front: front) { [weak self] zoom in
            guard let self, start == cameraStarts else { return }
            localFeed.cameraStarted(isMirrored: front)
            onBackCameraZoom?(zoom)
        }
    }

    // MARK: Signaling

    // swiftlint:disable:next cyclomatic_complexity
    private func handle(_ item: Work) async {
        switch item {
        case .partnerPresent:
            guard !isHeld else { return }
            // The partner may have missed the last camera, screen and connection messages while
            // their phone reconnected.
            send(.camera(cameraState))
            send(.screen(isOn: screen.isSharing))
            send(.connection(isWeak: health.isMineWeak))
            guard !isConnected else { return }
            switch role {
            case .offerer:
                queueOffer()
            case .answerer where peerConnection.remoteDescription != nil:
                send(.restart)
            case .answerer:
                break
            }
        case let .signal(message):
            await receive(message)
        case .offer:
            isOfferQueued = false
            await sendOffer()
        case .answer:
            guard isHeld else { return }
            isHeld = false
            await sendAnswer()
            send(.camera(cameraState))
            send(.screen(isOn: screen.isSharing))
        }
    }

    /// Every message to the relay goes through here, so a ringing phone sends nothing.
    private func send(_ message: CallSignal.Message) {
        guard !isHeld else { return }
        relay.send(message)
    }

    /// Offers once for every reason to offer that arrives before the offer goes out.
    private func queueOffer() {
        guard !isOfferQueued else { return }
        isOfferQueued = true
        work.yield(.offer)
    }

    // swiftlint:disable:next cyclomatic_complexity
    private func receive(_ message: CallSignal.Message) async {
        switch message {
        case let .offer(sdp, number) where role == .answerer:
            await acceptOffer(sdp, number: number)
        case let .answer(sdp, number) where role == .offerer:
            guard number == offerNumber, peerConnection.signalingState == .haveLocalOffer else { return }
            try? await peerConnection.setRemoteDescription(LKRTCSessionDescription(type: .answer, sdp: sdp))
            await addPendingCandidates()
            // The answering phone ignored the camera and screen messages it heard while it rang.
            send(.camera(cameraState))
            send(.screen(isOn: screen.isSharing))
        case let .candidate(candidate):
            await receive(candidate)
        case let .camera(state):
            guard !isHeld else { return }
            onPartnerCamera?(state)
        case let .screen(isOn):
            guard !isHeld else { return }
            onPartnerScreen?(isOn)
        case let .connection(isWeak):
            guard !isHeld else { return }
            health.isPartnersWeak = isWeak
            onWeakConnection?(health.weakSide)
        case .restart where role == .offerer:
            queueOffer()
        case .offer, .answer, .restart:
            break
        }
    }

    private func sendOffer() async {
        do {
            if peerConnection.signalingState == .haveLocalOffer {
                // The partner's phone rejoined before it answered, so the last offer is lost.
                try await peerConnection.setLocalDescription(LKRTCSessionDescription(type: .rollback, sdp: ""))
            }
            if offerNumber > 0 {
                peerConnection.restartIce()
            }
            let offer = try await CallCodecs.withOpusDTX(peerConnection.offer(
                for: LKRTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil)
            ))
            try await peerConnection.setLocalDescription(offer)
            offerNumber += 1
            send(.offer(sdp: offer.sdp, number: offerNumber))
        } catch {
            // The next time the partner joins, or the call's connect timer, tries again.
        }
    }

    private func addPendingCandidates() async {
        let candidates = pendingCandidates
        pendingCandidates = []
        for candidate in candidates {
            try? await peerConnection.add(candidate)
        }
    }

    private static let streamID = "paeonia"
}

// MARK: Answering

extension CallMediaSession {
    /// A ringing phone only takes the offer. Setting its answer would start the network checks
    /// and the encryption handshake with the caller, and the caller keeps only one early
    /// handshake, which could be the one from the partner's other ringing device.
    private func acceptOffer(_ sdp: String, number: Int) async {
        do {
            try await peerConnection.setRemoteDescription(LKRTCSessionDescription(type: .offer, sdp: sdp))
        } catch {
            // The caller offers again when the connection does not come up.
            return
        }
        offerNumber = number
        if videoTransceiver == nil {
            attachAnswererTracks()
        }
        await addPendingCandidates()
        if !isHeld {
            await sendAnswer()
        }
    }

    /// Answers the offer that waits, if one does.
    private func sendAnswer() async {
        guard peerConnection.signalingState == .haveRemoteOffer else { return }
        do {
            let answer = try await CallCodecs.withOpusDTX(peerConnection.answer(
                for: LKRTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil)
            ))
            try await peerConnection.setLocalDescription(answer)
            send(.answer(sdp: answer.sdp, number: offerNumber))
        } catch {
            // The caller offers again when the connection does not come up.
        }
    }
}

// MARK: Tracks

extension CallMediaSession {
    /// The caller's first offer carries audio, the camera and the screen both ways. The camera's
    /// transceiver comes before the screen's, which is how the answering phone tells them apart.
    private func addTransceivers() {
        let audioInit = LKRTCRtpTransceiverInit()
        audioInit.direction = .sendRecv
        audioInit.streamIds = [Self.streamID]
        if let transceiver = peerConnection.addTransceiver(with: audioTrack, init: audioInit) {
            CallCodecs.configure(transceiver, factory: CallMediaFactory.shared)
        }

        let videoInit = LKRTCRtpTransceiverInit()
        videoInit.direction = .sendRecv
        videoInit.streamIds = [Self.streamID]
        guard let transceiver = peerConnection.addTransceiver(of: .video, init: videoInit) else { return }
        CallCodecs.configure(transceiver, factory: CallMediaFactory.shared)
        useVideoTransceiver(transceiver)

        guard let screenTransceiver = peerConnection.addTransceiver(of: .video, init: videoInit) else { return }
        CallCodecs.configure(screenTransceiver, factory: CallMediaFactory.shared)
        screen.use(screenTransceiver, limits: screenLimits)
    }

    /// The answering phone uses the transceivers the offer created, so nothing needs a new offer.
    private func attachAnswererTracks() {
        for transceiver in peerConnection.transceivers {
            transceiver.setDirection(.sendRecv, error: nil)
            transceiver.sender.streamIds = [Self.streamID]
            CallCodecs.configure(transceiver, factory: CallMediaFactory.shared)
            switch transceiver.mediaType {
            case .audio:
                transceiver.sender.track = audioTrack
            case .video where videoTransceiver == nil:
                useVideoTransceiver(transceiver)
            case .video:
                screen.use(transceiver, limits: screenLimits)
            default:
                break
            }
        }
    }

    private func useVideoTransceiver(_ transceiver: LKRTCRtpTransceiver) {
        videoTransceiver = transceiver
        transceiver.sender.track = isCameraOn ? videoTrack : nil
        applyVideoLimits()
        remoteVideoTrack = transceiver.receiver.track as? LKRTCVideoTrack
        remoteVideoTrack?.add(partnerFeed)
    }

    // MARK: Connection

    fileprivate func sendCandidate(_ candidate: CallIceCandidate) {
        send(.candidate(candidate))
    }

    fileprivate func receive(_ candidate: CallIceCandidate) async {
        let iceCandidate = LKRTCIceCandidate(
            sdp: candidate.sdp,
            sdpMLineIndex: candidate.sdpMLineIndex,
            sdpMid: candidate.sdpMid
        )
        if peerConnection.remoteDescription == nil || peerConnection.signalingState == .haveLocalOffer {
            pendingCandidates.append(iceCandidate)
        } else {
            try? await peerConnection.add(iceCandidate)
        }
    }

    fileprivate func connectionStateChanged(_ state: LKRTCPeerConnectionState) {
        switch state {
        case .connected:
            guard !isConnected else { return }
            isConnected = true
            statsLog.start(peerConnection) { [weak self] sample in
                self?.useVideoPath(sample.mediaPath)
                self?.onStatsSample?(sample)
                self?.checkSendingHealth(sample)
            }
            onConnectionChange?(true)
        case .disconnected, .failed:
            guard isConnected else { return }
            isConnected = false
            statsLog.stop()
            // The call shows "Reconnecting" instead, and judges the new connection afresh.
            if health.isMineWeak {
                send(.connection(isWeak: false))
            }
            health = CallConnectionHealth()
            onWeakConnection?(nil)
            onConnectionChange?(false)
        default:
            break
        }
    }

    /// The phones pick a new path after a network change, so this runs for every stats sample.
    private func useVideoPath(_ path: CallMediaPath?) {
        guard let path, path != videoPath else { return }
        videoPath = path
        applyVideoLimits()
    }

    private func applyVideoLimits() {
        let limits = CallVideoLimits(path: videoPath, heat: heat, besideScreen: screen.isSharing)
        camera.setMaxFramesPerSecond(limits.maxFramesPerSecond)
        if let sender = videoTransceiver?.sender {
            CallCodecs.limitVideo(sender, to: limits)
        }
        screen.limit(to: screenLimits)
    }

    private var screenLimits: CallVideoLimits {
        .screen(path: videoPath, heat: heat)
    }

    private func checkSendingHealth(_ sample: CallStatsSample) {
        guard health.add(sample) else { return }
        send(.connection(isWeak: health.isMineWeak))
        onWeakConnection?(health.weakSide)
    }

    // MARK: Camera and heat

    /// Lowers or restores what the video sends as the phone heats up or cools down.
    func setHeat(_ heat: CallHeat) {
        guard heat != self.heat else { return }
        self.heat = heat
        applyVideoLimits()
    }

    private var cameraState: CallCameraState {
        guard isCameraOn else { return .off }
        return isCameraInterrupted ? .paused : .on
    }

    private func cameraInterrupted(_ isInterrupted: Bool) {
        guard isInterrupted != isCameraInterrupted else { return }
        isCameraInterrupted = isInterrupted
        send(.camera(cameraState))
    }

    private func networkChanged(_ path: NWPath) {
        let interface = path.availableInterfaces.first?.type
        defer { lastInterface = interface }
        // The first update is the network the call started on.
        guard pathMonitorHasReported, path.status == .satisfied, interface != lastInterface else {
            pathMonitorHasReported = true
            return
        }
        restart()
    }
}

// MARK: Screen sharing

extension CallMediaSession {
    /// Shows the system's picker. Sharing starts once the person picks there (`onScreenShare`).
    func startScreenShare() {
        screen.start()
    }

    func stopScreenShare() {
        screen.stop()
    }

    fileprivate func screenSharingChanged(_ isOn: Bool) {
        applyVideoLimits()
        send(.screen(isOn: isOn))
        onScreenShare?(isOn)
    }
}

nonisolated enum CallMediaError: Error {
    case couldNotCreateConnection
}

/// WebRTC calls its delegate on its own thread. This moves each event to the main thread.
private nonisolated final class PeerConnectionObserver: NSObject, LKRTCPeerConnectionDelegate, @unchecked Sendable {
    /// Set and read on the main thread only.
    nonisolated(unsafe) weak var session: CallMediaSession?

    func peerConnection(_ peerConnection: LKRTCPeerConnection, didGenerate candidate: LKRTCIceCandidate) {
        let value = CallIceCandidate(
            sdp: candidate.sdp,
            sdpMid: candidate.sdpMid,
            sdpMLineIndex: candidate.sdpMLineIndex
        )
        onMain { $0.sendCandidate(value) }
    }

    func peerConnection(_ peerConnection: LKRTCPeerConnection, didChange newState: LKRTCPeerConnectionState) {
        onMain { $0.connectionStateChanged(newState) }
    }

    private func onMain(_ body: @escaping @MainActor (CallMediaSession) -> Void) {
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                if let session = self.session {
                    body(session)
                }
            }
        }
    }

    func peerConnection(_ peerConnection: LKRTCPeerConnection, didChange stateChanged: LKRTCSignalingState) {}
    func peerConnection(_ peerConnection: LKRTCPeerConnection, didAdd stream: LKRTCMediaStream) {}
    func peerConnection(_ peerConnection: LKRTCPeerConnection, didRemove stream: LKRTCMediaStream) {}
    func peerConnectionShouldNegotiate(_ peerConnection: LKRTCPeerConnection) {}
    func peerConnection(_ peerConnection: LKRTCPeerConnection, didChange newState: LKRTCIceConnectionState) {}
    func peerConnection(_ peerConnection: LKRTCPeerConnection, didChange newState: LKRTCIceGatheringState) {}
    func peerConnection(_ peerConnection: LKRTCPeerConnection, didRemove candidates: [LKRTCIceCandidate]) {}
    func peerConnection(_ peerConnection: LKRTCPeerConnection, didOpen dataChannel: LKRTCDataChannel) {}
}
