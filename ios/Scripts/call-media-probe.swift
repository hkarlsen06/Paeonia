// Runs a call between two WebRTC connections in one Mac process, with the app's real
// CallCodecs.swift and CallStatsLog.swift, and checks how the call compresses its media.
// Run it through scripts/call-media-probe, which finds the pinned LiveKitWebRTC build.
// `--defaults` skips CallCodecs to show WebRTC's own choices. The checks of CallCodecs
// choices then have to fail, which shows the probe tells the two apart (see `Check.Kind`).

import CoreMedia
import CoreVideo
import Foundation
@preconcurrency import LiveKitWebRTC

@main
enum CallMediaProbe {
    /// How long the call runs, then the caller shares its screen beside its camera in each of
    /// `ScreenPhase.all`.
    static let callSeconds = 20.0
    static let screenSeconds = 10.0
    static let sampleInterval = Duration.milliseconds(100)

    static func main() async {
        let tuned = !CommandLine.arguments.contains("--defaults")
        say(tuned ? "Mode: CallCodecs" : "Mode: WebRTC defaults")
        LKRTCInitializeSSL()
        let microphone = FakeMicrophone()
        let factory = LKRTCPeerConnectionFactory(
            encoderFactory: tuned ? CallVideoEncoderFactory() : LKRTCDefaultVideoEncoderFactory(),
            decoderFactory: LKRTCDefaultVideoDecoderFactory(),
            audioDevice: microphone
        )
        let caller = Peer(name: "caller", factory: factory, tuned: tuned)
        let partner = Peer(name: "partner", factory: factory, tuned: tuned)
        await connect(caller, partner, factory: tuned ? factory : nil)
        say("Connected. Sending a voice-like sound and silence by turns of 1 s, and panning 1080p noise at 30 fps, "
            + "for \(Int(callSeconds)) s.")

        let peers = [caller, partner]
        let call = await run(peers, microphone)
        say("Sharing the caller's \(ScreenSource.width)x\(ScreenSource.height) screen of scrolling text with a video "
            + "playing on it, at about 48 fps at uneven gaps, beside its camera, for \(Int(screenSeconds)) s on a "
            + "cool phone's limits, then on a warm one's and on a hot one's.")
        let screenPhases = await shareScreen(caller, tuned: tuned, microphone)
        let afterVoice = await shareAfterVoice(factory: factory, tuned: tuned, microphone)

        let offer = caller.connection.localDescription?.sdp ?? ""
        let answer = partner.connection.localDescription?.sdp ?? ""
        say("Offer:\n" + mediaLines(offer))
        say("Answer:\n" + mediaLines(answer))
        let checks = [
            Check("the offer asks for Opus DTX (usedtx=1)", .tuning, holds: opusAsksForDTX(offer)),
            Check("the answer asks for Opus DTX (usedtx=1)", .tuning, holds: opusAsksForDTX(answer)),
        ]
            + peers.flatMap { checks($0, call[$0.name] ?? []) }
            + screenChecks(caller, shownBy: partner, screenPhases)
            + afterVoiceChecks(afterVoice)
        let passed = report(checks, tuned: tuned)
        caller.connection.close()
        partner.connection.close()
        exit(passed ? 0 : 1)
    }

    /// Runs the call and returns each peer's samples.
    static func run(_ peers: [Peer], _ microphone: FakeMicrophone) async -> [String: [Timed]] {
        let statsLog = CallStatsLog { say("CallStatsLog caller: \($0)") }
        statsLog.start(peers[0].connection)
        defer { statsLog.stop() }
        return await record(peers, for: callSeconds, microphone) { _, _ in }
    }

    /// Samples each peer's stats every `sampleInterval` for `seconds`.
    static func record(
        _ peers: [Peer],
        for seconds: Double,
        _ microphone: FakeMicrophone,
        onSample: (Peer, CallStatsSample) -> Void
    ) async -> [String: [Timed]] {
        var samples: [String: [Timed]] = [:]
        let start = ContinuousClock.now
        while ContinuousClock.now - start < .seconds(seconds) {
            for peer in peers {
                let sample = await CallStatsSample.read(peer.connection)
                onSample(peer, sample)
                samples[peer.name, default: []].append(Timed(microphone.seconds, sample))
            }
            try? await Task.sleep(for: sampleInterval)
        }
        return samples
    }

    /// Offers and answers the way `CallMediaSession` does, and applies `CallCodecs` at the same
    /// points when `factory` is set.
    static func connect(
        _ caller: Peer,
        _ partner: Peer,
        factory: LKRTCPeerConnectionFactory?,
        callerCamera: Bool = true
    ) async {
        let configure: (LKRTCRtpTransceiver) -> Void = { transceiver in
            factory.map { CallCodecs.configure(transceiver, factory: $0) }
        }
        let dtx: (LKRTCSessionDescription) -> LKRTCSessionDescription = { description in
            factory == nil ? description : CallCodecs.withOpusDTX(description)
        }
        let transceiverInit = LKRTCRtpTransceiverInit()
        transceiverInit.direction = .sendRecv
        if let audio = caller.connection.addTransceiver(with: caller.audioTrack, init: transceiverInit) {
            configure(audio)
        }
        if let video = caller.connection.addTransceiver(of: .video, init: transceiverInit) {
            configure(video)
            video.sender.track = callerCamera ? caller.videoTrack : nil
        }
        addScreenTransceiver(to: caller, tuned: factory != nil, configure: configure)
        do {
            try await caller.connection.setLocalDescription(dtx(caller.connection.offer(for: noConstraints)))
            try await partner.connection.setRemoteDescription(caller.gatheredDescription())
            for (index, transceiver) in partner.connection.transceivers.enumerated() {
                transceiver.setDirection(.sendRecv, error: nil)
                configure(transceiver)
                // Audio, then the camera. The screen's transceiver sends nothing until a share.
                transceiver.sender.track = [partner.audioTrack, partner.videoTrack].dropFirst(index).first
            }
            try await partner.connection.setLocalDescription(dtx(partner.connection.answer(for: noConstraints)))
            try await caller.connection.setRemoteDescription(partner.gatheredDescription())
        } catch {
            fail("offer and answer: \(error)")
        }
        caller.watchPartnerVideo()
        partner.watchPartnerVideo()
        let connected = await waitUntil(seconds: 10) {
            caller.connection.connectionState == .connected && partner.connection.connectionState == .connected
        }
        if !connected {
            fail("the two connections never connected")
        }
    }

