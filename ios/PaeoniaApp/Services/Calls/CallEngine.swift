import AVFoundation
import Foundation
import UIKit

extension CallCenter {
    /// The app's one call center. The app delegate creates it at launch, so PushKit and the system
    /// call UI are ready before any screen exists, even when signed out.
    static let shared: CallCenter = {
        #if targetEnvironment(simulator)
        let engine = CallEngine(system: SimulatorCallSystem())
        #else
        let engine = CallEngine(system: LiveCommunicationCallSystem())
        #endif
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

    /// Ends the call on this phone and on the server before sign-out, account deletion or the end
    /// of the relationship takes the sign-in or the partner away.
    func endCallForLeaving() async {
        await (engine as? CallEngine)?.endForLeaving()
    }

    /// Ends the call while iOS closes the app, such as when the person swipes it away.
    func endCallBeforeTermination() {
        (engine as? CallEngine)?.endBeforeTermination()
    }
}

/// Runs calls with the partner: the system call UI (`CallSystem`), VoIP pushes, the
/// server's call row, call setup over the relay, and the WebRTC media. `CallMachine` decides
/// every phase change. This class carries out what it asks and publishes the result in
/// `CallCenter.session`. `docs/calling-plan.md` has the design.
final class CallEngine {
    /// How long the call screen shows why a call ended.
    static let endedLinger: Duration = .seconds(2)
    static let heartbeatInterval: Duration = .seconds(15)
    /// A heartbeat that takes longer is dropped, so the next one goes out on time.
    static let heartbeatTimeout: Duration = .seconds(5)
    /// How long leaving the account or the relationship waits for the server to hear the call end.
    static let leavingTimeout: Duration = .seconds(4)
    /// The local ring timer fires this long after the server's deadline, which the live query
    /// normally reports first.
    static let ringGrace: TimeInterval = 5
    static let ringWatchInterval: Duration = .seconds(2)

    weak var center: CallCenter?
    let backend = CallBackend()
    let deviceID = CallDeviceID.current
    let system: any CallSystem
    let partnerVideo = CallVideoFeed()
    let localVideo = CallVideoFeed()
    let partnerScreen = CallVideoFeed()
    let sounds = CallSoundPlayer()
    private(set) lazy var pictureInPicture = CallPictureInPicture(partner: partnerVideo, partnerScreen: partnerScreen)
    var run: CallRun?
    /// Calls that rang on this phone in this run of the app. The push and the live query can both
    /// announce one call, and only the first counts.
    var reportedCallIDs: Set<UUID> = []
    /// Calls that ended on this phone, so a late push for one is reported and ended at once.
    var finishedCallIDs: Set<UUID> = []
    /// The partner's time zone from the last read, nil when unknown or while their location
    /// sharing is off.
    var knownPartnerTimeZone: TimeZone?
    var partnerTimeZoneRefresh: Task<Void, Never>?
    private var pushRegistry: CallPushRegistry?
    private var routeObserver: (any NSObjectProtocol)?
    private var backgroundObserver: (any NSObjectProtocol)?
    private var audioRestartObserver: (any NSObjectProtocol)?
    private var clearTask: Task<Void, Never>?

    init(system: any CallSystem) {
        self.system = system
    }

    func start() {
        CallAudio.configureAtLaunch(sounds: sounds)
        system.start(delegate: self)
        partnerVideo.onFrameSize = { [weak self] size in self?.partnerVideoSizeChanged(size) }
        partnerVideo.onStallChange = { [weak self] isStalled in self?.partnerVideoStallChanged(isStalled) }
        partnerScreen.onFrameSize = { [weak self] size in self?.partnerScreenSizeChanged(size) }
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
        backgroundObserver = handRingsToSystemInBackground()
        audioRestartObserver = rebuildAudioAfterServiceRestarts()
        watchLiveCalls()
    }

    /// No call is ringing or running, though one may still show why it ended.
    var isIdle: Bool {
        run?.isFinished ?? true
    }

    // MARK: Running the state machine

    /// Starts a call: the session the screens show, the call's audio category, and its first timers.
    /// A call opens the full call screen, except a ring inside the app, which starts as the pill.
    @discardableResult
    func begin(_ run: CallRun, effects: [CallEffect], ringsInApp: Bool = false) -> CallRun {
        removeRun()
        self.run = run
        watchPower(of: run)
        PaeoniaAudioSession.setCallActive(true)
        CallAudio.prepareCategory()
        center?.presentation = ringsInApp ? .bubble : .full
        center?.session = CallSession(
            id: run.callID,
            direction: run.machine.direction,
            phase: run.machine.phase,
            audioRoute: CallAudio.currentRoute(),
            ringsInApp: ringsInApp
        )
        for effect in effects {
            perform(effect, for: run)
        }
        updateRingWatch(run)
        return run
    }

    func send(_ event: CallEvent, to run: CallRun) {
        guard run === self.run else { return }
        let previous = run.machine.phase
        let effects = run.machine.reduce(event, now: .now)
        noteQuality(of: run, from: previous)
        publish(run, previous: previous)
        for effect in effects {
            perform(effect, for: run)
        }
        updateHeartbeat(run)
        updateRingWatch(run)
    }

