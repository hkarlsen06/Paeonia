import SwiftUI

/// Where the admin writes why a user is banned. Continue opens a confirmation that
/// says what the ban does, and the ban only goes through from there.
struct AdminBanReasonSheet: View {
    let userName: String
    let isWorking: Bool
    /// Returns true when the ban went through, which closes the sheet.
    let onBan: (String) async -> Bool

    @Environment(\.dismiss) private var dismiss
    @Environment(PaeoniaBannerCenter.self) private var bannerCenter
    @State private var reason = ""
    @State private var isConfirming = false

    var body: some View {
        NavigationStack {
            ScrollView {
                form
            }
            .scrollBounceBehavior(.basedOnSize)
            .scrollDismissesKeyboard(.interactively)
            .paeoniaScreenBackground()
            .paeoniaBottomBar {
                continueButton
            }
            .navigationTitle(Text(.adminBanTitle))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    cancelButton
                }
            }
            .alert(Text(.adminBanConfirmTitle(userName)), isPresented: $isConfirming) {
                Button(role: .destructive) {
                    ban()
                } label: {
                    Text(.adminBanConfirmAction)
                }

                Button(role: .cancel, action: {}) {
                    Text(.commonCancel)
                }
            } message: {
                Text(.adminBanConfirmMessage(userName, userName))
            }
        }
        // The sheet covers the app's banner, so it mounts the shared one itself.
        .paeoniaTopBanner(bannerCenter)
        .presentationDetents([.large])
        .presentationBackground(.paeoniaBackgroundPrimary)
        .interactiveDismissDisabled(isWorking)
    }

    private var form: some View {
        VStack(alignment: .leading, spacing: PaeoniaSpacing.sectionSpacing) {
            Text(.adminBanIntro(userName))
                .font(PaeoniaTypography.body)
                .foregroundStyle(.paeoniaTextSecondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: PaeoniaSpacing.space8) {
                Text(.adminBanReasonLabel)
                    .font(PaeoniaTypography.bodyEmphasis)
                    .foregroundStyle(.paeoniaTextPrimary)
                    .accessibilityHidden(true)

                PrivacySafetyMultilineField(
                    text: $reason,
                    label: .adminBanReasonLabel,
                    placeholder: .adminBanReasonPlaceholder,
                    lineLimit: 4...9,
                    characterLimit: AdminUserDetailViewModel.reasonLengthLimit
                )
            }
        }
        .padding(.horizontal, PaeoniaSpacing.screenHorizontalPadding)
        .padding(.top, PaeoniaSpacing.screenTopSpacing)
        .padding(.bottom, PaeoniaSpacing.space24)
    }

    private var cancelButton: some View {
        Button {
            dismiss()
        } label: {
            Text(.commonCancel)
        }
        .disabled(isWorking)
    }

    private var continueButton: some View {
        Button {
            isConfirming = true
        } label: {
            Text(.adminBanContinue)
        }
        .buttonStyle(PaeoniaPrimaryButtonStyle())
        .disabled(!AdminUserDetailViewModel.isValidReason(reason) || isWorking)
        .padding(.horizontal, PaeoniaSpacing.screenHorizontalPadding)
        .padding(.vertical, PaeoniaSpacing.space12)
        .background(.paeoniaBackgroundPrimary)
    }

    private func ban() {
        let reason = reason
        Task {
            if await onBan(reason) {
                dismiss()
            }
        }
    }
}
