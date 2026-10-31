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

    private var isActive: Bool {
        isFocused.wrappedValue == field
    }

    var body: some View {
        textInput
        .font(PaeoniaTypography.body)
        .foregroundStyle(.paeoniaTextPrimary)
        .focused(isFocused, equals: field)
        .paeoniaTextFieldChrome(isFocused: isActive)
        .animation(PaeoniaMotion.stateChange, value: isActive)
        .onChange(of: text) { _, newText in
            guard let characterLimit, MemoryDataService.isOverLimit(newText, characterLimit) else { return }
            text = MemoryDataService.prefix(newText, fittingCodePoints: characterLimit)
        }
    }

    @ViewBuilder
    private var textInput: some View {
        let input = TextField(
            text: $text,
            prompt: Text(placeholder).foregroundStyle(.paeoniaTextSecondary),
            axis: .vertical
        ) {
            Text(placeholder)
        }
        if let lineLimit { input.lineLimit(lineLimit) } else { input }
    }
}
