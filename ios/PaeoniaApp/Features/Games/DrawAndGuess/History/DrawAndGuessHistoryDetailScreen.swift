import SwiftUI

/// Opens the detail of one drawing. The view model is made once per visit, so
/// the replay keeps its place when the stack redraws this screen.
struct DrawAndGuessHistoryDetailHost: View {
    private enum Load {
        case loading
        case loaded(DrawAndGuessHistoryDetailViewModel)
        case failed(PaeoniaFailure)
    }

    let history: DrawAndGuessHistoryViewModel
    let roundID: UUID
    @State private var load: Load

    /// A round that is already on the phone opens at once. Any other, such as a saved drawing
    /// opened right after a launch, is read first.
    init(history: DrawAndGuessHistoryViewModel, roundID: UUID) {
        self.history = history
        self.roundID = roundID
        _load = State(initialValue: history.makeDetail(roundID: roundID).map(Load.loaded) ?? .loading)
    }

    var body: some View {
        switch load {
        case let .loaded(viewModel):
            DrawAndGuessHistoryDetailScreen(viewModel: viewModel)
        case .loading:
            placeholder {
                ProgressView()
                    .tint(.paeoniaAccentPrimary)
                    .controlSize(.large)
            }
            .task { await loadRound() }
        case let .failed(failure):
            placeholder {
                PaeoniaLoadFailureView(
                    failure: failure,
                    offlineTitle: .gamesDrawAndGuessChooseOfflineTitle,
                    offlineMessage: .gamesDrawAndGuessHistoryOfflineMessage,
                    failedMessage: .gamesDrawAndGuessHistoryFailedMessage
                ) {
                    Button {
                        load = .loading
                    } label: {
                        Text(.commonTryAgain)
                    }
                    .buttonStyle(PaeoniaSecondaryButtonStyle())
                }
                .padding(.horizontal, PaeoniaSpacing.screenHorizontalPadding)
                .paeoniaReadableWidth(PaeoniaSpacing.focusedContentWidth)
            }
        }
    }

    private func placeholder(@ViewBuilder content: () -> some View) -> some View {
        content()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .paeoniaScreenBackground(.paeoniaBackgroundSecondary)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.paeoniaBackgroundSecondary, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .preferredColorScheme(.dark)
    }

    private func loadRound() async {
        do {
            if let round = try await history.loadRound(id: roundID) {
                load = .loaded(history.makeDetail(round: round))
            } else if !Task.isCancelled {
                // The couple has no such drawing, which no connection would fix.
                load = .failed(.other)
            }
        } catch {
            if !Task.isCancelled {
                load = .failed(PaeoniaFailure(error))
            }
        }
    }
}

/// A finished drawing: it plays back once at the drawn pace, then shows the word,
/// who drew it, how the round went, and the star toggle.
struct DrawAndGuessHistoryDetailScreen: View {
    let viewModel: DrawAndGuessHistoryDetailViewModel

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The square stops growing here, like the widget canvas, so strokes keep their weight.
    private static let maxSide: CGFloat = 640

