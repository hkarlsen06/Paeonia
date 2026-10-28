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
            let fade = min(time / 0.0005, 1) * min((seconds - time) / 0.06, 1)
            let value = signal(frame, channel) * fade
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

struct FeltNoise {
    var state: UInt64
    var upper = 0.0
    var softened = 0.0
    var lower = 0.0
    let upperWeight: Double
    let lowerWeight: Double

    init(seed: UInt64, low: Double, high: Double) {
        state = seed
        upperWeight = 1 - exp(-2 * .pi * high / sampleRate)
        lowerWeight = 1 - exp(-2 * .pi * low / sampleRate)
    }

    mutating func next() -> Double {
        state &+= 0x9e37_79b9_7f4a_7c15
        var mixed = state
        mixed = (mixed ^ (mixed >> 30)) &* 0xbf58_476d_1ce4_e5b9
        mixed = (mixed ^ (mixed >> 27)) &* 0x94d0_49bb_1331_11eb
        let white = Double((mixed ^ (mixed >> 31)) >> 11) / Double(1 << 53) * 2 - 1
        upper += upperWeight * (white - upper)
        softened += upperWeight * (upper - softened)
        lower += lowerWeight * (softened - lower)
        return softened - lower
    }
}

var gatherNoise = FeltNoise(seed: 0x7061656f6e6961, low: 160, high: 1_400)
let gather = (0..<Int(1.95 * sampleRate)).map { frame in
    let time = Double(frame) / sampleRate
    let pressure = pow(min(time / 1.45, 1), 1.35)
    return gatherNoise.next() * (0.015 + 0.985 * pressure)
}
try writeCue("Gather", seconds: 1.95, peak: 0.075) { index, _ in
    gather[index]
}

var contactNoise = FeltNoise(seed: 0x66656c74, low: 90, high: 700)
var breathLeft = FeltNoise(seed: 0x7061706572, low: 220, high: 1_800)
var breathRight = FeltNoise(seed: 0x6272757368, low: 220, high: 1_800)
struct ReleaseFrame {
    let contact: Double
    let left: Double
    let right: Double
}
let release = (0..<Int(0.9 * sampleRate)).map { frame in
    let time = Double(frame) / sampleRate
    let contactEnvelope = (1 - exp(-time / 0.0004)) * exp(-time / 0.007)
        * max(0, 1 - time / 0.045)
    let breathEnvelope = (1 - exp(-time / 0.008)) * exp(-time / 0.14)
        * min(max((0.75 - time) / 0.15, 0), 1) * 0.045
    return ReleaseFrame(
        contact: contactNoise.next() * contactEnvelope,
        left: breathLeft.next() * breathEnvelope,
        right: breathRight.next() * breathEnvelope
    )
}
try writeCue("Release", seconds: 0.9, peak: 0.22) { index, channel in
    let frame = release[index]
    let time = Double(index) / sampleRate
    let opening = min(time / 0.15, 1) * 0.3
    let center = (frame.left + frame.right) * 0.5
    let side = channel == 0 ? frame.left : frame.right
    return frame.contact + center * (1 - opening) + side * opening
}
