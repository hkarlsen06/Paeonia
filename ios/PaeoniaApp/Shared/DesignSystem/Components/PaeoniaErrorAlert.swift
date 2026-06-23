import SwiftUI

/// Title and message for a notice that should be shown as a system pop-up.
///
/// Paeonia presents notices (errors and similar interruptions) as dismissible
/// system alerts rather than inline banners, so they never push the underlying
/// screen around. Use `View.paeoniaErrorAlert(_:onDismiss:)` to present one.
struct PaeoniaAlertContent: Equatable {
    let title: LocalizedStringResource
    let message: LocalizedStringResource
}

extension View {
    /// Presents `content` as a dismissible system alert. When the user dismisses
    /// it, `onDismiss` is called so the owner can clear its notice state.
    func paeoniaErrorAlert(
        _ content: PaeoniaAlertContent?,
        onDismiss: @escaping () -> Void
    ) -> some View {
        let isPresented = Binding(
            get: { content != nil },
            set: { presented in
                if !presented {
                    onDismiss()
                }
            }
        )

        return alert(
            content.map { Text($0.title) } ?? Text(verbatim: ""),
            isPresented: isPresented,
            presenting: content
        ) { _ in
            // No explicit buttons: the system adds a localized "OK" that dismisses.
        } message: { content in
            Text(content.message)
        }
    }
}
