import SwiftUI

/// One data request type: what it does, the latest request's status and date, and
/// the button that sends a new request.
struct PrivacyRequestRow: View {
    let kind: PrivacyRequestKind
    let latestRequest: PrivacyRequest?
    /// True until the first load settles, so "nothing sent yet" is not shown for
    /// requests that have not arrived.
    let isLoading: Bool
    let isSubmitting: Bool
    let onRequest: () -> Void

    private var isActive: Bool {
        latestRequest?.isActive == true
    }

    var body: some View {
        VStack(alignment: .leading, spacing: PaeoniaSpacing.space12) {
            VStack(alignment: .leading, spacing: PaeoniaSpacing.space4) {
                Text(kind.title)
                    .font(PaeoniaTypography.bodyEmphasis)
                    .foregroundStyle(.paeoniaTextPrimary)

                Text(kind.description)
                    .font(PaeoniaTypography.caption)
                    .foregroundStyle(.paeoniaTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            statusArea

            Button(action: onRequest) {
                Text(buttonTitle)
            }
            .buttonStyle(PaeoniaSecondaryButtonStyle())
            .disabled(isLoading || isSubmitting || isActive)
        }
        .padding(PaeoniaSpacing.space16)
    }

    @ViewBuilder
    private var statusArea: some View {
        if isLoading {
            ProgressView()
                .controlSize(.small)
                .accessibilityLabel(Text(.privacySafetyLoading))
        } else if let latestRequest {
            status(latestRequest)
        }
    }

    private func status(_ request: PrivacyRequest) -> some View {
        VStack(alignment: .leading, spacing: PaeoniaSpacing.space4) {
            HStack(alignment: .firstTextBaseline, spacing: PaeoniaSpacing.space8) {
                Label {
                    Text(request.status.title)
                } icon: {
                    Image(systemName: statusIcon(request.status))
                        .accessibilityHidden(true)
                }
                .foregroundStyle(statusColor(request.status))
                .frame(maxWidth: .infinity, alignment: .leading)

                Text(request.requestedAt, format: .dateTime.day().month().year())
                    .foregroundStyle(.paeoniaTextSecondary)
            }
            .font(PaeoniaTypography.caption)
            .fixedSize(horizontal: false, vertical: true)

            if let message = request.visibleStatusMessage?.nilIfBlank {
                Text(verbatim: message)
                    .font(PaeoniaTypography.caption)
                    .foregroundStyle(.paeoniaTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var buttonTitle: LocalizedStringResource {
        if isSubmitting {
            return .privacySafetyRequestSending
        }
        if isActive {
            return .privacySafetyRequestActive
        }
        return kind.actionTitle
    }

    private func statusIcon(_ status: PrivacyRequestStatus) -> String {
        switch status {
        case .submitted, .verifying, .processing:
            "clock"
        case .completed:
            "checkmark.circle"
        case .rejected, .cancelled:
            "xmark.circle"
        }
    }

    private func statusColor(_ status: PrivacyRequestStatus) -> Color {
        switch status {
        case .submitted, .verifying, .processing:
            .paeoniaAccentPrimary
        case .completed:
            .paeoniaSuccess
        case .rejected, .cancelled:
            .paeoniaTextTertiary
        }
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
