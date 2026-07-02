import SwiftUI

/// A pre-auth sheet for a partner who already has an invite code. It only captures
/// the code; redeeming it still needs an account, so on submit the code is stashed
/// and the caller moves the user to sign-in — after which the paywall picks the code
/// up so they join their partner instead of paying.
struct WelcomeInviteCodeSheet: View {
    /// Called with a full-length, sanitized code. The caller stores it and proceeds
    /// to sign-in; this sheet dismisses itself.
    let onSubmit: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var code = ""
    @FocusState private var fieldFocused: Bool

    @ScaledMetric(relativeTo: .title2) private var codeCellHeight: CGFloat = 56

    private var isComplete: Bool {
        code.count == PairingInviteCode.length
    }

    var body: some View {
        VStack(spacing: PaeoniaSpacing.space24) {
            VStack(spacing: PaeoniaSpacing.space8) {
                Text(.welcomeInviteCodeTitle)
                    .font(PaeoniaTypography.title)
                    .foregroundStyle(.paeoniaTextPrimary)
                    .multilineTextAlignment(.center)

                Text(.welcomeInviteCodeSubtitle)
                    .font(PaeoniaTypography.body)
                    .foregroundStyle(.paeoniaTextSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            codeField

            Button(action: submit) {
                Text(.welcomeInviteCodeContinue)
            }
            .buttonStyle(PaeoniaPrimaryButtonStyle())
            .disabled(!isComplete)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, PaeoniaSpacing.screenHorizontalPadding)
        .padding(.top, PaeoniaSpacing.space32)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(.paeoniaBackgroundPrimary)
        .preferredColorScheme(.dark)
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
        .onAppear { fieldFocused = true }
    }

    private var codeField: some View {
        ZStack {
            TextField("", text: $code)
                .focused($fieldFocused)
                .keyboardType(.asciiCapable)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .textContentType(.oneTimeCode)
                .submitLabel(.join)
                .foregroundStyle(.clear)
                .tint(.clear)
                .frame(height: 1)
                .opacity(0.01)
                .onChange(of: code) { _, newValue in
                    let sanitized = Self.sanitize(newValue)
                    if sanitized != newValue {
                        code = sanitized
                    }
                }
                .onSubmit(submit)

            HStack(spacing: PaeoniaSpacing.space8) {
                ForEach(0..<PairingInviteCode.length, id: \.self) { index in
                    characterCell(at: index)
                }
            }
            .allowsHitTesting(false)
        }
        .contentShape(Rectangle())
        .onTapGesture { fieldFocused = true }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(.welcomeInviteCodeTitle))
        .accessibilityValue(Text(code))
        .accessibilityAddTraits(.isButton)
    }

    private func characterCell(at index: Int) -> some View {
        let characters = Array(code)
        let character = index < characters.count ? String(characters[index]) : ""
        let isFilled = index < characters.count
        let isCurrent = fieldFocused && index == characters.count

        return Text(character)
            .font(.system(.title2, design: .rounded).weight(.semibold))
            .foregroundStyle(.paeoniaTextPrimary)
            .frame(maxWidth: .infinity)
            .frame(minHeight: codeCellHeight)
            .background(Color.paeoniaBackgroundElevated)
            .clipShape(RoundedRectangle(cornerRadius: PaeoniaRadius.radius12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: PaeoniaRadius.radius12, style: .continuous)
                    .strokeBorder(
                        borderColor(isCurrent: isCurrent, isFilled: isFilled),
                        lineWidth: isCurrent ? PaeoniaRadius.strokeEmphasis : PaeoniaRadius.strokeDefault
                    )
            }
    }

    private func borderColor(isCurrent: Bool, isFilled: Bool) -> Color {
        if isCurrent {
            return .paeoniaAccentPrimary
        }
        if isFilled {
            return Color.paeoniaAccentPrimary.opacity(0.4)
        }
        return Color.paeoniaTextTertiary.opacity(0.25)
    }

    private func submit() {
        let sanitized = Self.sanitize(code)
        guard sanitized.count == PairingInviteCode.length else {
            fieldFocused = true
            return
        }

        onSubmit(sanitized)
        dismiss()
    }

    static func sanitize(_ value: String) -> String {
        let allowed = value.uppercased().filter { $0.isLetter || $0.isNumber }
        return String(allowed.prefix(PairingInviteCode.length))
    }
}

#if DEBUG
#Preview {
    Color.paeoniaBackgroundPrimary
        .sheet(isPresented: .constant(true)) {
            WelcomeInviteCodeSheet(onSubmit: { _ in })
        }
        .preferredColorScheme(.dark)
}
#endif