    static func checks(_ peer: Peer, _ samples: [Timed]) -> [Check] {
        guard let last = samples.last?.sample else { fail("no stats from \(peer.name)") }
        let name = peer.name
        let audio = AudioTurns(samples)
        let target = samples.compactMap(\.sample.camera.sent.targetBitsPerSecond).max() ?? 0
        let peak = (two: peakVideoBitsPerSecond(samples, over: 2), ten: peakVideoBitsPerSecond(samples, over: 10))
        let widest = samples.compactMap(\.sample.camera.frameWidth).max() ?? 0
        let shown = peer.partnerVideo.snapshot()
        say("\(name) audio: \(Int(audio.speech.packetsPerSecond)) packets/s and \(Int(audio.speech.bytesPerPacket)) "
            + "bytes a packet in speech, \(Int(audio.silence.packetsPerSecond)) packets/s in silence")
        let path = last.mediaPath.map { "\($0)" } ?? "unknown"
        say("\(name) video on the \(path) path: \(last.camera.sent.codec ?? "-"), "
            + "highest encoder target \(Int(target / 1_000)) kbps, peak sent \(Int(peak.two / 1_000)) kbps over 2 s "
            + "and \(Int(peak.ten / 1_000)) kbps over 10 s, widest frame \(widest); it showed \(shown.frames) "
            + "partner frames, last \(shown.size)")
        return [
            Check("\(name) finds the direct path", .always, holds: last.mediaPath == .direct),
            Check(
                "\(name)'s audio packets in speech carry two Opus frames (RED): over 120 bytes, "
                    + "where one 32 kbps frame is 80",
                .tuning,
                holds: audio.speech.bytesPerPacket > 120
            ),
            Check(
                "\(name) sends under 30% as many audio packets in silence as in speech (DTX)",
                .tuning,
                holds: audio.silence.packetsPerSecond < 0.3 * audio.speech.packetsPerSecond
            ),
            Check("\(name) sends video as video/H265", .tuning, holds: last.camera.sent.codec == "video/H265"),
            Check(
                "\(name)'s video encoder target on the direct path goes over WebRTC's own 2.5 Mbps",
                .tuning,
                holds: target > 2_500_000
            ),
            Check("\(name)'s video encoder target stays at or under 4 Mbps", .always, holds: target <= 4_000_000),
            Check("\(name)'s sent video stays under 4.4 Mbps over every 10 s", .always, holds: peak.ten < 4_400_000),
            Check("\(name)'s sent video reaches over 1 Mbps", .always, holds: peak.two > 1_000_000),
            Check("\(name) shows over 100 frames of the partner's video", .always, holds: shown.frames > 100),
        ]
    }

    /// Prints each check and returns whether every one came out as this run expects.
    static func report(_ checks: [Check], tuned: Bool) -> Bool {
        var passed = true
        for check in checks {
            guard let wanted = check.expected(tuned: tuned) else {
                say("SKIP \(check.claim)")
                continue
            }
            passed = passed && check.holds == wanted
            say("\(check.holds == wanted ? "PASS" : "FAIL") \(wanted ? "" : "not: ")\(check.claim)")
        }
        return passed
    }

    static let noConstraints = LKRTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil)

    static func waitUntil(seconds: Double, _ condition: () -> Bool) async -> Bool {
        let start = ContinuousClock.now
        while !condition() {
            guard ContinuousClock.now - start < .seconds(seconds) else { return false }
            try? await Task.sleep(for: .milliseconds(50))
        }
        return true
    }

    nonisolated static func say(_ line: String) {
        FileHandle.standardOutput.write(Data((line + "\n").utf8))
    }

    static func fail(_ message: String) -> Never {
        FileHandle.standardError.write(Data("call-media-probe: \(message)\n".utf8))
        exit(1)
    }
}

/// The screen share: the caller shares a scrolling screen beside its camera.
extension CallMediaProbe {
    /// The third transceiver, which sends nothing until a share, as `CallMediaSession` adds it.
    static func addScreenTransceiver(to caller: Peer, tuned: Bool, configure: (LKRTCRtpTransceiver) -> Void) {
        let transceiverInit = LKRTCRtpTransceiverInit()
        transceiverInit.direction = .sendRecv
        guard let screen = caller.connection.addTransceiver(of: .video, init: transceiverInit) else {
            fail("could not add the caller's screen transceiver")
        }
        configure(screen)
        if tuned {
            CallCodecs.limitScreen(screen.sender, to: .screen())
        }
    }

