import Foundation

/// The couple's dates and memories as Siri, Shortcuts and Spotlight see them, read from this
/// phone's caches with its queued writes laid over them, the way the app shows them. Nothing
/// here reads the network, and without access every list is empty.
enum SiriContent {
    static func dates() async -> [CoupleDateEntity] {
        await forEntityQuery(otherwise: []) { await dates(for: $0) }
    }

    /// Visible memories, newest first.
    static func memories() async -> [MemoryRecord] {
        await forEntityQuery(otherwise: []) { await memories(for: $0) }
    }

    /// What `read` loads for the couple an entity query may read for, or `nothing`. Loading takes
    /// time, and App Lock or lost access may arrive meanwhile, so the couple is asked again before
    /// anything is handed out.
    static func forEntityQuery<Content>(
        otherwise nothing: Content,
        read: (SiriCouple) async -> Content
    ) async -> Content {
        guard let couple = await coupleForEntityQuery() else { return nothing }
        let content = await read(couple)
        return await coupleForEntityQuery() == couple ? content : nothing
    }

    /// The couple an entity query may read for. Nil without access and while App Lock hides the app.
    @MainActor
    static func coupleForEntityQuery() async -> SiriCouple? {
        await SiriAppContext.shared.access()
            .coupleForEntityQuery(appIsLocked: AppLockModel.shared.hidesContentFromQueries)
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
