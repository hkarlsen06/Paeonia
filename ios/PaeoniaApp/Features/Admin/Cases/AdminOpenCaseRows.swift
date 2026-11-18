import SwiftUI

/// One open report: who reported whom, the reason they chose, what they wrote to Paeonia, and when.
struct AdminOpenReportRow: View {
    let report: AdminOpenReport

    var body: some View {
        VStack(alignment: .leading, spacing: PaeoniaSpacing.space4) {
            Text(.adminCasesReportTitle(name(report.reporterDisplayName), name(report.reportedDisplayName)))
                .font(PaeoniaTypography.bodyEmphasis)
                .foregroundStyle(.paeoniaTextPrimary)

            if let reason = report.reason {
                Text(reason.title)
                    .font(PaeoniaTypography.caption.weight(.semibold))
                    .foregroundStyle(.paeoniaTextSecondary)
            }

            AdminCaseNote(note: report.note)
            AdminCaseDate(date: report.createdAt)
        }
        .padding(.vertical, PaeoniaSpacing.space4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private func name(_ displayName: String?) -> String {
        displayName?.trimmedNonEmpty ?? String(localized: .adminUserNoName)
    }
}

/// One open request to correct something: who asked, what they wrote, and when.
struct AdminCorrectionRequestRow: View {
    let request: AdminCorrectionRequest

    var body: some View {
        VStack(alignment: .leading, spacing: PaeoniaSpacing.space4) {
            AdminUserName(name: request.userDisplayName)
                .font(PaeoniaTypography.bodyEmphasis)
                .foregroundStyle(.paeoniaTextPrimary)

            AdminCaseNote(note: request.requesterNote)
            AdminCaseDate(date: request.requestedAt)
        }
        .padding(.vertical, PaeoniaSpacing.space4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

/// What the person wrote, when they wrote anything.
private struct AdminCaseNote: View {
    let note: String?

    var body: some View {
        if let note = note?.trimmedNonEmpty {
            Text(note)
                .font(PaeoniaTypography.caption)
                .foregroundStyle(.paeoniaTextSecondary)
        }
    }
}

private struct AdminCaseDate: View {
    let date: Date

    var body: some View {
        Text(date, format: .dateTime.day().month().year().hour().minute())
            .font(PaeoniaTypography.caption)
            .foregroundStyle(.paeoniaTextTertiary)
    }
}
