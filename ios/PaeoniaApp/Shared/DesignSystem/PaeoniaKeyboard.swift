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
    /// Shows a "Done" button above the keyboard that dismisses it.
    ///
    /// iOS 26 draws a `.keyboard` toolbar item as a glass capsule sitting right on
    /// the keyboard, and padding only grows the capsule (FB22938104). So the shared
    /// capsule is hidden and the button draws its own glass with a gap below it.
    /// It stays a keyboard toolbar item, so it moves with the keyboard frame by
    /// frame. A bar driven by keyboard notifications runs on its own timing and
    /// jumps ahead of the keyboard.
    func keyboardDoneToolbar() -> some View {
        modifier(KeyboardDoneButtonModifier())
    }

    /// Dismisses the keyboard when the user taps anywhere on this view that isn't an
    /// interactive control. A convenience for sighted users, not an accessibility
    /// control, so it intentionally carries no button trait — VoiceOver dismisses the
    /// keyboard through its own affordances. Interactive subviews keep their own taps,
    /// except button rows in a `Form` or `List`: the gesture swallows those, so don't
    /// put it on one. Use `keyboardDoneToolbar` and `scrollDismissesKeyboard` there.
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

extension View {
    /// Pins a bar of buttons to the bottom of the screen. It stays there when the
    /// keyboard opens: the keyboard covers it instead of pushing it up, and it comes
    /// back when the keyboard closes. The content above still makes room for the
    /// keyboard, so a focused field stays visible.
    ///
    /// Only for action bars. An input that belongs above the keyboard, like a chat
    /// composer, should use `safeAreaInset` directly.
    func paeoniaBottomBar<Bar: View>(
        spacing: CGFloat? = nil,
        @ViewBuilder bar: () -> Bar
    ) -> some View {
        modifier(PaeoniaBottomBarModifier(spacing: spacing, bar: bar()))
    }
}

private struct PaeoniaBottomBarModifier<Bar: View>: ViewModifier {
    let spacing: CGFloat?
    let bar: Bar

    @State private var isKeyboardDocked = false

    func body(content: Content) -> some View {
        content
            .safeAreaInset(edge: .bottom, spacing: spacing) {
                if !isKeyboardDocked {
                    bar
                }
            }
            .onDockedKeyboardChange { isKeyboardDocked = $0 }
    }
}

private struct KeyboardDoneButtonModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button {
                        PaeoniaKeyboard.dismiss()
                    } label: {
                        Text(.commonDone)
                            .fontWeight(.semibold)
                    }
                    .buttonStyle(.glass)
                    .controlSize(.large)
                    .tint(.paeoniaAccentPrimary)
                    .padding(.bottom, PaeoniaSpacing.space8)
                }
                .sharedBackgroundVisibility(.hidden)
            }
    }
}

extension View {
    /// Reports whether a full keyboard is docked at the bottom of the screen. An
    /// iPad's floating keyboard, or the short shortcut bar shown with a hardware
    /// keyboard, counts as not docked. It fires as the keyboard starts to move, in the
    /// same pass that makes room for it, so layout changed here moves with the keyboard.
    func onDockedKeyboardChange(_ action: @escaping (Bool) -> Void) -> some View {
        onReceive(
            NotificationCenter.default.publisher(for: UIResponder.keyboardWillChangeFrameNotification)
        ) { notification in
            action(isDockedKeyboard(notification))
        }
        .onReceive(
            NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)
        ) { _ in
            action(false)
        }
    }
}

private func isDockedKeyboard(_ notification: Notification) -> Bool {
    guard
        let frame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect,
        let screen = notification.object as? UIScreen
    else {
        return false
    }
    // ponytail: fixed height cutoff between the shortcut bar (about 55 points)
    // and the smallest docked keyboard (over 200); revisit if iOS changes either.
    return frame.maxY >= screen.bounds.maxY - 1 && frame.height > 120
}
