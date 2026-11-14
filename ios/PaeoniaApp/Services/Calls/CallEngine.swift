import AVFoundation
import Foundation
@preconcurrency import LiveCommunicationKit
import UIKit

extension CallCenter {
    /// The app's one call center. The app delegate creates it at launch, so PushKit and the system
    /// call UI are ready before any screen exists, even when signed out.
    static let shared: CallCenter = {
        let engine = CallEngine()
        let center = CallCenter(engine: engine)
        engine.center = center
        if !PaeoniaApp.isHostingUnitTests {
            engine.start()
        }
        return center
    }()

    /// A call started from the Phone app's Recents or from Siri.
    func continueCall(from activity: NSUserActivity) {
        (engine as? CallEngine)?.startCall(from: activity)
    }
}

/// Runs calls with the partner: the system call UI (LiveCommunicationKit), VoIP pushes, the
/// server's call row, call setup over the relay, and the WebRTC media. `CallMachine` decides
/// every phase change. This class carries out what it asks and publishes the result in
/// `CallCenter.session`. `docs/calling-plan.md` has the design.
final class CallEngine {
    /// How long the call screen shows why a call ended.
    static let endedLinger: Duration = .seconds(2)
    static let heartbeatInterval: Duration = .seconds(15)
    /// The local ring timer fires this long after the server's deadline, which the live query
    /// normally reports first.
    static let ringGrace: TimeInterval = 5

    weak var center: CallCenter?
    let backend = CallBackend()
    let deviceID = CallDeviceID.current
    /// LiveCommunicationKit's manager is safe to call from any thread, but is not marked
    /// `Sendable`, and its async methods leave the main actor.
    nonisolated(unsafe) let manager: ConversationManager
    let partnerVideo = CallVideoFeed()
    let localVideo = CallVideoFeed()
    private(set) lazy var pictureInPicture = CallPictureInPicture(feed: partnerVideo)
    var run: CallRun?
    /// Calls reported to the system as incoming in this run of the app. The push and the live
    /// query can both announce one call, and only the first report counts.
    var reportedCallIDs: Set<UUID> = []
    /// Calls that ended on this phone, so a late push for one is reported and ended at once.
    var finishedCallIDs: Set<UUID> = []
    private let systemDelegate = CallConversationDelegate()
    private var pushRegistry: CallPushRegistry?
    private var routeObserver: (any NSObjectProtocol)?
    private var clearTask: Task<Void, Never>?

    init() {
        manager = ConversationManager(configuration: ConversationManager.Configuration(
            ringtoneName: nil,
            iconTemplateImageData: nil,
            maximumConversationGroups: 1,
            maximumConversationsPerConversationGroup: 1,
            includesConversationInRecents: true,
            supportsVideo: true,
            supportedHandleTypes: [.generic]
        ))
    }

