import SwiftUI

/// Sign-in with a code sent by email. The person types their address, then the
/// 6-digit code from the email. A new address gets an account the same way. The
/// banner sits under the sheet, so what went wrong shows under the field.
struct EmailSignInSheet: View {
    /// Returns nil once the code is on its way.
    let onSendCode: (String) async -> EmailSignInError?
    /// Returns nil once signed in. The root then moves on to the next screen.
    let onVerifyCode: (String) async -> EmailSignInError?

    private enum Step: Equatable {
        case email
        case code(sentTo: String)
    }

    /// What the line under the field says.
    private enum Status: Equatable {
        case idle
        case working
        case failed(EmailSignInError)
        case sentNewCode
    }

    private enum Field {
        case email
        case code
    }

    @Environment(\.dismiss) private var dismiss
    @State private var step = Step.email
    @State private var status = Status.idle
    @State private var email = ""
    @State private var code = ""
    @FocusState private var focusedField: Field?

    private static let codeLength = 6

    private var isWorking: Bool {
        status == .working
    }

    private var typedEmail: String {
        email.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: PaeoniaSpacing.space24) {
                switch step {
                case .email:
                    emailStep
                case let .code(sentTo):
                    codeStep(sentTo: sentTo)
                }
            }
            .padding(.horizontal, PaeoniaSpacing.screenHorizontalPadding)
            .padding(.top, PaeoniaSpacing.space32)
            .padding(.bottom, PaeoniaSpacing.space16)
            .frame(maxWidth: .infinity)
        }
        .scrollBounceBehavior(.basedOnSize)
        .paeoniaScreenBackground()
        .preferredColorScheme(.dark)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        // VoiceOver does not read new text under the field on its own.
        .onChange(of: status) { _, newStatus in
            switch newStatus {
            case let .failed(error):
                AccessibilityNotification.Announcement(String(localized: error.message)).post()
            case .sentNewCode:
                AccessibilityNotification.Announcement(String(localized: .authEmailResent)).post()
            case .idle, .working:
                break
            }
        }
    }

    // MARK: Email

    @ViewBuilder
    private var emailStep: some View {
        header(title: .authEmailTitle, message: Text(.authEmailMessage))

        VStack(spacing: PaeoniaSpacing.space8) {
            TextField(text: $email, prompt: Text(.authEmailFieldLabel)) {
                Text(.authEmailFieldLabel)
            }
            .focused($focusedField, equals: .email)
            .textContentType(.emailAddress)
            .keyboardType(.emailAddress)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .submitLabel(.send)
            .onSubmit(sendCode)
            .padding(.horizontal, PaeoniaSpacing.space12)
            .padding(.vertical, PaeoniaSpacing.space12)
            .background(.paeoniaSurfaceSecondary)
            .clipShape(RoundedRectangle(cornerRadius: PaeoniaRadius.radius12))
            .accessibilityIdentifier("auth.email.field")
            .onAppear { focusedField = .email }
            .onChange(of: email) {
                if case .failed = status {
                    status = .idle
                }
            }

            statusLine
        }

        Button(action: sendCode) {
            Text(.authEmailSend)
        }
        .buttonStyle(PaeoniaPrimaryButtonStyle(isLoading: isWorking))
        .disabled(!typedEmail.contains("@"))
        .accessibilityIdentifier("auth.email.send")
    }

    private func sendCode() {
        let address = typedEmail
        guard !isWorking, address.contains("@") else {
            return
        }

        status = .working
        Task {
            if let error = await onSendCode(address) {
                status = .failed(error)
                focusedField = .email
            } else {
                status = .idle
                code = ""
                step = .code(sentTo: address)
            }
        }
    }

    // MARK: Code

    @ViewBuilder
    private func codeStep(sentTo address: String) -> some View {
        // Verbatim, because Text's Markdown parsing turns the address into a mail link.
        header(title: .authEmailCodeTitle, message: Text(verbatim: String(localized: .authEmailCodeMessage(address))))

        VStack(spacing: PaeoniaSpacing.space8) {
            codeField
            statusLine
        }

        VStack(spacing: 0) {
            Button {
                resendCode(to: address)
            } label: {
                Text(.authEmailResend)
            }
            .buttonStyle(PaeoniaQuietButtonStyle())
            .accessibilityIdentifier("auth.email.resend")

            Button(action: changeEmail) {
                Text(.authEmailChange)
            }
            .buttonStyle(PaeoniaQuietButtonStyle())
            .accessibilityIdentifier("auth.email.change")
        }
        .disabled(isWorking)
    }

    /// An invisible field under the code cells, like the invite code sheet.
    private var codeField: some View {
        ZStack {
            TextField("", text: $code)
                .focused($focusedField, equals: .code)
                .keyboardType(.numberPad)
                .textContentType(.oneTimeCode)
                .foregroundStyle(.clear)
                .tint(.clear)
                .frame(height: 1)
                .opacity(0.01)
                .onChange(of: code) { _, newValue in
                    let digits = String(newValue.filter { $0.isASCII && $0.isNumber }.prefix(Self.codeLength))
                    if digits != newValue {
                        code = digits
                        return
                    }
                    guard !digits.isEmpty else { return }
                    if status != .working {
                        status = .idle
                    }
                    if digits.count == Self.codeLength {
                        verifyCode(digits)
                    }
                }

            PairingCodeCellLayout { index in
                PairingCodeCell(code: code, index: index, isFocused: focusedField == .code)
            }
            .allowsHitTesting(false)
        }
        .contentShape(Rectangle())
        .onTapGesture { focusedField = .code }
        .onAppear { focusedField = .code }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(.authEmailCodeLabel))
        .accessibilityValue(Text(code).speechSpellsOutCharacters())
        .accessibilityHint(Text(.authEmailCodeHint))
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("auth.email.codeField")
    }

    private func verifyCode(_ code: String) {
        guard !isWorking else {
            return
        }

        status = .working
        Task {
            guard let error = await onVerifyCode(code) else {
                dismiss()
                return
            }
            status = .failed(error)
            self.code = ""
            focusedField = .code
        }
    }

    private func resendCode(to address: String) {
        guard !isWorking else {
            return
        }

        status = .working
        code = ""
        Task {
            if let error = await onSendCode(address) {
                status = .failed(error)
            } else {
                status = .sentNewCode
            }
            focusedField = .code
        }
    }

    private func changeEmail() {
        status = .idle
        code = ""
        step = .email
    }

    // MARK: Shared

    private func header(title: LocalizedStringResource, message: Text) -> some View {
        VStack(spacing: PaeoniaSpacing.space8) {
            Text(title)
                .font(PaeoniaTypography.title)
                .foregroundStyle(.paeoniaTextPrimary)
                .multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)

            message
                .font(PaeoniaTypography.body)
                .foregroundStyle(.paeoniaTextSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// The error or the new-code confirmation, or a spinner while a code is checked.
    @ViewBuilder
    private var statusLine: some View {
        switch status {
        case .idle:
            EmptyView()
        case .working:
            if case .code = step {
                ProgressView()
                    .tint(.paeoniaTextSecondary)
            }
        case let .failed(error):
            statusText(error.message, color: .paeoniaErrorText)
        case .sentNewCode:
            statusText(.authEmailResent, color: .paeoniaTextSecondary)
        }
    }

    private func statusText(_ text: LocalizedStringResource, color: Color) -> some View {
        Text(text)
            .font(PaeoniaTypography.caption)
            .foregroundStyle(color)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity)
    }
}

extension EmailSignInError {
    var message: LocalizedStringResource {
        switch self {
        case .invalidEmail: .authEmailErrorInvalidEmail
        case .wrongCode: .authEmailErrorWrongCode
        case .codeExpired: .authEmailErrorCodeExpired
        case .tooManyTries: .authEmailErrorTooManyTries
        case .failed(.offline): .authNoticeSignInFailedMessage
        case .failed(.other): .commonActionFailedMessage
        }
    }
}

#if DEBUG
#Preview {
    Color.paeoniaBackgroundPrimary
        .sheet(isPresented: .constant(true)) {
            EmailSignInSheet(
                onSendCode: { _ in nil },
                onVerifyCode: { _ in .wrongCode }
            )
        }
        .preferredColorScheme(.dark)
}
#endif
