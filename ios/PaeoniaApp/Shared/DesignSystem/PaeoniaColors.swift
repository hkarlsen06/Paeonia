import SwiftUI
import UIKit

// Paeonia ships a single, canonical plum-led brand theme for MVP. These tokens
// are the only place raw brand colors live; feature views must use the semantic
// names below and never hardcode hex values. The palette is intentionally fixed
// (not light/dark adaptive) so the app always feels like a private plum evening
// space. Accessibility settings such as Dynamic Type and Reduce Motion still
// apply; the brand surface does not.
//
// Canonical palette values come from the delivered logo and the marketing brand
// guidelines (docs/phase-2-design/09-marketing-brand-guidelines.md).

private enum PaeoniaPaletteHex {
    static let plumDeep: UInt32 = 0x2A_0B_1E
    static let plum: UInt32 = 0x38_0F_27
    static let plumSurfaceLow: UInt32 = 0x43_1A_30
    static let plumRaised: UInt32 = 0x4F_20_3A
    static let plumPressed: UInt32 = 0x5C_2A_47

    static let petalLight: UInt32 = 0xF2_7E_B2
    static let pink: UInt32 = 0xEF_50_94
    static let petalWarm: UInt32 = 0xE8_5D_86
    static let petalMist: UInt32 = 0xFD_E7_F1

    static let blush: UInt32 = 0xFB_F3_F7

    // Extra drawing ink hues, chosen to read clearly on the plum widget surface.
    static let inkGold: UInt32 = 0xF2_B8_4B
    static let inkBlue: UInt32 = 0x6F_B1_F0
    static let inkLavender: UInt32 = 0xB9_9C_F2

    static let error: UInt32 = 0xE5_48_4D
    static let warning: UInt32 = 0xE8_91_5D
    static let success: UInt32 = 0x5B_B9_8B
}

private enum PaeoniaPalette {
    // Plum brand ramp, dark to light.
    static let plumDeep = Color(paeoniaHex: PaeoniaPaletteHex.plumDeep)
    static let plum = Color(paeoniaHex: PaeoniaPaletteHex.plum)
    static let plumSurfaceLow = Color(paeoniaHex: PaeoniaPaletteHex.plumSurfaceLow)
    static let plumRaised = Color(paeoniaHex: PaeoniaPaletteHex.plumRaised)
    static let plumPressed = Color(paeoniaHex: PaeoniaPaletteHex.plumPressed)

    // Pink / petal accents.
    static let petalLight = Color(paeoniaHex: PaeoniaPaletteHex.petalLight)
    static let pink = Color(paeoniaHex: PaeoniaPaletteHex.pink)
    static let petalWarm = Color(paeoniaHex: PaeoniaPaletteHex.petalWarm)
    static let petalMist = Color(paeoniaHex: PaeoniaPaletteHex.petalMist)

    // Light text used on the plum surface.
    static let blush = Color(paeoniaHex: PaeoniaPaletteHex.blush)

    // Extra drawing ink hues.
    static let inkGold = Color(paeoniaHex: PaeoniaPaletteHex.inkGold)
    static let inkBlue = Color(paeoniaHex: PaeoniaPaletteHex.inkBlue)
    static let inkLavender = Color(paeoniaHex: PaeoniaPaletteHex.inkLavender)

    // State colors, kept calm and never generic red unless the state is real.
    static let error = Color(paeoniaHex: PaeoniaPaletteHex.error)
    static let warning = Color(paeoniaHex: PaeoniaPaletteHex.warning)
    static let success = Color(paeoniaHex: PaeoniaPaletteHex.success)
}

extension Color {
    static let paeoniaBackgroundPrimary = PaeoniaPalette.plum
    static let paeoniaBackgroundSecondary = PaeoniaPalette.plumDeep
    static let paeoniaBackgroundElevated = PaeoniaPalette.plumRaised

    static let paeoniaSurfacePrimary = PaeoniaPalette.plumRaised
    static let paeoniaSurfaceSecondary = PaeoniaPalette.plumSurfaceLow
    static let paeoniaSurfacePressed = PaeoniaPalette.plumPressed
    static let paeoniaSurfaceDisabled = PaeoniaPalette.plumSurfaceLow

    static let paeoniaTextPrimary = PaeoniaPalette.blush
    static let paeoniaTextSecondary = PaeoniaPalette.blush.opacity(0.74)
    static let paeoniaTextTertiary = PaeoniaPalette.blush.opacity(0.55)
    static let paeoniaTextInverse = PaeoniaPalette.plumDeep

