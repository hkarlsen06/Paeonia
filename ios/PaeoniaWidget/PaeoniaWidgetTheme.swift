import SwiftUI
import WidgetKit

enum PaeoniaWidgetSpacing {
    static let space6: CGFloat = 6
    static let space8: CGFloat = 8
    static let space12: CGFloat = 12
    static let space14: CGFloat = 14
    static let space16: CGFloat = 16
}

enum PaeoniaWidgetTypography {
    static func wordmark(family: WidgetFamily) -> Font {
        .system(size: family == .systemSmall ? 15 : 17, weight: .semibold, design: .serif)
    }

    static func metadata(family: WidgetFamily) -> Font {
        .system(size: family == .systemSmall ? 10 : 11, weight: .medium, design: .default)
    }

    static func title(family: WidgetFamily) -> Font {
        .system(size: family == .systemSmall ? 13 : 15, weight: .semibold, design: .default)
    }

    static func action(family: WidgetFamily) -> Font {
        .system(size: family == .systemSmall ? 10 : 12, weight: .semibold, design: .default)
    }
}

private enum PaeoniaWidgetPalette {
    static let plum = Color(paeoniaWidgetHex: 0x38_0F_27)
    static let petalLight = Color(paeoniaWidgetHex: 0xF2_7E_B2)
    static let pink = Color(paeoniaWidgetHex: 0xEF_50_94)
    static let blush = Color(paeoniaWidgetHex: 0xFB_F3_F7)
}

extension Color {
    static let paeoniaWidgetBackground = PaeoniaWidgetPalette.plum
    static let paeoniaWidgetTextPrimary = PaeoniaWidgetPalette.blush
    static let paeoniaWidgetTextSecondary = PaeoniaWidgetPalette.blush.opacity(0.68)
    static let paeoniaWidgetAccentPrimary = PaeoniaWidgetPalette.petalLight
    static let paeoniaWidgetAccentSecondary = PaeoniaWidgetPalette.pink
    static let paeoniaWidgetDrawing = PaeoniaWidgetPalette.blush
}

extension ShapeStyle where Self == Color {
    static var paeoniaWidgetBackground: Color { Color.paeoniaWidgetBackground }
    static var paeoniaWidgetTextPrimary: Color { Color.paeoniaWidgetTextPrimary }
    static var paeoniaWidgetTextSecondary: Color { Color.paeoniaWidgetTextSecondary }
    static var paeoniaWidgetAccentPrimary: Color { Color.paeoniaWidgetAccentPrimary }
    static var paeoniaWidgetAccentSecondary: Color { Color.paeoniaWidgetAccentSecondary }
    static var paeoniaWidgetDrawing: Color { Color.paeoniaWidgetDrawing }
}

private extension Color {
    init(paeoniaWidgetHex hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: 1
        )
    }
}
