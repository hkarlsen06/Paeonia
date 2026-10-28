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
              signal: (Double, Int) -> Double) throws {
    let frames = Int(seconds * sampleRate)
    guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2),
          let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frames)),
          let channels = buffer.floatChannelData else { fatalError("Cannot allocate audio buffer") }
    buffer.frameLength = AVAudioFrameCount(frames)
    var measured = 0.0
    for channel in 0..<2 {
        for frame in 0..<frames {
            let time = Double(frame) / sampleRate
            let fade = min(time / 0.006, 1) * min((seconds - time) / 0.06, 1)
            let value = signal(time, channel) * fade
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

try writeCue("Gather", seconds: 1.95, peak: 0.32) { time, channel in
    let progress = min(time / 1.45, 1)
    let pitchPhase = time < 1.45 ? time * time / 1.45 : 2 * time - 1.45
    let turn = time * 1.4 + progress * progress * 4.2
    let pan = 0.7 + 0.3 * sin(turn + Double(channel) * .pi)
    var air = 0.0
    for partial in 1...18 {
        let frequency = 170 + Double(partial * partial) * 7.3
        let phase = 2 * Double.pi * frequency * (time + 0.12 * pitchPhase)
        air += sin(phase + Double(partial) * 2.39996 + Double(channel) * 0.3) / Double(partial + 4)
    }
    let body = sin(2 * Double.pi * (196 * time + 42 * pitchPhase)) * 0.15
    return (air * 0.5 + body) * (0.12 + 0.88 * progress * progress) * pan
}

try writeCue("Release", seconds: 0.9, peak: 0.42) { time, channel in
    let spread = Double(channel) * 0.002 * (1 - exp(-time * 12))
    let local = max(0, time - spread)
    let body = sin(2 * Double.pi * 392 * local) * exp(-time * 4.5)
    let overtone = sin(2 * Double.pi * 587.33 * local) * exp(-time * 6) * 0.35
    let shimmer = sin(2 * Double.pi * 784 * local) * exp(-time * 8) * 0.14
    return (body + overtone + shimmer) * (1 - exp(-time * 240))
}

try writeCue("Land", seconds: 0.6, peak: 0.14) { time, channel in
    let phase = Double(channel) * 0.04
    return (sin(2 * Double.pi * 196 * time + phase)
            + sin(2 * Double.pi * 392 * time + phase) * 0.18)
        * exp(-time * 8) * (1 - exp(-time * 130))
}
