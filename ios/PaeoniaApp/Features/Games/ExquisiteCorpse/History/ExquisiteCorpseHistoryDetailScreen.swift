import SwiftUI

/// Opens the detail of one creature. The view model is made once per visit, so
/// the unfolding keeps its place when the stack redraws this screen.
struct ExquisiteCorpseHistoryDetailHost: View {
    private enum Load {
        case loading
        case loaded(ExquisiteCorpseHistoryDetailViewModel)
        case failed(PaeoniaFailure)
    }

    let history: ExquisiteCorpseHistoryViewModel
    let figureID: UUID
    @State private var load: Load

    /// A creature that is already on the phone opens at once. Any other, such as a saved
    /// creature opened right after a launch, is read first.
    init(history: ExquisiteCorpseHistoryViewModel, figureID: UUID) {
        self.history = history
        self.figureID = figureID
        _load = State(initialValue: history.makeDetail(figureID: figureID).map(Load.loaded) ?? .loading)
    }

    var body: some View {
        switch load {
        case let .loaded(viewModel):
            ExquisiteCorpseHistoryDetailScreen(viewModel: viewModel)
        case .loading:
            placeholder {
                ProgressView()
                    .tint(.paeoniaAccentPrimary)
                    .controlSize(.large)
            }
            .task { await loadFigure() }
        case let .failed(failure):
            placeholder {
                PaeoniaLoadFailureView(
                    failure: failure,
                    offlineTitle: .gamesDrawAndGuessChooseOfflineTitle,
                    offlineMessage: .exquisiteCorpseHistoryOfflineMessage,
                    failedMessage: .exquisiteCorpseHistoryFailedMessage
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

    private func loadFigure() async {
        do {
            if let figure = try await history.loadFigure(id: figureID) {
                load = .loaded(history.makeDetail(figure: figure))
            } else if !Task.isCancelled {
                // The couple has no such creature, which no connection would fix.
                load = .failed(.other)
            }
        } catch {
            if !Task.isCancelled {
                load = .failed(PaeoniaFailure(error))
            }
        }
    }
}

/// A finished creature: the folded paper opens once at the pace of the reveal,
/// then shows the number, the date, who drew each part, and the star toggle.
struct ExquisiteCorpseHistoryDetailScreen: View {
    let viewModel: ExquisiteCorpseHistoryDetailViewModel

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// The details and the note about stars, measured, so the figure gets the
    /// height that is left under them.
    @State private var textHeight: CGFloat = 0

    /// The figure never grows past this, so strokes keep their weight.
    private static let maxSide: CGFloat = 320
    private static let minSide: CGFloat = 96
    private static let replayRowHeight: CGFloat = 44

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(spacing: PaeoniaSpacing.space16) {
                    figure(side: side(in: proxy.size))
                    replayRow
                    VStack(spacing: PaeoniaSpacing.space16) {
                        details
                        Text(.favoritesPrivacyHint)
                            .font(PaeoniaTypography.caption)
                            .foregroundStyle(.paeoniaTextTertiary)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)
                    }
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { textHeight = $0 }
                }
                .padding(.horizontal, PaeoniaSpacing.screenHorizontalPadding)
                .padding(.vertical, PaeoniaSpacing.space16)
                .paeoniaReadableWidth()
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .paeoniaScreenBackground(.paeoniaBackgroundSecondary)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.paeoniaBackgroundSecondary, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .preferredColorScheme(.dark)
        .favoriteToolbarItem(.corpseFigure(viewModel.figure.id), identifier: "corpse.history.star")
        .paeoniaShareToolbar(viewModel.content.shareable, identifier: "corpse.history.share")
        .task { await viewModel.load(showsAtOnce: reduceMotion) }
        .onChange(of: viewModel.timeline.stage) { _, stage in
            viewModel.timelineStageChanged(to: stage)
        }
        .onDisappear { viewModel.stop() }
        .accessibilityIdentifier("corpse.history.detail")
    }

    // MARK: - Figure

    /// The side of one part: as wide as the space allows, and no taller than a
    /// third of the height left under the text, so the whole creature is in view.
    /// A tall text block (large text sizes) makes the screen scroll instead.
    private func side(in size: CGSize) -> CGFloat {
        let width = size.width - PaeoniaSpacing.screenHorizontalPadding * 2
        // Two gaps between the three rows, the padding above and below, the replay
        // button and the figure's margin.
        let chrome = PaeoniaSpacing.space16 * 4 + Self.replayRowHeight + ExquisiteCorpseRevealCamera.margin * 2
        let fitting = (size.height - textHeight - chrome) / CGFloat(ExquisiteCorpsePartKind.allCases.count)
        return max(Self.minSide, min(Self.maxSide, width, fitting))
    }

    private func figure(side: CGFloat) -> some View {
        let height = side * CGFloat(ExquisiteCorpsePartKind.allCases.count) + ExquisiteCorpseRevealCamera.margin * 2
        let camera = ExquisiteCorpseRevealCamera(
            stage: CGSize(width: side, height: height),
            overviewHeight: height,
            viewportHeight: height,
            captionHeight: 0
        )
        // VoiceOver has "Show the whole figure" as an action on the figure instead of a tap.
        // swiftlint:disable:next accessibility_trait_for_button
        return ZStack {
            ExquisiteCorpseRevealFigure(
                player: viewModel.player,
                camera: camera,
                shot: .overview,
                openParts: viewModel.timeline.openParts,
                isLoaded: viewModel.drawingState == .ready,
                isWaiting: viewModel.drawingState == .loading,
                reduceMotion: reduceMotion,
                cameraAnimation: nil
            )
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(figureLabel)
            .accessibilityAddTraits(.isImage)
            .accessibilityActions {
                if viewModel.drawingState == .ready {
                    Button { viewModel.showWholeFigure() } label: { Text(.exquisiteCorpseRevealShowAll) }
                    Button { viewModel.replay() } label: { Text(.exquisiteCorpseRevealReplay) }
                }
            }
            .accessibilityIdentifier("corpse.history.figure")
            if viewModel.drawingState == .failed {
                GameDrawingPlaceholder(loadFailed: true) {
                    Task { await viewModel.retryLoading(showsAtOnce: reduceMotion) }
                }
            }
        }
        .frame(width: side, height: height)
        .contentShape(Rectangle())
        .onTapGesture { viewModel.showWholeFigure() }
    }

    private var figureLabel: Text {
        viewModel.drawingState == .loading
            ? Text(.gamesDrawingLoading)
            : Text(.exquisiteCorpseRevealFigureA11Y(viewModel.content.number, viewModel.content.partnerName))
    }

    // MARK: - Below the figure

    private var replayRow: some View {
        Button {
            viewModel.replay()
        } label: {
            Label {
                Text(.exquisiteCorpseRevealReplay)
            } icon: {
                Image(systemName: "arrow.counterclockwise")
            }
        }
        .buttonStyle(PaeoniaQuietButtonStyle())
        .disabled(viewModel.drawingState != .ready)
        .accessibilityIdentifier("corpse.history.replay")
    }

    private var details: some View {
        VStack(spacing: PaeoniaSpacing.space12) {
            VStack(spacing: PaeoniaSpacing.space4) {
                Text(.exquisiteCorpseRevealNumber(viewModel.content.number))
                    .font(PaeoniaTypography.heroTitle)
                    .foregroundStyle(.paeoniaTextPrimary)
                    .accessibilityAddTraits(.isHeader)
                Text(verbatim: viewModel.dateText)
                    .font(PaeoniaTypography.caption)
                    .foregroundStyle(.paeoniaTextSecondary)
            }
            .frame(maxWidth: .infinity)
            .accessibilityElement(children: .combine)
            ExquisiteCorpseRevealCredits(parts: viewModel.content.parts)
        }
    }
}