    /// Turns the caller's screen share on the way `CallMediaSession` does, and records the caller
    /// in each phase.
    static func shareScreen(
        _ caller: Peer,
        tuned: Bool,
        _ microphone: FakeMicrophone
    ) async -> [(ScreenPhase, [Timed])] {
        caller.screenSender.track = caller.screenTrack
        caller.screen.start()
        let statsLog = CallStatsLog { say("CallStatsLog caller: \($0)") }
        statsLog.start(caller.connection)
        defer {
            statsLog.stop()
            caller.screen.stop()
        }
        var phases: [(ScreenPhase, [Timed])] = []
        for phase in ScreenPhase.all {
            if tuned {
                CallCodecs.limitVideo(
                    caller.videoSender,
                    to: CallVideoLimits(heat: phase.heat, besideScreen: true)
                )
                let screenLimits = CallVideoLimits.screen(heat: phase.heat)
                CallCodecs.limitScreen(caller.screenSender, to: screenLimits)
                caller.screen.setMaxFramesPerSecond(screenLimits.maxFramesPerSecond)
            }
            let samples = await record([caller], for: screenSeconds, microphone) { _, _ in }[caller.name] ?? []
            phases.append((phase, samples))
        }
        return phases
    }

    /// The caller's screen beside its camera, in each phase.
    static func screenChecks(_ caller: Peer, shownBy partner: Peer, _ phases: [(ScreenPhase, [Timed])]) -> [Check] {
        let shown = partner.partnerScreen.snapshot()
        say("partner showed \(shown.frames) frames of the caller's screen, last \(shown.size)")
        return phases.flatMap { screenChecks($0, $1) }
            + [Check("the partner shows over 100 frames of the caller's screen", .always, holds: shown.frames > 100)]
    }

    static func screenChecks(_ phase: ScreenPhase, _ samples: [Timed]) -> [Check] {
        let run = ScreenRun(samples)
        say("caller screen on \(phase.name): \(run.summary)")
        let caller = "the caller's screen on \(phase.name)"
        let camera = "the caller's camera beside its screen on \(phase.name)"
        let checks = [
            Check("\(caller) goes as video/H265", .tuning, holds: run.codec == "video/H265"),
            Check(
                "\(caller) sends about \(phase.framesPerSecond) fps: a median over 80% of it, and never 2 over",
                .tuning,
                holds: run.sends(about: phase.framesPerSecond)
            ),
            Check(
                "\(caller) fits its bits with a picture under \(phase.maxWidth) wide, not with fewer frames",
                .tuning,
                holds: (run.widths.min() ?? phase.maxWidth) < phase.maxWidth
            ),
            Check(
                "\(caller) has an encoder target at or under \(Int(phase.screenBudget / 1_000)) kbps",
                phase.screenBudgetKind,
                holds: run.screenTarget > 0 && run.screenTarget <= phase.screenBudget
            ),
            Check(
                "\(camera) stays at or under \(Int(phase.cameraBudget / 1_000)) kbps",
                .tuning,
                holds: run.cameraTarget > 0 && run.cameraTarget <= phase.cameraBudget
            ),
            Check("\(camera) sends at most \(phase.cameraMax) fps", .tuning, holds: run.cameraRate <= phase.cameraMax),
            Check(
                "the caller's screen and camera on \(phase.name) send under \(Int(phase.totalCap * 1.1 / 1_000)) kbps "
                    + "together over every 5 s",
                phase.totalCapKind,
                holds: run.peakTogether < phase.totalCap * 1.1
            ),
        ]
        guard phase.heat != .normal else { return checks }
        return checks + [Check(
            "\(caller) is never over \(phase.maxWidth) wide, the size the heat allows",
            .tuning,
            holds: !run.widths.isEmpty && run.widths.allSatisfy { $0 <= phase.maxWidth }
        )]
    }
}

/// A phone that has sent only its voice starts sharing its screen, as an iPad with its camera off
/// did on 2026-11-17 (`CallCodecs.startVideoEstimate`). The probe's peers probe their way higher
/// on the Mac's loopback, so the run sets the iPad's 300 kbps itself, which WebRTC lowers further
/// while only voice goes. It checks that the lift sets WebRTC's estimate, and that a share started
/// from it begins near full size, where one started from voice's estimate begins at a quarter of
/// the width.
extension CallMediaProbe {
    static let afterVoiceSeconds = 4.0
    /// About how long ScreenCaptureKit takes to start capturing after the person picks, which is
    /// the head start `CallMediaSession` gives the lift.
    static let captureStart = Duration.milliseconds(300)

    /// A new call whose caller keeps its camera off and shares its screen the way
    /// `CallMediaSession` starts one.
    static func shareAfterVoice(
        factory: LKRTCPeerConnectionFactory,
        tuned: Bool,
        _ microphone: FakeMicrophone
    ) async -> AfterVoice? {
        guard tuned else { return nil }
        say("Starting a new call whose caller sends only its voice, then shares its screen for "
            + "\(Int(afterVoiceSeconds)) s on a cool phone's limits.")
        let sharer = Peer(name: "sharer", factory: factory, tuned: true)
        let watcher = Peer(name: "watcher", factory: factory, tuned: true)
        defer {
            sharer.screen.stop()
            sharer.connection.close()
            watcher.connection.close()
        }
        await connect(sharer, watcher, factory: factory, callerCamera: false)
        let limits = CallVideoLimits.screen()
        CallCodecs.limitScreen(sharer.screenSender, to: limits)
        // WebRTC's own probing after the connection ends first, so it cannot lift the estimate.
        _ = await record([sharer], for: 3, microphone) { _, _ in }
        sharer.connection.setBweMinBitrateBps(nil, currentBitrateBps: NSNumber(value: 300_000), maxBitrateBps: nil)
        let voice = await record([sharer], for: 2, microphone) { _, _ in }[sharer.name] ?? []
        let available = voice.last?.sample.availableOutgoingBitsPerSecond
        CallCodecs.startVideoEstimate(sharer.connection, available: available, limits: limits)
        try? await Task.sleep(for: captureStart)
        let lifted = await CallStatsSample.read(sharer.connection).availableOutgoingBitsPerSecond
        sharer.screenSender.track = sharer.screenTrack
        sharer.screen.start()
        let share = await record([sharer], for: afterVoiceSeconds, microphone) { _, _ in }[sharer.name] ?? []
        return AfterVoice(voice: available, lifted: lifted, share: share)
    }

