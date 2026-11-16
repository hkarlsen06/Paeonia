import SwiftUI

/// A sheet for typing or pasting a partner's invite code. The welcome screen and the
/// invite screen both use it. It only collects the code. The caller decides what to do
/// with it in `onSubmit`, which gets a normalized 6-character code and returns `true`
/// when the sheet should close. On `false` the sheet stays open with the keyboard up,
/// so the user can fix the code. The caller reports why through the banner.
struct PairingCodeEntrySheet: View {
    let title: LocalizedStringResource
    let message: LocalizedStringResource
    let submitTitle: LocalizedStringResource
    let onSubmit: (String) async -> Bool

    @Environment(\.dismiss) private var dismiss
    @Environment(PaeoniaBannerCenter.self) private var bannerCenter
    @State private var code = ""
    @State private var isSubmitting = false
    @FocusState private var fieldFocused: Bool

    private var isComplete: Bool {
        code.count == PairingInviteCode.length
    }

    var body: some View {
        ScrollView {
            VStack(spacing: PaeoniaSpacing.space24) {
                VStack(spacing: PaeoniaSpacing.space8) {
                    Text(title)
                        .font(PaeoniaTypography.title)
                        .foregroundStyle(.paeoniaTextPrimary)
                        .multilineTextAlignment(.center)
                        .accessibilityAddTraits(.isHeader)

                    Text(message)
                        .font(PaeoniaTypography.body)
                        .foregroundStyle(.paeoniaTextSecondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }

                codeField

                pasteButton

                submitButton
            }
            .padding(.horizontal, PaeoniaSpacing.screenHorizontalPadding)
            .padding(.top, PaeoniaSpacing.space32)
            .padding(.bottom, PaeoniaSpacing.space16)
            .frame(maxWidth: .infinity)
        }
        .scrollBounceBehavior(.basedOnSize)
        .paeoniaScreenBackground()
        // The sheet covers the root's banner, so it mounts its own copy of the same
        // banner to show errors above itself.
        .paeoniaBanner(bannerCenter)
        .preferredColorScheme(.dark)
        .presentationDetents([.medium, .large])
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
                .submitLabel(.go)
                .foregroundStyle(.clear)
                .tint(.clear)
                .frame(height: 1)
                .opacity(0.01)
                .onChange(of: code) { _, newValue in
                    let cleaned = PairingInviteCode.entryText(newValue)
                    if cleaned != newValue {
                        code = cleaned
                    }
                }
                .onSubmit(submit)

            PairingCodeCellLayout { index in
                PairingCodeCell(code: code, index: index, isFocused: fieldFocused)
            }
            .allowsHitTesting(false)
        }
        .contentShape(Rectangle())
        .onTapGesture { fieldFocused = true }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(.pairingInviteCodeLabel))
        .accessibilityValue(Text(code).speechSpellsOutCharacters())
        .accessibilityHint(Text(.pairingCodeEntryFieldHint))
        .accessibilityAddTraits(.isButton)
    }

    private var pasteButton: some View {
        PasteButton(payloadType: String.self) { strings in
            code = PairingInviteCode.entryText(strings.joined(separator: " "))
        }
        .labelStyle(.titleAndIcon)
        .buttonBorderShape(.capsule)
        .tint(.paeoniaAccentSecondary)
    }

    private var submitButton: some View {
        Button(action: submit) {
            Text(submitTitle)
        }
        .buttonStyle(PaeoniaPrimaryButtonStyle(isLoading: isSubmitting))
        .disabled(!isComplete)
    }

    private func submit() {
        guard !isSubmitting else {
            return
        }

        let entry = PairingInviteCode.entryText(code)
        guard entry.count == PairingInviteCode.length else {
            fieldFocused = true
            return
        }

        isSubmitting = true
        Task {
            let shouldDismiss = await onSubmit(entry)
            isSubmitting = false
            if shouldDismiss {
                dismiss()
            } else {
                fieldFocused = true
            }
        }
    }
}

/// One character of a typed code. The cell where the next character goes is outlined
/// while the field has focus. The email sign-in sheet uses it for its code too.
struct PairingCodeCell: View {
    let code: String
    let index: Int
    let isFocused: Bool

    @ScaledMetric(relativeTo: .title2) private var height: CGFloat = 56

    var body: some View {
        let characters = Array(code)
        let isFilled = index < characters.count
        let isCurrent = isFocused && index == characters.count

        Text(isFilled ? String(characters[index]) : "")
            .font(.system(.title2, design: .rounded).weight(.semibold))
            .foregroundStyle(.paeoniaTextPrimary)
            .frame(maxWidth: .infinity)
            .frame(minHeight: height)
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
}

/// Lays out the six code cells in one row, or in two rows of three at accessibility
/// text sizes so the characters can grow without squeezing or clipping.
struct PairingCodeCellLayout<Cell: View>: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @ViewBuilder let cell: (Int) -> Cell

    private var cellsPerRow: Int {
        dynamicTypeSize.isAccessibilitySize ? PairingInviteCode.length / 2 : PairingInviteCode.length
    }

    var body: some View {
        VStack(spacing: PaeoniaSpacing.space8) {
            ForEach(0..<PairingInviteCode.length / cellsPerRow, id: \.self) { row in
                HStack(spacing: PaeoniaSpacing.space8) {
                    ForEach(0..<cellsPerRow, id: \.self) { column in
                        cell(row * cellsPerRow + column)
                    }
                }
            }
        }
    }
}

#if DEBUG
#Preview {
    Color.paeoniaBackgroundPrimary
        .sheet(isPresented: .constant(true)) {
            PairingCodeEntrySheet(
                title: .welcomeInviteCodeTitle,
                message: .welcomeInviteCodeSubtitle,
                submitTitle: .welcomeInviteCodeContinue,
                onSubmit: { _ in true }
            )
            .environment(PaeoniaBannerCenter())
        }
        .preferredColorScheme(.dark)
}
#endif
