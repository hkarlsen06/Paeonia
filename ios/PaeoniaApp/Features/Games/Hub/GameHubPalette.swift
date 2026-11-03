import CoreGraphics
import SwiftUI

/// The colors of a game card's moving backdrop (`GameHubFluidBackdrop`), taken from the
/// picture on the card. There are always `count` of them, the most common color first.
/// The card's text reads on every one of them, because the type caps each color's
/// relative luminance at `maximumLuminance` when it is made.
nonisolated struct GameHubPalette: Hashable, Sendable {
    static let count = 4
    /// The status line, blush at 74 percent under the card's lightest plum shadow (25
    /// percent), keeps 4.5:1 on any hue at this luminance. White text gets 5.5:1.
    static let maximumLuminance: Float = 0.14

    let colors: [Color.Resolved]

    private init(capping colors: [Color.Resolved]) {
        self.colors = colors.map(Self.capped)
    }

    /// The pink and lavender of the room the daily question card shows, for a picture
    /// with too few colored pixels to choose from.
    static let fallback = GameHubPalette(capping: [
        PaeoniaPalette.pink, PaeoniaPalette.lavender, PaeoniaPalette.petalWarm, PaeoniaPalette.plumPressed,
    ].map { $0.resolve(in: EnvironmentValues()) })

    /// The colors of `images` together. Transparent, grayish and dark pixels don't count,
    /// and more saturated pixels count more. Each color is the average of one band of
    /// hues, at least 30 degrees from the others, made vivid enough for a dark backdrop.
    init(images: [CGImage]) {
        var bands = [HueBand](repeating: HueBand(), count: Self.bandCount)
        for image in images {
            for pixel in Self.pixels(of: image) {
                guard let band = Self.band(of: pixel) else { continue }
                bands[band].add(pixel)
            }
        }
        let total = bands.reduce(0) { $0 + $1.weight }
        guard total >= Self.minimumWeight else {
            self = .fallback
            return
        }
        var chosen: [Int] = []
        for band in bands.indices.sorted(by: { bands[$0].weight > bands[$1].weight }) {
            let isColorOfPicture = chosen.isEmpty || bands[band].weight >= total * Self.minimumShare
            guard chosen.count < Self.count, isColorOfPicture else { break }
            let isDistinct = chosen.allSatisfy { other in
                let distance = abs(other - band)
                return min(distance, Self.bandCount - distance) >= Self.minimumBandDistance
            }
            if isDistinct { chosen.append(band) }
        }
        var colors = chosen.map { Self.deepened(bands[$0].average) }
        // A picture with fewer hues fills the rest with deeper shades of its own colors,
        // so the backdrop shows no color the picture lacks.
        let found = colors.count
        for fill in 0 ..< Self.count - found {
            colors.append(Self.capped(colors[fill % found]).dimmed(by: [0.5, 0.3, 0.2][fill / found]))
        }
        self.init(capping: colors)
    }

    // MARK: - Reading the pixels

    private static let side = 48
    private static let bandCount = 24
    private static let minimumBandDistance = 2
    /// Below this share of the colored pixels, a hue is a speck, not a color of the picture.
    private static let minimumShare = 0.05
    /// One percent of the sample, counted as fully saturated pixels.
    private static let minimumWeight = Double(side * side) / 100
    private static let minimumSaturation = 0.72

    private struct Pixel {
        let red, green, blue: Double
    }

    /// The image drawn into a 48 by 48 sRGB sample, without the transparent pixels.
    private static func pixels(of image: CGImage) -> [Pixel] {
        var bytes = [UInt8](repeating: 0, count: side * side * 4)
        let drawn = bytes.withUnsafeMutableBytes { buffer -> Bool in
            guard let space = CGColorSpace(name: CGColorSpace.sRGB),
                  let context = CGContext(
                      data: buffer.baseAddress, width: side, height: side, bitsPerComponent: 8,
                      bytesPerRow: side * 4, space: space,
                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                  )
            else { return false }
            context.interpolationQuality = .medium
            context.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
            return true
        }
        guard drawn else { return [] }
        return stride(from: 0, to: bytes.count, by: 4).compactMap { index in
            let alpha = Double(bytes[index + 3]) / 255
            guard alpha >= 0.5 else { return nil }
            return Pixel(
                red: Double(bytes[index]) / 255 / alpha,
                green: Double(bytes[index + 1]) / 255 / alpha,
                blue: Double(bytes[index + 2]) / 255 / alpha
            )
        }
    }

    /// The hue band a pixel counts toward, or nil when it is grayish or dark.
    private static func band(of pixel: Pixel) -> Int? {
        let hsb = HSB(pixel)
        guard hsb.saturation >= 0.2, hsb.brightness >= 0.35 else { return nil }
        return min(Int(hsb.hue * Double(bandCount)), bandCount - 1)
    }

    private struct HueBand {
        var weight = 0.0
        var red = 0.0
        var green = 0.0
        var blue = 0.0

        mutating func add(_ pixel: Pixel) {
            let saturation = HSB(pixel).saturation
            weight += saturation
            red += pixel.red * saturation
            green += pixel.green * saturation
            blue += pixel.blue * saturation
        }

        var average: Color.Resolved {
            Color.Resolved(
                colorSpace: .sRGB, red: Float(red / weight), green: Float(green / weight), blue: Float(blue / weight)
            )
        }
    }

    private struct HSB {
        let hue, saturation, brightness: Double

        init(_ pixel: Pixel) {
            let high = max(pixel.red, pixel.green, pixel.blue)
            let low = min(pixel.red, pixel.green, pixel.blue)
            let range = high - low
            brightness = high
            saturation = high > 0 ? range / high : 0
            guard range > 0 else {
                hue = 0
                return
            }
            let sector: Double = switch high {
            case pixel.red: (pixel.green - pixel.blue) / range
            case pixel.green: 2 + (pixel.blue - pixel.red) / range
            default: 4 + (pixel.red - pixel.green) / range
            }
            hue = (sector / 6).truncatingRemainder(dividingBy: 1) + (sector < 0 ? 1 : 0)
        }
    }

    // MARK: - Shaping the colors

    /// `color` made vivid enough for a dark backdrop, with a yellow hue turned to amber.
    /// Pastel colors darkened to the luminance cap look dusty, and yellow looks olive.
    private static func deepened(_ color: Color.Resolved) -> Color.Resolved {
        let hsb = HSB(Pixel(red: Double(color.red), green: Double(color.green), blue: Double(color.blue)))
        let isYellow = (35.0 / 360 ..< 90.0 / 360).contains(hsb.hue)
        return Color(
            hue: isYellow ? 30.0 / 360 : hsb.hue,
            saturation: max(hsb.saturation, minimumSaturation),
            brightness: hsb.brightness
        )
        .resolve(in: EnvironmentValues())
    }

    /// `color` darkened, at the same hue and saturation, until its relative luminance is
    /// at most `maximumLuminance`. Scaling the linear light keeps the color's chroma.
    private static func capped(_ color: Color.Resolved) -> Color.Resolved {
        let luminance = color.relativeLuminance
        guard luminance > maximumLuminance else { return color }
        return color.dimmed(by: maximumLuminance / luminance)
    }
}

nonisolated extension Color.Resolved {
    /// The WCAG relative luminance, from 0 for black to 1 for white.
    var relativeLuminance: Float {
        0.2126 * max(0, linearRed) + 0.7152 * max(0, linearGreen) + 0.0722 * max(0, linearBlue)
    }

    /// The color with its light scaled by `factor`, from 0 to 1. Its luminance scales by the same factor.
    func dimmed(by factor: Float) -> Color.Resolved {
        var dimmed = self
        dimmed.linearRed = max(0, linearRed) * factor
        dimmed.linearGreen = max(0, linearGreen) * factor
        dimmed.linearBlue = max(0, linearBlue) * factor
        return dimmed
    }
}