    func start() {
        CallAudio.configureAtLaunch()
        systemDelegate.engine = self
        manager.delegate = systemDelegate
        pushRegistry = CallPushRegistry(
            onToken: { token in
                Task { await PushRegistrationServiceFactory.shared.updateVoIPPushToken(token) }
            },
            onPush: { [weak self] ring, mustReport, completion in
                guard let self else { return completion() }
                receivePush(ring, mustReport: mustReport, completion: completion)
            }
        )
        routeObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshAudioRoute() }
        }
        watchLiveCalls()
    }

    /// No call is ringing or running, though one may still show why it ended.
    var isIdle: Bool {
        run?.isFinished ?? true
    }

    // MARK: Running the state machine

    /// Starts a call: the session the screens show, the call's audio category, and its first timers.
    @discardableResult
    func begin(_ run: CallRun, effects: [CallEffect]) -> CallRun {
        removeRun()
        self.run = run
        PaeoniaAudioSession.setCallActive(true)
        CallAudio.prepareCategory()
        localVideo.isMirrored = true
        center?.presentation = .full
        center?.session = CallSession(
            id: run.callID,
            direction: run.machine.direction,
            phase: run.machine.phase,
            audioRoute: CallAudio.currentRoute()
        )
        for effect in effects {
            perform(effect, for: run)
        }
        return run
    }

    func send(_ event: CallEvent, to run: CallRun) {
        guard run === self.run else { return }
        let previous = run.machine.phase
        let effects = run.machine.reduce(event, now: .now)
        publish(run, previous: previous)
        for effect in effects {
            perform(effect, for: run)
        }
        updateHeartbeat(run)
    }

    private func publish(_ run: CallRun, previous: CallPhase) {
        guard let center, let current = center.session else { return }
        var session = current
        if session.id != run.callID {
            // `start_call` answered the partner's ringing call, so the call took its id.
            session = CallSession(
                id: run.callID,
                direction: current.direction,
                phase: current.phase,
                isMuted: current.isMuted,
                audioRoute: current.audioRoute,
                isCameraOn: current.isCameraOn,
                isPartnerCameraOn: current.isPartnerCameraOn,
                isUsingFrontCamera: current.isUsingFrontCamera
            )
        }
        session.phase = run.machine.phase
        if session != current {
            center.session = session
        }
        reportProgress(of: run, from: previous)
        updatePictureInPicture()
    }

    private func perform(_ effect: CallEffect, for run: CallRun) {
        switch effect {
        case let .startTimer(timer, fireAt):
            run.timers[timer]?.cancel()
            run.timers[timer] = Task { [weak self] in
                try? await Task.sleep(for: .seconds(max(0, fireAt.timeIntervalSinceNow)))
                guard !Task.isCancelled else { return }
                self?.send(.timerFired(timer), to: run)
            }
        case let .cancelTimer(timer):
            run.timers.removeValue(forKey: timer)?.cancel()
        case .connectMedia:
            connectMedia(run)
        case .restartConnection:
            run.media?.restart()
        case let .finish(reason, server):
            finish(run, reason: reason, server: server)
        }
    }

    private func connectMedia(_ run: CallRun) {
        Task {
            do {
                let servers = try await backend.iceServers(callID: run.callID)
                guard run === self.run, !run.isFinished else { return }
                let media = try makeMedia(for: run, servers: servers)
                run.media = media
                media.start()
            } catch {
                send(.failed(CallFailure(error)), to: run)
            }
        }
    }

    private func makeMedia(for run: CallRun, servers: CallIceServers) throws -> CallMediaSession {
        let session = center?.session
        let media = try CallMediaSession(
            callID: run.callID,
            role: run.role,
            servers: servers,
            backend: backend,
            partnerFeed: partnerVideo,
            localFeed: localVideo,
            isMuted: session?.isMuted ?? false,
            isCameraOn: session?.isCameraOn ?? false,
            isFrontCamera: session?.isUsingFrontCamera ?? true
        )
        media.onConnectionChange = { [weak self, weak run] isConnected in
            guard let self, let run else { return }
            send(isConnected ? .connected : .connectionLost, to: run)
        }
        media.onPartnerCamera = { [weak self, weak run] isOn in
            guard let self, let run else { return }
            partnerCameraChanged(isOn, in: run)
        }
        return media
    }

    /// Tells the server this phone is still in the call, while the call is answered.
    private func updateHeartbeat(_ run: CallRun) {
        guard run.heartbeat == nil, run.machine.phase.isAnswered else { return }
        let callID = run.callID
        run.heartbeat = Task { [backend] in
            while !Task.isCancelled {
                try? await backend.heartbeat(callID: callID)
                try? await Task.sleep(for: Self.heartbeatInterval)
            }
        }
    }

    private func finish(_ run: CallRun, reason: CallEndReason, server: CallServerEnd?) {
        run.stop()
        finishedCallIDs.formUnion([run.callID, run.conversationID])
        pictureInPicture.setEnabled(false)
        if let server {
            let callID = run.callID
            Task { [backend] in
                switch server {
                case .decline:
                    try? await backend.declineCall(callID: callID)
                case .end:
                    try? await backend.endCall(callID: callID)
                }
            }
        }
        if !run.isEndingFromSystem, let conversation = conversation(of: run) {
            manager.reportConversationEvent(.conversationEnded(.now, Self.systemReason(reason)), for: conversation)
        }
        scheduleClear(of: run)
    }

    // MARK: Ending

    /// Shows why a call could not start, such as a call back to someone who is no longer the
    /// partner, then clears it like an ended call.
    func showEnded(_ reason: CallEndReason) {
        guard isIdle else { return }
        if run != nil {
            removeRun()
            restoreAppAudio()
        }
        center?.presentation = .full
        center?.session = CallSession(id: UUID(), direction: .outgoing, phase: .ended(reason))
        clearTask = Task { [weak self] in
            try? await Task.sleep(for: Self.endedLinger)
            guard !Task.isCancelled, let self, run == nil else { return }
            center?.session = nil
        }
    }

    private func scheduleClear(of run: CallRun) {
        clearTask?.cancel()
        clearTask = Task { [weak self] in
            try? await Task.sleep(for: Self.endedLinger)
            guard !Task.isCancelled, let self, self.run === run else { return }
            removeRun()
            center?.session = nil
            restoreAppAudio()
        }
    }

    /// Gives the audio session back to the rest of the app once no call needs it.
    private func restoreAppAudio() {
        PaeoniaAudioSession.setCallActive(false)
        // Off the main thread, because setting the category can block for a moment.
        Task.detached(priority: .utility) { PaeoniaAudioSession.useAmbient() }
    }

    /// Drops the finished call and its video. The caller decides what happens to the audio
    /// session: a new call keeps it, and anything else restores it with `restoreAppAudio()`.
    func removeRun() {
        clearTask?.cancel()
        clearTask = nil
        run?.stop()
        run = nil
        partnerVideo.clear()
        localVideo.clear()
    }
}

private extension CallPhase {
    /// Someone answered, so the server's row is active and wants heartbeats.
    var isAnswered: Bool {
        switch self {
        case .connecting, .active, .reconnecting: true
        case .ringing, .ended: false
        }
    }
}
