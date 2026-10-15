import CoreGraphics
import Foundation
import Testing
@testable import PaeoniaApp

struct LudoBoardArtTests {
    /// A color for each fixed-frame corner that is easy to tell apart, as red, green and blue.
    private let cornerColors: [[CGFloat]] = [[1, 0, 0], [0, 1, 0], [0, 0, 1], [1, 1, 0]]

    private func palette() -> LudoBoardArt.Palette {
        let corners = cornerColors.map { color in
            let cgColor = CGColor(srgbRed: color[0], green: color[1], blue: color[2], alpha: 1)
            return LudoBoardArt.Corner(color: cgColor, light: cgColor, spot: nil)
        }
        let white = CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1)
        return LudoBoardArt.Palette(
            base: white,
            track: white,
            corners: corners,
            homeNear: white,
            homeFar: white,
            peony: nil,
            grain: nil
        )
    }

    /// The color of the picture at a board point (x, z) in cells, as red, green and blue from 0 to 255.
    private func sample(_ image: CGImage, at point: SIMD2<Float>) -> [UInt8] {
        let side = image.width
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        let context = CGContext(
            data: &pixels,
            width: side,
            height: side,
            bitsPerComponent: 8,
            bytesPerRow: side * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        )
        context?.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
        let half = LudoBoardArt.half
        let column = Int((point.x + half) / (half * 2) * Float(side))
        let row = Int((point.y + half) / (half * 2) * Float(side))
        let offset = (row * side + column) * 4
        return Array(pixels[offset..<(offset + 3)])
    }

    @Test func eachYardIsPaintedWhereItsCornerIsOnTheBoard() throws {
        for viewer in [BoardPlayer.one, .two] {
            let pictures = try #require(LudoBoardArt.paint(viewer: viewer, palette: palette()))

            #expect(pictures.color.width == LudoSceneStyle.boardArtSide)
            let bumps = try #require(pictures.bumps)
            #expect(bumps.width == LudoSceneStyle.boardBumpSide)
            for corner in 0..<4 {
                // The middle of the yard, away from the carved panel's groove.
                let middle = LudoWorld.position(LudoBoardGeometry.yardCenter(corner: corner, viewer: viewer))
                let color = sample(pictures.color, at: SIMD2(middle.x + 1, middle.z + 1))
                let wanted = cornerColors[corner]

                for channel in 0..<3 {
                    let gap = abs(Int(color[channel]) - Int(wanted[channel] * 255))
                    #expect(gap < 40, "viewer \(viewer) corner \(corner)")
                }
            }
        }
    }

    @Test func theBumpsAreLeftOutWhenNotAskedFor() throws {
        let pictures = try #require(LudoBoardArt.paint(viewer: .one, palette: palette(), makesBumps: false))

        #expect(pictures.bumps == nil)
    }

    @Test func myYardIsAtTheBottomLeftOfThePicture() throws {
        let pictures = try #require(LudoBoardArt.paint(viewer: .one, palette: palette()))
        let mine = LudoBoardGeometry.corner(of: .one)
        let color = sample(pictures.color, at: SIMD2(-4.5, 4.5))
        let wanted = cornerColors[mine]

        for channel in 0..<3 {
            #expect(abs(Int(color[channel]) - Int(wanted[channel] * 255)) < 40)
        }
    }
}
