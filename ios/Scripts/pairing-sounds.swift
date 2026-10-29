import AVFoundation
import Foundation

let sampleRate = 44_100.0
guard CommandLine.arguments.count == 2 else {
    FileHandle.standardError.write(Data("Usage: swift pairing-sounds.swift <output folder>\n".utf8))
    exit(1)
}
let directory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

func writeCue(_ name: String, seconds: Double, peak: Double,
              fadeOut: Double, signal: (Int, Int) -> Double) throws {
    let frames = Int(seconds * sampleRate)
    guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2),
          let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frames)),
          let channels = buffer.floatChannelData else { fatalError("Cannot allocate audio buffer") }
    buffer.frameLength = AVAudioFrameCount(frames)
    var measured = 0.0
    for channel in 0..<2 {
        for frame in 0..<frames {
            let time = Double(frame) / sampleRate
            let fade = min(time / 0.0005, 1) * min(Double(frames - 1 - frame) / sampleRate / fadeOut, 1)
            let value = signal(frame, channel) * fade
            precondition(value.isFinite, "Non-finite audio sample")
            channels[channel][frame] = Float(value)
            measured = max(measured, abs(value))
        }
    }
    for channel in 0..<2 {
        for frame in 0..<frames { channels[channel][frame] *= Float(peak / max(measured, 0.001)) }
    }
    let url = directory.appendingPathComponent("Pairing\(name).caf")
    var settings = format.settings
    settings[AVLinearPCMIsNonInterleaved] = false
    let file = try AVAudioFile(forWriting: url, settings: settings)
    try file.write(from: buffer)
    let summary = "Pairing\(name).caf duration=\(seconds)s peak=\(peak)\n"
    FileHandle.standardOutput.write(Data(summary.utf8))
}

let timingURL = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    .appendingPathComponent("../PaeoniaApp/Features/Pairing/Celebration/PairingCelebrationSchedule.swift")
let timingSource = try String(contentsOf: timingURL, encoding: .utf8)
func timing(_ name: String) -> Double {
    let pattern = "static let \(name): Double = ([0-9.]+)"
    guard let expression = try? NSRegularExpression(pattern: pattern) else { fatalError("Invalid timing pattern") }
    guard let match = expression.firstMatch(
        in: timingSource, range: NSRange(timingSource.startIndex..., in: timingSource)),
          let range = Range(match.range(at: 1), in: timingSource),
          let value = Double(timingSource[range]) else { fatalError("Missing timing \(name)") }
    return value
}
let gatherDuration = timing("absorb")
let releaseDuration = timing("partnerHold") + timing("landingSettle")

// Cmaj9 opens into Ab6/9. C stays shared while E falls to Eb and B falls to Bb.
let opening: [(UInt8, UInt8)] = [(48, 44), (60, 49), (64, 44), (67, 38), (71, 31), (74, 35)]
let arrival: [(UInt8, UInt8)] = [
    (44, 53), (51, 35), (60, 48), (63, 42), (65, 29), (70, 28), (75, 34), (80, 31)
]

// Render the Mac's sampled piano here. The app only plays the finished PCM assets.
func pianoChord(_ notes: [(UInt8, UInt8)], seconds: Double) throws -> [[Double]] {
    let engine = AVAudioEngine()
    let piano = AVAudioUnitSampler()
    engine.attach(piano)
    guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2),
          let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 512)
    else { fatalError("Cannot allocate piano buffer") }
    try engine.connectNode(piano, to: engine.mainMixerNode, format: format)
    let soundBank = URL(fileURLWithPath:
        "/System/Library/Components/CoreAudio.component/Contents/Resources/gs_instruments.dls")
    try piano.loadSoundBankInstrument(at: soundBank, program: 0,
                                     bankMSB: UInt8(kAUSampler_DefaultMelodicBankMSB), bankLSB: 0)
    piano.sendController(91, withValue: 0, onChannel: 0)
    piano.sendController(93, withValue: 0, onChannel: 0)
    try engine.enableManualRenderingMode(.offline, format: format, maximumFrameCount: 512)
    try engine.start()
    defer { engine.stop() }
    for (note, velocity) in notes { piano.startNote(note, withVelocity: velocity, onChannel: 0) }

    let frames = Int(seconds * sampleRate)
    var samples = Array(repeating: [Double](), count: 2)
    for channel in 0..<2 { samples[channel].reserveCapacity(frames) }
    while samples[0].count < frames {
        let count = AVAudioFrameCount(min(512, frames - samples[0].count))
        guard try engine.renderOffline(count, to: buffer) == .success,
              let channels = buffer.floatChannelData,
              buffer.frameLength == count else { fatalError("Piano rendering failed") }
        for channel in 0..<2 {
            samples[channel].append(contentsOf: (0..<Int(count)).map { Double(channels[channel][$0]) })
        }
    }
    return samples
}