    static func afterVoiceChecks(_ run: AfterVoice?) -> [Check] {
        guard let run else { return [] }
        let widths = run.share.compactMap(\.sample.screen.frameWidth)
        let sent = peakBitsPerSecond(run.share, over: 1) { $0.screen.sent.bytesSent }
        let start = min(CallCodecs.videoStartBitsPerSecond, CallVideoLimits.screen().maxBitsPerSecond)
        say("screen after voice alone: estimate \(Int((run.voice ?? 0) / 1_000)) kbps after voice, "
            + "\(Int((run.lifted ?? 0) / 1_000)) kbps after the lift; the screen then sent up to "
            + "\(Int(sent / 1_000)) kbps over 1 s, frames \(widths.min() ?? 0) to \(widths.max() ?? 0) wide")
        return [
            Check(
                "a phone that sent only its voice estimates its upload under 400 kbps",
                .tunedRunOnly,
                holds: (run.voice ?? .infinity) < 400_000
            ),
            Check(
                "a share after voice alone lifts WebRTC's estimate to at least \(start / 1_000) kbps before it starts",
                .tunedRunOnly,
                holds: (run.lifted ?? 0) >= Double(start)
            ),
            Check(
                "that share sends over 1 Mbps over a second and is never under 3/4 of its width",
                .tunedRunOnly,
                holds: sent > 1_000_000 && !widths.isEmpty
                    && widths.allSatisfy { $0 >= ScreenSource.width * 3 / 4 - 4 }
            ),
        ]
    }
}

struct AfterVoice {
    let voice: Double?
    let lifted: Double?
    let share: [Timed]
}

/// What the caller's screen and the camera beside it sent in one phase, from 2 s in, once the
/// encoders follow the phase's limits.
struct ScreenRun {
    let codec: String?
    let screenTarget: Double
    let cameraTarget: Double
    let widths: [Int]
    /// The median of the screen's frame rate samples.
    let typicalRate: Double
    let fastestRate: Double
    let cameraRate: Double
    let peakTogether: Double
    let limitations: [String]

    init(_ samples: [Timed]) {
        let settled = samples.filter { $0.sample.seconds - (samples.first?.sample.seconds ?? 0) >= 2 }
        let screens = settled.map(\.sample.screen)
        let rates = screens.compactMap(\.framesPerSecond).sorted()
        codec = screens.last?.sent.codec
        screenTarget = screens.compactMap(\.sent.targetBitsPerSecond).max() ?? 0
        cameraTarget = settled.compactMap(\.sample.camera.sent.targetBitsPerSecond).max() ?? 0
        widths = screens.compactMap(\.frameWidth)
        typicalRate = rates.isEmpty ? 0 : rates[rates.count / 2]
        fastestRate = rates.last ?? 0
        cameraRate = settled.compactMap(\.sample.camera.framesPerSecond).max() ?? 0
        peakTogether = peakBitsPerSecond(settled, over: 5) { $0.camera.sent.bytesSent + $0.screen.sent.bytesSent }
        limitations = Set(screens.compactMap(\.qualityLimitation)).sorted()
    }

    func sends(about rate: Int) -> Bool {
        typicalRate > 0.8 * Double(rate) && fastestRate <= Double(rate + 1)
    }

    var summary: String {
        "\(codec ?? "-"), highest encoder target \(Int(screenTarget / 1_000)) kbps, frames \(widths.min() ?? 0) to "
            + "\(widths.max() ?? 0) wide, \(Int(typicalRate)) fps typical and \(Int(fastestRate)) at most, limited by "
            + "\(limitations.isEmpty ? "-" : limitations.joined(separator: ", ")); camera beside it: highest encoder "
            + "target \(Int(cameraTarget / 1_000)) kbps, up to \(Int(cameraRate)) fps; both together peak at "
            + "\(Int(peakTogether / 1_000)) kbps over 5 s"
    }
}

/// One stretch of the screen share: the limits it runs on, and what the checks expect of it.
struct ScreenPhase {
    let name: String
    let heat: CallHeat
    let screenBudget: Double
    let screenBudgetKind: Check.Kind
    /// The screen's limit in `CallVideoLimits`.
    let framesPerSecond: Int
    /// The widest the screen may be at this heat.
    let maxWidth: Int
    let cameraBudget: Double
    /// What the screen and the camera beside it may send together.
    let totalCap: Double
    let totalCapKind: Check.Kind

    /// One frame a second over the camera's limit beside the screen, for the stats' rounding.
    var cameraMax: Double {
        Double(CallVideoLimits(heat: heat, besideScreen: true).maxFramesPerSecond + 1)
    }

