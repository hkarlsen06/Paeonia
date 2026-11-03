import SwiftUI

nonisolated enum PaeoniaRadius {
    static let radius8: CGFloat = 8
    static let radius12: CGFloat = 12
    static let radius16: CGFloat = 16
    static let radius20: CGFloat = 20
    static let radius24: CGFloat = 24
    static let radius28: CGFloat = 28
    static let radiusFull: CGFloat = .greatestFiniteMagnitude
    /// Every card's corners match the tab bar's. The bar is a 62 pt capsule, 20 pt in from the
    /// screen's sides like the cards, so a card that meets its top edge shares its outline.
    static let card: CGFloat = 31

    static let strokeHairline: CGFloat = 0.5
    static let strokeDefault: CGFloat = 1
    static let strokeEmphasis: CGFloat = 1.5
}
