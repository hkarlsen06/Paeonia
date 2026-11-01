import Observation
import SwiftUI

extension EnvironmentValues {
    /// Only the live root injects persistent production stores. Local flows inject their own stores.
    @Entry var mediaAlternativeEditingService: MediaAlternativeEditingService?
}

@MainActor
@Observable
final class MediaAlternativeEditorModel {
    var isPresented = false
    var text = ""
    private(set) var isSaving = false
    private(set) var pending: PendingMediaAlternative?
    private(set) var acceptedText: String?
    private(set) var hasReadPending = false
    private(set) var pendingReadFailed = false
    private(set) var failureCount = 0
    private let target: MediaAlternativeTarget?
    private let ownerUserID: UUID?
    private let coupleID: UUID?
    private let service: MediaAlternativeEditingService?
    private let operationProvider: any SyncClientOperationProviding
    private var stamp: MediaAlternativeCacheUpdater.Stamp?
    private let sync: (@MainActor () async -> Void)?

    init(target: MediaAlternativeTarget?, context: ThreadChatContext, service: MediaAlternativeEditingService?) {
        self.target = target
        ownerUserID = context.participants.currentUserID
        coupleID = context.coupleID
        self.service = service
        operationProvider = context.operationProvider ?? SyncClientOperationFactory.shared
        sync = context.syncAfterLocalChange
    }

    var isEditable: Bool { target != nil && ownerUserID != nil && coupleID != nil && service != nil }
    var isReadyToOpen: Bool { !isEditable || hasReadPending && !pendingReadFailed }
    var canEdit: Bool { isEditable && stamp != nil && isReadyToOpen }
    var lengthError: LocalizedStringResource {
        if case .widgetDrawing? = target { return .drawingDescriptionTooLong }
        return .mediaAccessibilityTooLong
    }
    var isTooLong: Bool { DailyAnswerDraft.measuredLength(of: text) > (target?.maximumLength ?? 10_000) }

    func matches(target: MediaAlternativeTarget?, context: ThreadChatContext) -> Bool {
        self.target == target && ownerUserID == context.participants.currentUserID && coupleID == context.coupleID
    }

    func prepare() async {
        guard let service, let ownerUserID, target != nil else { return }
        stamp = await service.cache.stamp(ownerUserID: ownerUserID)
        await reloadPending()
    }

    func observe() async {
        await prepare()
        guard service != nil, let ownerUserID, target != nil else { return }
        for await change in LocalStoreChanges.changes(in: .pendingOperations) {
            guard !Task.isCancelled else { return }
            guard change.ownerUserID == nil || change.ownerUserID == ownerUserID else { continue }
            await reloadPending()
        }
    }

    func open(currentText: String?) {
        guard isReadyToOpen else { return }
        text = pending?.text ?? currentText ?? ""
        isPresented = true
    }

    func save() async {
        guard canEdit, !isSaving, !isTooLong, let service, let ownerUserID, let coupleID, let target, let stamp
        else { return }
        isSaving = true
        defer { isSaving = false }
        do {
            let operation = operationProvider.makeOperation()
            let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
            try await service.queue(MediaAlternativeEdit(coupleID: coupleID, target: target, text: cleaned),
                                    ownerUserID: ownerUserID, operation: operation, stamp: stamp)
            pending = PendingMediaAlternative(operationID: operation.id, text: cleaned, hasFailedAttempt: false)
            isPresented = false
            Task { await sync?() }
        } catch {
            failureCount += 1
        }
    }

    func retry() { Task { await sync?() } }

    func sourceChanged() {
        if pending == nil { acceptedText = nil }
    }

