import SwiftUI

/// The reason menu on the report form. The whole field-shaped area opens the
/// menu, and VoiceOver reads the label once, followed by the chosen reason.
struct ReportReasonField: View {
    @Binding var selection: PrivacyReportReason?

    private var selectionTitle: LocalizedStringResource {
        selection?.title ?? .reportAndLeaveReasonPlaceholder
    }

    var body: some View {
        VStack(alignment: .leading, spacing: PaeoniaSpacing.space8) {
            Text(.reportAndLeaveReasonLabel)
                .font(PaeoniaTypography.bodyEmphasis)
                .foregroundStyle(.paeoniaTextPrimary)
                .accessibilityHidden(true)

            Menu {
                Picker(selection: $selection) {
                    ForEach(PrivacyReportReason.allCases, id: \.self) { reason in
                        Text(reason.title)
                            .tag(Optional(reason))
                    }
                } label: {
                    Text(.reportAndLeaveReasonLabel)
                }
                .pickerStyle(.inline)
            } label: {
                menuLabel
            }
            .tint(.paeoniaAccentPrimary)
            .accessibilityLabel(Text(.reportAndLeaveReasonLabel))
            .accessibilityValue(Text(selectionTitle))

            if selection?.suggestsEmergencyHelp == true {
                Text(.reportAndLeaveEmergencyHint)
                    .font(PaeoniaTypography.caption)
                    .foregroundStyle(.paeoniaTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var menuLabel: some View {
        HStack(spacing: PaeoniaSpacing.space8) {
            Text(selectionTitle)
                .font(PaeoniaTypography.body)
                .foregroundStyle(selection == nil ? .paeoniaTextTertiary : .paeoniaTextPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)

            Image(systemName: "chevron.up.chevron.down")
                .font(PaeoniaTypography.caption)
                .foregroundStyle(.paeoniaTextTertiary)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, PaeoniaSpacing.space16)
        .frame(maxWidth: .infinity, minHeight: PaeoniaSpacing.buttonHeight, alignment: .leading)
        .background(.paeoniaSurfaceSecondary)
        .overlay {
            RoundedRectangle(cornerRadius: PaeoniaRadius.radius16, style: .continuous)
                .stroke(.paeoniaSurfacePressed, lineWidth: PaeoniaRadius.strokeDefault)
        }
        .clipShape(RoundedRectangle(cornerRadius: PaeoniaRadius.radius16, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: PaeoniaRadius.radius16, style: .continuous))
    }
}
