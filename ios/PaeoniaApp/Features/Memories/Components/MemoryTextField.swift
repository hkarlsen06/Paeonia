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
    /// `.horizontal` keeps the field to one line, so Return submits instead of adding a line.
    var axis: Axis = .vertical
    var lineLimit: ClosedRange<Int> = 1...4
    var characterLimit: Int?

    private var isActive: Bool {
        isFocused.wrappedValue == field
    }

    var body: some View {
        TextField(
            text: $text,
            prompt: Text(placeholder),
            axis: axis
        ) {
            Text(placeholder)
        }
        .lineLimit(lineLimit)
        .font(PaeoniaTypography.body)
        .foregroundStyle(.paeoniaTextPrimary)
        .padding(PaeoniaSpacing.space12)
        .focused(isFocused, equals: field)
        .background(.paeoniaBackgroundSecondary)
        .clipShape(RoundedRectangle(cornerRadius: PaeoniaRadius.radius12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: PaeoniaRadius.radius12, style: .continuous)
                .stroke(
                    isActive ? Color.paeoniaAccentPrimary : Color.paeoniaSurfacePressed,
                    lineWidth: isActive ? PaeoniaRadius.strokeEmphasis : PaeoniaRadius.strokeDefault
                )
        }
        .animation(PaeoniaMotion.stateChange, value: isActive)
        .onChange(of: text) { _, newText in
            guard let characterLimit, MemoryDataService.isOverLimit(newText, characterLimit) else { return }
            text = MemoryDataService.prefix(newText, fittingCodePoints: characterLimit)
        }
    }
}
