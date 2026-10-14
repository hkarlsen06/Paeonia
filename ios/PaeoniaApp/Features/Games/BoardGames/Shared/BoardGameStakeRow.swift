import SwiftUI

/// The text of a stake. The server accepts 1 to 60 characters on one line and
/// counts Unicode scalars, so the phone counts them the same way.
nonisolated enum BoardGameStake {
    static let maxCharacters = 60

    static func length(of text: String) -> Int {
        text.unicodeScalars.count
    }

    /// The text without line breaks, cut to `maxCharacters`. `didOverflow` is
    /// true when characters were cut off.
    static func clamp(_ text: String) -> (text: String, didOverflow: Bool) {
        var result = ""
        var length = 0
        for character in text where !character.isNewline {
            let size = character.unicodeScalars.count
            if length + size > maxCharacters {
                return (result, true)
            }
            result.append(character)
            length += size
        }
        return (result, false)
    }

    /// The stake to send: the text without spaces around it, or nil when nothing is left.
    static func committed(_ draft: String) -> String? {
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

/// The line above the board for what the couple plays for. The starter sees a
/// quiet button before the first move, then a one-line field, then the stake in
/// a capsule with a pencil to change it. After the first move everyone sees the
/// stake in a capsule. It takes no space when `state` is `.hidden`.
struct BoardGameStakeRow: View {
    let state: BoardGameStakeState
    /// The text the starter writes. It goes to the server with the first move.
    @Binding var draft: String
    let partnerName: String
    /// The field was closed. `draft` holds the trimmed text, or nothing.
    let onCommitDraft: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @FocusState private var isFocused: Bool
    @State private var isEditing = false
    /// A character was refused because the stake is full. The counter turns red until the text gets shorter.
    @State private var didOverflow = false

    var body: some View {
        content
            .frame(maxWidth: .infinity)
            .animation(PaeoniaMotion.stateChange, value: isEditing)
            .onChange(of: state) { _, newState in
                if newState != .writable {
                    isEditing = false
                    isFocused = false
                }
            }
    }

    @ViewBuilder
    private var content: some View {
        switch state {
        case .hidden:
            EmptyView()
        case let .fixed(text):
            capsule(text, showsPencil: false)
                .accessibilityIdentifier("boardGames.stake")
        case .writable:
            writable
        }
    }

    // MARK: Writable

    @ViewBuilder
    private var writable: some View {
        if isEditing {
            VStack(spacing: PaeoniaSpacing.space4) {
                field
                hint
            }
        } else if let text = BoardGameStake.committed(draft) {
            VStack(spacing: PaeoniaSpacing.space4) {
                Button(action: beginEditing) {
                    capsule(text, showsPencil: true)
                        .padding(.vertical, PaeoniaSpacing.space4)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityHint(Text(.boardGamesStakeEditHint))
                .accessibilityIdentifier("boardGames.stake.edit")
                hint
            }
        } else {
            Button(action: beginEditing) {
                Label {
                    Text(.boardGamesStakeButton)
                } icon: {
                    Image(systemName: "plus")
                        .accessibilityHidden(true)
                }
            }
            .buttonStyle(PaeoniaQuietButtonStyle())
            .accessibilityIdentifier("boardGames.stake.add")
        }
    }

    private var field: some View {
        HStack(spacing: PaeoniaSpacing.space8) {
            giftIcon
            TextField(text: $draft, prompt: Text(.boardGamesStakePlaceholder)) {
                Text(.boardGamesStakeButton)
            }
            .font(PaeoniaTypography.body)
            .submitLabel(.done)
            .focused($isFocused)
            .onSubmit { isFocused = false }
            .onAppear { isFocused = true }
            .accessibilityIdentifier("boardGames.stake.field")
            counter
        }
        .padding(.horizontal, PaeoniaSpacing.space16)
        .frame(minHeight: PaeoniaSpacing.compactButtonHeight)
        .background(.paeoniaSurfaceSecondary, in: Capsule(style: .continuous))
        .overlay {
            Capsule(style: .continuous)
                .strokeBorder(.paeoniaAccentPrimary, lineWidth: PaeoniaRadius.strokeEmphasis)
        }
        .frame(maxWidth: BoardGameMetrics.maxBoard)
        .onChange(of: draft) { _, newValue in
            enforceLimit(newValue)
        }
        .onChange(of: isFocused) { _, focused in
            if !focused {
                finishEditing()
            }
        }
    }

    private var counter: some View {
        let length = BoardGameStake.length(of: draft)
        let limit = BoardGameStake.maxCharacters
        return Text(.boardGamesStakeCount(length, limit))
            .font(PaeoniaTypography.caption)
            .monospacedDigit()
            .foregroundStyle(didOverflow ? .paeoniaErrorText : .paeoniaTextTertiary)
            .accessibilityLabel(Text(.boardGamesStakeCountA11Y(length, limit)))
    }

    private var hint: some View {
        Text(.boardGamesStakeHint(partnerName))
            .font(PaeoniaTypography.caption)
            .foregroundStyle(.paeoniaTextSecondary)
            .multilineTextAlignment(.center)
    }

    // MARK: Capsule

    private var giftIcon: some View {
        Image(systemName: "gift")
            .foregroundStyle(.paeoniaAccentPrimary)
            .accessibilityHidden(true)
    }

    /// "Playing for: <text>" on one line. A long stake shortens in the middle.
    /// VoiceOver reads all of it.
    private func capsule(_ text: String, showsPencil: Bool) -> some View {
        HStack(spacing: PaeoniaSpacing.space8) {
            giftIcon
            Text(.boardGamesStakePlayingFor(text))
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
                .truncationMode(.middle)
            if showsPencil {
                Image(systemName: "pencil")
                    .font(PaeoniaTypography.caption)
                    .foregroundStyle(.paeoniaTextTertiary)
                    .accessibilityHidden(true)
            }
        }
        .font(PaeoniaTypography.body)
        .foregroundStyle(.paeoniaTextPrimary)
        .padding(.horizontal, PaeoniaSpacing.space16)
        .frame(minHeight: PaeoniaSpacing.space40)
        .background(.paeoniaSurfaceSecondary, in: Capsule(style: .continuous))
    }

    // MARK: Editing

    private func beginEditing() {
        isEditing = true
    }

    private func enforceLimit(_ text: String) {
        let clamped = BoardGameStake.clamp(text)
        if clamped.text != text {
            draft = clamped.text
        }
        if clamped.didOverflow {
            didOverflow = true
        } else if BoardGameStake.length(of: clamped.text) < BoardGameStake.maxCharacters {
            didOverflow = false
        }
    }

    private func finishEditing() {
        guard isEditing else { return }
        isEditing = false
        didOverflow = false
        draft = BoardGameStake.committed(draft) ?? ""
        onCommitDraft()
    }
}

#if DEBUG
#Preview("Writable") {
    @Previewable @State var draft = ""
    VStack(spacing: PaeoniaSpacing.space24) {
        BoardGameStakeRow(state: .writable, draft: $draft, partnerName: "Robin", onCommitDraft: {})
        BoardGameStakeRow(state: .fixed("Loser makes coffee"), draft: $draft, partnerName: "Robin", onCommitDraft: {})
        BoardGameStakeRow(
            state: .fixed("The loser makes dinner, does the dishes and picks the next film for a month"),
            draft: $draft,
            partnerName: "Robin",
            onCommitDraft: {}
        )
        BoardGameStakeRow(state: .hidden, draft: $draft, partnerName: "Robin", onCommitDraft: {})
    }
    .padding(.horizontal, PaeoniaSpacing.screenHorizontalPadding)
    .frame(maxHeight: .infinity)
    .background(.paeoniaBackgroundSecondary)
    .preferredColorScheme(.dark)
}
#endif
