import SwiftUI

/// Palette hues shared by the app and widget. Feature code uses semantic roles.
nonisolated enum PaeoniaPalette {
    static let plumDeep = Color(paeoniaHex: 0x2A_0B_1E)
    static let plum = Color(paeoniaHex: 0x38_0F_27)
    static let plumSurfaceLow = Color(paeoniaHex: 0x43_1A_30)
    static let plumRaised = Color(paeoniaHex: 0x4F_20_3A)
    static let plumPressed = Color(paeoniaHex: 0x5C_2A_47)
    static let outgoingMessage = Color(paeoniaHex: 0x68_1B_3C)
    static let petalLight = Color("AccentColor")
    static let pink = Color(paeoniaHex: 0xEF_50_94)
    static let petalWarm = Color(paeoniaHex: 0xE8_5D_86)
    static let petalWarmLight = Color(paeoniaHex: 0xF5_87_A6)
    static let petalMist = Color(paeoniaHex: 0xFD_E7_F1)
    static let blush = Color(paeoniaHex: 0xFB_F3_F7)
    static let gold = Color(paeoniaHex: 0xF2_B8_4B)
    static let blue = Color(paeoniaHex: 0x6F_B1_F0)
    static let lavender = Color(paeoniaHex: 0xB9_9C_F2)
    static let coral = Color(paeoniaHex: 0xE5_48_4D)
    static let coralLight = Color(paeoniaHex: 0xFF_80_84)
    static let coralBright = Color(paeoniaHex: 0xEA_5C_61)
    static let orange = Color(paeoniaHex: 0xE8_91_5D)
    static let mint = Color(paeoniaHex: 0x82_BA_A5)
    static let green = Color(paeoniaHex: 0x5B_B9_8B)
}

nonisolated enum PaeoniaBrandColors {
    static let background = PaeoniaPalette.plum
    static let textPrimary = PaeoniaPalette.blush
    static let textSecondary = PaeoniaPalette.blush.opacity(0.74)
    static let accent = PaeoniaPalette.petalLight
}

nonisolated private extension Color {
    /// Builds a fixed sRGB color from a `0xRRGGBB` literal. Palette literals stay in this file.
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
