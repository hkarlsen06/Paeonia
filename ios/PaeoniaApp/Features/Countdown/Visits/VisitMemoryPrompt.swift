import Foundation

/// What the Us tab asks after a visit (`HomeVisitMemoryCard`): to start a memory with photos
/// from it, or to add this person's photos to the memory the partner started. Each phone reads
/// the days on its own calendar, like `Visit.phase`.
nonisolated enum VisitMemoryPrompt: Equatable, Sendable {
    /// Nobody made a memory for the visit yet.
    case startMemory(Visit)
    /// The visit has a memory without this person's photos. `partnerAddedPhotos` says whether
    /// it holds the partner's.
    case addYourPhotos(Visit, memoryID: UUID, partnerAddedPhotos: Bool)

    /// The card shows from the day after the visit's last day through this many days after it.
    static let shownDays = 14

    var visit: Visit {
        switch self {
        case let .startMemory(visit), let .addYourPhotos(visit, _, _): visit
        }
    }

    /// The partner's photos wait for this person's. Otherwise the prompt only offers.
    var waitsForViewer: Bool {
        if case .addYourPhotos(_, _, partnerAddedPhotos: true) = self { true } else { false }
    }

    /// The prompt about `visit` for `viewerID` on `today`. Nil before the day after the visit,
    /// from day 15 after its last day, once the viewer hid it, and once the viewer has a photo in
    /// a memory of the visit. `memories` are the couple's memories on this phone.
    init?(visit: Visit, memories: [MemorySnapshot], viewerID: UUID, today: LockScreenCalendarDate) {
        guard !visit.memoryPromptDismissed, let end = LockScreenCalendarDate(visit.endDate) else { return nil }
        guard (1...Self.shownDays).contains(end.days(until: today)) else { return nil }
        let linked = memories
            .filter { $0.visitID == visit.id && $0.isVisible }
            .sorted { $0.createdAt < $1.createdAt }
        guard let memory = linked.first else {
            self = .startMemory(visit)
            return
        }
        let photos = linked.flatMap(\.media).filter(\.isVisible)
        guard !photos.contains(where: { $0.ownerUserID == viewerID }) else { return nil }
        self = .addYourPhotos(visit, memoryID: memory.memoryID, partnerAddedPhotos: !photos.isEmpty)
    }

    /// What the Us tab asks first: the partner's photos that wait for the viewer, from the visit
    /// that ended last among those, or else the ask about the visit that ended last.
    static func current(
        visits: [Visit],
        memories: [MemorySnapshot],
        viewerID: UUID,
        today: LockScreenCalendarDate
    ) -> Self? {
        let all = prompts(visits: visits, memories: memories, viewerID: viewerID, today: today)
        return all.first(where: \.waitsForViewer) ?? all.first
    }

    /// The prompt of one kind, from the visit that ended last among those that have one. The Us
    /// tab shows a prompt that waits for the viewer among its first cards and the others under its
    /// tiles, so two visits can each have a card, and one visit never has two.
    static func current(
        visits: [Visit],
        memories: [MemorySnapshot],
        viewerID: UUID,
        today: LockScreenCalendarDate,
        waitingForViewer: Bool
    ) -> Self? {
        prompts(visits: visits, memories: memories, viewerID: viewerID, today: today)
            .first { $0.waitsForViewer == waitingForViewer }
    }

    private static func prompts(
        visits: [Visit],
        memories: [MemorySnapshot],
        viewerID: UUID,
        today: LockScreenCalendarDate
    ) -> [Self] {
        visits
            .sorted { $0.endDate > $1.endDate }
            .compactMap { Self(visit: $0, memories: memories, viewerID: viewerID, today: today) }
    }
}
