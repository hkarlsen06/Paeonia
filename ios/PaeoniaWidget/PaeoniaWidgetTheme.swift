import SwiftUI
import WidgetKit

enum PaeoniaWidgetSpacing {
    static let space8: CGFloat = 8
    static let space12: CGFloat = 12
}

enum PaeoniaWidgetTypography {
    static func metadata(family: WidgetFamily) -> Font {
        switch family {
        case .systemSmall:
            .caption2.weight(.medium)
        default:
            .caption.weight(.medium)
        }
    }

    static func title(family: WidgetFamily) -> Font {
        switch family {
        case .systemSmall:
            .caption.weight(.semibold)
        default:
            .callout.weight(.semibold)
        }
    }
}

private enum PaeoniaWidgetPalette {
    static let plum = Color(paeoniaWidgetHex: 0x38_0F_27)
    static let petalLight = Color(paeoniaWidgetHex: 0xF2_7E_B2)
    static let blush = Color(paeoniaWidgetHex: 0xFB_F3_F7)
}

extension Color {
    static let paeoniaWidgetBackground = PaeoniaWidgetPalette.plum
    static let paeoniaWidgetTextPrimary = PaeoniaWidgetPalette.blush
    static let paeoniaWidgetTextSecondary = PaeoniaWidgetPalette.blush.opacity(0.68)
    static let paeoniaWidgetAccentPrimary = PaeoniaWidgetPalette.petalLight
}

extension ShapeStyle where Self == Color {
    static var paeoniaWidgetBackground: Color { Color.paeoniaWidgetBackground }
    static var paeoniaWidgetTextPrimary: Color { Color.paeoniaWidgetTextPrimary }
    static var paeoniaWidgetTextSecondary: Color { Color.paeoniaWidgetTextSecondary }
    static var paeoniaWidgetAccentPrimary: Color { Color.paeoniaWidgetAccentPrimary }
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