// Soften the hammer and add quiet room reflections, with different delays in each ear.
func soften(_ samples: [[Double]], cutoff: Double, room: Double) -> [[Double]] {
    var result = samples
    let coefficient = 1 - exp(-2 * .pi * cutoff / sampleRate)
    for channel in 0..<2 {
        var first = 0.0
        var second = 0.0
        for frame in samples[channel].indices {
            first += coefficient * (samples[channel][frame] - first)
            second += coefficient * (first - second)
            result[channel][frame] = second
        }
    }
    let dry = result
    for channel in 0..<2 {
        for (seconds, gain) in [(0.019, 0.40), (0.043, 0.29), (0.079, 0.18), (0.127, 0.10)] {
            let delay = Int((seconds + Double(channel) * 0.007) * sampleRate)
            for frame in delay..<samples[channel].count {
                result[channel][frame] += dry[1 - channel][frame - delay] * gain * room
            }
        }
    }
    return result
}

// Level a 240 ms window before reversing, so the chord stays audible throughout the pull.
func sustainGains(_ samples: [[Double]]) -> [Double] {
    let frames = samples[0].count
    var energy = [Double](repeating: 0, count: frames + 1)
    for frame in 0..<frames {
        energy[frame + 1] = energy[frame] +
            (samples[0][frame] * samples[0][frame] + samples[1][frame] * samples[1][frame]) * 0.5
    }
    let radius = Int(0.12 * sampleRate)
    return (0..<frames).map { frame in
        let lower = max(0, frame - radius)
        let upper = min(frames, frame + radius + 1)
        let rms = sqrt((energy[upper] - energy[lower]) / Double(upper - lower))
        return 0.025 / max(rms, 0.002)
    }
}

let openingPiano = soften(try pianoChord(opening, seconds: gatherDuration), cutoff: 1_900, room: 0.25)
let openingGains = sustainGains(openingPiano)
// A held G sits above Cmaj9, then rises a semitone to Ab at the release.
let upperHarmony = soften(try pianoChord([(79, 44)], seconds: gatherDuration), cutoff: 1_400, room: 0.85)
let harmonyGains = sustainGains(upperHarmony)
let arrivalPiano = soften(try pianoChord(arrival, seconds: releaseDuration), cutoff: 2_800, room: 0.55)

struct PianoNote {
    let pitch: UInt8
    let velocity: UInt8
    let start: Double
}

func pianoPhrase(_ notes: [PianoNote], seconds: Double, gain: Double) throws -> [[Double]] {
    var samples = Array(repeating: [Double](repeating: 0, count: Int(seconds * sampleRate)), count: 2)
    for note in notes {
        let start = Int(note.start * sampleRate)
        let voice = soften(try pianoChord([(note.pitch, note.velocity)], seconds: seconds - note.start),
                           cutoff: 2_500, room: 0.85)
        for channel in 0..<2 {
            for frame in 0..<min(voice[channel].count, samples[channel].count - start) {
                let age = Double(frame) / sampleRate
                let attack = 1 - exp(-age / 0.018)
                samples[channel][start + frame] += voice[channel][frame] * attack * exp(-age / 0.52) * gain
            }
        }
    }
    return samples
}

// G, D, E rise through the swell. The E then falls to the arrival chord's Eb.
let gatherPhrase = try pianoPhrase([
    PianoNote(pitch: 67, velocity: 40, start: 0.42),
    PianoNote(pitch: 74, velocity: 37, start: 1.02),
    PianoNote(pitch: 76, velocity: 35, start: 1.66)
], seconds: gatherDuration, gain: 0.38)

// Ab, Bb, C, Eb rise above the arrival chord with rounded attacks.
let sprinkle = try pianoPhrase([
    PianoNote(pitch: 80, velocity: 38, start: 0.18),
    PianoNote(pitch: 82, velocity: 36, start: 0.36),
    PianoNote(pitch: 84, velocity: 34, start: 0.54),
    PianoNote(pitch: 87, velocity: 32, start: 0.78)
], seconds: releaseDuration, gain: 0.50)

try writeCue("Gather", seconds: gatherDuration, peak: 0.14, fadeOut: 0.008) { frame, channel in
    let time = Double(frame) / sampleRate
    let progress = time / gatherDuration
    let attack = 1 - exp(-pow(time / 0.22, 2))
    let reverseFrame = openingPiano[channel].count - 1 - frame
    let reverse = openingPiano[channel][reverseFrame] * openingGains[reverseFrame]
    let pressure = 0.40 + 0.60 * progress * progress
    let harmonyProgress = min(max((progress - 0.24) / 0.28, 0), 1)
    let harmonyFade = harmonyProgress * harmonyProgress * (3 - 2 * harmonyProgress)
    let harmony = upperHarmony[channel][reverseFrame] * harmonyGains[reverseFrame] * harmonyFade * 0.24
    return attack * reverse * pressure + gatherPhrase[channel][frame] + harmony
}

try writeCue("Release", seconds: releaseDuration, peak: 0.24, fadeOut: 0.24) { frame, channel in
    let time = Double(frame) / sampleRate
    let attack = 1 - exp(-time / 0.002)
    return arrivalPiano[channel][frame] * attack * exp(-time / 1.15) + sprinkle[channel][frame]
}
