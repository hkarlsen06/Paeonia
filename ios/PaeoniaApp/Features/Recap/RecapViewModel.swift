import Foundation
import Observation

struct RecapPeople: Equatable {
    var currentUserID: UUID?
    var currentName = ""
    /// The partner as this person sees them, nickname included. Only this phone shows it.
    var partnerName = ""
    /// The name the partner chose. The share picture uses it, never a nickname.
    var partnerSharedName = ""
}

@Observable
final class RecapViewModel {
    private(set) var recaps: [AnniversaryRecap] = []
    var presented: AnniversaryRecap?
    private(set) var moments: [String: [LookBackItem]] = [:]
    var people = RecapPeople()
    let thumbnailLoader: any WidgetRevisionThumbnailLoading

    private let service: any RecapServing
    private let cache: any RecapCaching
    private let now: @Sendable () -> Date
    private var userID: UUID?
    private var coupleID: UUID?
    /// The due anniversaries the server answered for, each with the day it was asked and the start
    /// date it was asked for. A changed start date deletes the recaps, so it asks again.
    private var asked: Set<String> = []
    private var generation = 0
    /// An anniversary a push or link asked for before this phone had its recap. It opens when the
    /// recap arrives, or is dropped once the server has answered without it.
    @ObservationIgnored private var pendingLink: String?

    init(
        service: any RecapServing = NoOpRecapService(),
        cache: any RecapCaching = FileRecapCache.shared,
        thumbnailLoader: any WidgetRevisionThumbnailLoading = NoOpWidgetRevisionThumbnailLoader(),
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.service = service
        self.cache = cache
        self.thumbnailLoader = thumbnailLoader
        self.now = now
    }

    var homeRecap: AnniversaryRecap? {
        let today = RecapCalendar.today(now())
        return recaps.first { $0.isShown(today: today) }
    }

    func isAnniversaryToday(_ recap: AnniversaryRecap) -> Bool {
        recap.anniversaryDate == RecapCalendar.today(now())
    }

    func recap(on anniversaryDate: String) -> AnniversaryRecap? {
        recaps.first { $0.anniversaryDate == anniversaryDate }
    }

    func configure(userID: UUID?, coupleID: UUID?, startedOn: String?) async {
        if self.userID != userID || self.coupleID != coupleID {
            // The first account and couple need no reset, so a recap a push asked for before them opens.
            if (self.userID != nil && self.userID != userID) || (self.coupleID != nil && self.coupleID != coupleID) {
                presented = nil
                pendingLink = nil
            }
            self.userID = userID
            self.coupleID = coupleID
            generation += 1
            recaps = []
            moments = [:]
            asked = []
            guard let userID else { return }
            recaps = cache.load(ownerUserID: userID, coupleID: coupleID)?.recaps ?? []
            openPendingLink(serverAnswered: false)
        }
        await refresh(startedOn: startedOn)
    }

    func refresh(startedOn: String?) async {
        guard let userID else { return }
        let mine = generation
        let purgeCount = cache.purgeCount()
        guard var fetched = try? await service.fetchRecaps(), mine == generation, !Task.isCancelled else { return }
        var serverAnswered = true
        let today = RecapCalendar.today(now())
        let askKey = "\(today) \(startedOn ?? "")"
        if let due = dueAnniversary(startedOn: startedOn, today: today),
           !fetched.contains(where: { $0.anniversaryDate == due }), !asked.contains("\(due) \(askKey)") {
            // An answer counts as asked for that day and start date only. A failed call is tried again next read.
            do {
                let made = try await service.ensureRecap()
                guard mine == generation, !Task.isCancelled else { return }
                asked.insert("\(due) \(askKey)")
                if let made {
                    fetched = [made] + fetched.filter { $0.anniversaryDate != made.anniversaryDate }
                }
            } catch {
                serverAnswered = false
            }
        }
        guard mine == generation else { return }
        let saved = cache.save(
            RecapCacheEntry(coupleID: coupleID, recaps: fetched), ownerUserID: userID, unlessPurgedSince: purgeCount
        )
        recaps = saved ? fetched : []
        // Without the start date this read could not ask for the due recap, so a link keeps waiting.
        openPendingLink(serverAnswered: serverAnswered && startedOn != nil)
    }

    func loadMoments(for recap: AnniversaryRecap) async {
        let mine = generation
        guard let items = try? await service.fetchMoments(anniversaryDate: recap.anniversaryDate),
              mine == generation, !Task.isCancelled
        else { return }
        moments[recap.anniversaryDate] = items
    }

    /// Opens the recap of `anniversaryDate` for a push or link. When this phone does not have it
    /// yet, it opens once a read brings it, also when the Us tab has not read its recaps yet. False
    /// when a newer link took over meanwhile.
    func presentLink(_ anniversaryDate: String, startedOn: String?, isCurrent: () -> Bool) async -> Bool {
        if let recap = recap(on: anniversaryDate) {
            presented = recap
            return true
        }
        pendingLink = anniversaryDate
        await refresh(startedOn: startedOn)
        guard isCurrent() else {
            if pendingLink == anniversaryDate { pendingLink = nil }
            return false
        }
        return true
    }

    private func openPendingLink(serverAnswered: Bool) {
        guard let pendingLink else { return }
        if let recap = recap(on: pendingLink) {
            presented = recap
            self.pendingLink = nil
        } else if serverAnswered {
            self.pendingLink = nil
        }
    }

    private func dueAnniversary(startedOn: String?, today: String) -> String? {
        guard let startedOn,
              let anniversary = RecapCalendar.latestAnniversary(startedOn: startedOn, today: today),
              let days = RecapCalendar.days(from: anniversary, to: today),
              days < AnniversaryRecap.shownDays
        else { return nil }
        return anniversary
    }
}

extension RecapViewModel {
    static func live(thumbnailLoader: any WidgetRevisionThumbnailLoading) -> RecapViewModel {
        let service: any RecapServing
        if let client = try? PaeoniaConvexClientProvider.shared.client() {
            service = LiveRecapService(client: client)
        } else {
            service = NoOpRecapService()
        }
        return RecapViewModel(service: service, thumbnailLoader: thumbnailLoader)
    }
}
