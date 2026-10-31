import SwiftUI

extension View {
    func gameRowSurface(fill: Color, border: Color, borderWidth: CGFloat) -> some View {
        let shape = RoundedRectangle(cornerRadius: PaeoniaRadius.radius16, style: .continuous)
        return background(fill, in: shape)
            .overlay { shape.strokeBorder(border, lineWidth: borderWidth) }
            .contentShape(shape)
    }
}
