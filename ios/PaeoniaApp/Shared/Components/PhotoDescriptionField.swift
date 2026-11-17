import SwiftUI

struct PhotoDescriptionField: View {
    @Binding var text: String
    var alwaysVisible = false
    @AccessibilityPresentation(.media) private var showsMedia

    var body: some View {
        if alwaysVisible || showsMedia || text.unicodeScalars.count > 10_000 {
            PaeoniaMultilineTextField(text: $text, label: .mediaAccessibilityPhotoDescription)
            .lineLimit(2...5)
            .font(PaeoniaTypography.body)
            .accessibilityHint(Text(.mediaAccessibilityPhotoHelp))
        }
        if text.unicodeScalars.count > 10_000 {
            Text(.mediaAccessibilityTooLong)
                .foregroundStyle(.paeoniaErrorText)
        }
    }
}

nonisolated enum PhotoDescription {
    static func label(_ text: String?) -> String {
        text?.trimmedNonEmpty ?? String(localized: .mediaAccessibilityPhotoMissing)
    }
}
