#if DEBUG
  import SwiftUI

  nonisolated extension DeveloperScenario {
    static let recap: [DeveloperScenario] = [homeRecap, homeRecapLater, recapYear, recapFirstMonths, recapLeapDay]

    static let homeRecap = DeveloperScenario(
      "home-recap", "Recap · Us tab on the anniversary", "The recap card on the first anniversary", .memories
    ) { DeveloperPairedScenarioHost(scenario: $0) }
    static let homeRecapLater = DeveloperScenario(
      "home-recap-later", "Recap · Us tab days later", "The one-row recap card three days after", .memories
    ) { DeveloperPairedScenarioHost(scenario: $0) }
    static let recapYear = DeveloperScenario(
      "recap-year", "Recap · a full year", "Every page of a third-anniversary recap with two moments", .memories
    ) { _ in DeveloperRecapScenarioView(recap: DeveloperRecapFixture.fullYear) }
    static let recapFirstMonths = DeveloperScenario(
      "recap-first-months", "Recap · joined three months ago",
      "A recap that covers the time since the couple joined Paeonia", .memories
    ) { _ in DeveloperRecapScenarioView(recap: DeveloperRecapFixture.firstMonths) }
    static let recapLeapDay = DeveloperScenario(
      "recap-leap-day", "Recap · 29 February start",
      "The dates timeline of a couple that started on 29 February, with a recap on each anniversary", .memories
    ) { DeveloperPairedScenarioHost(scenario: $0) }
  }

  enum DeveloperRecapFixture {
    static func day(_ days: Int, yearsAgo years: Int = 0) -> String {
      let calendar = Calendar(identifier: .gregorian)
      let shifted = calendar.date(byAdding: DateComponents(year: -years, day: days), to: Date()) ?? Date()
      return RecapCalendar.today(shifted)
    }

    static func startedOn(for scenario: DeveloperScenario) -> String? {
      switch scenario {
      case .homeRecap: day(0, yearsAgo: 1)
      case .homeRecapLater: day(-3, yearsAgo: 1)
      case .recapLeapDay: "2024-02-29"
      default: nil
      }
    }

    @MainActor
    static func model(for scenario: DeveloperScenario) -> RecapViewModel {
      let recaps: [AnniversaryRecap] = switch scenario {
      case .homeRecap: [recap(anniversary: day(0), years: 1, start: day(0, yearsAgo: 1))]
      case .homeRecapLater: [recap(anniversary: day(-3), years: 1, start: day(-3, yearsAgo: 1))]
      case .recapLeapDay: [
        recap(anniversary: "2026-02-28", years: 2, start: "2025-02-28"),
        recap(anniversary: "2025-02-28", years: 1, start: "2024-04-02", sinceJoined: true),
      ]
      default: []
      }
      return model(recaps: recaps)
    }

    @MainActor
    static func model(recaps: [AnniversaryRecap]) -> RecapViewModel {
      let model = RecapViewModel(
        service: DeveloperRecapService(recaps: recaps, moments: moments),
        cache: DeveloperRecapCache()
      )
      // Alex calls Robin "Robbie". Only this phone shows the nickname; the share picture says Robin.
      model.people = RecapPeople(
        currentUserID: DeveloperScenarioFixture.currentUserID, currentName: "Alex", partnerName: "Robbie",
        partnerSharedName: "Robin"
      )
      return model
    }

    /// The first anniversary of `local-flow-paired`, whose couple started on 14 September 2025.
    static let localFlow = recap(anniversary: "2026-09-14", years: 1, start: "2025-09-14")

    static let fullYear = recap(anniversary: day(-2), years: 3, start: day(-2, yearsAgo: 1))
    static let firstMonths = AnniversaryRecap(
      anniversaryDate: day(-1), years: 4, periodStart: day(-93), periodEnd: day(-1), sinceJoined: true,
      countedOn: day(0),
      counts: .init(
        answeredTogether: 61, drawings: 12, memories: 3, memoryPhotos: 9, stories: 7, letters: 1, visits: 1,
        visitDays: 4, gameDays: 15, heartsAllTime: 240, longestStreakAllTime: 33
      )
    )

    static func recap(anniversary: String, years: Int, start: String, sinceJoined: Bool = false) -> AnniversaryRecap {
      AnniversaryRecap(
        anniversaryDate: anniversary, years: years, periodStart: start, periodEnd: anniversary,
        sinceJoined: sinceJoined, countedOn: anniversary,
        counts: .init(
          answeredTogether: 287, drawings: 54, memories: 18, memoryPhotos: 112, stories: 41, letters: 9,
          visits: 5, visitDays: 31, gameDays: 64, heartsAllTime: 1_204, longestStreakAllTime: 96
        )
      )
    }

    static let moments: [LookBackItem] = [
      LookBackItem(
        kind: .memory, contentDate: day(-120), onThisDay: false, question: nil, drawing: nil,
        memory: .init(memoryID: UUID(), title: "Cabin weekend", photoMediaAssetID: nil)
      ),
      LookBackItem(
        kind: .question, contentDate: day(-200), onThisDay: false,
        question: .init(
          instanceID: UUID(),
          shortPromptEN: "A small moment today",
          shortPromptNB: "Et lite øyeblikk i dag",
          ownAnswer: .init(
            userID: DeveloperScenarioFixture.currentUserID, text: "The walk home in the rain", selectedUserID: nil,
            hasPhoto: false, hasVoice: false
          ),
          partnerAnswer: .init(
            userID: DeveloperScenarioFixture.partnerUserID, text: "Your voice message this morning",
            selectedUserID: nil, hasPhoto: false, hasVoice: false
          )
        ),
        drawing: nil, memory: nil
      ),
    ]
  }

  private struct DeveloperRecapScenarioView: View {
    let recap: AnniversaryRecap
    @State private var model: RecapViewModel

    init(recap: AnniversaryRecap) {
      self.recap = recap
      _model = State(initialValue: DeveloperRecapFixture.model(recaps: [recap]))
    }

    var body: some View {
      RecapView(model: model, recap: recap)
        .preferredColorScheme(.dark)
    }
  }

  private struct DeveloperRecapService: RecapServing {
    let recaps: [AnniversaryRecap]
    let moments: [LookBackItem]

    // swiftlint:disable async_without_await
    func fetchRecaps() async throws -> [AnniversaryRecap] { recaps }
    func ensureRecap() async throws -> AnniversaryRecap? { nil }
    func fetchMoments(anniversaryDate _: String) async throws -> [LookBackItem] { moments }
    // swiftlint:enable async_without_await
  }

  private final class DeveloperRecapCache: RecapCaching, @unchecked Sendable {
    func load(ownerUserID _: UUID, coupleID _: UUID?) -> RecapCacheEntry? { nil }
    func purgeCount() -> Int { 0 }
    func save(_: RecapCacheEntry, ownerUserID _: UUID, unlessPurgedSince _: Int) -> Bool { true }
    func clearAll() {}
  }
#endif
