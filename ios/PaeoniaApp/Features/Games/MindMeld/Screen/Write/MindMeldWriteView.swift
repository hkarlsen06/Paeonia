import SwiftUI

/// Think of one word and lock it in, with the partner's progress in view. Round 1
/// asks for any word. Later rounds show the last two words and ask for one that
/// connects them. The word checks run in the view model as the person types.
///
/// At normal text sizes the phase fits above the keyboard without scrolling. The
/// partner and the round share the top line, the invite is a bell in the
/// toolbar, and only the last rounds of the trail show.
struct MindMeldWriteView: View {
    @Bindable var viewModel: MindMeldViewModel
    /// False while the "How to play" cards are open or about to open.
    let canShowKeyboard: Bool
    /// The last round's words are still falling in from their cards.
    var hidesPairWords = false

    @FocusState private var isFieldFocused: Bool
    /// Set once the screen has opened the keyboard by itself, so coming back from "Our
    /// melds" leaves it closed. Opened during the back animation, it covers Lock in.
    @State private var hasOpenedKeyboard = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// How long the screen waits before it opens the keyboard, so the phase change finishes first.
    private static let focusDelay: Duration = .milliseconds(350)

    /// Earlier rounds shown above the pair to connect.
    private static let earlierRoundsShown = 2

    var body: some View {
        GameFocusedLayout(barRidesKeyboard: true) {
            VStack(spacing: PaeoniaSpacing.space20) {
                topLine
                heading
                earlierWords
                fieldBlock
            }
            .frame(maxWidth: .infinity)
        } bottom: {
            lockInButton
        }
        .gameInviteToolbar(
            invite: viewModel.invite,
            partnerName: viewModel.partnerName,
            send: viewModel.sendInvite,
            identifier: "mindMeld.invite"
        )
        .animation(stateChange, value: viewModel.draftIssue)
        .animation(stateChange, value: viewModel.showsPartnerRestartedNote)
        // The keyboard waits for the last round's words to land, so it never pushes in mid-fall.
        .task(id: canShowKeyboard && !hidesPairWords) {
            guard canShowKeyboard, !hidesPairWords else {
                isFieldFocused = false
                hasOpenedKeyboard = false
                return
            }
            guard !hasOpenedKeyboard else { return }
            try? await Task.sleep(for: Self.focusDelay)
            guard !Task.isCancelled else { return }
            hasOpenedKeyboard = true
            isFieldFocused = true
        }
        .onChange(of: viewModel.draftIssue) { _, issue in
            guard let issue else { return }
            AccessibilityNotification.Announcement(String(localized: issue.message)).post()
        }
    }

    private var stateChange: Animation {
        reduceMotion ? PaeoniaMotion.buttonPress : PaeoniaMotion.stateChange
    }

    // MARK: Top line

    /// The partner on the left and the round on the right.
    private var topLine: some View {
        GameLiveRow {
            MindMeldPartnerStatusRow(
                partner: viewModel.partner, status: viewModel.partnerStatus, isPresent: viewModel.isPartnerHere
            )
        } trailing: {
            Text(.mindMeldRound(viewModel.resolution.roundNumber, viewModel.maxRounds))
                .font(PaeoniaTypography.caption.weight(.bold))
                .tracking(1.4)
                .textCase(.uppercase)
                .foregroundStyle(.paeoniaTextTertiary)
                .lineLimit(1)
        }
    }

    // MARK: Heading

