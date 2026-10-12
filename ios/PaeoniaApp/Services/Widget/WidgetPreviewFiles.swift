import Foundation

/// File housekeeping for the widget files in the App Group container.
nonisolated enum WidgetPreviewFiles {
    /// Removes the payload and the preview folder. Returns true when something
    /// was removed.
    static func removeWidgetVisibleFiles(in containerURL: URL, fileManager: FileManager) -> Bool {
        var didRemoveSomething = false
        let payloadURL = containerURL.appendingPathComponent(PaeoniaAppGroup.widgetPayloadPath)
        if fileManager.fileExists(atPath: payloadURL.path) {
            try? fileManager.removeItem(at: payloadURL)
            didRemoveSomething = true
        }

        let previewsURL = containerURL.appendingPathComponent(
            PaeoniaAppGroup.widgetPreviewsDirectory,
            isDirectory: true
        )
        if fileManager.fileExists(atPath: previewsURL.path) {
            try? fileManager.removeItem(at: previewsURL)
            didRemoveSomething = true
        }
        return didRemoveSomething
    }

    /// Preview names include the revision so a new timeline never points at the
    /// same URL as stale image bytes. Cleanup starts only after the new payload
    /// is atomically visible and keeps recent revisions for old timeline
    /// entries; a crash can leave an orphan but cannot break the current payload.
    static func removeExpiredUnreferencedPreviews(
        keeping referencedPaths: Set<String>,
        previewsURL: URL,
        olderThan expirationDate: Date,
        fileManager: FileManager
    ) {
        guard let files = try? fileManager.contentsOfDirectory(
            at: previewsURL,
            includingPropertiesForKeys: [.isRegularFileKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return
        }

        for fileURL in files {
            let relativePath = "\(PaeoniaAppGroup.widgetPreviewsDirectory)/\(fileURL.lastPathComponent)"
            let values = try? fileURL.resourceValues(
                forKeys: [.isRegularFileKey, .contentModificationDateKey]
            )
            guard !referencedPaths.contains(relativePath),
                  values?.isRegularFile == true,
                  let modifiedAt = values?.contentModificationDate,
                  modifiedAt <= expirationDate
            else {
                continue
            }
            try? fileManager.removeItem(at: fileURL)
        }
    }
}
