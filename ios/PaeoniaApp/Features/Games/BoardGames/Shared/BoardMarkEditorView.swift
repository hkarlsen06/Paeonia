import SwiftUI

/// The "Your mark" sheet. The person draws a small mark once, and the boards
/// print it on every piece they play. The sheet mounts its own top banner,
/// because it covers the app's.
struct BoardMarkEditorView: View {
    /// The color of my pieces.
    let color: Color

    @State private var model: BoardMarkEditorModel
    @Environment(\.dismiss) private var dismiss
    @Environment(PaeoniaBannerCenter.self) private var bannerCenter

    private static let maxCanvasSide: CGFloat = 360

    /// The sheet keeps the first model it gets, so a parent that builds a new model
    /// whenever it redraws cannot reset the canvas while the person draws.
    init(color: Color, model: BoardMarkEditorModel) {
        self.color = color
        _model = State(initialValue: model)
    }

    var body: some View {
        NavigationStack {
            content
                .paeoniaScreenBackground(.paeoniaBackgroundSecondary)
                .paeoniaBottomBar { bottomBar }
                .navigationTitle(Text(.boardGamesMarkTitle))
                .navigationBarTitleDisplayMode(.inline)
                .toolbarBackground(.paeoniaBackgroundSecondary, for: .navigationBar)
                // The sheet scrolls on short screens such as an iPad form sheet, so both
                // bars are opaque. Otherwise the content shows through them.
                .toolbarBackgroundVisibility(.visible, for: .navigationBar)
                .toolbarColorScheme(.dark, for: .navigationBar)
                .toolbar { cancelButton }
        }
        // The sheet covers the app's top banner, so it mounts its own copy.
        // Otherwise a failed save would look like nothing happened.
        .paeoniaTopBanner(bannerCenter)
        .presentationBackground(.paeoniaBackgroundSecondary)
        .preferredColorScheme(.dark)
        .interactiveDismissDisabled(model.isSaving)
        .onChange(of: model.failure) { _, failure in
            failureChanged(failure)
        }
    }