    static let paeoniaAccentPrimary = PaeoniaPalette.petalLight
    static let paeoniaAccentSecondary = PaeoniaPalette.pink
    static let paeoniaSuccess = PaeoniaPalette.success
    static let paeoniaWarning = PaeoniaPalette.warning
    static let paeoniaError = PaeoniaPalette.error
    static let paeoniaSyncPending = PaeoniaPalette.warning
    static let paeoniaSyncError = PaeoniaPalette.error

    static let paeoniaPartnerOne = PaeoniaPalette.petalLight
    static let paeoniaPartnerTwo = PaeoniaPalette.petalWarm
    static let paeoniaMemory = PaeoniaPalette.petalMist
    static let paeoniaPrompt = PaeoniaPalette.pink
    static let paeoniaWidgetDrawing = PaeoniaPalette.blush
    static let paeoniaInkGold = PaeoniaPalette.inkGold
    static let paeoniaInkBlue = PaeoniaPalette.inkBlue
    static let paeoniaInkLavender = PaeoniaPalette.inkLavender
}

extension UIColor {
    static let paeoniaAccentPrimary = UIColor(paeoniaHex: PaeoniaPaletteHex.petalLight)
    static let paeoniaAccentSecondary = UIColor(paeoniaHex: PaeoniaPaletteHex.pink)
    static let paeoniaPartnerTwo = UIColor(paeoniaHex: PaeoniaPaletteHex.petalWarm)
    static let paeoniaSuccess = UIColor(paeoniaHex: PaeoniaPaletteHex.success)
    static let paeoniaWidgetDrawing = UIColor(paeoniaHex: PaeoniaPaletteHex.blush)
    static let paeoniaInkGold = UIColor(paeoniaHex: PaeoniaPaletteHex.inkGold)
    static let paeoniaInkBlue = UIColor(paeoniaHex: PaeoniaPaletteHex.inkBlue)
    static let paeoniaInkLavender = UIColor(paeoniaHex: PaeoniaPaletteHex.inkLavender)
}

extension ShapeStyle where Self == Color {
    static var paeoniaBackgroundPrimary: Color { Color.paeoniaBackgroundPrimary }
    static var paeoniaBackgroundSecondary: Color { Color.paeoniaBackgroundSecondary }
    static var paeoniaBackgroundElevated: Color { Color.paeoniaBackgroundElevated }
    static var paeoniaSurfacePrimary: Color { Color.paeoniaSurfacePrimary }
    static var paeoniaSurfaceSecondary: Color { Color.paeoniaSurfaceSecondary }
    static var paeoniaSurfacePressed: Color { Color.paeoniaSurfacePressed }
    static var paeoniaSurfaceDisabled: Color { Color.paeoniaSurfaceDisabled }
    static var paeoniaTextPrimary: Color { Color.paeoniaTextPrimary }
    static var paeoniaTextSecondary: Color { Color.paeoniaTextSecondary }
    static var paeoniaTextTertiary: Color { Color.paeoniaTextTertiary }
    static var paeoniaTextInverse: Color { Color.paeoniaTextInverse }
    static var paeoniaAccentPrimary: Color { Color.paeoniaAccentPrimary }
    static var paeoniaAccentSecondary: Color { Color.paeoniaAccentSecondary }
    static var paeoniaSuccess: Color { Color.paeoniaSuccess }
    static var paeoniaWarning: Color { Color.paeoniaWarning }
    static var paeoniaError: Color { Color.paeoniaError }
    static var paeoniaSyncPending: Color { Color.paeoniaSyncPending }
    static var paeoniaSyncError: Color { Color.paeoniaSyncError }
    static var paeoniaPartnerOne: Color { Color.paeoniaPartnerOne }
    static var paeoniaPartnerTwo: Color { Color.paeoniaPartnerTwo }
    static var paeoniaMemory: Color { Color.paeoniaMemory }
    static var paeoniaPrompt: Color { Color.paeoniaPrompt }
    static var paeoniaWidgetDrawing: Color { Color.paeoniaWidgetDrawing }
}

private extension Color {
    /// Builds a fixed sRGB color from a `0xRRGGBB` literal. Kept private so brand
    /// hex values never leak outside this file.
    init(paeoniaHex hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: 1
        )
    }
}

private extension UIColor {
    convenience init(paeoniaHex hex: UInt32) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}
