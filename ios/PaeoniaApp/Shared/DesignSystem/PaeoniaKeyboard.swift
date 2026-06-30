import SwiftUI
import UIKit

/// Centralized keyboard dismissal for text-entry surfaces.
///
/// Paeonia standardizes on two complementary affordances, both routed through here so
/// every screen behaves the same:
///
/// - a "Done" button pinned above the keyboard (`keyboardDoneToolbar`), the
///   platform-standard way to put the keyboard away from anywhere; and
/// - tapping empty space to dismiss (`dismissesKeyboardOnBackgroundTap`).
///
/// Both resign the first responder globally, so a screen adopts them with one modifier
/// and never has to thread a `FocusState` through just to offer dismissal. `FocusState`
/// bound to a field still updates to `false` when the responder resigns, so focus-driven
/// chrome keeps working.
enum PaeoniaKeyboard {
    /// Resigns whatever is currently first responder, putting the keyboard away.
    static func dismiss() {
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder),
            to: nil,
            from: nil,
            for: nil
        )
    }
}

extension View {
    /// Pins a "Done" button above the keyboard that dismisses it. Composes with any
    /// existing `.toolbar` content on the view (SwiftUI merges multiple toolbars).
    func keyboardDoneToolbar() -> some View {
        toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button {
                    PaeoniaKeyboard.dismiss()
                } label: {
                    Text(.commonDone)
                        .fontWeight(.semibold)
                }
                .tint(.paeoniaAccentPrimary)
            }
        }
    }

    /// Dismisses the keyboard when the user taps anywhere on this view that isn't an
    /// interactive control. A convenience for sighted users, not an accessibility
    /// control, so it intentionally carries no button trait — VoiceOver dismisses the
    /// keyboard through its own affordances. Interactive subviews keep their own taps.
    func dismissesKeyboardOnBackgroundTap() -> some View {
        contentShape(Rectangle())
            .onTapGesture {
                PaeoniaKeyboard.dismiss()
            }
    }

    /// The standard Paeonia treatment for a text-entry surface: a "Done" button above
    /// the keyboard plus tap-empty-space-to-dismiss. Apply to the screen or form
    /// container that holds the text fields.
    func keyboardDismissable() -> some View {
        dismissesKeyboardOnBackgroundTap()
            .keyboardDoneToolbar()
    }
}
