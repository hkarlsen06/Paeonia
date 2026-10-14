import SwiftUI

/// How the story page looks. The page reads like a book, so it uses the system
/// serif at the `title3` text style and scales with Dynamic Type.
enum StoryChainPageStyle {
    /// The widest the text column grows, in points.
    static let measure: CGFloat = 560
    static let lineSpacing: CGFloat = 6
    /// The partner's live draft is drawn at this opacity.
    static let ghostOpacity = 0.5
    static let bodyFont = Font.system(.title3, design: .serif, weight: .regular)
    static let titleFont = Font.system(.largeTitle, design: .serif, weight: .semibold)
    /// The ink of my own lines.
    static let mineInk = Color.paeoniaTextPrimary
    /// The ink of my partner's lines.
    static let partnerInk = Color.paeoniaAccentPrimary
}
