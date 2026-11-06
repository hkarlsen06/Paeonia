import PencilKit

extension WidgetDrawingViewModel {
    private static let draftPersistenceDelay: Duration = .milliseconds(250)

    func refreshDraftSaveFailure() {
        draftSaveFailed = [usableDraftKey, setAsideKey].compactMap { $0 }.contains {
            draftStore.hasRetainedDraft(for: $0)
        }
    }

    /// Flushes the latest edit before leaving. A failed file write keeps the
    /// complete draft in the shared store and exposes a retry on the canvas.
    func persistDraftIfNeeded() {
        draftPersistenceTask?.cancel()
        draftPersistenceTask = nil
        persistDraftImmediatelyIfNeeded()
    }

    /// The draft key while it is still safe to use: nil without a couple, and
    /// nil after a privacy purge ran while this screen stayed open.
    var usableDraftKey: WidgetDrawingDraftKey? {
        guard let draftKey,
              draftStore.purgeGeneration(for: draftKey.ownerUserID) == draftPurgeGeneration
        else {
            return nil
        }
        return draftKey
    }

    func scheduleDraftPersistence() {
        guard usableDraftKey != nil else {
            return
        }

        draftPersistenceTask?.cancel()
        draftPersistenceTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(for: Self.draftPersistenceDelay)
            } catch {
                return
            }
            guard let self, !Task.isCancelled else {
                return
            }
            self.draftPersistenceTask = nil
            self.persistDraftInBackground()
        }
    }

    /// True when the canvas holds work that is not sent, so a draft is kept.
    private var shouldKeepDraft: Bool {
        hasUnsavedEdits && (!drawing.strokes.isEmpty || lastSavedDrawingSignature != nil
            || accessibilityText != savedAccessibilityText)
    }

    /// Writes the draft now, on the main actor.
    func persistDraftImmediatelyIfNeeded() {
        guard let draftKey = usableDraftKey else {
            return
        }

        draftOrder.performNow {
            if shouldKeepDraft {
                saveDraft(drawing.dataRepresentation(), base: (savedBaseline ?? PKDrawing()).paeoniaStrokeFingerprint,
                          description: accessibilityText, key: draftKey)
            } else {
                draftStore.removeDraft(for: draftKey)
                refreshDraftSaveFailure()
            }
        }
    }

    func retryDraftSave() {
        persistDraftIfNeeded()
        if let key = setAsideKey, let aside = setAsideDrawing {
            saveDraft(
                aside.dataRepresentation(), base: "", description: draftStore.description(for: key) ?? "", key: key
            )
        }
    }

    func saveDraft(_ data: Data, base: String, description: String, key: WidgetDrawingDraftKey) {
        do {
            try draftStore.saveDraft(data, base: base, description: description, for: key)
            refreshDraftSaveFailure()
        } catch {
            draftSaveFailed = true
        }
    }

    /// Encodes a large drawing off the main actor, then commits it in ticket order.
    private func persistDraftInBackground() {
        guard let draftKey = usableDraftKey else {
            return
        }
        guard shouldKeepDraft else {
            persistDraftImmediatelyIfNeeded()
            return
        }
        let ticket = draftOrder.nextTicket()
        let snapshot = DraftSnapshot(drawing: drawing, baseline: savedBaseline ?? PKDrawing())
        let description = accessibilityText
        Task { [self] in
            let encoded = await Self.encodeDraft(snapshot)
            guard usableDraftKey == draftKey else { return }
            draftOrder.perform(ticket) {
                saveDraft(encoded.data, base: encoded.base, description: description, key: draftKey)
            }
        }
    }

    private struct DraftSnapshot: Sendable {
        let drawing: PKDrawing
        let baseline: PKDrawing
    }

    @concurrent
    private static func encodeDraft(_ snapshot: DraftSnapshot) async -> (data: Data, base: String) {
        (snapshot.drawing.dataRepresentation(), snapshot.baseline.paeoniaStrokeFingerprint)
    }

    func clearDraft() {
        draftPersistenceTask?.cancel()
        draftPersistenceTask = nil
        guard let draftKey = usableDraftKey else {
            return
        }
        draftOrder.performNow {
            draftStore.removeDraft(for: draftKey)
            refreshDraftSaveFailure()
        }
    }
}
