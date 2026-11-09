import SwiftUI

/// The top of bottom controls, or the bottom content edge of the selected tab.
/// The highest edge leaves every bottom control available while a banner is visible.
struct PaeoniaBannerBottomEdgeKey: PreferenceKey {
    static let defaultValue: CGFloat? = nil

    static func reduce(value: inout CGFloat?, nextValue: () -> CGFloat?) {
        guard let next = nextValue() else { return }
        value = value.map { min($0, next) } ?? next
    }
}

extension View {
    func paeoniaBannerBottomEdge(at edge: VerticalEdge = .top, isActive: Bool = true) -> some View {
        background {
            GeometryReader { proxy in
                Color.clear.preference(
                    key: PaeoniaBannerBottomEdgeKey.self,
                    value: isActive
                        ? (edge == .top ? proxy.frame(in: .global).minY : proxy.frame(in: .global).maxY)
                        : nil
                )
            }
        }
    }
}
