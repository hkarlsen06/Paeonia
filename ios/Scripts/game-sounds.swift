// Makes the games' sound effects in ios/PaeoniaApp/Resources/GameSounds. Every sound is
// synthesized here, so there is nothing to download. Change a recipe and run it again:
//   swiftc -O -o /tmp/game-sounds ios/Scripts/game-sounds.swift
//   /tmp/game-sounds ios/PaeoniaApp/Resources/GameSounds
// The recipes aim for soft, close sounds: low wooden "thock" bodies, short clicks, paper
// and felt, and no harsh highs. A sound the games repeat in a row gets a few variants,
// numbered from 1, and the app picks one at random so no two hits are the same.
// `GameSound` in ios/PaeoniaApp/Features/Games/Shared/Sound lists the names.

import AVFoundation
import Foundation

let rate = 44_100.0

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("game-sounds: \(message)\n".utf8))
    exit(1)
}

// MARK: Randomness

/// SplitMix64, seeded per sound and variant, so a run makes the same files every time.
struct Random {
    var state: UInt64

    init(_ name: String, _ variant: Int) {
        state = 0xcbf2_9ce4_8422_2325
        for byte in "\(name)#\(variant)".utf8 {
            state = (state ^ UInt64(byte)) &* 0x100_0000_01b3
        }
    }

    mutating func next() -> Double {
        state &+= 0x9e37_79b9_7f4a_7c15
        var mixed = state
        mixed = (mixed ^ (mixed >> 30)) &* 0xbf58_476d_1ce4_e5b9
        mixed = (mixed ^ (mixed >> 27)) &* 0x94d0_49bb_1331_11eb
        return Double((mixed ^ (mixed >> 31)) >> 11) / Double(1 << 53)
    }

    mutating func signed() -> Double { next() * 2 - 1 }

    /// A factor near 1, up to `spread` either way.
    mutating func jitter(_ spread: Double) -> Double { 1 + signed() * spread }
}

var random = Random("", 0)

// MARK: Signals

func count(_ seconds: Double) -> Int { max(1, Int(seconds * rate)) }

func noise(_ seconds: Double) -> [Double] {
    (0..<count(seconds)).map { _ in random.signed() }
}

/// A decaying sine. With `from`, the pitch starts there and settles on `hz` over about
/// `glide` seconds. That small drop is most of what makes a hit sound like a thock.
func mode(_ hz: Double, decay: Double, from: Double? = nil, glide: Double = 0.006) -> [Double] {
    let start = from ?? hz
    var phase = random.next() * 0.3
    return (0..<count(decay * 7)).map { index in
        let time = Double(index) / rate
        phase += 2 * .pi * (hz + (start - hz) * exp(-time / glide)) / rate
        return sin(phase) * exp(-time / decay)
    }
}

/// Noise that starts at once and dies away over `decay`, the contact of a hit.
func burst(decay: Double) -> [Double] {
    noise(decay * 7).enumerated().map { index, value in value * exp(-Double(index) / rate / decay) }
}

/// Noise shaped by a half sine, `power` sharpening the middle. For air and paper.
func swell(_ seconds: Double, power: Double = 1) -> [Double] {
    let total = count(seconds)
    return noise(seconds).enumerated().map { index, value in
        value * pow(sin(.pi * Double(index) / Double(total)), power)
    }
}

/// Sparse tiny clicks, `perSecond` of them on average, for crinkling paper and rattles.
func crackle(_ seconds: Double, perSecond: Double) -> [Double] {
    var out = [Double](repeating: 0, count: count(seconds))
    let chance = perSecond / rate
    for index in out.indices where random.next() < chance {
        let level = 0.3 + 0.7 * random.next()
        let decay = 0.0003 + 0.0008 * random.next()
        let sign: Double = random.next() < 0.5 ? -1 : 1
        for offset in 0..<count(decay * 6) where index + offset < out.count {
            out[index + offset] += sign * level * random.signed() * exp(-Double(offset) / rate / decay)
        }
    }
    return out
}