    static let all = [
        // WebRTC's own limit for a screen this size is 2.5 Mbps, under the cool phone's 4 Mbps.
        ScreenPhase(
            name: "a cool phone", heat: .normal,
            screenBudget: 4_000_000, screenBudgetKind: .always, framesPerSecond: 30, maxWidth: ScreenSource.width,
            cameraBudget: 1_500_000, totalCap: 5_500_000, totalCapKind: .tunedRunOnly
        ),
        // The screen stays whole at 30 fps, and the camera beside it gives way.
        ScreenPhase(
            name: "a warm phone", heat: .warm,
            screenBudget: 2_500_000, screenBudgetKind: .always, framesPerSecond: 30, maxWidth: ScreenSource.width,
            cameraBudget: 400_000, totalCap: 2_900_000, totalCapKind: .tuning
        ),
        ScreenPhase(
            name: "a hot phone", heat: .hot,
            screenBudget: 1_000_000, screenBudgetKind: .tuning, framesPerSecond: 24,
            maxWidth: Int((Double(ScreenSource.width) * 2 / 3).rounded()),
            cameraBudget: 150_000, totalCap: 1_150_000, totalCapKind: .tuning
        ),
    ]
}

struct Check {
    enum Kind {
        /// Holds with and without CallCodecs.
        case always
        /// Holds with CallCodecs and fails without it.
        case tuning
        /// Checked only with CallCodecs. Without it WebRTC lowers its own limit with the
        /// resolution it picks, so the result depends on the run.
        case tunedRunOnly
    }

    let claim: String
    let kind: Kind
    let holds: Bool

    init(_ claim: String, _ kind: Kind, holds: Bool) {
        self.claim = claim
        self.kind = kind
        self.holds = holds
    }

    /// Whether the check should hold in this run, or nil when the run does not check it.
    func expected(tuned: Bool) -> Bool? {
        switch kind {
        case .always: true
        case .tuning: tuned
        case .tunedRunOnly: tuned ? true : nil
        }
    }
}

/// A stats sample and where the fake microphone was in its sound at that moment.
struct Timed {
    let microphoneSeconds: Double
    let sample: CallStatsSample

    init(_ microphoneSeconds: Double, _ sample: CallStatsSample) {
        self.microphoneSeconds = microphoneSeconds
        self.sample = sample
    }
}

/// What the audio sent in the speech turns and in the silent turns. Skips the first 0.4 s of
/// each turn, where Opus is still settling into the new sound.
struct AudioTurns {
    struct Totals {
        var packets = 0
        var bytes = 0
        var seconds = 0.0

        var packetsPerSecond: Double { Double(packets) / max(seconds, 0.001) }
        var bytesPerPacket: Double { Double(bytes) / Double(max(packets, 1)) }
    }

    var speech = Totals()
    var silence = Totals()

    init(_ samples: [Timed]) {
        for (earlier, later) in zip(samples, samples.dropFirst()) {
            let middle = (earlier.microphoneSeconds + later.microphoneSeconds) / 2
            guard middle.truncatingRemainder(dividingBy: 1) > 0.4 else { continue }
            let packets = later.sample.audio.packetsSent - earlier.sample.audio.packetsSent
            let bytes = later.sample.audio.bytesSent - earlier.sample.audio.bytesSent
            let seconds = later.sample.seconds - earlier.sample.seconds
            if FakeMicrophone.isSpeech(at: middle) {
                speech.packets += packets
                speech.bytes += bytes
                speech.seconds += seconds
            } else {
                silence.packets += packets
                silence.bytes += bytes
                silence.seconds += seconds
            }
        }
    }
}

func peakVideoBitsPerSecond(_ samples: [Timed], over window: Double) -> Double {
    peakBitsPerSecond(samples, over: window) { $0.camera.sent.bytesSent }
}

func peakBitsPerSecond(_ samples: [Timed], over window: Double, bytes: (CallStatsSample) -> Int) -> Double {
    var peak = 0.0
    for (index, earlier) in samples.enumerated() {
        let windowEnd = samples[index...].first { $0.sample.seconds - earlier.sample.seconds >= window }
        guard let later = windowEnd else { break }
        let bits = Double(bytes(later.sample) - bytes(earlier.sample)) * 8
        peak = max(peak, bits / (later.sample.seconds - earlier.sample.seconds))
    }
    return peak
}

func opusAsksForDTX(_ sdp: String) -> Bool {
    let lines = sdp.components(separatedBy: "\r\n")
    let opus = lines.filter { $0.lowercased().contains(" opus/48000") }
        .compactMap { $0.split(separator: " ").first?.split(separator: ":").last }
    return !opus.isEmpty && opus.allSatisfy { payloadType in
        lines.contains { $0.hasPrefix("a=fmtp:\(payloadType) ") && $0.contains("usedtx=1") }
    }
}

/// Each media line with its two most preferred codecs, and the Opus settings.
func mediaLines(_ sdp: String) -> String {
    let lines = sdp.components(separatedBy: "\r\n")
    var shown: [String] = []
    for line in lines where line.hasPrefix("m=") {
        shown.append(line)
        for payloadType in line.split(separator: " ").dropFirst(3).prefix(2) {
            shown += lines.filter { $0.hasPrefix("a=rtpmap:\(payloadType) ") }
        }
    }
    shown += lines.filter { $0.hasPrefix("a=fmtp:") && $0.contains("useinbandfec") }
    return shown.map { "  " + $0 }.joined(separator: "\n")
}

