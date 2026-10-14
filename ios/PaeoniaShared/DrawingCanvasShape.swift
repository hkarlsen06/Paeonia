import SwiftUI

/// The rounded square of the drawing canvas, scaled to any size. The drawing
/// screen rounds a canvas about 360 points wide by 28 points on a phone, so a
/// saved drawing shown smaller in the app or the widget keeps the same corners.
struct DrawingCanvasShape: Shape {
    func path(in rect: CGRect) -> Path {
        let radius = min(rect.width, rect.height) * 28 / 360
        return RoundedRectangle(cornerRadius: radius, style: .continuous).path(in: rect)
    }
}
