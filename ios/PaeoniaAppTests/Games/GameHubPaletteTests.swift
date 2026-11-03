import CoreGraphics
import SwiftUI
import Testing

@testable import PaeoniaApp

/// A game card's text sits on its picture's colors, so every palette must keep it readable.
struct GameHubPaletteTests {
    @Test(arguments: [
        [srgb(1, 1, 0)],
        [srgb(0.6, 1, 1), srgb(1, 0.85, 0.95)],
        (0 ..< 48).map { step in Color(hue: Double(step) / 48, saturation: 1, brightness: 1).resolve(in: .init()) },
    ])
    func theStatusLineReadsOnEveryColor(stripes: [Color.Resolved]) throws {
        let palette = GameHubPalette(images: [try image(stripes)])
        #expect(palette.colors.count == GameHubPalette.count)
        for color in palette.colors {
            #expect(statusLineContrast(on: color) >= 4.5)
        }
    }

    @Test func aGrayPictureGetsTheFallback() throws {
        let grays = [srgb(0.5, 0.5, 0.5), srgb(0.95, 0.95, 0.95), srgb(0.05, 0.05, 0.05)]
        let palette = GameHubPalette(images: [try image(grays)])
        #expect(palette == .fallback)
    }
}

/// The status line's contrast where the card's plum shadow is lightest: secondary text,
/// blush at 74 percent, over `color` under the shadow at the title.
private func statusLineContrast(on color: Color.Resolved) -> Float {
    let environment = EnvironmentValues()
    let shadow = Color.paeoniaBackgroundSecondary.resolve(in: environment)
    let text = PaeoniaPalette.blush.resolve(in: environment)
    let under = mix(color, shadow, Float(PaeoniaIllustratedCardLayout.shadowAtTitle))
    let lit = mix(under, text, 0.74)
    let (light, dark) = (lit.relativeLuminance, under.relativeLuminance)
    return (max(light, dark) + 0.05) / (min(light, dark) + 0.05)
}

/// `top` over `base` at `opacity`, blended in sRGB as SwiftUI composites.
private func mix(_ base: Color.Resolved, _ top: Color.Resolved, _ opacity: Float) -> Color.Resolved {
    Color.Resolved(
        colorSpace: .sRGB,
        red: base.red + (top.red - base.red) * opacity,
        green: base.green + (top.green - base.green) * opacity,
        blue: base.blue + (top.blue - base.blue) * opacity
    )
}

private func srgb(_ red: Float, _ green: Float, _ blue: Float) -> Color.Resolved {
    Color.Resolved(colorSpace: .sRGB, red: red, green: green, blue: blue)
}

/// An opaque image of vertical stripes in the given colors.
private func image(_ stripes: [Color.Resolved]) throws -> CGImage {
    let width = 96
    let space = try #require(CGColorSpace(name: CGColorSpace.sRGB))
    let context = try #require(CGContext(
        data: nil, width: width, height: 32, bitsPerComponent: 8, bytesPerRow: 0,
        space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ))
    let stripeWidth = Double(width) / Double(stripes.count)
    for (index, stripe) in stripes.enumerated() {
        context.setFillColor(
            red: CGFloat(stripe.red), green: CGFloat(stripe.green), blue: CGFloat(stripe.blue), alpha: 1
        )
        context.fill(CGRect(x: Double(index) * stripeWidth, y: 0, width: stripeWidth, height: 32))
    }
    return try #require(context.makeImage())
}
