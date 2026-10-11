import SwiftUI

/// A row that does something right here instead of opening a screen: the same
/// leading-icon shape as `PaeoniaDisclosureRow`, with no chevron, and a spinner
/// while its work runs. Destructive rows use the error tint for icon and title.
struct SettingsActionRow: View {
    let title: LocalizedStringResource
    let systemImage: String
    var isDestructive = false
    var isBusy = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: PaeoniaSpacing.space12) {
                Image(systemName: systemImage)
                    .font(PaeoniaTypography.bodyEmphasis)
                    .foregroundStyle(tint)
                    .frame(width: PaeoniaSpacing.space24)
                    .accessibilityHidden(true)

                Text(title)
                    .font(PaeoniaTypography.bodyEmphasis)
                    .foregroundStyle(isDestructive ? .paeoniaError : .paeoniaTextPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if isBusy {
                    ProgressView()
                        .tint(.paeoniaTextSecondary)
                        .accessibilityHidden(true)
                }
            }
            .padding(.horizontal, PaeoniaSpacing.space16)
            .padding(.vertical, PaeoniaSpacing.space8)
            .frame(maxWidth: .infinity, minHeight: PaeoniaSpacing.buttonHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isBusy)
    }

    private var tint: Color {
        isDestructive ? .paeoniaError : .paeoniaAccentPrimary
    }
}
