import SwiftUI

/// Sits above the composer while the person changes a message they sent, like
/// Tidex's edit banner. The cross stops editing.
struct ThreadChatEditBanner: View {
    let onCancel: () -> Void

    var body: some View {
        HStack(spacing: PaeoniaSpacing.space8) {
            Image(systemName: "pencil")
                .font(PaeoniaTypography.caption.weight(.semibold))
                .foregroundStyle(.paeoniaAccentPrimary)
                .accessibilityHidden(true)
            Text(.dailyChatComposerEditing)
                .font(PaeoniaTypography.caption.weight(.semibold))
                .foregroundStyle(.paeoniaTextPrimary)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, PaeoniaSpacing.space12)
        .padding(.vertical, PaeoniaSpacing.space8)
        .padding(.trailing, PaeoniaSpacing.space32)
        .frame(minHeight: 44)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(alignment: .trailing) {
            Button(action: onCancel) {
                Image(systemName: "xmark")
                    .font(PaeoniaTypography.caption.weight(.semibold))
                    .foregroundStyle(.paeoniaTextSecondary)
                    .frame(width: 28, height: 28)
                    .background(Color.paeoniaTextPrimary.opacity(0.08), in: Circle())
                    // The circle stays small. The tap area is at least 44pt.
                    .contentShape(Rectangle().inset(by: -8))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(.dailyChatComposerCancelEdit))
            .padding(.trailing, PaeoniaSpacing.space8)
        }
    }
}
