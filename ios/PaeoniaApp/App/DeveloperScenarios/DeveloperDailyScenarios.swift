#if DEBUG
  import SwiftUI

  actor DeveloperDailyChallengeService: DailyChallengeServicing {
    enum Mode {
      case unanswered
      case partial
      case revealed
      case empty
      case loading
      case failing
      case offline

      static func mode(for scenario: DeveloperScenario) -> Mode {
        switch scenario {
        case .questionsPartial: .partial
        case .questionsRevealed: .revealed
        case .questionsEmpty: .empty
        case .questionsLoading: .loading
        case .questionsError: .failing
        case .questionsOfflineQueued: .offline
        default: .unanswered
        }
      }
    }

    private let mode: Mode
    private let base = PreviewDailyChallengeService()

    init(mode: Mode) {
      self.mode = mode
    }

    func loadToday(currentUserID: UUID) async throws -> DailyChallengeLoadResult {
      switch mode {
      case .loading:
        try await Task.sleep(for: .seconds(3_600))
        return try await base.loadToday(currentUserID: currentUserID)
      case .failing:
        throw URLError(.notConnectedToInternet)
      case .empty:
        return DailyChallengeLoadResult(
          snapshot: .empty(currentUserID: currentUserID),
          streak: .none
        )
      case .unanswered:
        return try await base.loadToday(currentUserID: currentUserID)
      case .offline:
        return DailyChallengeLoadResult(
          snapshot: DailyChallengeSnapshot(
            currentUserID: currentUserID,
            coupleDayID: DeveloperScenarioDailyFixture.coupleDayID,
            questions: [
              offlineQuestion()
            ],
            refreshedAt: DeveloperScenarioFixture.now
          ),
          streak: healthyStreak
        )
      case .partial:
        let loaded = try await base.loadToday(currentUserID: currentUserID)
        let answered = previewHistoryQuestion(
          localDate: "2026-07-15",
          slot: 1,
          seededFor: currentUserID,
          prompt: "What made you smile today?",
          ownText: "Your good-morning photo.",
          partnerText: "The voice note you sent on the bus.",
          currentUserID: currentUserID
        )
        return replacingQuestions(in: loaded, with: [answered] + loaded.snapshot.questions)
      case .revealed:
        let questions = [
          previewHistoryQuestion(
            localDate: "2026-07-15",
            slot: 1,
            seededFor: currentUserID,
            prompt: "What small moment made you think of us today?",
            ownText: "I walked past the bakery we like.",
            partnerText: "Our song played while I was making dinner.",
            currentUserID: currentUserID
          ),
          previewHistoryQuestion(
            localDate: "2026-07-15",
            slot: 2,
            seededFor: UUID(),
            prompt: "What are you looking forward to together?",
            ownText: "A slow Sunday morning.",
            partnerText: "The train ride to Bergen.",
            currentUserID: currentUserID
          ),
        ]
        return DailyChallengeLoadResult(
          snapshot: DailyChallengeSnapshot(
            currentUserID: currentUserID,
            coupleDayID: nil,
            questions: questions,
            refreshedAt: DeveloperScenarioFixture.now
          ),
          streak: healthyStreak
        )
      }
    }

    func startToday(currentUserID: UUID, operation _: SyncClientOperation) async throws
      -> DailyChallengeLoadResult
    {
      try await loadToday(currentUserID: currentUserID)
    }

    func loadHistory(currentUserID: UUID) async throws -> [DailyChallengeQuestion] {
      try await base.loadHistory(currentUserID: currentUserID)
    }

    func loadStreak() async throws -> CoupleStreak { healthyStreak }

    func submitAnswer(
      instanceID _: UUID, answerID _: UUID, payload _: DailyAnswerPayload,
      operation _: SyncClientOperation
    ) async throws -> UUID { UUID() }
    func editTextAnswer(instanceID _: UUID, text _: String, operation _: SyncClientOperation)
      async throws -> UUID
    { UUID() }
    func editPartnerChoice(
      instanceID _: UUID, selectedUserID _: UUID, operation _: SyncClientOperation
    ) async throws -> UUID { UUID() }
    func shuffleQuestion(currentUserID: UUID, slotNumber _: Int, operation _: SyncClientOperation)
      async throws -> DailyChallengeLoadResult
    {
      try await loadToday(currentUserID: currentUserID)
    }

    private var healthyStreak: CoupleStreak {
      CoupleStreak(
        currentCount: 6,
        longestCount: 12,
        lastQualifiedDate: "2026-07-15",
        restoreAvailable: false,
        restorableCount: 0,
        restoreDeadline: nil
      )
    }

    private func offlineQuestion() -> DailyChallengeQuestion {
      DailyChallengeQuestion(
        id: DeveloperScenarioDailyFixture.questionID,
        coupleDayID: DeveloperScenarioDailyFixture.coupleDayID,
        coupleID: DeveloperScenarioFixture.coupleID,
        localDate: "2026-07-16",
        effectiveLocalDate: "2026-07-16",
        startsAt: DeveloperScenarioFixture.now,
        endsAt: DeveloperScenarioFixture.now.addingTimeInterval(86_400),
        seededForUserID: DeveloperScenarioFixture.partnerUserID,
        slotNumber: 1,
        status: .active,
        questionID: UUID(),
        questionVersionID: UUID(),
        questionKey: "developer_offline_question",
        prompt: "What made you feel close to me today?",
        shortPrompt: "A close moment today",
        answerKinds: [.text],
        ownAnswer: nil,
        partnerAnswer: DailyQuestionAnswerSummary(
          id: UUID(),
          answeredAt: DeveloperScenarioFixture.now.addingTimeInterval(-600)
        ),
        canViewPartnerAnswer: false,
        ownAnswerDetail: nil,
        partnerAnswerDetail: nil,
        origin: .partner,
        isCurrentDay: true
      )
    }

    private func replacingQuestions(
      in result: DailyChallengeLoadResult,
      with questions: [DailyChallengeQuestion]
    ) -> DailyChallengeLoadResult {
      DailyChallengeLoadResult(
        snapshot: DailyChallengeSnapshot(
          currentUserID: result.snapshot.currentUserID,
          coupleDayID: result.snapshot.coupleDayID,
          questions: questions,
          refreshedAt: result.snapshot.refreshedAt
        ),
        streak: healthyStreak
      )
    }
  }

  @MainActor
  struct DeveloperQuestionsHistoryScenarioView: View {
    private let service: DeveloperDailyChallengeService
    @State private var dailyViewModel: DailyChallengeViewModel
    @State private var historyViewModel: DailyChallengeHistoryViewModel

    init() {
      let service = DeveloperDailyChallengeService(mode: .unanswered)
      let participants = DailyChallengeParticipants(
        currentUserID: DeveloperScenarioFixture.currentUserID,
        currentDisplayName: "Alex",
        partnerUserID: DeveloperScenarioFixture.partnerUserID,
        partnerDisplayName: "Robin"
      )
      self.service = service
      _dailyViewModel = State(initialValue: DailyChallengeViewModel(service: service))
      _historyViewModel = State(
        initialValue: DailyChallengeHistoryViewModel(
          service: service,
          currentUserID: DeveloperScenarioFixture.currentUserID,
          participants: participants
        )
      )
    }

    var body: some View {
      DailyChallengeHistoryView(
        viewModel: historyViewModel,
        dailyChallengeViewModel: dailyViewModel
      )
      .task {
        await dailyViewModel.configure(
          participants: DailyChallengeParticipants(
            currentUserID: DeveloperScenarioFixture.currentUserID,
            currentDisplayName: "Alex",
            partnerUserID: DeveloperScenarioFixture.partnerUserID,
            partnerDisplayName: "Robin"
          )
        )
      }
    }
  }
#endif
