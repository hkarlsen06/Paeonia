import SwiftUI

/// One admin action: what happened to whom, who did it, why, and when.
struct AdminAuditRow: View {
    let entry: AdminAuditEntry

    var body: some View {
        VStack(alignment: .leading, spacing: PaeoniaSpacing.space4) {
            title
                .font(PaeoniaTypography.bodyEmphasis)
                .foregroundStyle(.paeoniaTextPrimary)

            if let reason = entry.reason?.trimmedNonEmpty {
                Text(.adminAuditReason(reason))
                    .font(PaeoniaTypography.caption)
                    .foregroundStyle(.paeoniaTextSecondary)
                    .textSelection(.enabled)
            }

            HStack(spacing: PaeoniaSpacing.space4) {
                byline
                Text(verbatim: "·")
                    .accessibilityHidden(true)
                Text(entry.createdAt, format: .dateTime.day().month().year().hour().minute())
            }
            .font(PaeoniaTypography.caption)
            .foregroundStyle(.paeoniaTextTertiary)
        }
        .padding(.vertical, PaeoniaSpacing.space4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private var targetName: String {
        entry.targetDisplayName?.trimmedNonEmpty ?? String(localized: .adminUserNoName)
    }

    @ViewBuilder
    private var title: some View {
        switch entry.action {
        case .userBanned: Text(.adminAuditBanned(targetName))
        case .userUnbanned: Text(.adminAuditUnbanned(targetName))
        case .other: Text(.adminAuditOther(targetName))
        }
    }

    @ViewBuilder
    private var byline: some View {
        if let name = entry.adminDisplayName?.trimmedNonEmpty {
            Text(.adminAuditByAdmin(name))
        } else if let operatorName = entry.operatorIdentifier?.trimmedNonEmpty {
            Text(.adminAuditByOperator(operatorName))
        } else {
            Text(.adminAuditByUnknown)
        }
    }
}