func times(_ first: [Double], _ second: [Double]) -> [Double] {
    zip(first, second).map { $0 * $1 }
}

// MARK: Filters

/// The biquads from Robert Bristow-Johnson's Audio EQ Cookbook.
struct Biquad {
    var b0 = 0.0, b1 = 0.0, b2 = 0.0, a1 = 0.0, a2 = 0.0

    static func lowpass(_ hz: Double, q quality: Double = 0.707) -> Biquad {
        let (cosine, alpha) = terms(hz, quality)
        return Biquad(numerator: [(1 - cosine) / 2, 1 - cosine, (1 - cosine) / 2], cosine: cosine, alpha: alpha)
    }

    static func highpass(_ hz: Double, q quality: Double = 0.707) -> Biquad {
        let (cosine, alpha) = terms(hz, quality)
        return Biquad(numerator: [(1 + cosine) / 2, -(1 + cosine), (1 + cosine) / 2], cosine: cosine, alpha: alpha)
    }

    /// A band pass whose peak stays at 0 dB.
    static func bandpass(_ hz: Double, q quality: Double) -> Biquad {
        let (cosine, alpha) = terms(hz, quality)
        return Biquad(numerator: [alpha, 0, -alpha], cosine: cosine, alpha: alpha)
    }

    private static func terms(_ hz: Double, _ quality: Double) -> (Double, Double) {
        let omega = 2 * .pi * min(hz, rate * 0.45) / rate
        return (cos(omega), sin(omega) / (2 * quality))
    }

    private init(numerator: [Double], cosine: Double, alpha: Double) {
        let a0 = 1 + alpha
        b0 = numerator[0] / a0
        b1 = numerator[1] / a0
        b2 = numerator[2] / a0
        a1 = -2 * cosine / a0
        a2 = (1 - alpha) / a0
    }

    func run(_ input: [Double]) -> [Double] {
        var x1 = 0.0, x2 = 0.0, y1 = 0.0, y2 = 0.0
        return input.map { x in
            let y = b0 * x + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
            x2 = x1
            x1 = x
            y2 = y1
            y1 = y
            return y
        }
    }
}

/// A band pass whose middle slides from `from` to `to` hertz, for whooshes.
func sweep(_ input: [Double], from: Double, to: Double, q quality: Double) -> [Double] {
    var output = [Double](repeating: 0, count: input.count)
    var x1 = 0.0, x2 = 0.0, y1 = 0.0, y2 = 0.0
    var filter = Biquad.bandpass(from, q: quality)
    for index in input.indices {
        if index % 32 == 0 {
            let progress = Double(index) / Double(max(input.count - 1, 1))
            filter = Biquad.bandpass(from * pow(to / from, progress), q: quality)
        }
        let x = input[index]
        let y = filter.b0 * x + filter.b1 * x1 + filter.b2 * x2 - filter.a1 * y1 - filter.a2 * y2
        x2 = x1
        x1 = x
        y2 = y1
        y1 = y
        output[index] = y
    }
    return output
}

// MARK: Mixing

struct Mix {
    var samples: [Double] = []

    mutating func add(_ signal: [Double], at seconds: Double = 0, gain: Double = 1) {
        let start = Int(seconds * rate)
        if samples.count < start + signal.count {
            samples += [Double](repeating: 0, count: start + signal.count - samples.count)
        }
        for (index, value) in signal.enumerated() {
            samples[start + index] += value * gain
        }
    }
}

// MARK: Instruments

