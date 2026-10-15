// Makes the Ludo surface textures and the studio light in
// ios/PaeoniaApp/Resources/Assets.xcassets/Ludo from CC0 downloads. Run it again
// to change the tint, the speckle or the strength of the bumps.
//
// Download each into its own empty folder, outside the repo:
//   https://ambientcg.com/get?file=Porcelain002_1K-PNG.zip
//   https://ambientcg.com/get?file=Clay005_1K-PNG.zip
//   https://dl.polyhaven.org/file/ph-assets/HDRIs/hdr/1k/studio_small_08_1k.hdr
// Then, from an empty output folder:
//   swiftc -O -o ludo-surfaces ios/Scripts/ludo-surfaces.swift
//   ./ludo-surfaces studio_small_08_1k.hdr Porcelain002_1K-PNG_Roughness.png \
//     Clay005_1K-PNG_Color.png Clay005_1K-PNG_NormalGL.png Clay005_1K-PNG_Roughness.png <outDir>
// and copy the files into the image sets and the LudoStudio data set.
// LudoStudioPreview.jpg is only for checking the light by eye.
// The sky colors match the hub series: see "Light" in docs/games/ludo.md.

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("ludo-surfaces: \(message)\n".utf8))
    exit(1)
}

func require<Value>(_ value: Value?, _ what: String) -> Value {
    guard let value else { fail(what) }
    return value
}

func report(_ message: String) {
    FileHandle.standardOutput.write(Data("\(message)\n".utf8))
}

let arguments = CommandLine.arguments
guard arguments.count == 7 else {
    fail("usage: ludo-surfaces <hdr> <porcelainRoughness> <clayColor> <clayNormalGL> <clayRoughness> <outDir>")
}
let outFolder = URL(fileURLWithPath: arguments[6])

/// Four floats a pixel: red, green, blue, alpha.
struct FloatImage {
    var width: Int
    var height: Int
    var pixels: [Float]

    init(width: Int, height: Int) {
        self.width = width
        self.height = height
        pixels = [Float](repeating: 0, count: width * height * 4)
    }
}

/// Reads a picture as floats: linear light for the HDR, the stored values for data maps.
func load(_ path: String, linear: Bool) -> FloatImage {
    let source = require(CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil), "cannot open \(path)")
    let image = require(CGImageSourceCreateImageAtIndex(source, 0, nil), "cannot read \(path)")
    var result = FloatImage(width: image.width, height: image.height)
    let space = require(CGColorSpace(name: linear ? CGColorSpace.extendedLinearSRGB : CGColorSpace.sRGB), "color space")
    let info = CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.floatComponents.rawValue
        | CGBitmapInfo.byteOrder32Little.rawValue
    result.pixels.withUnsafeMutableBytes { buffer in
        let context = require(
            CGContext(
                data: buffer.baseAddress,
                width: image.width,
                height: image.height,
                bitsPerComponent: 32,
                bytesPerRow: image.width * 16,
                space: space,
                bitmapInfo: info
            ),
            "context for \(path)"
        )
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    }
    return result
}

/// A smaller picture, each pixel the average of a square of the original.
func shrunk(_ image: FloatImage, by factor: Int) -> FloatImage {
    var result = FloatImage(width: image.width / factor, height: image.height / factor)
    for row in 0..<result.height {
        for column in 0..<result.width {
            for channel in 0..<4 {
                var sum: Float = 0
                for down in 0..<factor {
                    for across in 0..<factor {
                        let source = (row * factor + down) * image.width + column * factor + across
                        sum += image.pixels[source * 4 + channel]
                    }
                }
                result.pixels[(row * result.width + column) * 4 + channel] = sum / Float(factor * factor)
            }
        }
    }
    return result
}

