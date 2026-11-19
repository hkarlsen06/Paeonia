import SwiftUI

/// A styled multiline text field matching the daily composer: surface background, a
/// hairline border that brightens on focus, and Dynamic Type-friendly body text.
/// With `characterLimit`, typing stops at the limit, so the text never gets longer
/// than the server accepts.
struct MemoryTextField<Field: Hashable>: View {
    @Binding var text: String
    let placeholder: LocalizedStringResource
    var isFocused: FocusState<Field?>.Binding
    let field: Field
    var lineLimit: ClosedRange<Int>? = 1...4
    var characterLimit: Int?
    /// Return runs this instead of starting a new line (`PaeoniaMultilineTextField`).
    var onReturn: (() -> Void)?

    private var isActive: Bool {
        isFocused.wrappedValue == field
    }

    var body: some View {
        textInput
        .font(PaeoniaTypography.body)
        .foregroundStyle(.paeoniaTextPrimary)
        .focused(isFocused, equals: field)
        .paeoniaTextFieldChrome(isFocused: isActive) { isFocused.wrappedValue = field }
        .animation(PaeoniaMotion.stateChange, value: isActive)
        .onChange(of: text) { _, newText in
            guard let characterLimit, MemoryDataService.isOverLimit(newText, characterLimit) else { return }
            text = MemoryDataService.prefix(newText, fittingCodePoints: characterLimit)
        }
    }

    @ViewBuilder
    private var textInput: some View {
        let input = PaeoniaMultilineTextField(
            text: $text,
            label: placeholder,
            prompt: Text(placeholder).foregroundStyle(.paeoniaTextSecondary),
            onReturn: onReturn
        )
        if let lineLimit { input.lineLimit(lineLimit) } else { input }
    }
}