/// A felt-covered wooden hit: a low body that drops a little in pitch, two higher
/// partials and the click where the surfaces meet. `bright` lifts the click and partials.
func thock(_ body: Double, decay: Double, bright: Double = 1) -> [Double] {
    var mix = Mix()
    mix.add(mode(body, decay: decay, from: body * 1.35, glide: 0.005))
    mix.add(mode(body * 2.62, decay: decay * 0.45), gain: 0.32 * bright)
    mix.add(mode(body * 6.1, decay: decay * 0.2), gain: 0.1 * bright)
    mix.add(Biquad.bandpass(2_600 * random.jitter(0.1), q: 0.9).run(burst(decay: 0.0022)), gain: 0.45 * bright)
    mix.add(Biquad.lowpass(900).run(burst(decay: 0.008)), gain: 0.6)
    return mix.samples
}

/// A small, hard hit such as a die or a wooden tile: three close partials and a click,
/// over a short knock from the table.
func clack(_ hz: Double, table: Double, decay: Double = 0.011) -> [Double] {
    var mix = Mix()
    mix.add(mode(hz, decay: decay), gain: 0.6)
    mix.add(mode(hz * 1.47 * random.jitter(0.02), decay: decay * 0.7), gain: 0.4)
    mix.add(mode(hz * 2.9 * random.jitter(0.03), decay: decay * 0.35), gain: 0.2)
    mix.add(Biquad.bandpass(3_600, q: 0.8).run(burst(decay: 0.0011)), gain: 0.55)
    mix.add(mode(table, decay: 0.024, from: table * 1.25), gain: 0.55)
    return mix.samples
}

/// A kalimba tine: a clean note with a quick metallic overtone and a soft thumb touch.
func tine(_ hz: Double, decay: Double = 0.42) -> [Double] {
    var mix = Mix()
    mix.add(mode(hz, decay: decay))
    mix.add(mode(hz * 2.01, decay: decay * 0.22), gain: 0.1)
    mix.add(mode(hz * 5.95, decay: 0.035), gain: 0.16)
    mix.add(Biquad.bandpass(hz * 3, q: 1).run(burst(decay: 0.002)), gain: 0.18)
    let attack = count(0.0015)
    for index in 0..<attack { mix.samples[index] *= Double(index) / Double(attack) }
    return mix.samples
}

/// A marimba bar struck with a soft mallet: warm, round and short.
func bar(_ hz: Double, decay: Double = 0.3) -> [Double] {
    var mix = Mix()
    mix.add(mode(hz, decay: decay))
    mix.add(mode(hz * 3.93, decay: decay * 0.18), gain: 0.18)
    mix.add(mode(hz * 9.2, decay: 0.012), gain: 0.05)
    mix.add(Biquad.lowpass(700).run(burst(decay: 0.006)), gain: 0.35)
    return mix.samples
}

/// Paper landing flat: a dull slap with a little body under it.
func slap(_ body: Double, gain: Double = 1) -> [Double] {
    var mix = Mix()
    mix.add(Biquad.lowpass(2_600).run(burst(decay: 0.006)), gain: 0.7 * gain)
    mix.add(mode(body, decay: 0.016, from: body * 1.3), gain: 0.4 * gain)
    return mix.samples
}

// MARK: Notes

/// The pitch `semitones` above A4.
func note(_ semitones: Double) -> Double { 440 * pow(2, semitones / 12) }

let c4 = note(-9), e4 = note(-5), g4 = note(-2), a3 = note(-12), a4 = note(0)
let c5 = note(3), d5 = note(5), e5 = note(7), g5 = note(10), gSharp5 = note(11)
let c6 = note(15), d6 = note(17), g6 = note(22)

// MARK: Recipes

struct Recipe {
    var name: String
    var variants = 1
    /// The loudest sample, from 0 to 1. The app scales it again per moment.
    var peak: Double
    var make: () -> [Double]
}

