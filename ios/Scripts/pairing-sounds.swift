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

func key(_ time: Double, frequency: Double, decay: Double = 6) -> Double {
    guard time >= 0 else { return 0 }
    let attack = 1 - exp(-time * 150)
    let phase = 2 * Double.pi * frequency * time
    return attack * (sin(phase) * exp(-time * decay)
        + 0.22 * sin(phase * 2) * exp(-time * (decay + 5))
        + 0.06 * sin(phase * 3) * exp(-time * (decay + 10)))
}

try writeCue("Gather", seconds: 1.95, peak: 0.18) { time, _ in
    let notes: [(Double, Double)] = [
        (0, 261.6256), (0.34, 329.6276), (0.67, 391.9954),
        (0.98, 329.6276), (1.24, 391.9954)
    ]
    return notes.reduce(0) { value, note in
        value + key(time - note.0, frequency: note.1, decay: 5) * 0.7
    }
}

try writeCue("Release", seconds: 0.9, peak: 0.23) { time, _ in
    key(time, frequency: 261.6256, decay: 5)
        + key(time, frequency: 329.6276, decay: 6) * 0.35
        + key(time, frequency: 391.9954, decay: 7) * 0.22
}

try writeCue("Land", seconds: 0.6, peak: 0.065) { time, _ in
    key(time, frequency: 261.6256, decay: 10)
}
