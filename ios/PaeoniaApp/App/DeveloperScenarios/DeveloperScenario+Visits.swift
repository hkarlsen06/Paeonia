#if DEBUG
  import SwiftUI

  /// The visit scenarios. `visit-none` and `visit-upcoming` open the real paired tabs on the Us
  /// tab. `visit-detail` and `visit-editor` open those screens on their own.
  nonisolated extension DeveloperScenario {
    static let visits: [DeveloperScenario] = [visitNone, visitUpcoming, visitDetail, visitEditor]

    static let visitNone = DeveloperScenario(
      "visit-none", "Visit · none planned", "The Us tab asks when the partners meet next", .relationship
    ) { DeveloperPairedScenarioHost(scenario: $0) }
    static let visitUpcoming = DeveloperScenario(
      "visit-upcoming", "Visit · upcoming", "The Us tab counts down to a visit in Bergen", .relationship
    ) { DeveloperPairedScenarioHost(scenario: $0) }
    static let visitDetail = DeveloperScenario(
      "visit-detail", "Visit · detail", "The next visit with three things to do, one ticked", .relationship
    ) { _ in DeveloperVisitScreen(content: .detail) }
    static let visitEditor = DeveloperScenario(
      "visit-editor", "Visit · editor", "Planning a new visit", .relationship
    ) { _ in DeveloperVisitScreen(content: .editor) }
  }

  /// In-memory visits for the scenarios and the local flows. Nothing reaches the server.
  @MainActor
  enum DeveloperVisitsFixture {
    static let ownerUserID = DeveloperScenarioFixture.currentUserID

    static func model(for scenario: DeveloperScenario) -> VisitsViewModel {
      model(scenario == .visitUpcoming || scenario == .visitDetail ? planned() : CoupleVisits())
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
      let today = calendar.startOfDay(for: now)
      func day(_ offset: Int) -> String {
        PairingStartDate(date: calendar.date(byAdding: .day, value: offset, to: today) ?? today, calendar: calendar)
          .rawValue
      }
      let bergen = MemoryPlace(
        name: "Bryggen", latitude: 60.397, longitude: 5.324, city: "Bergen", countryCode: "NO"
      )
      return CoupleVisits(
        visits: [Visit(id: UUID(), startDate: day(12), endDate: day(16), place: bergen)],
        items: [
          TogetherListItem(id: UUID(), title: "Ice skating at Frogner", isDone: false),
          TogetherListItem(id: UUID(), title: "Cook ramen together", isDone: true),
          TogetherListItem(id: UUID(), title: "Fløyen at sunset", isDone: false),
        ]
      )
    }
  }

  /// The visit screen or the editor, on its own, with in-memory visits.
  struct DeveloperVisitScreen: View {
    enum Content {
      case detail
      case editor
    }

    let content: Content
    @State private var visits = DeveloperVisitsFixture.model(
      DeveloperVisitsFixture.planned()
    )

    var body: some View {
      Group {
        switch content {
        case .detail:
          VisitDetailView(visits: visits)
        case .editor:
          VisitEditorView(visit: nil, visits: visits)
        }
      }
      .environment(visits)
      .task { await visits.configure(ownerUserID: DeveloperVisitsFixture.ownerUserID) }
    }
  }
#endif