func write(_ image: FloatImage, gray: Bool, name: String, jpeg: Bool) {
    let channels = gray ? 1 : 4
    var bytes = [UInt8](repeating: 255, count: image.width * image.height * channels)
    for pixel in 0..<(image.width * image.height) {
        for channel in 0..<(gray ? 1 : 3) {
            let value = (image.pixels[pixel * 4 + channel] * 255).rounded()
            bytes[pixel * channels + channel] = UInt8(max(0, min(255, value)))
        }
    }
    let space = require(CGColorSpace(name: gray ? CGColorSpace.linearGray : CGColorSpace.sRGB), "color space")
    let provider = require(CGDataProvider(data: Data(bytes) as CFData), "pixels")
    let alpha = gray ? CGImageAlphaInfo.none : CGImageAlphaInfo.noneSkipLast
    let picture = require(
        CGImage(
            width: image.width,
            height: image.height,
            bitsPerComponent: 8,
            bitsPerPixel: 8 * channels,
            bytesPerRow: image.width * channels,
            space: space,
            bitmapInfo: CGBitmapInfo(rawValue: alpha.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: true,
            intent: .defaultIntent
        ),
        "picture \(name)"
    )
    let url = outFolder.appendingPathComponent(name + (jpeg ? ".jpg" : ".png"))
    let type = (jpeg ? UTType.jpeg : UTType.png).identifier as CFString
    let destination = require(CGImageDestinationCreateWithURL(url as CFURL, type, 1, nil), "file \(name)")
    let options = jpeg ? [kCGImageDestinationLossyCompressionQuality: 0.9] as CFDictionary : nil
    CGImageDestinationAddImage(destination, picture, options)
    guard CGImageDestinationFinalize(destination) else { fail("cannot write \(name)") }
}

func luminance(_ color: SIMD3<Float>) -> Float {
    0.2126 * color.x + 0.7152 * color.y + 0.0722 * color.z
}

func color(of image: FloatImage, at pixel: Int) -> SIMD3<Float> {
    SIMD3(image.pixels[pixel * 4], image.pixels[pixel * 4 + 1], image.pixels[pixel * 4 + 2])
}

/// Gray from `low` to `high`, from the darkest to the brightest one percent of the picture.
func remapped(_ image: FloatImage, from low: Float, to high: Float) -> FloatImage {
    var values = (0..<(image.width * image.height)).map { luminance(color(of: image, at: $0)) }
    let sorted = values.sorted()
    let darkest = sorted[sorted.count / 100]
    let brightest = sorted[sorted.count * 99 / 100]
    values = values.map { low + (high - low) * max(0, min(1, ($0 - darkest) / max(brightest - darkest, 0.0001))) }
    var result = image
    for pixel in values.indices {
        for channel in 0..<3 {
            result.pixels[pixel * 4 + channel] = values[pixel]
        }
    }
    return result
}

/// A normal map with its bumps scaled by `strength`.
func flattened(_ image: FloatImage, strength: Float) -> FloatImage {
    var result = image
    for pixel in 0..<(image.width * image.height) {
        let raw = color(of: image, at: pixel) * 2 - 1
        var normal = SIMD3(raw.x * strength, raw.y * strength, max(raw.z, 0.01))
        normal /= (normal * normal).sum().squareRoot()
        for channel in 0..<3 {
            result.pixels[pixel * 4 + channel] = normal[channel] * 0.5 + 0.5
        }
    }
    return result
}

// MARK: Surfaces

let porcelainRoughness = load(arguments[2], linear: false)
let clayColor = load(arguments[3], linear: false)
let clayNormal = load(arguments[4], linear: false)
let clayRoughness = load(arguments[5], linear: false)

/// The same numbers on every run.
struct Seeded {
    var state: UInt64 = 0x5EED

    mutating func next() -> Float {
        state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        return Float(state >> 40) / Float(1 << 24)
    }
}

/// The clay body shows faintly through the glaze, with sparse iron speckles, mostly small.
func glazeDetail() -> FloatImage {
    var glaze = remapped(shrunk(clayColor, by: 2), from: 0.9, to: 1.0)
    let side = glaze.width
    var random = Seeded()
    for _ in 0..<60 {
        let size = random.next()
        let centerX = random.next() * Float(side)
        let centerY = random.next() * Float(side)
        let radius = 1.2 + size * size * size * 4.5
        let darkness = 0.66 + random.next() * 0.2
        for row in Int(centerY - 10)...Int(centerY + 10) {
            for column in Int(centerX - 10)...Int(centerX + 10) {
                let distance = ((Float(column) - centerX) * (Float(column) - centerX)
                    + (Float(row) - centerY) * (Float(row) - centerY)).squareRoot()
                let cover = max(0, min(1, (radius - distance) / 1.5 + 0.5))
                guard cover > 0 else { continue }
                let pixel = ((row + side) % side * side + (column + side) % side) * 4
                for channel in 0..<3 {
                    glaze.pixels[pixel + channel] *= 1 - cover * (1 - darkness)
                }
            }
        }
    }
    return glaze
}

// Color pictures in three channels: a one-channel picture tints only the red.
write(glazeDetail(), gray: false, name: "LudoGlazeDetail", jpeg: false)
let glazeRoughness = remapped(shrunk(porcelainRoughness, by: 2), from: 0.55, to: 1.0)
write(glazeRoughness, gray: true, name: "LudoGlazeRoughness", jpeg: false)
write(flattened(shrunk(clayNormal, by: 2), strength: 0.3), gray: false, name: "LudoGlazeNormal", jpeg: true)
write(remapped(clayColor, from: 0.8, to: 1.0), gray: false, name: "LudoClayDetail", jpeg: true)
write(flattened(clayNormal, strength: 0.8), gray: false, name: "LudoClayNormal", jpeg: true)
write(remapped(clayRoughness, from: 0.75, to: 1.0), gray: true, name: "LudoClayRoughness", jpeg: true)

// MARK: Light

func linearColor(_ hex: UInt32) -> SIMD3<Float> {
    func linear(_ value: Float) -> Float {
        value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
    }
    return SIMD3(
        linear(Float((hex >> 16) & 0xFF) / 255),
        linear(Float((hex >> 8) & 0xFF) / 255),
        linear(Float(hex & 0xFF) / 255)
    )
}

func smooth(_ value: Float) -> Float {
    let fraction = max(0, min(1, value))
    return fraction * fraction * (3 - 2 * fraction)
}

func mix(_ first: SIMD3<Float>, _ second: SIMD3<Float>, _ amount: Float) -> SIMD3<Float> {
    first + (second - first) * amount
}

let skyLeft = linearColor(0xE88DBA)
let skyRight = linearColor(0xA992E6)
let skyZenith = linearColor(0xF6DCEA)
let ground = linearColor(0x2A0B1E)

/// The painted sky the app used before: `down` is 0 at the zenith and 1 at the horizon.
func paintedSky(across: Float, down: Float) -> SIMD3<Float> {
    guard down < 1 else { return ground }
    let horizon = mix(skyLeft, skyRight, smooth((across - 0.35) / 0.3))
    let sky = mix(skyZenith, horizon, smooth(down))
    return mix(sky, ground, smooth((down - 0.85) / 0.15))
}

/// The photo keeps its lights. The sky above tints it pink and lavender, and the floor
/// turns dark plum. It is scaled to the brightness of the painted sky.
func tintedStudio() -> FloatImage {
    var studio = load(arguments[1], linear: true)
    var paintedSum: Float = 0
    var studioSum: Float = 0
    for row in 0..<studio.height {
        for column in 0..<studio.width {
            let pixel = row * studio.width + column
            let across = Float(column) / Float(studio.width)
            let down = Float(row) / Float(studio.height / 2)
            paintedSum += luminance(paintedSky(across: across, down: down))
            let sky = paintedSky(across: across, down: min(down, 0.85))
            let skyTint = mix(SIMD3(repeating: 1), sky / max(luminance(sky), 0.01), 0.55)
            let floorTint = ground / max(luminance(ground), 0.001) * 0.08
            let tinted = color(of: studio, at: pixel) * mix(skyTint, floorTint, smooth((down - 0.9) / 0.2))
            studio.pixels[pixel * 4] = tinted.x
            studio.pixels[pixel * 4 + 1] = tinted.y
            studio.pixels[pixel * 4 + 2] = tinted.z
            studio.pixels[pixel * 4 + 3] = 1
            studioSum += luminance(tinted)
        }
    }
    let scale = paintedSum / studioSum
    report("environment scale \(scale)")
    for pixel in 0..<(studio.width * studio.height) {
        for channel in 0..<3 {
            studio.pixels[pixel * 4 + channel] *= scale
        }
    }
    // Half the size is plenty for lighting and soft reflections.
    return shrunk(studio, by: 2)
}

func writeOpenEXR(_ image: FloatImage, name: String) {
    var halves = image.pixels.map { Float16($0) }
    let data = halves.withUnsafeMutableBytes { Data($0) }
    let provider = require(CGDataProvider(data: data as CFData), "studio pixels")
    let space = require(CGColorSpace(name: CGColorSpace.extendedLinearSRGB), "color space")
    let info = CGImageAlphaInfo.noneSkipLast.rawValue | CGBitmapInfo.floatComponents.rawValue
        | CGBitmapInfo.byteOrder16Little.rawValue
    let picture = require(
        CGImage(
            width: image.width,
            height: image.height,
            bitsPerComponent: 16,
            bitsPerPixel: 64,
            bytesPerRow: image.width * 8,
            space: space,
            bitmapInfo: CGBitmapInfo(rawValue: info),
            provider: provider,
            decode: nil,
            shouldInterpolate: true,
            intent: .defaultIntent
        ),
        "studio picture"
    )
    let url = outFolder.appendingPathComponent(name + ".exr")
    let destination = require(
        CGImageDestinationCreateWithURL(url as CFURL, "com.ilm.openexr-image" as CFString, 1, nil),
        "file \(name)"
    )
    CGImageDestinationAddImage(destination, picture, nil)
    guard CGImageDestinationFinalize(destination) else { fail("cannot write \(name)") }
}

let studio = tintedStudio()
writeOpenEXR(studio, name: "LudoStudio")

/// The light squeezed into ordinary brightness, to look at.
var preview = studio
for index in preview.pixels.indices where index % 4 != 3 {
    let value = preview.pixels[index]
    preview.pixels[index] = pow(value / (1 + value), 1 / 2.2)
}
write(preview, gray: false, name: "LudoStudioPreview", jpeg: true)
