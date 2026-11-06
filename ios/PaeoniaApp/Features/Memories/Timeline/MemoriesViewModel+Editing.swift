import Foundation

// MARK: - Edit steps

// Internal, not private, so `MemoriesViewModel+Place.swift` can use the shared steps.
extension MemoriesViewModel {
    enum StepResult {
        case unchanged
        case saved
        case failed
        case partiallySaved

        var savedChanges: Bool {
            switch self {
            case .saved, .partiallySaved: true
            case .unchanged, .failed: false
            }
        }

        var hasFailed: Bool {
            switch self {
            case .failed, .partiallySaved: true
            case .unchanged, .saved: false
            }
        }
    }

    /// Sends the title and date. A field the person didn't touch keeps its current
    /// value. If the partner's change lands on this phone while this runs, the edit is
    /// worked out again from the newer record instead of undoing that change.
    func saveDetails(_ edit: MemoryEdit, _ latest: MemoryRecord, _ userID: UUID) async -> StepResult {
        var current = latest
        for _ in 0..<3 {
            guard let change = detailChange(edit, current) else { return .unchanged }
            do {
                _ = try await memoryService.updateMemory(
                    ownerUserID: userID,
                    memoryID: current.snapshot.memoryID,
                    expectedRevision: current.snapshot.revision,
                    title: change.title,
                    memoryDate: change.date,
                    photoDescriptions: edit.existingDescriptions.map {
                        MemoryPhotoDescription(mediaAssetID: $0.key, text: $0.value)
                    },
                    operation: operationProvider.makeOperation()
                )
                return .saved
            } catch MemoryDataServiceError.staleRevision {
                do {
                    guard let fresh = try await storedVisibleRecord(current.snapshot.memoryID) else {
                        notice = .memoryRemoved
                        return .failed
                    }
                    current = fresh
                } catch {
                    report("Reading newer memory details failed", error, notice: .editFailed)
                    return .failed
                }
            } catch {
                report("Saving memory details failed", error, notice: .editFailed)
                return .failed
            }
        }
        notice = .editFailed
        return .failed
    }

    /// The title and date to send, or nil when they already match `current`.
    func detailChange(_ edit: MemoryEdit, _ current: MemoryRecord) -> (title: String, date: String)? {
        let base = edit.base.snapshot
        let title = edit.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let nextTitle = title != (base.title ?? "") ? title : (current.snapshot.title ?? title)
        let nextDate = edit.date != base.memoryDate ? edit.date : current.snapshot.memoryDate
        guard nextTitle != current.snapshot.title || nextDate != current.snapshot.memoryDate
            || edit.existingDescriptions.contains(where: { id, text in
                current.snapshot.media.first { $0.mediaAssetID == id }?.accessibilityText != text
            }) else {
            return nil
        }
        return (nextTitle, nextDate)
    }

    func saveNote(_ edit: MemoryEdit, _ latest: MemoryRecord, _ userID: UUID) async -> StepResult {
        let note = edit.note.trimmingCharacters(in: .whitespacesAndNewlines)
        let baseNote = edit.base.snapshot.ownNote?.body?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !note.isEmpty, note != baseNote, note != latest.snapshot.ownNote?.body else {
            return .unchanged
        }
        let saved = await perform("Saving a memory note failed", notice: .noteFailed) {
            _ = try await self.memoryService.upsertMemoryNote(
                ownerUserID: userID,
                memoryID: latest.snapshot.memoryID,
                expectedRevision: latest.snapshot.ownNote?.revision,
                body: note,
                operation: self.operationProvider.makeOperation()
            )
        }
        return saved ? .saved : .failed
    }

    func removePhotos(_ edit: MemoryEdit, _ latest: MemoryRecord, _ userID: UUID) async -> StepResult {
        let stillVisible = Set(latest.snapshot.media.filter(\.isVisible).map(\.memoryMediaID))
        let toRemove = edit.removedMedia.filter { stillVisible.contains($0.memoryMediaID) }
        guard !toRemove.isEmpty else { return .unchanged }
        var removedAny = false
        for media in toRemove {
            let removed = await perform("Removing a memory photo failed", notice: .editFailed) {
                _ = try await self.memoryService.removeMemoryMedia(
                    ownerUserID: userID,
                    memoryID: latest.snapshot.memoryID,
                    memoryMediaID: media.memoryMediaID,
                    operation: self.operationProvider.makeOperation()
                )
            }
            guard removed else { return removedAny ? .partiallySaved : .failed }
            removedAny = true
        }
        return .saved
    }
}
