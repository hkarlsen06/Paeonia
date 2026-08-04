import SwiftUI

/// A settings row with a switch: a title and supporting line in their own column,
/// keeping a comfortable gap from the trailing toggle so long copy wraps instead of
/// crowding the control.
struct SettingsToggleRow: View {
    let title: LocalizedStringResource
    let subtitle: LocalizedStringResource
    @Binding var isOn: Bool
    var isEnabled: Bool = true

    var body: some View {
        HStack(alignment: .center, spacing: PaeoniaSpacing.space16) {
            VStack(alignment: .leading, spacing: PaeoniaSpacing.space4) {
                Text(title)
                    .font(PaeoniaTypography.body)
                    .foregroundStyle(.paeoniaTextPrimary)
                Text(subtitle)
                    .font(PaeoniaTypography.caption)
                    .foregroundStyle(.paeoniaTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Toggle("", isOn: $isOn)
                .labelsHidden()
                .tint(.paeoniaAccentPrimary)
                .disabled(!isEnabled)
                .accessibilityLabel(Text(title))
        }
    }
}
