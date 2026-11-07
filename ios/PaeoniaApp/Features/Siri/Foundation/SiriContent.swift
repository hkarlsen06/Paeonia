import Foundation

/// The couple's dates and memories as Siri, Shortcuts and Spotlight see them, read from this
/// phone's caches with its queued writes laid over them, the way the app shows them. Nothing
/// here reads the network, and without access every list is empty.
enum SiriContent {
    static func dates() async -> [CoupleDateEntity] {
        guard let couple = await SiriAppContext.shared.access().couple else { return [] }
        return await dates(for: couple)
    }

    /// Visible memories, newest first.
    static func memories() async -> [MemoryRecord] {
        guard let couple = await SiriAppContext.shared.access().couple else { return [] }
        return await memories(for: couple)
    }

    static func photos() async -> [MemoryPhotoEntity] {
        MemoryPhotoEntity.all(in: await memories())
    }

    static func dates(for couple: SiriCouple) async -> [CoupleDateEntity] {
        let model = CoupleDatesViewModel()
        await model.configure(ownerUserID: couple.ownerUserID)
        return CoupleDateEntity.all(in: model.dates, names: couple.dateNames)
    }

    /// The same list the Memories tab and Search show: hidden, removed and pending-delete
    /// memories are left out.
    static func memories(for couple: SiriCouple) async -> [MemoryRecord] {
        let records = (try? await MemoryDataServiceFactory.makeDefault().loadCachedMemories(
            ownerUserID: couple.ownerUserID,
            includeHidden: false
        )) ?? []
        return MemoryTimeline.grouped(records).flatMap(\.memories)
    }
}