/// One end of the call, with its own tracks fed by the shared fake microphone and its own
/// noise camera.
final class Peer {
    let name: String
    let connection: LKRTCPeerConnection
    let audioTrack: LKRTCAudioTrack
    let videoTrack: LKRTCVideoTrack
    let screenTrack: LKRTCVideoTrack
    let screen: ScreenSource
    let partnerVideo = FrameCounter()
    let partnerScreen = FrameCounter()
    private let camera: NoiseCamera
    private var partnerTracks: [LKRTCVideoTrack] = []

    init(name: String, factory: LKRTCPeerConnectionFactory, tuned: Bool) {
        self.name = name
        let configuration = LKRTCConfiguration()
        configuration.sdpSemantics = .unifiedPlan
        configuration.bundlePolicy = .maxBundle
        configuration.rtcpMuxPolicy = .require
        guard let connection = factory.peerConnection(
            with: configuration,
            constraints: CallMediaProbe.noConstraints,
            delegate: nil
        ) else {
            CallMediaProbe.fail("could not create the \(name) connection")
        }
        self.connection = connection
        let audioSource = factory.audioSource(with: CallMediaProbe.noConstraints)
        audioTrack = factory.audioTrack(with: audioSource, trackId: "audio")
        let source = factory.videoSource()
        videoTrack = factory.videoTrack(with: source, trackId: "video")
        camera = NoiseCamera(source: source)
        camera.start()
        let screenSource = tuned ? CallCodecs.screenSource(from: factory) : factory.videoSource(forScreenCast: true)
        screenTrack = factory.videoTrack(with: screenSource, trackId: "screen")
        screen = ScreenSource(source: screenSource)
    }

    /// The session description once every network candidate is in it, so the other end needs
    /// no candidates sent on their own.
    func gatheredDescription() async -> LKRTCSessionDescription {
        guard await CallMediaProbe.waitUntil(seconds: 10, { connection.iceGatheringState == .complete }),
              let description = connection.localDescription
        else {
            CallMediaProbe.fail("\(name) never finished gathering network candidates")
        }
        return description
    }

    var videoSender: LKRTCRtpSender {
        videoSenders[0]
    }

    var screenSender: LKRTCRtpSender {
        videoSenders[1]
    }

    /// The camera's, then the screen's, as `CallMediaSession` adds them.
    private var videoSenders: [LKRTCRtpSender] {
        let senders = connection.transceivers.filter { $0.mediaType == .video }.map(\.sender)
        guard senders.count == 2 else { CallMediaProbe.fail("\(name) has \(senders.count) video senders, not 2") }
        return senders
    }

    /// Keeps the tracks, because a track removes its renderers when it is freed.
    func watchPartnerVideo() {
        partnerTracks = connection.transceivers.compactMap { $0.receiver.track as? LKRTCVideoTrack }
        guard partnerTracks.count == 2 else {
            CallMediaProbe.fail("\(name) receives \(partnerTracks.count) videos, not 2")
        }
        partnerTracks[0].add(partnerVideo)
        partnerTracks[1].add(partnerScreen)
    }
}

nonisolated final class FrameCounter: NSObject, LKRTCVideoRenderer, @unchecked Sendable {
    private let lock = NSLock()
    private var frames = 0
    private var size = "-"

    func setSize(_ size: CGSize) {}

    func renderFrame(_ frame: LKRTCVideoFrame?) {
        guard let frame else { return }
        lock.withLock {
            frames += 1
            size = "\(frame.width)x\(frame.height)"
        }
    }

    func snapshot() -> (frames: Int, size: String) {
        lock.withLock { (frames, size) }
    }
}

/// 1920x1080 frames at 30 fps, as CallCamera captures, of a noise picture that pans, with fresh
/// grain on top, so the encoder always wants more bits than the cap allows.
nonisolated final class NoiseCamera: @unchecked Sendable {
    static let width = 1_920
    static let height = 1_080

    private let source: LKRTCVideoSource
    private let capturer: LKRTCVideoCapturer
    private let queue = DispatchQueue(label: "noise-camera")
    private var timer: DispatchSourceTimer?
    private var pool: CVPixelBufferPool?
    private var random = Random(state: 0x9e37_79b9_7f4a_7c15)
    /// Twice the frame in each direction, so a frame-sized window can pan across it.
    private let picture: [UInt8]
    private var frameNumber = 0

    init(source: LKRTCVideoSource) {
        self.source = source
        capturer = LKRTCVideoCapturer(delegate: source)
        let attributes: [CFString: Any] = [
            kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange,
            kCVPixelBufferWidthKey: Self.width,
            kCVPixelBufferHeightKey: Self.height,
            kCVPixelBufferIOSurfacePropertiesKey: [:] as CFDictionary,
        ]
        CVPixelBufferPoolCreate(nil, nil, attributes as CFDictionary, &pool)
        let block = 8
        picture = (0..<(4 * Self.width * Self.height)).map { index in
            let row = index / (2 * Self.width) / block
            let column = index % (2 * Self.width) / block
            var cell = Random(state: UInt64(row &* 92_821 &+ column &* 68_917 &+ 1))
            return UInt8(truncatingIfNeeded: cell.next())
        }
    }

    func start() {
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now(), repeating: .nanoseconds(1_000_000_000 / 30))
        timer.setEventHandler { [weak self] in self?.sendFrame() }
        timer.resume()
        self.timer = timer
    }

    private func sendFrame() {
        guard let pool else { return }
        var buffer: CVPixelBuffer?
        CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer)
        guard let buffer else { return }
        frameNumber += 1
        let left = frameNumber * 3 % Self.width
        let top = frameNumber % Self.height
        CVPixelBufferLockBaseAddress(buffer, [])
        if let luma = CVPixelBufferGetBaseAddressOfPlane(buffer, 0)?.assumingMemoryBound(to: UInt8.self),
           let chroma = CVPixelBufferGetBaseAddressOfPlane(buffer, 1) {
            let lumaRow = CVPixelBufferGetBytesPerRowOfPlane(buffer, 0)
            for row in 0..<Self.height {
                let from = (top + row) * 2 * Self.width + left
                for column in 0..<Self.width {
                    let grain = UInt8(truncatingIfNeeded: random.next()) % 9
                    luma[row * lumaRow + column] = picture[from + column] / 2 &+ grain
                }
            }
            let chromaBytes = CVPixelBufferGetBytesPerRowOfPlane(buffer, 1) * CVPixelBufferGetHeightOfPlane(buffer, 1)
            memset(chroma, 128, chromaBytes)
        }
        CVPixelBufferUnlockBaseAddress(buffer, [])
        let frame = LKRTCVideoFrame(
            buffer: LKRTCCVPixelBuffer(pixelBuffer: buffer),
            rotation: ._0,
            timeStampNs: Int64(CMClockGetTime(CMClockGetHostTimeClock()).seconds * 1_000_000_000)
        )
        source.capturer(capturer, didCapture: frame)
    }
}

