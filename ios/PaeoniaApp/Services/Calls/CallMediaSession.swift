import Foundation
import Network
@preconcurrency import LiveKitWebRTC

/// The audio and video connection between the two phones for one call, set up over the relay.
///
/// Both media sections are in the first offer, so turning a camera on or off swaps the video
/// sender's track and never needs a new offer. The caller offers whenever the partner's phone is
/// in the relay room and the phones are not connected. A later offer restarts the network path
/// (an ICE restart), which is how the call recovers after a drop or a network change.
final class CallMediaSession {
    nonisolated enum Role: Sendable {
        /// Sends the offers. The phone that started the call.
        case offerer
        case answerer
    }

    /// True when the phones reached each other, false when the connection dropped.
    var onConnectionChange: ((Bool) -> Void)?
    var onPartnerCamera: ((Bool) -> Void)?

    private let role: Role
    private let relay: CallRelay
    private let peerConnection: LKRTCPeerConnection
    private let observer: PeerConnectionObserver
    private let audioTrack: LKRTCAudioTrack
    private let videoTrack: LKRTCVideoTrack
    private let camera: CallCamera
    private let partnerFeed: CallVideoFeed
    private let localFeed: CallVideoFeed
    private let statsLog = CallStatsLog()
    private var videoTransceiver: LKRTCRtpTransceiver?
    private var remoteVideoTrack: LKRTCVideoTrack?
    private var isCameraOn: Bool
    /// Counts camera starts, so only the newest one ends the wait in `localFeed`.
    private var cameraStarts = 0
    private var isConnected = false
    /// The number of the newest offer this phone sent. Only its answer applies.
    private var offerNumber = 0
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
    }

    init(
        callID: UUID,
        role: Role,
        servers: CallIceServers,
        backend: CallBackend,
        partnerFeed: CallVideoFeed,
        localFeed: CallVideoFeed,
        isMuted: Bool,
        isCameraOn: Bool,
        isFrontCamera: Bool
    ) throws {
        let factory = CallMediaFactory.shared
        let observer = PeerConnectionObserver()
        self.role = role
        peerConnection = try Self.makePeerConnection(servers: servers, observer: observer)
        self.observer = observer
        self.partnerFeed = partnerFeed
        self.localFeed = localFeed
        self.isCameraOn = isCameraOn
        relay = CallRelay(callID: callID, backend: backend)
        audioTrack = factory.audioTrack(
            with: factory.audioSource(with: LKRTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil)),
            trackId: "audio"
        )
        audioTrack.isEnabled = !isMuted
        let videoSource = factory.videoSource()
        videoTrack = factory.videoTrack(with: videoSource, trackId: "video")
        camera = CallCamera(source: videoSource)
        let (stream, continuation) = AsyncStream.makeStream(of: Work.self)
        work = continuation

        videoTrack.add(localFeed)
        if role == .offerer {
            addTransceivers()
        }
        observer.session = self
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
        }
        videoTransceiver?.sender.track = isOn ? videoTrack : nil
        relay.send(.camera(isOn: isOn))
    }

    /// The local video keeps the old camera's last frame and mirroring until the new camera
    /// sends, so flipping never shows the old picture mirrored the new way.
    private func startCamera(front: Bool) {
        cameraStarts += 1
        let start = cameraStarts
        localFeed.cameraWillStart()
        camera.start(front: front) { [weak self] in
            guard let self, start == cameraStarts else { return }
            localFeed.cameraStarted(isMirrored: front)
        }
    }

    // MARK: Signaling

    private func handle(_ item: Work) async {
        switch item {
        case .partnerPresent:
            // The partner may have missed the last camera message while their phone reconnected.
            relay.send(.camera(isOn: isCameraOn))
            guard !isConnected else { return }
            switch role {
            case .offerer:
                queueOffer()
            case .answerer where peerConnection.remoteDescription != nil:
                relay.send(.restart)
            case .answerer:
                break
            }
        case let .signal(message):
            await receive(message)
        case .offer:
            isOfferQueued = false
            await sendOffer()
        }
    }

    /// Offers once for every reason to offer that arrives before the offer goes out.
    private func queueOffer() {
        guard !isOfferQueued else { return }
        isOfferQueued = true
        work.yield(.offer)
    }

    private func receive(_ message: CallSignal.Message) async {
        switch message {
        case let .offer(sdp, number) where role == .answerer:
            await acceptOffer(sdp, number: number)
        case let .answer(sdp, number) where role == .offerer:
            guard number == offerNumber, peerConnection.signalingState == .haveLocalOffer else { return }
            try? await peerConnection.setRemoteDescription(LKRTCSessionDescription(type: .answer, sdp: sdp))
            await addPendingCandidates()
        case let .candidate(candidate):
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
        case let .camera(isOn):
            onPartnerCamera?(isOn)
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
            relay.send(.offer(sdp: offer.sdp, number: offerNumber))
        } catch {
            // The next time the partner joins, or the call's connect timer, tries again.
        }
    }

    private func acceptOffer(_ sdp: String, number: Int) async {
        do {
            try await peerConnection.setRemoteDescription(LKRTCSessionDescription(type: .offer, sdp: sdp))
            if videoTransceiver == nil {
                attachAnswererTracks()
            }
            await addPendingCandidates()
            let answer = try await CallCodecs.withOpusDTX(peerConnection.answer(
                for: LKRTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil)
            ))
            try await peerConnection.setLocalDescription(answer)
            relay.send(.answer(sdp: answer.sdp, number: number))
        } catch {
            // The caller offers again when the connection does not come up.
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

// MARK: Tracks

extension CallMediaSession {
    /// The caller's first offer carries audio and video both ways.
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
            case .video:
                useVideoTransceiver(transceiver)
            default:
                break
            }
        }
    }

    private func useVideoTransceiver(_ transceiver: LKRTCRtpTransceiver) {
        videoTransceiver = transceiver
        transceiver.sender.track = isCameraOn ? videoTrack : nil
        remoteVideoTrack = transceiver.receiver.track as? LKRTCVideoTrack
        remoteVideoTrack?.add(partnerFeed)
    }

    // MARK: Connection

    fileprivate func sendCandidate(_ candidate: CallIceCandidate) {
        relay.send(.candidate(candidate))
    }

    fileprivate func connectionStateChanged(_ state: LKRTCPeerConnectionState) {
        switch state {
        case .connected:
            guard !isConnected else { return }
            isConnected = true
            statsLog.start(peerConnection)
            onConnectionChange?(true)
        case .disconnected, .failed:
            guard isConnected else { return }
            isConnected = false
            statsLog.stop()
            onConnectionChange?(false)
        default:
            break
        }
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

nonisolated enum CallMediaError: Error {
    case couldNotCreateConnection
}

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
