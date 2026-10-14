import SwiftUI

/// Pick what to draw: one of three words, or a word of your own. The round starts
/// when the player taps Start, so picking a row is only a selection.
struct DrawAndGuessChooseWordView: View {
    @Bindable var viewModel: DrawAndGuessViewModel

    /// The words on screen. The screen keeps showing them while it fades out after
    /// a pick, when the view model has already cleared its own list.
    @State private var shownChoices: [DrawAndGuessWordChoice]
    @State private var selected: DrawAndGuessDifficulty?
    @State private var isWritingOwn = false
    @State private var isStarting = false
    @State private var showsTooShort = false
    @FocusState private var isFieldFocused: Bool
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(viewModel: DrawAndGuessViewModel) {
        self.viewModel = viewModel
        _shownChoices = State(initialValue: viewModel.choices)
    }

    private var canStart: Bool {
        isWritingOwn ? viewModel.customWordValidation.word != nil : selected != nil
    }

    var body: some View {
        GameFocusedLayout {
            VStack(alignment: .leading, spacing: PaeoniaSpacing.space16) {
                DrawAndGuessScoreHeader(viewModel: viewModel)
                if !(isWritingOwn && verticalSizeClass == .compact) {
                    heading
                }
                if viewModel.choicesUnavailable, !isWritingOwn {
                    offline
                } else {
                    rows
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .animation(reduceMotion ? nil : PaeoniaMotion.stateChange, value: isWritingOwn)
        } bottom: {
            Button {
                start()
            } label: {
                Text(.gamesDrawAndGuessChooseStart)
            }
            .buttonStyle(PaeoniaPrimaryButtonStyle(isLoading: isStarting))
            .disabled(!canStart)
            .accessibilityIdentifier("draw.choose.start")
        }
        .drawAndGuessScoreToolbar(viewModel)
        .onChange(of: viewModel.choices) { _, new in
            if !new.isEmpty { shownChoices = new }
        }
        .onChange(of: viewModel.customWordValidation) { old, new in
            if case .invalid(let failure) = new, failure != .tooShort, new != old {
                PaeoniaHaptics.validationError()
                let message = String(localized: DrawAndGuessOwnWordField.message(for: failure))
                AccessibilityNotification.Announcement(message).post()
            }
            if case .valid = new { showsTooShort = false }
        }
    }

    // MARK: Heading

    private var heading: some View {
        VStack(alignment: .leading, spacing: PaeoniaSpacing.space4) {
            Text(.gamesDrawAndGuessChooseTitle)
                .font(PaeoniaTypography.heroTitle)
                .foregroundStyle(.paeoniaTextPrimary)
                .accessibilityAddTraits(.isHeader)
            Text(viewModel.isFirstTurn
                ? .gamesDrawAndGuessChooseSubtitleFirst(viewModel.partnerName)
                : .gamesDrawAndGuessChooseSubtitle(viewModel.partnerName))
                .font(PaeoniaTypography.body)
                .foregroundStyle(.paeoniaTextSecondary)
        }
    }

    private var offline: some View {
        PaeoniaEmptyStateView(
            title: .gamesDrawAndGuessChooseOfflineTitle,
            message: .gamesDrawAndGuessChooseOfflineMessage,
            systemImage: "wifi.slash"
        ) {
            Button {
                Task { await viewModel.refresh() }
            } label: {
                Text(.commonTryAgain)
            }
            .buttonStyle(PaeoniaSecondaryButtonStyle())
        }
    }

    // MARK: Rows

    @ViewBuilder
    private var rows: some View {
        VStack(spacing: PaeoniaSpacing.space12) {
            if !isWritingOwn {
                ForEach(shownChoices) { choice in
                    DrawAndGuessWordRow(choice: choice, isSelected: selected == choice.difficulty) {
                        PaeoniaHaptics.selection()
                        withAnimation(PaeoniaMotion.buttonPress) { selected = choice.difficulty }
                    }
                    .transition(.opacity)
                }
            }
            if isWritingOwn {
                DrawAndGuessOwnWordField(
                    viewModel: viewModel,
                    showsTooShort: $showsTooShort,
                    isWritingOwn: $isWritingOwn,
                    isFieldFocused: $isFieldFocused
                )
            } else {
                DrawAndGuessOwnWordRow {
                    selected = nil
                    isWritingOwn = true
                    isFieldFocused = true
                }
            }
        }
    }

    // MARK: Start

    private func start() {
        if isWritingOwn, case .invalid(.tooShort) = viewModel.customWordValidation {
            showsTooShort = true
            PaeoniaHaptics.validationError()
            return
        }
        guard canStart, !isStarting else { return }
        PaeoniaHaptics.drawingSent()
        isStarting = true
        isFieldFocused = false
        Task {
            if isWritingOwn {
                await viewModel.chooseCustomWord()
            } else if let choice = viewModel.choices.first(where: { $0.difficulty == selected }) {
                await viewModel.chooseWord(choice)
            }
            isStarting = false
        }
    }
}

/// One of the three words: the word, how hard it is and what it is worth.
struct DrawAndGuessWordRow: View {
    let choice: DrawAndGuessWordChoice
    let isSelected: Bool
    let action: () -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Button(action: action) {
            rowContent
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(.gamesDrawAndGuessChooseRowA11Y(
            DrawAndGuessAnswer.display(choice.word),
            String(localized: choice.difficulty.title),
            String(localized: .gamesDrawAndGuessPoints(choice.points))
        )))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("draw.choice.\(choice.difficulty.rawValue)")
    }

    private var rowContent: some View {
        HStack(spacing: PaeoniaSpacing.space12) {
            VStack(alignment: .leading, spacing: PaeoniaSpacing.space2) {
                Text(DrawAndGuessAnswer.display(choice.word))
                    .font(PaeoniaTypography.title)
                    .foregroundStyle(.paeoniaTextPrimary)
                Text(.gamesDrawAndGuessChooseRowDetail(
                    String(localized: choice.difficulty.title),
                    String(localized: .gamesDrawAndGuessPoints(choice.points))
                ))
                .font(PaeoniaTypography.caption)
                .foregroundStyle(.paeoniaTextSecondary)
            }
            Spacer(minLength: PaeoniaSpacing.space8)
            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.paeoniaAccentPrimary)
                    .accessibilityHidden(true)
                    .transition(.scale.combined(with: .opacity))
            } else if !dynamicTypeSize.isAccessibilitySize {
                pips
            }
        }
        .padding(PaeoniaSpacing.cardContentPadding)
        .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
        .background(.paeoniaSurfaceSecondary)
        .clipShape(RoundedRectangle(cornerRadius: PaeoniaRadius.radius16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: PaeoniaRadius.radius16, style: .continuous)
                .strokeBorder(
                    isSelected ? .paeoniaAccentPrimary : .clear,
                    lineWidth: PaeoniaRadius.strokeEmphasis
                )
        }
        .contentShape(RoundedRectangle(cornerRadius: PaeoniaRadius.radius16, style: .continuous))
    }

    /// One, two or three flowers, as many as the word is worth.
    private var pips: some View {
        HStack(spacing: PaeoniaSpacing.space4) {
            ForEach(0..<max(1, min(choice.points, 3)), id: \.self) { _ in
                Image(systemName: "camera.macro")
                    .foregroundStyle(.paeoniaAccentPrimary)
            }
        }
        .font(.subheadline)
        .accessibilityHidden(true)
    }
}

extension DrawAndGuessDifficulty {
    var title: LocalizedStringResource {
        switch self {
        case .easy: .gamesDrawAndGuessDifficultyEasy
        case .medium: .gamesDrawAndGuessDifficultyMedium
        case .hard: .gamesDrawAndGuessDifficultyHard
        case .custom: .gamesDrawAndGuessDifficultyCustom
        }
    }
}
