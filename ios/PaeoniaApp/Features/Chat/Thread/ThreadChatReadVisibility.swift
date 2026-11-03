import SwiftUI

/// A cell counts as read only after it intersects the chat viewport and stays there.
struct ThreadChatReadVisibility: ViewModifier {
    let viewport: CGRect
    let enabled: Bool
    let changed: (Bool) -> Void
    @State private var intersectsViewport = false

    func body(content: Content) -> some View {
        content
            .onGeometryChange(for: Bool.self) { geometry in
                let frame = geometry.frame(in: .global)
                return !viewport.isEmpty && !frame.isEmpty && frame.intersects(viewport)
            } action: { intersectsViewport = $0 }
            .task(id: enabled && intersectsViewport) {
                guard enabled && intersectsViewport else {
                    changed(false)
                    return
                }
                try? await Task.sleep(for: .milliseconds(150))
                guard !Task.isCancelled else { return }
                changed(true)
            }
            .onDisappear { changed(false) }
    }
}
