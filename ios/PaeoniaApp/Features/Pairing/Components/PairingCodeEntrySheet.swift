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
        // The content sits in the middle of the space above the keyboard.
        GeometryReader { proxy in
            ScrollViewReader { scroller in
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
                    .frame(maxWidth: .infinity, minHeight: proxy.size.height)
                }
                .scrollBounceBehavior(.basedOnSize)
                .keepsCodeCellsInView(scroller, visibleHeight: proxy.size.height, code: code)
            }
        }
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
        PairingCodeCellLayout { index in
            PairingCodeCell(code: code, index: index, isFocused: fieldFocused)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .id(PairingCodeCellLayoutID.cells)
        .background {
            TextField("", text: $code)
                .focused($fieldFocused)
                .keyboardType(.asciiCapable)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .textContentType(.oneTimeCode)
                .submitLabel(.go)
                .foregroundStyle(.clear)
                .tint(.clear)
                .opacity(0.01)
                .allowsHitTesting(false)
                .onChange(of: code) { _, newValue in
                    let cleaned = PairingInviteCode.entryText(newValue)
                    if cleaned != newValue {
                        code = cleaned
                    }
                }
                .onSubmit(submit)
                .codeFieldAccessibility(
                    label: .pairingInviteCodeLabel,
                    hint: .pairingCodeEntryFieldHint,
                    code: code,
                    identifier: "pairing.codeEntry.field"
                )
        }
        .focusesCodeFieldOnTap(isFocused: fieldFocused) { fieldFocused = $0 }
    }

    private var pasteButton: some View {
        PasteButton(payloadType: String.self) { strings in
            code = PairingInviteCode.entryText(strings.joined(separator: " "))
        }
        .labelStyle(.titleAndIcon)
        .buttonBorderShape(.capsule)
        .tint(.paeoniaAccentSecondary)
        .accessibilityIdentifier("pairing.codeEntry.paste")
    }

    private var submitButton: some View {
        Button(action: submit) {
            Text(submitTitle)
        }
        .buttonStyle(PaeoniaPrimaryButtonStyle(isLoading: isSubmitting))
        .disabled(!isComplete)
        .accessibilityIdentifier("pairing.codeEntry.submit")
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

enum PairingCodeCellLayoutID: Hashable {
    case cells
}

extension View {
    /// At the largest text sizes on a short screen the cells take two rows, and the keyboard
    /// can cover the second. Scrolls the cells' bottom edge into view when the keyboard
    /// changes the visible height and as the code grows. Put it on the scroll view, and
    /// `.id(PairingCodeCellLayoutID.cells)` on the cells.
    func keepsCodeCellsInView(_ scroller: ScrollViewProxy, visibleHeight: CGFloat, code: String) -> some View {
        onChange(of: visibleHeight) { scroller.scrollTo(PairingCodeCellLayoutID.cells, anchor: .bottom) }
            .onChange(of: code.count) { scroller.scrollTo(PairingCodeCellLayoutID.cells, anchor: .bottom) }
    }

    /// Makes the invisible text field behind the code cells the one element VoiceOver
    /// reads, over the cells' whole frame, with the code spelled out. The cells are hidden
    /// from accessibility. Otherwise VoiceOver finds a second, unnamed text field where the
    /// keyboard's focus is.
    func codeFieldAccessibility(
        label: LocalizedStringResource,
        hint: LocalizedStringResource,
        code: String,
        identifier: String
    ) -> some View {
        frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityLabel(Text(label))
            .accessibilityValue(Text(code).speechSpellsOutCharacters())
            .accessibilityHint(Text(hint))
            .accessibilityIdentifier(identifier)
    }

    /// Focuses the hidden text field under the code cells when someone taps them.
    func focusesCodeFieldOnTap(isFocused: Bool, setFocused: @escaping (Bool) -> Void) -> some View {
        modifier(CodeFieldTap(isFocused: isFocused, setFocused: setFocused))
    }
}

/// Closing the floating iPad keypad with a tap outside it leaves the field focused, so
/// focusing it again changes nothing and the keypad stays away. The keypad posts no
/// keyboard notifications, so when no docked keyboard is up, a tap drops the focus
/// and gives it back, which brings the keypad back. A docked keyboard is left alone,
/// because dropping the focus would slide it down and up again.
private struct CodeFieldTap: ViewModifier {
    let isFocused: Bool
    let setFocused: (Bool) -> Void

    @State private var keyboardIsDocked = true

    func body(content: Content) -> some View {
        content
            .contentShape(Rectangle())
            .onTapGesture {
                guard isFocused, !keyboardIsDocked else {
                    setFocused(true)
                    return
                }
                setFocused(false)
                Task { setFocused(true) }
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
                keyboardIsDocked = true
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
                keyboardIsDocked = false
            }
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