let recipes: [Recipe] = [
    // Shared by every game.
    Recipe(name: "Tap", variants: 4, peak: 0.42) {
        thock(215 * random.jitter(0.06), decay: 0.022)
    },
    Recipe(name: "Tick", variants: 4, peak: 0.3) {
        var mix = Mix()
        let hz = 1_150 * random.jitter(0.07)
        mix.add(mode(hz, decay: 0.009))
        mix.add(mode(hz * 2.4, decay: 0.004), gain: 0.3)
        mix.add(Biquad.bandpass(4_200, q: 1.2).run(burst(decay: 0.0012)), gain: 0.4)
        return mix.samples
    },
    // A knock and a short rising note, so it sounds like it goes up and away.
    Recipe(name: "Send", variants: 2, peak: 0.45) {
        var mix = Mix()
        let pip = 880 * random.jitter(0.02)
        mix.add(thock(170 * random.jitter(0.04), decay: 0.035))
        mix.add(mode(pip, decay: 0.06, from: pip * 0.6, glide: 0.02), at: 0.015, gain: 0.35)
        mix.add(mode(pip * 2, decay: 0.03, from: pip * 1.2, glide: 0.02), at: 0.015, gain: 0.08)
        return Biquad.lowpass(4_000).run(mix.samples)
    },
    Recipe(name: "Nudge", variants: 2, peak: 0.38) {
        bar(g4 * random.jitter(0.004))
    },
    Recipe(name: "Chime", peak: 0.42) {
        var mix = Mix()
        mix.add(bar(g4), gain: 0.3)
        mix.add(tine(g5))
        mix.add(tine(d6), at: 0.075, gain: 0.8)
        return mix.samples
    },
    Recipe(name: "Win", peak: 0.52) {
        var mix = Mix()
        mix.add(bar(c4, decay: 0.38), gain: 0.4)
        for (index, hz) in [c5, e5, g5, c6].enumerated() {
            mix.add(tine(hz, decay: 0.5), at: Double(index) * 0.085, gain: 1 - Double(index) * 0.05)
        }
        return mix.samples
    },
    Recipe(name: "Bonus", peak: 0.4) {
        var mix = Mix()
        mix.add(tine(e5))
        mix.add(tine(gSharp5), at: 0.09, gain: 0.85)
        return mix.samples
    },
    Recipe(name: "Soft", peak: 0.36) {
        var mix = Mix()
        mix.add(bar(a3), gain: 0.3)
        mix.add(tine(a4, decay: 0.36))
        mix.add(tine(e4, decay: 0.42), at: 0.14, gain: 0.9)
        return Biquad.lowpass(3_000).run(mix.samples)
    },
    Recipe(name: "Wrong", peak: 0.42) {
        var mix = Mix()
        mix.add(thock(160, decay: 0.03, bright: 0.4))
        mix.add(thock(146, decay: 0.03, bright: 0.4), at: 0.075, gain: 0.8)
        return Biquad.lowpass(1_500).run(mix.samples)
    },
    // A wooden peg snapped into place: the tip touches, the body lands a beat
    // later, and a soft ring two octaves up rounds it off. No noise wash, so it
    // stays clean when moves come quickly.
    Recipe(name: "Mark", variants: 3, peak: 0.42) {
        var mix = Mix()
        let body = 300 * random.jitter(0.04)
        mix.add(Biquad.bandpass(3_400, q: 1).run(burst(decay: 0.0009)), gain: 0.3)
        mix.add(thock(body, decay: 0.02, bright: 0.5), at: 0.012)
        mix.add(mode(body * 4, decay: 0.05), at: 0.012, gain: 0.18)
        return Biquad.lowpass(5_000).run(mix.samples)
    },
    Recipe(name: "Stamp", variants: 2, peak: 0.52) {
        var mix = Mix()
        let body = 130 * random.jitter(0.05)
        mix.add(mode(body, decay: 0.05, from: body * 1.6, glide: 0.008))
        mix.add(mode(body * 2.4, decay: 0.02), gain: 0.35)
        mix.add(Biquad.lowpass(1_800).run(burst(decay: 0.012)), gain: 0.7)
        mix.add(Biquad.bandpass(1_800, q: 0.7).run(burst(decay: 0.004)), gain: 0.3)
        return mix.samples
    },

    // Ludo.
    Recipe(name: "LudoDieKnock", variants: 4, peak: 0.5) {
        clack(1_750 * random.jitter(0.06), table: 240 * random.jitter(0.05))
    },
    Recipe(name: "LudoDieSettle", variants: 3, peak: 0.42) {
        var mix = Mix()
        let hz = 1_750 * random.jitter(0.05)
        for (time, gain) in [(0.0, 1.0), (0.045, 0.42), (0.074, 0.2), (0.091, 0.09)] {
            mix.add(
                clack(hz * random.jitter(0.02), table: 240, decay: 0.009),
                at: time * random.jitter(0.1),
                gain: gain
            )
        }
        return mix.samples
    },
    Recipe(name: "LudoStep", variants: 4, peak: 0.42) {
        var mix = Mix()
        let hz = 820 * random.jitter(0.06)
        mix.add(mode(hz, decay: 0.016), gain: 0.55)
        mix.add(mode(hz * 2.25, decay: 0.008), gain: 0.3)
        mix.add(mode(4_100 * random.jitter(0.05), decay: 0.003), gain: 0.15)
        mix.add(mode(200 * random.jitter(0.05), decay: 0.02, from: 260), gain: 0.7)
        mix.add(Biquad.bandpass(3_000, q: 0.9).run(burst(decay: 0.0012)), gain: 0.45)
        return mix.samples
    },
    Recipe(name: "LudoCapture", peak: 0.52) {
        var mix = Mix()
        mix.add(thock(175, decay: 0.03))
        mix.add(clack(900, table: 170, decay: 0.014), gain: 0.6)
        let air = sweep(swell(0.36, power: 1.2), from: 2_600, to: 800, q: 1.1)
        mix.add(Biquad.lowpass(3_000).run(air), at: 0.05, gain: 0.32)
        return mix.samples
    },
    Recipe(name: "LudoHome", peak: 0.42) {
        var mix = Mix()
        mix.add(thock(200, decay: 0.02), gain: 0.6)
        mix.add(tine(c6, decay: 0.34), at: 0.02)
        mix.add(tine(g6, decay: 0.3), at: 0.08, gain: 0.7)
        return mix.samples
    },

    // Connect Four.
    Recipe(name: "ConnectFourDrop", variants: 3, peak: 0.52) {
        var mix = Mix()
        let hz = 950 * random.jitter(0.05)
        let disc = { (decay: Double) -> [Double] in
            var disc = Mix()
            disc.add(mode(hz, decay: decay), gain: 0.6)
            disc.add(mode(hz * 2.2, decay: decay * 0.5), gain: 0.35)
            disc.add(mode(2_700 * random.jitter(0.04), decay: decay * 0.3), gain: 0.25)
            disc.add(Biquad.bandpass(3_500, q: 0.8).run(burst(decay: 0.0012)), gain: 0.5)
            return disc.samples
        }
        mix.add(disc(0.02))
        mix.add(mode(190 * random.jitter(0.05), decay: 0.035, from: 250), gain: 0.8)
        mix.add(disc(0.012), at: 0.03 * random.jitter(0.1), gain: 0.35)
        mix.add(disc(0.008), at: 0.05 * random.jitter(0.1), gain: 0.12)
        return mix.samples
    },

    // Exquisite Corpse: a fold of paper creased flat.
    Recipe(name: "Fold", variants: 3, peak: 0.45) {
        var mix = Mix()
        let length = 0.11 * random.jitter(0.15)
        let rising = (0..<count(length)).map { Double($0) / Double(count(length)) }
        mix.add(Biquad.bandpass(3_500, q: 0.8).run(times(crackle(length, perSecond: 380), rising)), gain: 0.9)
        mix.add(thock(220 * random.jitter(0.06), decay: 0.022, bright: 0.5), at: length - 0.01, gain: 0.7)
        mix.add(slap(260), at: length - 0.01, gain: 0.6)
        return mix.samples
    },

    // Mind Meld: a card flicked over and laid down.
    Recipe(name: "Flip", variants: 3, peak: 0.4) {
        var mix = Mix()
        mix.add(sweep(swell(0.05), from: 1_400, to: 4_200, q: 1.4), gain: 0.5)
        mix.add(slap(320 * random.jitter(0.06)), at: 0.04)
        mix.add(mode(320 * 2.9, decay: 0.005), at: 0.04, gain: 0.15)
        return mix.samples
    },

    // Story Chain: a page turned. A light lift, then the page lands on the stack.
    // No swish, because a long noise wash sounds like a broom.
    Recipe(name: "Page", variants: 2, peak: 0.4) {
        var mix = Mix()
        let land = 0.07 * random.jitter(0.1)
        mix.add(slap(300 * random.jitter(0.05), gain: 0.45))
        mix.add(slap(220 * random.jitter(0.05)), at: land)
        mix.add(thock(170, decay: 0.025, bright: 0.3), at: land, gain: 0.5)
        return Biquad.lowpass(2_500).run(mix.samples)
    },
]

