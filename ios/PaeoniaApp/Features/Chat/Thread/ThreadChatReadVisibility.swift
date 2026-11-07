import SwiftUI

/// The part of the screen where chat rows count as read. ExyteChat keeps the rows it has
/// built and redraws one only when its content changes, so a row that took these values
/// from the page would keep the ones it was built with. The page and every row share one
/// of these instead, and each row redraws when the page changes it.
@Observable
final class ThreadChatReadViewport {
    /// The message list's frame in global coordinates, above the composer.
    var frame = CGRect.zero
    /// False until the opening scroll settles, so rows that pass by on the way stay unread.
    var isReady = false
}

/// A cell counts as read only after it intersects the chat viewport and stays there.
struct ThreadChatReadVisibility: ViewModifier {
    let viewport: ThreadChatReadViewport
    let changed: (Bool) -> Void
    @State private var intersectsViewport = false

    func body(content: Content) -> some View {
        let readable = viewport.isReady ? viewport.frame : .zero
        content
            .onGeometryChange(for: Bool.self) { geometry in
                let frame = geometry.frame(in: .global)
                return !readable.isEmpty && !frame.isEmpty && frame.intersects(readable)
            } action: { intersectsViewport = $0 }
            .task(id: intersectsViewport) {
                guard intersectsViewport else {
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
