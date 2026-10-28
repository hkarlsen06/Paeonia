import SwiftUI

/// Restores a map gesture area when its view reappears with unchanged geometry.
struct HomeMapArea: ViewModifier {
    let name: String
    let explorer: HomeMapExplorer?
    var extendsAcrossRows = false

    @State private var frame: CGRect?

    func body(content: Content) -> some View {
        content
            .onGeometryChange(for: CGRect.self) { proxy in
                let frame = proxy.frame(in: .global)
                guard extendsAcrossRows else { return frame }
                let top = frame.minY - PaeoniaSpacing.space16
                return CGRect(x: 0, y: top, width: .greatestFiniteMagnitude, height: frame.maxY - top)
            } action: { frame in
                self.frame = frame
                explorer?.setArea(name, frame)
            }
            // Tab switches preserve the geometry, so returning may not call its action.
            .onAppear { explorer?.setArea(name, frame) }
            .onChange(of: explorer.map(ObjectIdentifier.init)) { _, _ in
                explorer?.setArea(name, frame)
            }
            .onDisappear { explorer?.setArea(name, nil) }
    }
}