    private var heading: some View {
        VStack(spacing: PaeoniaSpacing.space8) {
            if viewModel.showsPartnerRestartedNote {
                Label {
                    Text(.mindMeldRestartPartnerNote(viewModel.partnerName))
                } icon: {
                    Image(systemName: "arrow.counterclockwise").accessibilityHidden(true)
                }
                .font(PaeoniaTypography.caption)
                .foregroundStyle(.paeoniaTextSecondary)
                .multilineTextAlignment(.center)
                .transition(.opacity)
                .accessibilityIdentifier("mindMeld.partnerRestarted")
            }
            Text(viewModel.isFirstRound ? .mindMeldWriteFirstTitle : .mindMeldWriteConnectTitle)
                .font(PaeoniaTypography.title)
                .foregroundStyle(.paeoniaTextPrimary)
                .multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)
            if viewModel.isFirstRound {
                Text(.mindMeldWriteFirstSubtitle(viewModel.partnerName))
                    .font(PaeoniaTypography.body)
                    .foregroundStyle(.paeoniaTextSecondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
    }

    /// The pair to connect, with the rounds before it in small type above, so the
    /// couple sees the words come closer. Only the last earlier rounds show, so a
    /// long game still fits above the keyboard. "Our melds" keeps the whole trail.
    @ViewBuilder
    private var earlierWords: some View {
        if let pair = viewModel.resolution.connectingPair {
            let earlier = viewModel.resolution.trail.dropLast().suffix(Self.earlierRoundsShown).map {
                (mine: $0.mine, theirs: $0.theirs, isMeld: false, isCounted: false)
            }
            VStack(spacing: PaeoniaSpacing.space12) {
                if !earlier.isEmpty {
                    MindMeldTrailView(pairs: earlier)
                }
                MindMeldWordPair(
                    mine: pair.mine,
                    theirs: pair.theirs,
                    roundID: viewModel.resolution.connectingRoundID,
                    hidesWords: hidesPairWords
                )
            }
            .accessibilityIdentifier("mindMeld.pair")
        }
    }

    // MARK: Field

    private var fieldBlock: some View {
        VStack(spacing: PaeoniaSpacing.space8) {
            field
            underFieldLine
        }
    }

    private var field: some View {
        TextField(text: $viewModel.draft) {
            Text(.mindMeldWritePlaceholder)
        }
        .font(PaeoniaTypography.title)
        .multilineTextAlignment(.center)
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()
        .submitLabel(.done)
        .focused($isFieldFocused)
        // Return only closes the keyboard. A locked word is final, so locking
        // in takes the Lock in button above the keyboard.
        .onSubmit { isFieldFocused = false }
        .padding(.horizontal, PaeoniaSpacing.space16)
        .frame(maxWidth: .infinity, minHeight: 64)
        .background(.paeoniaSurfaceSecondary, in: fieldShape)
        .overlay {
            fieldShape.strokeBorder(borderColor, lineWidth: borderWidth)
        }
        .animation(PaeoniaMotion.stateChange, value: isFieldFocused)
        .accessibilityIdentifier("mindMeld.field")
    }

    private var fieldShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: PaeoniaRadius.radius16, style: .continuous)
    }

    private var borderColor: Color {
        if viewModel.draftIssue != nil { return .paeoniaErrorText }
        return isFieldFocused ? .paeoniaAccentPrimary : .paeoniaSurfacePressed
    }

    private var borderWidth: CGFloat {
        viewModel.draftIssue != nil || isFieldFocused ? PaeoniaRadius.strokeEmphasis : PaeoniaRadius.strokeHairline
    }

    /// One line: what is wrong with the word, or in round 1 the Surprise me button.
    /// Round 1 keeps the button's height, so a message and the button swap in
    /// place. Later rounds take no room until a message shows.
    private var underFieldLine: some View {
        ZStack {
            if let issue = viewModel.draftIssue {
                Label {
                    Text(issue.message)
                } icon: {
                    Image(systemName: "exclamationmark.circle").accessibilityHidden(true)
                }
                .font(PaeoniaTypography.caption)
                .foregroundStyle(.paeoniaErrorText)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .transition(.opacity)
                .accessibilityIdentifier("mindMeld.issue")
            } else if viewModel.isFirstRound {
                Button {
                    PaeoniaHaptics.selection()
                    GameSound.tap.play(volume: 0.7)
                    viewModel.surpriseMe()
                } label: {
                    Label {
                        Text(.mindMeldWriteSurprise)
                    } icon: {
                        Image(systemName: "dice").accessibilityHidden(true)
                    }
                }
                .buttonStyle(PaeoniaQuietButtonStyle())
                .transition(.opacity)
                .accessibilityIdentifier("mindMeld.surprise")
            }
        }
        .frame(maxWidth: .infinity, minHeight: viewModel.isFirstRound ? PaeoniaSpacing.compactButtonHeight : 0)
    }

    // MARK: Lock in

    private var lockInButton: some View {
        Button {
            lockIn()
        } label: {
            Label {
                Text(.mindMeldWriteLockIn)
            } icon: {
                Image(systemName: "lock.fill").accessibilityHidden(true)
            }
        }
        .buttonStyle(PaeoniaPrimaryButtonStyle())
        .disabled(!viewModel.canLockIn)
        .accessibilityIdentifier("mindMeld.lockIn")
    }

    private func lockIn() {
        if viewModel.lockIn() {
            PaeoniaHaptics.drawingSent()
            GameSound.send.play()
            isFieldFocused = false
        } else {
            PaeoniaHaptics.validationError()
        }
    }
}

extension MindMeldWordIssue {
    /// The line under the field. A repeated word shows in capitals, as the cards do.
    var message: LocalizedStringResource {
        switch self {
        case .tooLong: .mindMeldWriteErrorTooLong
        case .tooManyWords: .mindMeldWriteErrorTooManyWords
        case .noLetters: .mindMeldWriteErrorNoLetters
        case .badCharacters: .mindMeldWriteErrorCharacters
        case let .repeatOf(word): .mindMeldWriteErrorRepeat(word.localizedUppercase)
        }
    }
}
