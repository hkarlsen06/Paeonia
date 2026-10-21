import SwiftUI

/// Opens the detail of one drawing. The view model is made once per visit, so
/// the replay keeps its place when the stack redraws this screen.
struct DrawAndGuessHistoryDetailHost: View {
    @State private var viewModel: DrawAndGuessHistoryDetailViewModel?

    init(history: DrawAndGuessHistoryViewModel, roundID: UUID) {
        _viewModel = State(initialValue: history.makeDetail(roundID: roundID))
    }

    var body: some View {
        if let viewModel {
            DrawAndGuessHistoryDetailScreen(viewModel: viewModel)
        } else {
            Color.paeoniaBackgroundSecondary
                .ignoresSafeArea()
                .toolbarBackground(.paeoniaBackgroundSecondary, for: .navigationBar)
                .toolbarColorScheme(.dark, for: .navigationBar)
        }
    }
}

/// A finished drawing: it plays back once at the drawn pace, then shows the word,
/// who drew it, how the round went, and the star toggle.
struct DrawAndGuessHistoryDetailScreen: View {
    let viewModel: DrawAndGuessHistoryDetailViewModel

    @Environment(PaeoniaBannerCenter.self) private var bannerCenter
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The square stops growing here, like the widget canvas, so strokes keep their weight.
    private static let maxSide: CGFloat = 640

    var body: some View {
        ScrollView {
            VStack(spacing: PaeoniaSpacing.space20) {
                drawing
                replayRow
                details
                Text(.gamesStarPrivacy)
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
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { starButton }
        }
        .task { await viewModel.load(showsAtOnce: reduceMotion) }
        .onChange(of: viewModel.stars.notice) { _, notice in
            guard let notice else { return }
            bannerCenter.show(notice.banner)
            viewModel.stars.clearNotice()
        }
        .accessibilityIdentifier("draw.history.detail")
    }

    // MARK: - Star

    private var starTitle: LocalizedStringResource {
        viewModel.isStarred ? .gamesStarButtonStarred : .gamesStarButton
    }

    private var starButton: some View {
        let isStarred = viewModel.isStarred
        return Button {
            PaeoniaHaptics.selection()
            Task { await viewModel.toggleStar() }
        } label: {
            Label {
                Text(starTitle)
            } icon: {
                Image(systemName: isStarred ? "star.fill" : "star")
            }
        }
        .accessibilityAddTraits(isStarred ? .isSelected : [])
        .accessibilityIdentifier("draw.history.star")
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
