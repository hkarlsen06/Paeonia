import SwiftUI

/// Visible text and an author-only correction action. Story photos use the same sheet as a compact reader.
struct MediaAlternativeReadout: View {
    let text: String?
    let isVoice: Bool
    var isDrawing = false
    var editingTarget: MediaAlternativeTarget?
    var isCompact = false
    var onPresentationChanged: ((Bool) -> Void)?
    @Environment(\.threadChatContext) private var context
    @Environment(\.mediaAlternativeEditingService) private var service
    @State private var storedModel: MediaAlternativeEditorModel?

    var body: some View {
        VStack(alignment: .leading, spacing: PaeoniaSpacing.space4) {
            readout
            pendingStatus
        }
        .font(PaeoniaTypography.body)
        .tint(.paeoniaAccentPrimary)
        .task(id: identity) {
            let next = MediaAlternativeEditorModel(target: editingTarget, context: context, service: service)
            storedModel = next
            await next.observe()
        }
        .onChange(of: model?.isPresented) { _, presented in onPresentationChanged?(presented == true) }
        .onChange(of: text) { _, _ in model?.sourceChanged() }
        .sheet(isPresented: Binding(
            get: { model?.isPresented == true }, set: { model?.isPresented = $0 }
        )) {
            if let model { MediaAlternativeEditor(model: model, isVoice: isVoice, isDrawing: isDrawing) }
        }
    }

    @ViewBuilder
    private var readout: some View {
        if isCompact {
            Button(title) { model?.open(currentText: displayedText) }
                .frame(minHeight: PaeoniaSpacing.compactButtonHeight)
                .disabled(model?.isReadyToOpen != true)
                .accessibilityIdentifier("media.alternative.open")
        } else {
            Text(title).font(PaeoniaTypography.caption)
            if isLoadingPending {
                ProgressView().accessibilityLabel(Text(.mediaAccessibilityLoading))
            } else if model?.pendingReadFailed != true {
                MediaAlternativeTextValue(text: displayedText, isVoice: isVoice, isDrawing: isDrawing)
            }
            if model?.canEdit == true {
                Button(editTitle) {
                    model?.open(currentText: displayedText)
                }
                .frame(minHeight: PaeoniaSpacing.compactButtonHeight)
                .accessibilityIdentifier("media.alternative.edit")
            }
        }
    }

    @ViewBuilder
    private var pendingStatus: some View {
        if model?.pendingReadFailed == true {
            Text(.mediaAccessibilityLoadFailed)
            if let retained = model?.pending?.text {
                MediaAlternativeTextValue(text: retained, isVoice: isVoice, isDrawing: isDrawing)
            }
            Button(.commonTryAgain) { Task { await model?.reloadPending() } }
                .frame(minHeight: PaeoniaSpacing.compactButtonHeight)
                .accessibilityIdentifier("media.alternative.retryLoading")
        }
        if model?.pending?.hasFailedAttempt == true {
            Text(.mediaAccessibilityWaiting).font(PaeoniaTypography.caption)
            Button(.commonTryAgain) { model?.retry() }
                .frame(minHeight: PaeoniaSpacing.compactButtonHeight)
                .accessibilityIdentifier("media.alternative.retry")
        }
    }

    private var displayedText: String? { model?.pending?.text ?? model?.acceptedText ?? text }
    private var model: MediaAlternativeEditorModel? {
        guard storedModel?.matches(target: editingTarget, context: context) == true else { return nil }
        return storedModel
    }
    private var isLoadingPending: Bool {
        editingTarget != nil && service != nil && model?.hasReadPending != true && model?.pendingReadFailed != true
    }
    private var title: LocalizedStringResource {
        if isVoice { return .mediaAccessibilityTranscript }
        return isDrawing ? .mediaAccessibilityDrawingDescription : .mediaAccessibilityPhotoDescription
    }
    private var editTitle: LocalizedStringResource {
        if isVoice { return .mediaAccessibilityEditTranscript }
        return isDrawing ? .mediaAccessibilityEditDrawing : .mediaAccessibilityEditPhoto
    }
    private var identity: Identity {
        Identity(owner: context.participants.currentUserID, couple: context.coupleID, target: editingTarget)
    }
    private struct Identity: Hashable {
        let owner: UUID?
        let couple: UUID?
        let target: MediaAlternativeTarget?
    }
}