    private var content: some View {
        ScrollView {
            VStack(spacing: PaeoniaSpacing.space24) {
                Text(.boardGamesMarkIntro)
                    .font(PaeoniaTypography.body)
                    .foregroundStyle(.paeoniaTextSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                canvas

                editButtons

                if model.failure == .tooBig {
                    Text(.boardGamesMarkTooBig)
                        .font(PaeoniaTypography.caption.weight(.semibold))
                        .foregroundStyle(.paeoniaErrorText)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }

                BoardMarkPreviews(color: color, style: previewStyle)
            }
            .padding(.horizontal, PaeoniaSpacing.screenHorizontalPadding)
            .padding(.top, PaeoniaSpacing.space8)
            .padding(.bottom, PaeoniaSpacing.space24)
            .paeoniaReadableWidth(PaeoniaSpacing.focusedContentWidth)
        }
        .scrollBounceBehavior(.basedOnSize)
    }

    @ToolbarContentBuilder
    private var cancelButton: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button {
                dismiss()
            } label: {
                Text(.commonCancel)
            }
            .disabled(model.isSaving)
            .accessibilityIdentifier("boardGames.mark.cancel")
        }
    }

    private var previewStyle: BoardPieceStyle {
        BoardPieceStyle(color: color, mark: model.previewMark, initial: model.initial)
    }

    // MARK: Canvas

    /// A square at most `maxCanvasSide` wide. The model learns its width, so it can
    /// scale the drawing to the size every phone stores.
    private var canvas: some View {
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .frame(maxWidth: Self.maxCanvasSide)
            .overlay {
                PencilKitCanvasView(
                    drawing: model.drawing,
                    drawingRevision: model.drawingRevision,
                    tool: model.tool,
                    toolConfigurationRevision: 0,
                    onCanvasReady: { _ in },
                    onDrawingChange: model.drawingChanged,
                    onStrokeInProgressChange: { _ in }
                )
                .allowsHitTesting(!model.isSaving)
                .accessibilityLabel(Text(.boardGamesMarkCanvasA11Y))
                .accessibilityIdentifier("boardGames.mark.canvas")
            }
            .background(.paeoniaBackgroundPrimary)
            .clipShape(RoundedRectangle(cornerRadius: PaeoniaRadius.radius28, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: PaeoniaRadius.radius28, style: .continuous)
                    .strokeBorder(.paeoniaSurfacePressed, lineWidth: PaeoniaRadius.strokeDefault)
                    .allowsHitTesting(false)
            }
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { side in
                model.canvasDidLayout(side: side)
            }
    }

    private var editButtons: some View {
        HStack(spacing: PaeoniaSpacing.space8) {
            Button {
                model.undo()
            } label: {
                Text(.widgetDrawingUndoButton)
            }
            .disabled(!model.canUndo || model.isSaving)
            .accessibilityIdentifier("boardGames.mark.undo")

            Button {
                model.clear()
            } label: {
                Text(.widgetDrawingClearButton)
            }
            .disabled(model.isEmpty || model.isSaving)
            .accessibilityIdentifier("boardGames.mark.clear")
        }
        .buttonStyle(PaeoniaQuietButtonStyle())
    }

    // MARK: Bottom bar

    private var bottomBar: some View {
        VStack(spacing: PaeoniaSpacing.space8) {
            Button {
                Task {
                    if await model.save() {
                        dismiss()
                    }
                }
            } label: {
                Text(.boardGamesMarkSave)
            }
            .buttonStyle(PaeoniaPrimaryButtonStyle(isLoading: model.isSaving))
            .disabled(!model.canSave)
            .accessibilityIdentifier("boardGames.mark.save")

            if model.hasSavedMark {
                Button {
                    Task {
                        if await model.useInitial() {
                            dismiss()
                        }
                    }
                } label: {
                    Text(.boardGamesMarkUseInitial)
                }
                .buttonStyle(PaeoniaQuietButtonStyle())
                .disabled(model.isSaving)
                .accessibilityIdentifier("boardGames.mark.useInitial")
            }
        }
        .padding(.horizontal, PaeoniaSpacing.screenHorizontalPadding)
        .padding(.vertical, PaeoniaSpacing.space12)
        .paeoniaReadableWidth(PaeoniaSpacing.focusedContentWidth)
        .background(.paeoniaBackgroundSecondary)
    }

    // MARK: Failures

    /// A failed save goes to the top banner, which the model then forgets. The
    /// too-big line shows inline, so VoiceOver gets it read out here.
    private func failureChanged(_ failure: BoardMarkEditorModel.Failure?) {
        switch failure {
        case .couldNotSave:
            bannerCenter.show(.error(message: String(localized: .boardGamesMarkSaveError)))
            model.clearFailure()
        case .tooBig:
            AccessibilityNotification.Announcement(String(localized: .boardGamesMarkTooBig)).post()
        case nil:
            break
        }
    }
}

/// The mark on a Connect Four disc, a Dots and Boxes box and an Ultimate
/// Tic-Tac-Toe cell, drawn the way the boards draw them. It repeats what the
/// canvas shows, so VoiceOver skips it.
private struct BoardMarkPreviews: View {
    let color: Color
    let style: BoardPieceStyle

    private let side: CGFloat = 72
    private var inset: CGFloat { side * 0.14 }

    var body: some View {
        HStack(spacing: PaeoniaSpacing.space24) {
            BoardMarkView(style: style, tint: .paeoniaTextInverse)
                .padding(inset)
                .frame(width: side, height: side)
                .background(color, in: Circle())

            BoardMarkView(style: style, tint: .paeoniaTextPrimary)
                .padding(inset)
                .frame(width: side, height: side)
                .background(
                    color.opacity(0.35),
                    in: RoundedRectangle(cornerRadius: PaeoniaRadius.radius12, style: .continuous)
                )

            BoardMarkView(style: style, tint: color)
                .padding(inset)
                .frame(width: side, height: side)
                .background(
                    .paeoniaSurfacePrimary,
                    in: RoundedRectangle(cornerRadius: PaeoniaRadius.radius12, style: .continuous)
                )
        }
        .frame(maxWidth: .infinity)
        .accessibilityHidden(true)
    }
}

#Preview {
    BoardMarkEditorView(
        color: .paeoniaPartnerOne,
        model: BoardMarkEditorModel(initialMarkData: nil, initial: "H", save: { _ in })
    )
    .environment(PaeoniaBannerCenter())
}
