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
              signal: (Int, Int) -> Double) throws {
    let frames = Int(seconds * sampleRate)
    guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2),
          let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frames)),
          let channels = buffer.floatChannelData else { fatalError("Cannot allocate audio buffer") }
    buffer.frameLength = AVAudioFrameCount(frames)
    var measured = 0.0
    for channel in 0..<2 {
        for frame in 0..<frames {
            let time = Double(frame) / sampleRate
            let fade = min(time / 0.0005, 1) * min(Double(frames - 1 - frame) / sampleRate / 0.06, 1)
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
let releaseDuration = timing("partnerHold")
let notes = [(261.625565, 1.0), (329.627557, 0.36), (391.995436, 0.42)]

func resonance(time: Double, brightness: Double, release: Bool, channel: Int) -> Double {
    var value = 0.0
    for (index, note) in notes.enumerated() {
        let (frequency, weight) = note
        let phase = Double(index) * 0.47
        let pan = index == 0 ? 1 : (index == channel + 1 ? 1.0 : 0.82)
        let fundamental = sin(2 * .pi * frequency * time + phase)
        let second = sin(2 * .pi * frequency * 2 * time + phase) * 0.14 * brightness
            * (release ? exp(-time / 0.16) : 1)
        let third = sin(2 * .pi * frequency * 3 * time + phase) * 0.045 * brightness
            * (release ? exp(-time / 0.09) : 1)
        let feltMode = sin(2 * .pi * frequency * 4.08 * time + phase) * 0.018 * brightness
            * (release ? exp(-time / 0.035) : pow(min(time / gatherDuration, 1), 3))
        let modalDecay = release ? exp(-time * (2.8 + Double(index) * 0.3)) : 1
        value += (fundamental + second + third + feltMode) * weight * pan * modalDecay
    }
    return value
}

try writeCue("Gather", seconds: gatherDuration, peak: 0.14) { frame, channel in
    let time = Double(frame) / sampleRate
    let progress = min(time / gatherDuration, 1)
    let attack = 1 - exp(-pow(time / 0.35, 2))
    let pressure = 0.10 + 0.90 * pow(progress, 1.35)
    return resonance(time: time, brightness: 0.18 + 0.82 * progress * progress,
                     release: false, channel: channel) * attack * pressure
}

try writeCue("Release", seconds: releaseDuration, peak: 0.24) { frame, channel in
    let time = Double(frame) / sampleRate
    let attack = 1 - exp(-time / 0.004)
    let contact = sin(2 * .pi * 523.25113 * time) * exp(-time / 0.14)
        + 0.10 * sin(2 * .pi * 1_046.50226 * time) * exp(-time / 0.045)
        + 0.025 * sin(2 * .pi * 1_569.75339 * time) * exp(-time / 0.025)
    let tail = resonance(time: time, brightness: exp(-time / 0.12), release: true, channel: channel)
    return attack * (contact * 0.8 + tail * 0.30)
}