// MARK: Finishing

/// Takes out rumble and fizz, trims the tail below -60 dB, fades both ends and sets the peak.
/// The fade out takes the last fifth, so a long ring dies away instead of stopping.
func finish(_ samples: [Double], peak: Double) -> [Double] {
    var output = Biquad.lowpass(9_000).run(Biquad.highpass(70).run(samples))
    let loudest = output.map(abs).max() ?? 0
    guard loudest > 0 else { fail("a recipe made silence") }
    if let last = output.lastIndex(where: { abs($0) > loudest * 0.001 }) {
        output = Array(output[...last])
    }
    let fadeIn = min(count(0.0003), output.count), fadeOut = min(max(count(0.012), output.count / 5), output.count)
    for index in 0..<fadeIn { output[index] *= Double(index) / Double(fadeIn) }
    for index in 0..<fadeOut { output[output.count - 1 - index] *= Double(index) / Double(fadeOut) }
    return output.map { $0 * peak / loudest }
}

func write(_ samples: [Double], to url: URL) throws {
    let settings: [String: Any] = [
        AVFormatIDKey: kAudioFormatLinearPCM,
        AVSampleRateKey: rate,
        AVNumberOfChannelsKey: 1,
        AVLinearPCMBitDepthKey: 16,
        AVLinearPCMIsFloatKey: false,
    ]
    let file = try AVAudioFile(forWriting: url, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: false)
    let frameCapacity = AVAudioFrameCount(samples.count)
    guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: frameCapacity),
          let channel = buffer.floatChannelData?[0] else { fail("could not make a buffer") }
    for (index, value) in samples.enumerated() { channel[index] = Float(value) }
    buffer.frameLength = AVAudioFrameCount(samples.count)
    try file.write(from: buffer)
}

guard CommandLine.arguments.count == 2 else { fail("usage: game-sounds <output folder>") }
let folder = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
for old in (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
where old.lastPathComponent.hasPrefix("GameSound") && old.pathExtension == "caf" {
    try? FileManager.default.removeItem(at: old)
}
for recipe in recipes {
    for variant in 1...recipe.variants {
        random = Random(recipe.name, variant)
        let samples = finish(recipe.make(), peak: recipe.peak)
        let url = folder.appendingPathComponent("GameSound\(recipe.name)\(variant).caf")
        do {
            try write(samples, to: url)
        } catch {
            fail("could not write \(url.lastPathComponent): \(error)")
        }
        let line = String(format: "%@  %.0f ms\n", url.lastPathComponent, Double(samples.count) / rate * 1_000)
        FileHandle.standardOutput.write(Data(line.utf8))
    }
}
