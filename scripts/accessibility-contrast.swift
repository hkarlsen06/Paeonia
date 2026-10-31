#!/usr/bin/env swift
import CoreGraphics
import Foundation
import ImageIO

// Measures the rendered swatches in the accessibility-colors developer scenarios.
// Convert the PNG's embedded color profile to sRGB before computing luminance.
guard CommandLine.arguments.count == 2 else {
    fputs("usage: swift scripts/accessibility-contrast.swift <screenshot.png>\n", stderr)
    exit(64)
}
let url = URL(fileURLWithPath: CommandLine.arguments[1])
guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
      let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
      let space = CGColorSpace(name: CGColorSpace.sRGB) else {
    fputs("Could not decode the screenshot\n", stderr)
    exit(65)
}
let width = image.width
let height = image.height
var bytes = [UInt8](repeating: 0, count: width * height * 4)
bytes.withUnsafeMutableBytes { buffer in
    guard let context = CGContext(
        data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
        bytesPerRow: width * 4, space: space,
        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
    ) else { fatalError("Could not create the sRGB image") }
    context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
}
func pixel(x: Int, y: Int) -> [UInt8] {
    let offset = (y * width + x) * 4
    return Array(bytes[offset..<(offset + 3)])
}
func luminance(_ color: [UInt8]) -> Double {
    zip(color, [0.2126, 0.7152, 0.0722]).reduce(0) { result, pair in
        let value = Double(pair.0) / 255
        let linear = value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        return result + linear * pair.1
    }
}
func hex(_ color: [UInt8]) -> String {
    color.map { String(format: "%02X", $0) }.joined()
}
var start = 0
var previous: [[UInt8]] = []
struct Sample {
    let y: Int
    let length: Int
    let colors: [[UInt8]]
}
var samples: [Sample] = []
for y in 0...height {
    let pair = y < height ? [pixel(x: width / 4, y: y), pixel(x: width * 3 / 4, y: y)] : []
    if pair != previous {
        if previous.count == 2, previous[0] != previous[1], y - start >= 12 {
            samples.append(Sample(y: start, length: y - start, colors: previous))
        }
        previous = pair
        start = y
    }
}
func writeLine(_ value: String) {
    FileHandle.standardOutput.write(Data((value + "\n").utf8))
}
writeLine("y,length,foreground_sRGB,background_sRGB,contrast,text_4_5,nontext_3")
for sample in samples {
    let first = luminance(sample.colors[0])
    let second = luminance(sample.colors[1])
    let ratio = (max(first, second) + 0.05) / (min(first, second) + 0.05)
    let fields = [
        String(sample.y), String(sample.length), hex(sample.colors[0]), hex(sample.colors[1]),
        String(format: "%.3f", ratio), String(ratio >= 4.5), String(ratio >= 3)
    ]
    writeLine(fields.joined(separator: ","))
}
guard samples.count >= 10 else {
    fputs("Expected ten rendered swatches; verify the scenario and screenshot\n", stderr)
    exit(65)
}