/// A phone screen at the size `CallScreenCapture` asks ScreenCaptureKit for, of lines of text-like
/// marks that scroll, with a video playing in a 16:9 box across the middle. Its frames come on a
/// 120 Hz display's ticks, about 48 a second at uneven gaps, as an iPhone's ScreenCaptureKit sent
/// them on 2026-11-17, and go to WebRTC through the app's `CallFrameGate`. The video is grain that
/// changes every frame, so the encoder wants more bits than the limits allow, as a phone screen
/// with a video or a game on it does.
nonisolated final class ScreenSource: @unchecked Sendable {
    static let width = 652
    static let height = 1_412
    static let videoRows = height / 3 ..< height / 3 + width * 9 / 16

    private let gate: CallFrameGate
    private var queue: DispatchQueue { gate.queue }
    private var timer: DispatchSourceTimer?
    private var pool: CVPixelBufferPool?
    /// Twice the screen's height, so a screen-sized window can scroll down it.
    private let page: [UInt8]
    private var frameNumber = 0
    private var random = Random(state: 0x853c_49e6_748f_ea9b)

    init(source: LKRTCVideoSource) {
        gate = CallFrameGate(source: source, queue: DispatchQueue(label: "screen-source"))
        let attributes: [CFString: Any] = [
            kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange,
            kCVPixelBufferWidthKey: Self.width,
            kCVPixelBufferHeightKey: Self.height,
            kCVPixelBufferIOSurfacePropertiesKey: [:] as CFDictionary,
        ]
        CVPixelBufferPoolCreate(nil, nil, attributes as CFDictionary, &pool)
        var random = Random(state: 0x2545_f491_4f6c_dd1d)
        let markCount = (Self.width / 8 + 1) * (2 * Self.height / 24 + 1)
        let marks = (0..<markCount).map { _ in random.next() % 3 != 0 }
        page = (0..<(2 * Self.width * Self.height)).map { index in
            let row = index / Self.width
            let column = index % Self.width
            let inLine = row % 24 < 14 && column % 8 < 6 && column > 30 && column < Self.width - 30
            return inLine && marks[(row / 24) * (Self.width / 8) + column / 8] ? 30 : 235
        }
    }

    func start() {
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now(), repeating: .nanoseconds(1_000_000_000 / 120))
        timer.setEventHandler { [weak self] in self?.tick() }
        timer.resume()
        self.timer = timer
        gate.startResending()
    }

    func stop() {
        timer?.cancel()
        timer = nil
        gate.stopResending()
    }

    /// As `CallScreenMedia.limit(to:)` sets it.
    func setMaxFramesPerSecond(_ rate: Int) {
        gate.setMaxFramesPerSecond(rate)
    }

    /// Two ticks in five bring a frame.
    private func tick() {
        if random.next() % 5 < 2 {
            sendFrame()
        }
    }

    private func sendFrame() {
        guard let pool else { return }
        var buffer: CVPixelBuffer?
        CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer)
        guard let buffer else { return }
        frameNumber += 1
        let top = frameNumber * 4 % Self.height
        CVPixelBufferLockBaseAddress(buffer, [])
        if let luma = CVPixelBufferGetBaseAddressOfPlane(buffer, 0)?.assumingMemoryBound(to: UInt8.self),
           let chroma = CVPixelBufferGetBaseAddressOfPlane(buffer, 1) {
            let lumaRow = CVPixelBufferGetBytesPerRowOfPlane(buffer, 0)
            page.withUnsafeBufferPointer { page in
                guard let start = page.baseAddress else { return }
                for row in 0..<Self.height {
                    (luma + row * lumaRow).update(from: start + (top + row) * Self.width, count: Self.width)
                }
            }
            for row in Self.videoRows {
                for column in 0..<Self.width {
                    luma[row * lumaRow + column] = 64 &+ UInt8(truncatingIfNeeded: random.next()) % 128
                }
            }
            let chromaBytes = CVPixelBufferGetBytesPerRowOfPlane(buffer, 1) * CVPixelBufferGetHeightOfPlane(buffer, 1)
            memset(chroma, 128, chromaBytes)
        }
        CVPixelBufferUnlockBaseAddress(buffer, [])
        gate.take(LKRTCCVPixelBuffer(pixelBuffer: buffer), rotation: ._0)
    }
}

