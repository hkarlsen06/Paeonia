#!/usr/bin/env swift
import CoreGraphics
import Foundation
import ImageIO

// A diagnostic for these three retained UI-2156 crops only, not a general audit.
// Their visible content is light text/SF symbols on dark plum surfaces. Convert
// the embedded profile to sRGB, then require a flat 3x3 neighborhood (each RGB
// channel within 1) to sample glyph interiors rather than antialias edges.
// Luminance above 0.1 selects glyph cores; the nearest flat pixel below 0.1 in
// four directions within 80 physical pixels samples the adjacent background.
// Count cores in 0.1...0.3 explicitly so medium-gray glyphs are not silently
// excluded. All three known crops have zero flat cores in that interval.
// Dark glyphs on dark surfaces, boundaries, selection markers, and other states
// are outside this crop-specific measurement and require separate evaluation.
func writeLine(_ value: String) {
    FileHandle.standardOutput.write(Data((value + "\n").utf8))
}

func measure(_ path: String) {
    guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil),
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
          let space = CGColorSpace(name: CGColorSpace.sRGB) else {
        fputs("Could not decode the crop or create sRGB\n", stderr)
        exit(65)
    }
    let w = image.width, h = image.height
    var rgb = [UInt8](repeating: 0, count: w * h * 4)
    rgb.withUnsafeMutableBytes { data in
        guard let context = CGContext(data: data.baseAddress, width: w, height: h, bitsPerComponent: 8,
            bytesPerRow: w * 4, space: space,
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue) else {
            fputs("Could not convert the crop to sRGB\n", stderr)
            exit(65)
        }
        context.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
    }
    var lum = [Double](repeating: 0, count: w * h)
    for pixel in 0..<(w * h) {
        for (channel, coefficient) in [0.2126, 0.7152, 0.0722].enumerated() {
            let c = Double(rgb[pixel * 4 + channel]) / 255
            lum[pixel] += coefficient * (c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4))
        }
    }
    func flat(_ x: Int, _ y: Int) -> Bool {
        guard x > 0, y > 0, x < w - 1, y < h - 1 else { return false }
        for dy in -1...1 { for dx in -1...1 { for c in 0..<3 {
            if abs(Int(rgb[((y + dy) * w + x + dx) * 4 + c]) - Int(rgb[(y * w + x) * 4 + c])) > 1 { return false }
        } } }
        return true
    }
    func hex(_ x: Int, _ y: Int) -> String {
        (0..<3).map { String(format: "%02X", rgb[(y * w + x) * 4 + $0]) }.joined()
    }
    var minimum = Double.infinity, maximum = 0.0, count = 0
    var worstForeground = "", worstBackground = "", foregroundPosition = "", backgroundPosition = ""
    var mediumCoreCount = 0
    for y in 1..<(h - 1) { for x in 1..<(w - 1) {
        guard lum[y * w + x] > 0.1, flat(x, y) else { continue }
        if lum[y * w + x] <= 0.3 { mediumCoreCount += 1 }
        var background: (Int, Int)?
        for distance in 2...80 {
            for (dx, dy) in [(distance,0),(-distance,0),(0,distance),(0,-distance)] {
                let bx = x + dx, by = y + dy
                guard bx > 0, by > 0, bx < w - 1, by < h - 1,
                      lum[by * w + bx] < 0.1, flat(bx,by) else { continue }
                background = (bx,by)
                break
            }
            if background != nil { break }
        }
        guard let (bx,by) = background else { continue }
        let ratio = (lum[y * w + x] + 0.05) / (lum[by * w + bx] + 0.05)
        if ratio < minimum {
            minimum = ratio
            worstForeground = hex(x,y); worstBackground = hex(bx,by)
            foregroundPosition = "\(x):\(y)"; backgroundPosition = "\(bx):\(by)"
        }
        maximum = max(maximum, ratio)
        count += 1
    } }
    let fields = [URL(fileURLWithPath: path).lastPathComponent, String(w), String(h), String(count),
        String(mediumCoreCount), String(format: "%.3f", minimum), String(format: "%.3f", maximum),
        worstForeground, worstBackground, foregroundPosition, backgroundPosition]
    writeLine(fields.joined(separator: ","))
}
guard CommandLine.arguments.count > 1 else {
    fputs("usage: swift .audit/accessibility/measure-audit-crops.swift <crop.png>...\n", stderr)
    exit(64)
}
writeLine("crop,width,height,glyph_core_samples,medium_tone_core_samples,min_ratio,max_ratio,fg_sRGB,bg_sRGB,fg_xy,bg_xy")
for path in CommandLine.arguments.dropFirst() { measure(path) }
