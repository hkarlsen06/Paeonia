import AppIntents
import CoreSpotlight
import Foundation
import GeoToolbox

/// The one call the privacy purge makes into Spotlight. The protocol keeps the OS out of
/// the purge's tests.
nonisolated protocol SiriEntityIndexClearing: Sendable {
    /// Removes every Paeonia entity from Spotlight. Safe to repeat.
    func removeAllEntities() async throws
}

/// Keeps Spotlight's index of the couple's dates, memories and memory photos equal to what
/// the person sees in the app. After a write to memories, dates, queued writes or access, it
/// rebuilds the entities from the caches, indexes the new and changed ones and deletes the
/// removed ones. It indexes nothing without access. The privacy purge clears the index
/// through `removeAllEntities` on sign-out, account deletion, leaving and lost access.
@MainActor
final class SiriEntityIndexer: SiriEntityIndexClearing {
    nonisolated static let shared = SiriEntityIndexer()

    private struct Indexed: Equatable {
        var calendars: [String: String] = [:]
        var dates: [CoupleDateID: String] = [:]
        var memories: [UUID: String] = [:]
        var photos: [MemoryPhotoID: String] = [:]
    }

    /// Core Spotlight's index is safe to use from any thread, which its Swift type doesn't say.
    private nonisolated(unsafe) let index = CSSearchableIndex(name: "no.paeonia.app.entities")
    /// What the index holds, as each entity's id and shown values. Nil when unknown, so the
    /// next pass replaces everything of each type.
    private var indexed: Indexed?
    /// Bumped by every removal, so a pass that started before one never writes after it.
    private var generation = 0
    private var observation: Task<Void, Never>?
    private var isRefreshing = false
    /// A pass asked for while one ran, and whether it must rewrite everything.
    private var pendingForce: Bool?

    private nonisolated init() {}

    /// Indexes what is on the phone now and follows later writes for the life of the app.
    func start() {
        guard observation == nil else { return }
        let changes = LocalStoreChanges.changes(in: .memories, .coupleDates, .pendingOperations, .access)
        observation = Task { [weak self] in
            await self?.refresh()
            for await _ in changes {
                // A burst of writes settles into one pass.
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { return }
                await self?.refresh()
            }
        }
    }

    /// `force` rewrites every entity, for Spotlight's reindex request. One pass runs at a time,
    /// and a request that arrives meanwhile runs once more after it.
    func refresh(force: Bool = false) async {
        guard !isRefreshing else {
            pendingForce = (pendingForce ?? false) || force
            return
        }
        isRefreshing = true
        defer { isRefreshing = false }
        var next: Bool? = force
        while let force = next {
            pendingForce = nil
            await pass(force: force)
            next = pendingForce
        }
    }

    private func pass(force: Bool) async {
        let started = generation
        guard let couple = await SiriAppContext.shared.access().couple else { return }
        let dates = await SiriContent.dates(for: couple)
        let records = await SiriContent.memories(for: couple)
        let memories = records.map(MemoryAlbumEntity.init)
        let photos = MemoryPhotoEntity.all(in: records)
        let wanted = Indexed(
            calendars: [CoupleCalendarEntity.shared.id: CoupleCalendarEntity.shared.title],
            dates: Dictionary(dates.map { ($0.id, Self.signature($0)) }, uniquingKeysWith: { first, _ in first }),
            memories: Dictionary(memories.map { ($0.id, Self.signature($0)) }, uniquingKeysWith: { first, _ in first }),
            photos: Dictionary(photos.map { ($0.id, Self.signature($0)) }, uniquingKeysWith: { first, _ in first })
        )
        guard generation == started, force || wanted != indexed else { return }
        let previous = force ? nil : indexed
        indexed = nil
        do {
            try await sync([CoupleCalendarEntity.shared], wanted.calendars, previous?.calendars, started)
            try await sync(dates, wanted.dates, previous?.dates, started)
            try await sync(memories, wanted.memories, previous?.memories, started)
            try await sync(photos, wanted.photos, previous?.photos, started)
            if generation == started {
                indexed = wanted
            }
        } catch {
            // The next write or launch tries again with a full rewrite.
        }
    }

    nonisolated func removeAllEntities() async throws {
        try await removeAll()
    }

    private func removeAll() async throws {
        generation += 1
        indexed = nil
        try await index.deleteAllSearchableItems()
    }

    private func sync<Entity: IndexedEntity>(
        _ entities: [Entity],
        _ wanted: [Entity.ID: String],
        _ previous: [Entity.ID: String]?,
        _ started: Int
    ) async throws {
        if let previous {
            let removed = previous.keys.filter { wanted[$0] == nil }
            if !removed.isEmpty {
                try await index.deleteAppEntities(identifiedBy: Array(removed), ofType: Entity.self)
            }
        } else {
            try await index.deleteAppEntities(ofType: Entity.self)
        }
        let changed = entities.filter { previous?[$0.id] != wanted[$0.id] }
        // A removal that ran while this pass waited wins.
        guard generation == started else { throw CancellationError() }
        if !changed.isEmpty {
            try await index.indexAppEntities(changed)
        }
    }

    private static func signature(_ date: CoupleDateEntity) -> String {
        [date.title, "\(date.startDate)", "\(date.recurrence != nil)", "\(date.nextDate)"].joined(separator: "|")
    }

    private static func signature(_ memory: MemoryAlbumEntity) -> String {
        [memory.name, "\(memory.creationDate.map(String.init(describing:)) ?? "")", memory.placeName ?? ""]
            .joined(separator: "|")
    }

    private static func signature(_ photo: MemoryPhotoEntity) -> String {
        [
            photo.memoryTitle ?? "",
            photo.photoDescription ?? "",
            photo.creationDate.map(String.init(describing:)) ?? "",
            photo.location?.commonName ?? "",
        ].joined(separator: "|")
    }
}