/// xorshift64, fast enough to make a frame of grain every 33 ms.
nonisolated struct Random {
    var state: UInt64

    mutating func next() -> UInt64 {
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        return state
    }
}

/// A microphone for WebRTC that plays 1 s of a speech-like sound, then 1 s of silence, by turns,
/// in 10 ms buffers of 48 kHz mono, and pulls the partner's audio out at the same pace.
nonisolated final class FakeMicrophone: NSObject, LKRTCAudioDevice, @unchecked Sendable {
    static let sampleRate = 48_000.0
    static let framesPerBuffer = 480

    static func isSpeech(at seconds: Double) -> Bool {
        Int(seconds) % 2 == 0
    }

    private let lock = NSLock()
    private var delegate: (any LKRTCAudioDeviceDelegate)?
    private var thread: Thread?
    private var recording = false
    private var playing = false
    private var framesDelivered = 0

    /// How far into its sound the microphone is.
    var seconds: Double {
        lock.withLock { Double(framesDelivered) / Self.sampleRate }
    }

    let deviceInputSampleRate = sampleRate
    let inputIOBufferDuration = 0.01
    let inputNumberOfChannels = 1
    let inputLatency = 0.0
    let deviceOutputSampleRate = sampleRate
    let outputIOBufferDuration = 0.01
    let outputNumberOfChannels = 1
    let outputLatency = 0.0
    var isInitialized: Bool { lock.withLock { delegate != nil } }
    var isPlayoutInitialized: Bool { isInitialized }
    var isRecordingInitialized: Bool { isInitialized }
    var isPlaying: Bool { lock.withLock { playing } }
    var isRecording: Bool { lock.withLock { recording } }

    func initialize(with delegate: any LKRTCAudioDeviceDelegate) -> Bool {
        lock.withLock { self.delegate = delegate }
        return true
    }

    func terminateDevice() -> Bool {
        lock.withLock {
            delegate = nil
            recording = false
            playing = false
        }
        return true
    }

    func initializePlayout() -> Bool { true }
    func initializeRecording() -> Bool { true }

    func startPlayout() -> Bool {
        lock.withLock { playing = true }
        startThread()
        return true
    }

    func stopPlayout() -> Bool {
        lock.withLock { playing = false }
        return true
    }

    func startRecording() -> Bool {
        lock.withLock { recording = true }
        startThread()
        return true
    }

    func stopRecording() -> Bool {
        lock.withLock { recording = false }
        return true
    }

    /// WebRTC expects recorded audio on one thread, so one thread runs both directions.
    private func startThread() {
        lock.lock()
        defer { lock.unlock() }
        guard thread == nil else { return }
        let thread = Thread { [weak self] in self?.run() }
        thread.qualityOfService = .userInteractive
        self.thread = thread
        thread.start()
    }

    private func run() {
        var samples = [Int16](repeating: 0, count: Self.framesPerBuffer)
        var next = Date()
        while true {
            let (delegate, recording, playing, firstFrame) = lock.withLock {
                (delegate, recording, playing, framesDelivered)
            }
            guard let delegate else { return }
            var flags = AudioUnitRenderActionFlags()
            var timestamp = AudioTimeStamp()
            timestamp.mSampleTime = Double(firstFrame)
            timestamp.mFlags = .sampleTimeValid
            if recording {
                for index in samples.indices {
                    samples[index] = Self.sample(at: Double(firstFrame + index) / Self.sampleRate)
                }
                Self.withBufferList(&samples) { list in
                    let frames = UInt32(Self.framesPerBuffer)
                    _ = delegate.deliverRecordedData(&flags, &timestamp, 1, frames, list, nil, nil)
                }
                lock.withLock { framesDelivered += Self.framesPerBuffer }
            }
            if playing {
                var output = [Int16](repeating: 0, count: Self.framesPerBuffer)
                Self.withBufferList(&output) { list in
                    _ = delegate.getPlayoutData(&flags, &timestamp, 0, UInt32(Self.framesPerBuffer), list)
                }
            }
            next += 0.01
            Thread.sleep(until: next)
        }
    }

    private static func withBufferList(
        _ samples: inout [Int16],
        _ body: (UnsafeMutablePointer<AudioBufferList>) -> Void
    ) {
        samples.withUnsafeMutableBytes { bytes in
            let buffer = AudioBuffer(mNumberChannels: 1, mDataByteSize: UInt32(bytes.count), mData: bytes.baseAddress)
            var list = AudioBufferList(mNumberBuffers: 1, mBuffers: buffer)
            body(&list)
        }
    }

    /// A voice-like sound: a gliding 120 to 180 Hz pitch with harmonics that fall off, shaped
    /// into syllables four times a second, or nothing in a silent second.
    private static func sample(at time: Double) -> Int16 {
        guard isSpeech(at: time) else { return 0 }
        let pitch = 150 + 30 * sin(2 * .pi * 1.3 * time)
        let phase = 2 * .pi * (150 * time - 30 / (2 * .pi * 1.3) * cos(2 * .pi * 1.3 * time))
        var value = 0.0
        for harmonic in 1...12 where Double(harmonic) * pitch < 4_000 {
            value += sin(Double(harmonic) * phase) / Double(harmonic)
        }
        let syllable = 0.2 + 0.8 * abs(sin(2 * .pi * 2 * time))
        return Int16(max(-1, min(1, 0.25 * syllable * value)) * Double(Int16.max))
    }
}
// One script, so scripts/call-media-probe compiles it with only the two app files it checks.
// swiftlint:disable:this file_length
