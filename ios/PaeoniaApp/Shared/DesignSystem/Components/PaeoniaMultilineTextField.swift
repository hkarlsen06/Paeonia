import SwiftUI

/// A text field that grows to more lines as the person types. Every multiline field in
/// the app is one of these.
///
/// On iOS 27.3 a `TextField` with `axis: .vertical` leaves its label out of accessibility,
/// so VoiceOver and Voice Control call the field "Horizontal scroll bar, 1 page" after its
/// text view's scroll indicator. This field sets the label for accessibility as well.
/// The label names what the field is for. It never repeats what the person typed.
struct PaeoniaMultilineTextField: View {
    @Binding var text: String
    let label: LocalizedStringResource
    var prompt: Text?

    var body: some View {
        TextField(text: $text, prompt: prompt, axis: .vertical) {
            Text(label)
        }
        .accessibilityLabel(Text(label))
    }
}
