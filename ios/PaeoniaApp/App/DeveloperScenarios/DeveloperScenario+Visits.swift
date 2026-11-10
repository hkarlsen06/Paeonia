#if DEBUG
  import SwiftUI

  /// The visit scenarios. `visit-none` and `visit-upcoming` open the real paired tabs on the Us
  /// tab. The others open the visit screen or the editor on their own.
  nonisolated extension DeveloperScenario {
    static let visits: [DeveloperScenario] = [
      visitNone, visitUpcoming, visitDetail, visitEditor, visitListFull, visitEditorFull,
    ]

    static let visitNone = DeveloperScenario(
      "visit-none", "Visit · none planned", "The Us tab asks when the partners meet next", .relationship
    ) { DeveloperPairedScenarioHost(scenario: $0) }
    static let visitUpcoming = DeveloperScenario(
      "visit-upcoming", "Visit · upcoming", "The Us tab counts down to a visit in Bergen", .relationship
    ) { DeveloperPairedScenarioHost(scenario: $0) }
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
  }

  /// In-memory visits for the scenarios and the local flows. Nothing reaches the server.
  @MainActor
  enum DeveloperVisitsFixture {
    static let ownerUserID = DeveloperScenarioFixture.currentUserID

    static func model(for scenario: DeveloperScenario) -> VisitsViewModel {
      model(scenario == .visitUpcoming ? planned() : CoupleVisits())
    }

    static func model(_ visits: CoupleVisits) -> VisitsViewModel {
      VisitsViewModel(
        cache: InMemoryVisitsCache(visits, ownerUserID: ownerUserID),
        pendingOperationStore: InMemoryPendingSyncOperationRepository(),
        operationProvider: DeveloperScenarioOperationProvider()
      )
    }

    /// A visit in Bergen 12 days from today, and three things to do, the second one ticked.
    static func planned(now: Date = Date(), calendar: Calendar = .current) -> CoupleVisits {
      let bergen = MemoryPlace(
        name: "Bryggen", latitude: 60.397, longitude: 5.324, city: "Bergen", countryCode: "NO"
      )
      return CoupleVisits(
        visits: [visit(from: 12, to: 16, place: bergen, now: now, calendar: calendar)],
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

    private static func visit(
      from start: Int, to end: Int, place: MemoryPlace?, now: Date, calendar: Calendar
    ) -> Visit {
      let today = calendar.startOfDay(for: now)
      func day(_ offset: Int) -> String {
        PairingStartDate(date: calendar.date(byAdding: .day, value: offset, to: today) ?? today, calendar: calendar)
          .rawValue
      }
      return Visit(id: UUID(), startDate: day(start), endDate: day(end), place: place)
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

    init(content: Content, visits: CoupleVisits, draft: String = "") {
      self.content = content
      let model = DeveloperVisitsFixture.model(visits)
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
