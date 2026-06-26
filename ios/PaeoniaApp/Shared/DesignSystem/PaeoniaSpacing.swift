import SwiftUI

enum PaeoniaSpacing {
    static let space2: CGFloat = 2
    static let space4: CGFloat = 4
    static let space8: CGFloat = 8
    static let space12: CGFloat = 12
    static let space16: CGFloat = 16
    static let space20: CGFloat = 20
    static let space24: CGFloat = 24
    static let space32: CGFloat = 32
    static let space40: CGFloat = 40

    static let screenHorizontalPadding: CGFloat = 20
    static let screenTopSpacing: CGFloat = 24
    static let sectionSpacing: CGFloat = 24
    static let cardContentPadding: CGFloat = 16
    static let buttonHeight: CGFloat = 52
    static let compactButtonHeight: CGFloat = 40

    /// Bottom inset for the small caption labels overlaid at the bottom of the Us
    /// tab tiles (the map distance and the widget CTA). Tuned to sit on the Apple
    /// Maps watermark line so the two tiles read consistently. Adjust this single
    /// value to nudge both labels together.
    static let tileCaptionBottomInset: CGFloat = 10
}