    private func publish(_ run: CallRun, previous: CallPhase) {
        guard let center, let current = center.session else { return }
        var session = current
        // The id changes when `start_call` answered the partner's ringing call instead.
        session.id = run.callID
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
        case .prepareMedia, .connectMedia:
            connectMedia(run)
        case .restartConnection:
            run.media?.restart()
        case let .finish(reason, server, goodbye):
            finish(run, reason: reason, server: server, goodbye: goodbye)
        case let .ringback(isOn):
            CallAudio.logState(isOn ? "ringback on" : "ringback off")
            sounds.setRingback(isOn)
        case let .playConnected(haptic):
            playConnected(haptic: haptic)
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
            partnerScreenFeed: partnerScreen,
            isMuted: session?.isMuted ?? false,
            isCameraOn: session?.isCameraOn ?? false,
            isFrontCamera: session?.isUsingFrontCamera ?? true,
            heat: run.power?.state.heat ?? .normal
        )
        media.onConnectionChange = { [weak self, weak run] isConnected in
            guard let self, let run else { return }
            send(isConnected ? .connected : .connectionLost, to: run)
        }
        media.onPartnerCamera = { [weak self, weak run] state in
            guard let self, let run else { return }
            partnerCameraChanged(state, in: run)
        }
        watchConnection(of: media, in: run)
        watchScreens(of: media, in: run)
        media.onBackCameraZoom = { [weak self, weak run] zoom in
            guard let self, let run, run === self.run else { return }
            center?.backCameraZoom = zoom
        }
        media.onStatsSample = { [weak run] sample in
            run?.quality.add(sample, thermalState: ProcessInfo.processInfo.thermalState)
        }
        return media
    }

    /// Tells the server this phone is still in the call, while the call is answered.
    private func updateHeartbeat(_ run: CallRun) {
        guard run.heartbeat == nil, run.machine.phase.isAnswered else { return }
        let callID = run.callID
        run.heartbeat = Task { [backend] in
            while !Task.isCancelled {
                let beat = Task { try? await backend.heartbeat(callID: callID) }
                try? await Task.sleep(for: Self.heartbeatTimeout)
                beat.cancel()
                try? await Task.sleep(for: Self.heartbeatInterval - Self.heartbeatTimeout)
            }
        }
    }

    private func finish(_ run: CallRun, reason: CallEndReason, server: CallServerEnd?, goodbye: CallGoodbye?) {
        run.stop()
        sendQualityReport(of: run, reason: reason)
        sounds.stopAll()
        CallAudio.stopEngine()
        sayGoodbye(goodbye, in: run)
        finishedCallIDs.formUnion([run.callID, run.conversationID])
        pictureInPicture.setEnabled(false)
        if let server {
            let callID = run.callID
            run.serverEnd = Task { [backend] in
                switch server {
                case .decline:
                    try? await backend.declineCall(callID: callID)
                case .end:
                    try? await backend.endCall(callID: callID)
                }
            }
        }
        if !run.isEndingFromSystem {
            afterGoodbye(in: run) { [system] in
                system.reportEnded(run.conversationID, reason: reason)
            }
        }
        scheduleClear(of: run)
        refreshCallContext()
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
        // Off the main thread, because setting the category can block for a moment, and after
        // the engine has stopped.
        CallAudio.queue.async { PaeoniaAudioSession.useAmbient() }
    }

    /// Drops the finished call and its video. The caller decides what happens to the audio
    /// session: a new call keeps it, and anything else restores it with `restoreAppAudio()`.
    func removeRun() {
        clearTask?.cancel()
        clearTask = nil
        run?.stop()
        run = nil
        center?.backCameraZoom = nil
        sounds.stopAll()
        CallAudio.stopEngine()
        partnerVideo.clear()
        localVideo.clear()
        partnerScreen.clear()
    }
}

// MARK: Media

private extension CallEngine {
    /// Starts the call's media session once, while the call rings or after the answer, and lets
    /// this phone answer the caller's offer once the call is answered. A start that fails while
    /// the call rings leaves the answer to try again. A start that fails after the answer ends
    /// the call.
    func connectMedia(_ run: CallRun) {
        if let media = run.media {
            if run.machine.phase.isAnswered {
                media.answer()
            }
        } else if run.mediaStart == nil {
            run.mediaStart = startMedia(run)
        }
    }

    func startMedia(_ run: CallRun) -> Task<Void, Never> {
        let isAnswered = run.machine.phase.isAnswered
        return Task {
            do {
                let servers = try await backend.iceServers(callID: run.callID)
                run.mediaStart = nil
                guard run === self.run, !run.isFinished else { return }
                let media = try makeMedia(for: run, servers: servers)
                run.media = media
                media.start()
                if run.machine.phase.isAnswered {
                    media.answer()
                }
            } catch {
                run.mediaStart = nil
                guard run === self.run, !run.isFinished else { return }
                if isAnswered {
                    send(.failed(CallFailure(error)), to: run)
                } else if run.machine.phase.isAnswered {
                    connectMedia(run)
                }
            }
        }
    }
}

extension CallEngine {
    /// Hangs up and waits, up to `leavingTimeout`, for the server to hear it while requests still
    /// carry the sign-in.
    func endForLeaving() async {
        guard let run, !run.isFinished else { return }
        send(.hangUp, to: run)
        guard let serverEnd = run.serverEnd else { return }
        let timeout = Task {
            try? await Task.sleep(for: Self.leavingTimeout)
            serverEnd.cancel()
        }
        await serverEnd.value
        timeout.cancel()
    }

    /// Hangs up while iOS closes the app. Nothing runs once `applicationWillTerminate` returns, so
    /// this keeps the main run loop going until the server has heard, which `endForLeaving`
    /// limits to `leavingTimeout`. Without it the partner's phone shows "Reconnecting" for 30
    /// seconds before the call ends.
    func endBeforeTermination() {
        guard let run, !run.isFinished else { return }
        var hasEnded = false
        Task {
            await endForLeaving()
            hasEnded = true
        }
        while !hasEnded {
            RunLoop.current.run(mode: .default, before: .now + 0.05)
        }
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
