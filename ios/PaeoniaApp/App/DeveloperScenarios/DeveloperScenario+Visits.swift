#if DEBUG
  import SwiftUI

  /// The visit scenarios. `visit-none`, `visit-upcoming`, `visit-together`,
  /// `visit-ended-yesterday` and the three `visit-ended` photo card scenarios open the real
  /// paired tabs on the Us tab. `visit-streak-sheet` opens
  /// the streak sheet on a day together. The others open the visit screen or the editor on their own.
  nonisolated extension DeveloperScenario {
    static let visits: [DeveloperScenario] = [
      visitNone, visitUpcoming, visitTogether, visitEndedYesterday, visitEnded, visitEndedPartnerAdded,
      visitEndedOld, visitStreakSheet, visitDetail, visitEditor, visitListFull, visitEditorFull, visitRefused,
    ]

    static let visitNone = DeveloperScenario(
      "visit-none", "Visit · none planned", "The Us tab asks when the partners meet next", .relationship
    ) { DeveloperPairedScenarioHost(scenario: $0) }
    static let visitUpcoming = DeveloperScenario(
      "visit-upcoming", "Visit · upcoming", "The Us tab counts down to a visit in Bergen", .relationship
    ) { DeveloperPairedScenarioHost(scenario: $0) }
    static let visitTogether = DeveloperScenario(
      "visit-together", "Visit · together", "The partners are together in Bergen and the streak rests",
      .relationship
    ) { DeveloperPairedScenarioHost(scenario: $0) }
    static let visitEndedYesterday = DeveloperScenario(
      "visit-ended-yesterday", "Visit · ended yesterday", "The first day apart again, so the streak needs both",
      .relationship
    ) { DeveloperPairedScenarioHost(scenario: $0) }
    static let visitEnded = DeveloperScenario(
      "visit-ended", "Visit · ended, no photos", "The Us tab asks for photos from the Bergen visit", .relationship
    ) { DeveloperPairedScenarioHost(scenario: $0) }
    static let visitEndedPartnerAdded = DeveloperScenario(
      "visit-ended-partner-added", "Visit · partner added photos",
      "The partner saved photos from the Bergen visit and the Us tab asks for yours", .relationship
    ) { DeveloperPairedScenarioHost(scenario: $0) }
    static let visitEndedOld = DeveloperScenario(
      "visit-ended-old", "Visit · ended 15 days ago", "The photo question is gone two weeks after a visit",
      .relationship
    ) { DeveloperPairedScenarioHost(scenario: $0) }
    static let visitStreakSheet = DeveloperScenario(
      "visit-streak-sheet", "Visit · streak sheet", "The streak pill and sheet on a day the partners are together",
      .streak
    ) { DeveloperStreakScenarioView(scenario: $0) }
    static let visitDetail = DeveloperScenario(
      "visit-detail", "Visit · detail", "The next visit with three things to do, one ticked", .relationship
    ) { _ in DeveloperVisitScreen(content: .detail, visits: DeveloperVisitsFixture.planned()) }
    static let visitEditor = DeveloperScenario(
      "visit-editor", "Visit · editor", "Planning a new visit", .relationship
    ) { _ in DeveloperVisitScreen(content: .editor, visits: DeveloperVisitsFixture.planned()) }
    static let visitListFull = DeveloperScenario(
      "visit-list-full", "Visit · list full", "Adding to a full list keeps the text and says why", .relationship
    ) { _ in DeveloperVisitScreen(content: .detail, visits: DeveloperVisitsFixture.full(), draft: "Northern lights") }
    static let visitEditorFull = DeveloperScenario(
      "visit-editor-full", "Visit · 20 planned", "Saving a 21st visit says why it can't", .relationship
    ) { _ in DeveloperVisitScreen(content: .editor, visits: DeveloperVisitsFixture.full()) }
    static let visitRefused = DeveloperScenario(
      "visit-refused", "Visit · refused writes", "A list item and two visits the server refused", .relationship
    ) { _ in
      DeveloperVisitScreen(
        content: .detail, visits: DeveloperVisitsFixture.planned(), refusals: DeveloperVisitsFixture.refusals()
      )
    }
  }

  /// In-memory visits for the scenarios and the local flows. Nothing reaches the server.
  @MainActor
  enum DeveloperVisitsFixture {
    static let ownerUserID = DeveloperScenarioFixture.currentUserID

    static func model(for scenario: DeveloperScenario) -> VisitsViewModel {
      switch scenario {
      case .visitUpcoming: model(planned())
      case .visitTogether: model(planned(from: -1, through: 2))
      case .visitEndedYesterday: model(planned(from: -4, through: -1))
      case .visitEnded, .visitEndedPartnerAdded: model(planned(from: -5, through: -2, id: endedVisitID))
      case .visitEndedOld: model(planned(from: -19, through: -15))
      default: model(CoupleVisits())
      }
    }

    /// The Bergen visit that ended in `visit-ended` and `visit-ended-partner-added`.
    nonisolated static let endedVisitID = UUID(uuidString: "71517000-0000-4000-8000-000000000001") ?? UUID()

    /// The memory the partner made of the ended Bergen visit, with two of their photos.
    nonisolated static func partnerVisitMemory(now: Date = Date()) -> MemoryRecord {
      let partner = DeveloperScenarioFixture.partnerUserID
      let photos = (1...2).map { index in
        MemoryMediaSnapshot(
          memoryMediaID: UUID(), mediaAssetID: UUID(), ownerUserID: partner, sortOrder: index, updatedAt: now
        )
      }
      return MemoryRecord(
        snapshot: MemorySnapshot(
          ownerUserID: DeveloperScenarioFixture.currentUserID,
          memoryID: UUID(),
          coupleID: DeveloperScenarioFixture.coupleID,
          title: "Bergen in the rain",
          memoryDate: PairingStartDate(date: now.addingTimeInterval(-5 * 86_400), calendar: .current).rawValue,
          place: nil,
          createdByUserID: partner,
          lastEditedByUserID: partner,
          revision: 1,
          moderationStatus: .visible,
          deletedAt: nil,
          createdAt: now,
          updatedAt: now,
          syncUpdatedAt: now,
          ownNote: nil,
          partnerNote: nil,
          visibleMemoryMediaIDs: photos.map(\.memoryMediaID),
          visibleMediaAssetIDs: photos.map(\.mediaAssetID),
          media: photos,
          threadID: nil,
          visitID: endedVisitID
        )
      )
    }

    static func model(_ visits: CoupleVisits, refusals: [VisitsRefusal] = []) -> VisitsViewModel {
      VisitsViewModel(
        cache: InMemoryVisitsCache(visits, refusals: refusals, ownerUserID: ownerUserID),
        pendingOperationStore: InMemoryPendingSyncOperationRepository(),
        operationProvider: DeveloperScenarioOperationProvider()
      )
    }

    /// A visit in Bergen, by default 12 to 16 days from today, and three things to do, the second
    /// one ticked.
    static func planned(
      from startOffset: Int = 12, through endOffset: Int = 16, id: UUID = UUID(), now: Date = Date(),
      calendar: Calendar = .current
    ) -> CoupleVisits {
      let bergen = MemoryPlace(
        name: "Bryggen", latitude: 60.397, longitude: 5.324, city: "Bergen", countryCode: "NO"
      )
      return CoupleVisits(
        visits: [visit(from: startOffset, to: endOffset, place: bergen, id: id, now: now, calendar: calendar)],
        items: [
          TogetherListItem(id: UUID(), title: "Ice skating at Frogner", isDone: false),
          TogetherListItem(id: UUID(), title: "Cook ramen together", isDone: true),
          TogetherListItem(id: UUID(), title: "Fløyen at sunset", isDone: false),
        ]
      )
    }

    /// The Bergen visit and 19 more ahead, the most a couple can plan, and a list of 100 things.
    static func full(now: Date = Date(), calendar: Calendar = .current) -> CoupleVisits {
      var visits = planned(now: now, calendar: calendar)
      visits.visits += (1..<Visit.maxOpenCount).map { week in
        visit(from: 30 + week * 7, to: 32 + week * 7, place: nil, now: now, calendar: calendar)
      }
      visits.items += (visits.items.count..<TogetherListItem.maxCount).map { index in
        TogetherListItem(id: UUID(), title: "Idea \(index + 1)", isDone: false)
      }
      return visits
    }

    /// A list item and two visits the server refused for good.
    static func refusals(now: Date = Date(), calendar: Calendar = .current) -> [VisitsRefusal] {
      [
        .item(title: "Northern lights"),
        .visit(visit(from: 40, to: 43, place: nil, now: now, calendar: calendar)),
        .visit(visit(from: 61, to: 63, place: nil, now: now, calendar: calendar)),
      ]
    }

    private static func visit(
      from start: Int, to end: Int, place: MemoryPlace?, id: UUID = UUID(), now: Date, calendar: Calendar
    ) -> Visit {
      let today = calendar.startOfDay(for: now)
      func day(_ offset: Int) -> String {
        PairingStartDate(date: calendar.date(byAdding: .day, value: offset, to: today) ?? today, calendar: calendar)
          .rawValue
      }
      return Visit(id: id, startDate: day(start), endDate: day(end), place: place)
    }
  }

  /// The visit screen or the editor, on its own, with in-memory visits.
  struct DeveloperVisitScreen: View {
    enum Content {
      case detail
      case editor
    }

    let content: Content
    @State private var visits: VisitsViewModel

    init(content: Content, visits: CoupleVisits, draft: String = "", refusals: [VisitsRefusal] = []) {
      self.content = content
      let model = DeveloperVisitsFixture.model(visits, refusals: refusals)
      model.itemDraft = draft
      _visits = State(initialValue: model)
    }

    var body: some View {
      Group {
        switch content {
        case .detail:
          VisitDetailView(visits: visits)
        case .editor:
          VisitEditorView(visit: nil, visits: visits)
        }
      }
      .visitsLifecycle(visits, ownerUserID: DeveloperVisitsFixture.ownerUserID) {}
    }
  }
#endif