    var body: some View {
        ScrollView {
            VStack(spacing: PaeoniaSpacing.space20) {
                drawing
                replayRow
                details
                Text(.favoritesPrivacyHint)
                    .font(PaeoniaTypography.caption)
                    .foregroundStyle(.paeoniaTextTertiary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, PaeoniaSpacing.screenHorizontalPadding)
            .padding(.vertical, PaeoniaSpacing.space16)
            .paeoniaReadableWidth()
        }
        .scrollBounceBehavior(.basedOnSize)
        .paeoniaScreenBackground(.paeoniaBackgroundSecondary)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.paeoniaBackgroundSecondary, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .preferredColorScheme(.dark)
        .favoriteToolbarItem(.gameRound(viewModel.round.id), identifier: "draw.history.star")
        .paeoniaShareToolbar(viewModel.shareable, identifier: "draw.history.share")
        .task { await viewModel.load(showsAtOnce: reduceMotion) }
        .accessibilityIdentifier("draw.history.detail")
    }

    // MARK: - Drawing

    /// The square is as wide as the space it is given, up to `maxSide`.
    private var drawing: some View {
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .frame(maxWidth: Self.maxSide)
            .overlay { GeometryReader { proxy in square(side: proxy.size.width) } }
            .frame(maxWidth: .infinity)
    }

    private func square(side: CGFloat) -> some View {
        GameSquare(side: side) {
            ZStack {
                switch viewModel.drawingState {
                case .ready:
                    GameReplaySurface(frames: viewModel.frames, side: side)
                        .allowsHitTesting(false)
                    if viewModel.isFastForwarding {
                        Image(systemName: "forward.fill")
                            .font(.title3)
                            .foregroundStyle(.paeoniaAccentPrimary)
                            .padding(PaeoniaSpacing.space12)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                            .accessibilityHidden(true)
                    }
                case .loading:
                    ProgressView()
                        .tint(.paeoniaAccentPrimary)
                        .accessibilityLabel(Text(.gamesDrawingLoading))
                case .failed:
                    failedState
                }
            }
        }
        .contentShape(Rectangle())
        .onLongPressGesture(minimumDuration: 0, maximumDistance: .infinity, perform: {}, onPressingChanged: holdChanged)
        .drawAndGuessDrawingAccessibility(
            label: Text(.gamesDrawAndGuessHistoryDetailDrawingA11Y(viewModel.word, viewModel.drawerName)),
            isDrawingShown: viewModel.drawingState == .ready
        )
        .accessibilityAction(named: Text(.gamesDrawAndGuessHistoryDetailReplay)) { viewModel.replay() }
        .accessibilityAction(named: Text(.gamesDrawAndGuessGuessReplaySkip)) { viewModel.showWholeDrawing() }
    }

    private var failedState: some View {
        PaeoniaEmptyStateView(
            title: .gamesNoticeDrawingUnavailableTitle,
            message: .gamesNoticeDrawingUnavailableMessage,
            systemImage: "exclamationmark.circle"
        ) {
            Button {
                Task { await viewModel.retryLoading(showsAtOnce: reduceMotion) }
            } label: {
                Text(.commonTryAgain)
            }
            .buttonStyle(PaeoniaSecondaryButtonStyle())
        }
        .padding(PaeoniaSpacing.space16)
    }

    private func holdChanged(_ isPressing: Bool) {
        guard viewModel.drawingState == .ready, viewModel.isFastForwarding != isPressing else { return }
        if isPressing { PaeoniaHaptics.selection() }
        viewModel.setFastForward(isPressing)
    }

    // MARK: - Below the drawing

    private var replayRow: some View {
        VStack(spacing: PaeoniaSpacing.space4) {
            Button {
                viewModel.replay()
            } label: {
                Label {
                    Text(.gamesDrawAndGuessHistoryDetailReplay)
                } icon: {
                    Image(systemName: "arrow.counterclockwise")
                }
            }
            .buttonStyle(PaeoniaQuietButtonStyle())
            .disabled(viewModel.drawingState != .ready)
            .accessibilityIdentifier("draw.history.replay")

            Text(.gamesDrawAndGuessHistoryDetailHoldHint)
                .font(PaeoniaTypography.caption)
                .foregroundStyle(.paeoniaTextTertiary)
                .multilineTextAlignment(.center)
                // VoiceOver has "Play again" as an action instead of holding.
                .accessibilityHidden(true)
        }
        .frame(maxWidth: .infinity)
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: PaeoniaSpacing.space12) {
            VStack(alignment: .leading, spacing: PaeoniaSpacing.space4) {
                Text(viewModel.word)
                    .font(PaeoniaTypography.heroTitle)
                    .foregroundStyle(.paeoniaTextPrimary)
                    .accessibilityAddTraits(.isHeader)
                Text(viewModel.drawnByLine)
                    .font(PaeoniaTypography.caption)
                    .foregroundStyle(.paeoniaTextSecondary)
            }
            Text(viewModel.resultLine)
                .font(PaeoniaTypography.body)
                .foregroundStyle(.paeoniaTextPrimary)
            ReactionSection(target: .drawAndGuessRound(viewModel.round.id))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
