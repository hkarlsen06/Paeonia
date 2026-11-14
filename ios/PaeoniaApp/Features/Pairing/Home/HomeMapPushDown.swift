import SwiftUI

/// How much taller than the screen the map layout's page grows, so a tall card pushes the
/// cards under it down instead of shrinking the map. The cards report it with
/// `homeMapPushesDown()`, and `HomeMapPageHeight` adds it to the page's height.
struct HomeMapPushDownKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value += nextValue()
    }
}

/// The map layout's page is at least `minHeight` tall, plus how far its tall cards push it
/// down. Nil leaves the page its own height.
struct HomeMapPageHeight: ViewModifier {
    let minHeight: CGFloat?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pushDown: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .frame(minHeight: minHeight.map { $0 + pushDown }, alignment: .top)
            .onPreferenceChange(HomeMapPushDownKey.self) { height in
                // In step with the card that comes or goes, which Home animates the same way.
                withAnimation(reduceMotion ? nil : PaeoniaMotion.homeLayoutChange) { pushDown = height }
            }
    }
}

extension View {
    /// On the map layout, this card takes only `creep` points of the map's height. The rest
    /// of its height pushes the cards under it down, below the tab bar until the person
    /// scrolls. The classic layout ignores it.
    func homeMapPushesDown(creep: CGFloat = 72) -> some View {
        background {
            GeometryReader { proxy in
                Color.clear.preference(key: HomeMapPushDownKey.self, value: max(proxy.size.height - creep, 0))
            }
        }
    }
}
