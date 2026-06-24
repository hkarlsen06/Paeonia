import SwiftUI

enum PaeoniaTypography {
    static let display = Font.largeTitle.bold()
    static let largeTitle = Font.largeTitle.weight(.semibold)
    static let heroTitle = Font.title.weight(.semibold)
    static let title = Font.title2.weight(.semibold)
    static let sectionTitle = Font.headline
    static let body = Font.body
    static let bodyEmphasis = Font.body.weight(.semibold)
    static let caption = Font.caption
    static let button = Font.headline
    static let countdownNumber = Font.system(.largeTitle, design: .rounded).weight(.bold)
    static let widgetPrimary = Font.headline
    static let widgetSecondary = Font.caption

    static func wordmark(size: CGFloat) -> Font {
        Font.system(size: size, weight: .semibold, design: .serif)
    }

    static func wordmarkTagline(size: CGFloat) -> Font {
        Font.system(size: size, weight: .semibold, design: .serif)
    }
}
