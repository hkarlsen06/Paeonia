// Draw & Guess test helper. Converts between PencilKit drawings and something an agent can read.
// PencilKit crashes without a bundle id, so build it with an embedded Info.plist (CFBundleIdentifier) first:
//   swiftc pk.swift -o /tmp/dng-pk -Xlinker -sectcreate -Xlinker __TEXT -Xlinker __info_plist -Xlinker Info.plist
//   /tmp/dng-pk render <in.pkdrawing> <out.png>
//   /tmp/dng-pk make <strokes.json> <out.pkdrawing>
// strokes.json: [{"color":"#RRGGBB","width":5,"points":[[x,y],...]}, ...] on the 320 point canonical canvas.
// The canvas is plum (#380F27). Use the app's inks: blush #FBF3F7 (default), petal #F27EB2, pink #EF5094,
// warm #E85D86, green #5BB98B, gold #F2B84B, blue #6FB1F0, lavender #B99CF2.
import AppKit
import Foundation
import PencilKit

let side: CGFloat = 320
let args = CommandLine.arguments

func color(_ hex: String?) -> NSColor {
    guard let hex, hex.count == 7, let value = Int(hex.dropFirst(), radix: 16) else { return color("#FBF3F7") }
    return NSColor(
        srgbRed: CGFloat((value >> 16) & 0xFF) / 255,
        green: CGFloat((value >> 8) & 0xFF) / 255,
        blue: CGFloat(value & 0xFF) / 255,
        alpha: 1
    )
}

switch args.count == 4 ? args[1] : "" {
case "render":
    let drawing = try PKDrawing(data: Data(contentsOf: URL(fileURLWithPath: args[2])))
    let bounds = CGRect(x: 0, y: 0, width: side, height: side)
    // The app's canvas forces light mode so PencilKit shows inks as stored.
    var ink = NSImage()
    NSAppearance(named: .aqua)!.performAsCurrentDrawingAppearance { ink = drawing.image(from: bounds, scale: 2) }
    let image = NSImage(size: bounds.size)
    image.lockFocus()
    color("#380F27").setFill() // paeoniaBackgroundPrimary, the canvas behind the ink
    bounds.fill()
    ink.draw(in: bounds)
    image.unlockFocus()
    let rep = NSBitmapImageRep(data: image.tiffRepresentation!)!
    try rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: args[3]))
    let inks = Set(drawing.strokes.map { "\($0.ink.inkType.rawValue) \($0.ink.color.usingColorSpace(.sRGB)?.description ?? "?")" })
    print("strokes=\(drawing.strokes.count) bounds=\(drawing.bounds) inks=\(inks.sorted())")
case "make":
    struct Stroke: Decodable { let color: String?; let width: CGFloat?; let points: [[CGFloat]] }
    let strokes = try JSONDecoder().decode([Stroke].self, from: Data(contentsOf: URL(fileURLWithPath: args[2])))
    let start = Date()
    let pkStrokes = strokes.enumerated().map { index, stroke in
        let width = stroke.width ?? 5
        let points = stroke.points.enumerated().map { i, p in
            PKStrokePoint(
                location: CGPoint(x: p[0], y: p[1]),
                timeOffset: Double(i) * 0.016,
                size: CGSize(width: width, height: width),
                opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2
            )
        }
        let path = PKStrokePath(controlPoints: points, creationDate: start.addingTimeInterval(Double(index)))
        return PKStroke(ink: PKInk(.pen, color: color(stroke.color)), path: path)
    }
    try PKDrawing(strokes: pkStrokes).dataRepresentation().write(to: URL(fileURLWithPath: args[3]))
    print("wrote \(pkStrokes.count) strokes")
default:
    print("usage: swift pk.swift render <in.pkdrawing> <out.png> | make <strokes.json> <out.pkdrawing>")
    exit(2)
}
