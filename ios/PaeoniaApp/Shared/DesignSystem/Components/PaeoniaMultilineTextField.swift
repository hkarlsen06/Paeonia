import SwiftUI

/// A text field that grows to more lines as the person types. Every multiline field in
/// the app is one of these.
///
/// On iOS 27.3 a `TextField` with `axis: .vertical` leaves its label out of accessibility,
/// so VoiceOver and Voice Control call the field "Horizontal scroll bar, 1 page" after its
/// text view's scroll indicator. This field sets the label for accessibility as well.
/// The label names what the field is for. It never repeats what the person typed.
///
/// A vertical `TextField` takes Return as a new line and never calls `onSubmit`, whatever
/// its `submitLabel` says. A field with `onReturn` keeps to one paragraph: a typed or
/// pasted line break is removed and `onReturn` runs instead.
struct PaeoniaMultilineTextField: View {
    @Binding var text: String
    let label: LocalizedStringResource
    var prompt: Text?
    var onReturn: (() -> Void)?

    var body: some View {
        TextField(text: $text, prompt: prompt, axis: .vertical) {
            Text(label)
        }
        .accessibilityLabel(Text(label))
        .onChange(of: text) { _, newText in
            guard let onReturn, newText.contains(where: \.isNewline) else { return }
            text = newText.filter { !$0.isNewline }
            onReturn()
        }
    }
}
