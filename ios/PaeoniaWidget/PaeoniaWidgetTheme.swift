import SwiftUI
import WidgetKit

enum PaeoniaWidgetSpacing {
    static let space8: CGFloat = 8
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

extension Color {
    static let paeoniaWidgetBackground = PaeoniaBrandColors.background
    static let paeoniaWidgetTextPrimary = PaeoniaBrandColors.textPrimary
    static let paeoniaWidgetTextSecondary = PaeoniaBrandColors.textSecondary
    static let paeoniaWidgetAccentPrimary = PaeoniaBrandColors.accent
}

extension ShapeStyle where Self == Color {
    static var paeoniaWidgetBackground: Color { Color.paeoniaWidgetBackground }
    static var paeoniaWidgetTextPrimary: Color { Color.paeoniaWidgetTextPrimary }
    static var paeoniaWidgetTextSecondary: Color { Color.paeoniaWidgetTextSecondary }
    static var paeoniaWidgetAccentPrimary: Color { Color.paeoniaWidgetAccentPrimary }
}
