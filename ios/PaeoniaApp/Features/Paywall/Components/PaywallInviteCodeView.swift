import SwiftUI

/// A segmented, MFA-style entry field for redeeming a partner invite code.
/// Lives below the fold on the paywall and is revealed when the user scrolls.
/// Submission happens from the bottom CTA (which swaps to a "join" button while
/// the field is focused), so this view holds no button of its own.
struct PaywallInviteCodeView: View {
    static let codeLength = PairingInviteCode.length

    @Binding var code: String
    var focus: FocusState<Bool>.Binding
    let isSubmitting: Bool
    let onSubmit: () -> Void

    @ScaledMetric(relativeTo: .title2) private var codeCellHeight: CGFloat = 56

    private var isFocused: Bool { focus.wrappedValue }

    var body: some View {
        VStack(alignment: .leading, spacing: PaeoniaSpacing.space16) {
            VStack(alignment: .leading, spacing: PaeoniaSpacing.space4) {
                Text(.paywallInviteTitle)
                    .font(PaeoniaTypography.bodyEmphasis)
                    .foregroundStyle(.paeoniaTextPrimary)

                Text(.paywallInviteSubtitle)
                    .font(PaeoniaTypography.caption)
                    .foregroundStyle(.paeoniaTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            codeField

            submitSection
        }
        .padding(PaeoniaSpacing.space20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.paeoniaSurfaceSecondary)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .frame(maxWidth: 430)
        .frame(maxWidth: .infinity)
    }

    private var codeField: some View {
        ZStack {
            TextField("", text: $code)
                .focused(focus)
                .keyboardType(.asciiCapable)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .textContentType(.oneTimeCode)
                .submitLabel(.join)
                .foregroundStyle(.clear)
                .tint(.clear)
                .accentColor(.clear)
                .frame(height: 1)
                .opacity(0.01)
                .onChange(of: code) { _, newValue in
                    let sanitized = Self.sanitize(newValue)
                    if sanitized != newValue {
                        code = sanitized
                    }
                }
                .onSubmit(handleSubmit)

            HStack(spacing: PaeoniaSpacing.space8) {
                ForEach(0..<Self.codeLength, id: \.self) { index in
                    characterCell(at: index)
                }
            }
            .allowsHitTesting(false)
        }
        .contentShape(Rectangle())
        .onTapGesture { focus.wrappedValue = true }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(.paywallInviteTitle))
        .accessibilityValue(Text(code))
        .accessibilityAddTraits(.isButton)
    }

    private var isComplete: Bool {
        Self.sanitize(code).count == Self.codeLength
    }

    private var submitSection: some View {
        VStack(spacing: PaeoniaSpacing.space8) {
            Button(action: handleSubmit) {
                Group {
                    if isSubmitting {
                        ProgressView()
                            .tint(.paeoniaTextInverse)
                            .accessibilityHidden(true)
                    } else {
                        Text(.paywallInviteAction)
                    }
                }
            }
            .buttonStyle(PaeoniaPrimaryButtonStyle())
            .disabled(!isComplete || isSubmitting)
            .sensoryFeedback(.impact(flexibility: .soft), trigger: isSubmitting)

            Text(.paywallInviteCtaCaption)
                .font(PaeoniaTypography.caption)
                .foregroundStyle(.paeoniaTextTertiary)
                .frame(maxWidth: .infinity, alignment: .center)
        }
    }

    private func characterCell(at index: Int) -> some View {
        let characters = Array(code)
        let character = index < characters.count ? String(characters[index]) : ""
        let isFilled = index < characters.count
        let isCurrent = isFocused && index == characters.count

        return Text(character)
            .font(.system(.title2, design: .rounded).weight(.semibold))
            .foregroundStyle(.paeoniaTextPrimary)
            .frame(maxWidth: .infinity)
            .frame(minHeight: codeCellHeight)
            .background(Color.paeoniaBackgroundElevated)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(borderColor(isCurrent: isCurrent, isFilled: isFilled), lineWidth: isCurrent ? 2 : 1.5)
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

    static func sanitize(_ value: String) -> String {
        let allowed = value.uppercased().filter { $0.isLetter || $0.isNumber }
        return String(allowed.prefix(codeLength))
    }

    private func handleSubmit() {
        let sanitized = Self.sanitize(code)
        if sanitized != code {
            code = sanitized
        }

        if sanitized.count == Self.codeLength {
            onSubmit()
        } else {
            focus.wrappedValue = true
        }
    }
}

private struct PaywallInviteCodeViewPreview: View {
    @FocusState private var focused: Bool
    @State private var code = ""

    var body: some View {
        PaywallInviteCodeView(code: $code, focus: $focused, isSubmitting: false, onSubmit: {})
            .padding()
            .background(.paeoniaSurfacePrimary)
            .preferredColorScheme(.dark)
    }
}

#Preview {
    PaywallInviteCodeViewPreview()
}