    func reloadPending() async {
        guard let service, let ownerUserID, let coupleID, let target else { return }
        do {
            let loaded = try await service.pendingEdit(ownerUserID: ownerUserID, coupleID: coupleID, target: target)
            guard !Task.isCancelled else { return }
            if pending != nil, loaded == nil {
                // History detail models hold a value snapshot. Keep the accepted correction
                // visible after its queue entry leaves, including a server-normalized result.
                acceptedText = await MediaAlternativeCacheWrites.shared.acceptedText(
                    ownerUserID: ownerUserID, target: target
                )
            }
            pending = loaded
            hasReadPending = true
            pendingReadFailed = false
        } catch {
            guard !Task.isCancelled else { return }
            pendingReadFailed = true
        }
    }
}

struct MediaAlternativeEditor: View {
    @Bindable var model: MediaAlternativeEditorModel
    let isVoice: Bool
    var isDrawing = false
    @Environment(PaeoniaBannerCenter.self) private var bannerCenter

    var body: some View {
        NavigationStack {
            Form { editorContents }
            .paeoniaGroupedList()
            .scrollDismissesKeyboard(.interactively)
            .keyboardDoneToolbar()
            .navigationTitle(Text(title))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { editorToolbar }
        }
        .preferredColorScheme(.dark)
        .interactiveDismissDisabled(model.isEditable)
        .paeoniaTopBanner(bannerCenter)
        .onChange(of: model.failureCount) { _, _ in
            bannerCenter.show(.error(message: String(localized: .mediaAccessibilitySaveFailed)))
        }
    }

    private var title: LocalizedStringResource {
        if isVoice { return .mediaAccessibilityTranscript }
        return isDrawing ? .mediaAccessibilityDrawingDescription : .mediaAccessibilityPhotoDescription
    }

    private var editorContents: some View {
        Section {
            if model.isEditable {
                if model.pendingReadFailed {
                    Text(.mediaAccessibilityLoadFailed)
                    Button(.commonTryAgain) { Task { await model.reloadPending() } }
                }
                TextField(text: $model.text, axis: .vertical) { Text(title) }
                    .lineLimit(4...12)
                    .accessibilityIdentifier("media.alternative.text")
                if model.isTooLong { Text(model.lengthError).foregroundStyle(.paeoniaErrorText) }
                Text(isVoice ? LocalizedStringResource.mediaAccessibilityTranscriptHint
                     : isDrawing ? .drawingDescriptionHint : .mediaAccessibilityPhotoHelp)
                Button(clearTitle, role: .destructive) { model.text = "" }
                    .disabled(model.text.isEmpty)
                    .accessibilityIdentifier("media.alternative.clear")
            } else {
                MediaAlternativeTextValue(text: model.text, isVoice: isVoice, isDrawing: isDrawing)
            }
        }
    }

    @ToolbarContentBuilder
    private var editorToolbar: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button(model.isEditable ? LocalizedStringResource.commonCancel : .commonDone) { model.isPresented = false }
                .disabled(model.isSaving)
                .accessibilityIdentifier("media.alternative.cancel")
        }
        if model.isEditable {
            ToolbarItem(placement: .confirmationAction) {
                Button(.mediaAccessibilitySave) { Task { await model.save() } }
                    .disabled(!model.canEdit || model.isTooLong || model.isSaving)
                    .accessibilityIdentifier("media.alternative.save")
            }
        }
    }

    private var clearTitle: LocalizedStringResource {
        if isVoice { return .mediaAccessibilityClearTranscript }
        return isDrawing ? .mediaAccessibilityClearDrawing : .mediaAccessibilityClearPhoto
    }
}

struct MediaAlternativeTextValue: View {
    let text: String?
    let isVoice: Bool
    var isDrawing = false

    var body: some View {
        if let text = text?.trimmedNonEmpty {
            Text(verbatim: text).textSelection(.enabled)
        } else {
            Text(isVoice ? LocalizedStringResource.mediaAccessibilityTranscriptMissing
                 : isDrawing ? .mediaAccessibilityDrawingMissing : .mediaAccessibilityPhotoMissing)
                .foregroundStyle(.paeoniaTextSecondary)
        }
    }
}
