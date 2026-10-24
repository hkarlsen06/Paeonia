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
      /// Like `unanswered`, but the partner answers today's question just as the user's
      /// answer lands, so the phone hears of both at once.
      case partnerAnswersMeanwhile
      /// Like `unanswered`, but the streak broke yesterday and today is its free save day.
      case streakSaveDay

      static func mode(for scenario: DeveloperScenario) -> Mode {
        scenario == .streakSaveHome ? .streakSaveDay : questionsMode(for: scenario)
      }

      private static func questionsMode(for scenario: DeveloperScenario) -> Mode {
        switch scenario {
        case .questionPartnerAnswersMeanwhile: .partnerAnswersMeanwhile
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
    private let pendingOperationStore: any PendingSyncOperationPersisting
    private var today: DailyChallengeLoadResult?

    init(mode: Mode, pendingOperationStore: any PendingSyncOperationPersisting) {
      self.mode = mode
      self.pendingOperationStore = pendingOperationStore
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
      case .unanswered, .partnerAnswersMeanwhile:
        return try await todayLandingQueuedAnswers(currentUserID: currentUserID)
      case .streakSaveDay:
        let loaded = try await todayLandingQueuedAnswers(currentUserID: currentUserID)
        return DailyChallengeLoadResult(snapshot: loaded.snapshot, streak: loadStreak())
      case .offline:
        return offlineResult(currentUserID: currentUserID)
      case .partial:
        let loaded = try await base.loadToday(currentUserID: currentUserID)
        return partialResult(loaded: loaded, currentUserID: currentUserID)
      case .revealed:
        return revealedResult(currentUserID: currentUserID)
      }
    }

    /// Stands in for the outbox and the server, which the scenarios don't run. Today's
    /// questions keep their ids across loads, and an answer queued since the last load
    /// lands on its question and unlocks the partner's answer.
    private func todayLandingQueuedAnswers(currentUserID: UUID) async throws -> DailyChallengeLoadResult {
      let loaded: DailyChallengeLoadResult
      if let today {
        loaded = today
      } else {
        loaded = try await base.loadToday(currentUserID: currentUserID)
      }
      var questions = loaded.snapshot.questions
      let operations = try await pendingOperationStore.inFlightOperations(
        ownerUserID: currentUserID,
        kind: .submitDailyAnswer
      )
      for operation in operations {
        guard
          let data = operation.requestData,
          let payload = try? JSONDecoder().decode(DailySubmitAnswerOperationPayload.self, from: data),
          let index = questions.firstIndex(where: { $0.id == payload.instanceID }),
          let ownDetail = payload.ownAnswerDetail(currentUserID: currentUserID)
        else { continue }
        let partnerAnswer = mode == .partnerAnswersMeanwhile && questions[index].partnerAnswer == nil
          ? DailyQuestionAnswerSummary(id: UUID(), answeredAt: Date())
          : questions[index].partnerAnswer
        questions[index] = questions[index].answered(with: ownDetail, partnerAnswer: partnerAnswer)
        try await pendingOperationStore.markSucceeded(clientOperationID: operation.operation.id, at: Date())
      }
      let result = DailyChallengeLoadResult(
        snapshot: DailyChallengeSnapshot(
          currentUserID: currentUserID,
          coupleDayID: loaded.snapshot.coupleDayID,
          questions: questions,
          refreshedAt: loaded.snapshot.refreshedAt
        ),
        streak: loaded.streak
      )
      today = result
      return result
    }

    private func offlineResult(currentUserID: UUID) -> DailyChallengeLoadResult {
      DailyChallengeLoadResult(
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
    }

    private func partialResult(
      loaded: DailyChallengeLoadResult, currentUserID: UUID
    ) -> DailyChallengeLoadResult {
      let answered = previewHistoryQuestion(
        localDate: "2026-07-15",
        prompt: "What made you smile today?",
        ownText: "Your good-morning photo.",
        partnerText: "The voice note you sent on the bus.",
        currentUserID: currentUserID
      )
      return replacingQuestions(in: loaded, with: [answered] + loaded.snapshot.questions)
    }

    private func revealedResult(currentUserID: UUID) -> DailyChallengeLoadResult {
      let questions = [
        previewHistoryQuestion(
          localDate: "2026-07-15",
          prompt: "What small moment made you think of your partner today?",
          ownText: "I walked past the bakery we like.",
          partnerText: "Our song played while I was making dinner.",
          currentUserID: currentUserID
        ),
        previewHistoryQuestion(
          localDate: "2026-07-14",
          prompt: "What are the two of you looking forward to?",
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

    func startToday(currentUserID: UUID, operation _: SyncClientOperation) async throws
      -> DailyChallengeLoadResult
    {
      try await loadToday(currentUserID: currentUserID)
    }

    func loadHistory(currentUserID: UUID) async throws -> [DailyChallengeQuestion] {
      try await base.loadHistory(currentUserID: currentUserID)
    }

    func loadStreak() -> CoupleStreak {
      mode == .streakSaveDay ? DeveloperStreakScenarioView.brokenStreak(saveEndsIn: 6 * 3_600) : healthyStreak
    }

    func submitAnswer(
      instanceID _: UUID, answerID _: UUID, payload _: DailyAnswerPayload,
      operation _: SyncClientOperation
    ) throws -> UUID { UUID() }
    func editTextAnswer(instanceID _: UUID, text _: String, operation _: SyncClientOperation)
      throws -> UUID
    { UUID() }
    func editPartnerChoice(
      instanceID _: UUID, selectedUserID _: UUID, operation _: SyncClientOperation
    ) throws -> UUID { UUID() }
    func shuffleQuestion(currentUserID: UUID, operation _: SyncClientOperation)
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
        status: .active,
        questionID: UUID(),
        questionVersionID: UUID(),
        questionKey: "developer_offline_question",
        prompt: "What made you feel close to your partner today?",
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

  private nonisolated extension DailySubmitAnswerOperationPayload {
    func ownAnswerDetail(currentUserID: UUID) -> DailyQuestionAnswerDetail? {
      var text: String?
      var selectedUserID: UUID?
      var option: DailyAnswerOption?
      switch content {
      case let .text(body):
        text = body
      case let .partnerChoice(userID):
        selectedUserID = userID
      case let .textAndPartnerChoice(body, userID):
        text = body
        selectedUserID = userID
      case let .optionChoice(choice):
        option = choice
      case let .textAndOptionChoice(body, choice):
        text = body
        option = choice
      case .media, .textAndMedia:
        // Nothing is uploaded here, so a photo or voice answer stays sending and keeps
        // showing the copy saved on this phone.
        return nil
      }
      return DailyQuestionAnswerDetail(
        answerUserID: currentUserID,
        answerID: answerID,
        answeredAt: Date(),
        isOwnAnswer: true,
        canViewAnswer: true,
        textBody: text,
        selectedUserID: selectedUserID,
        mediaAssetIDs: [],
        selectedOption: option
      )
    }
  }

  private nonisolated extension DailyChallengeQuestion {
    func answered(
      with ownDetail: DailyQuestionAnswerDetail,
      partnerAnswer: DailyQuestionAnswerSummary?
    ) -> DailyChallengeQuestion {
      let partnerDetail = partnerAnswer.map { summary in
        DailyQuestionAnswerDetail(
          answerUserID: DeveloperScenarioFixture.partnerUserID,
          answerID: summary.id,
          answeredAt: summary.answeredAt,
          isOwnAnswer: false,
          canViewAnswer: true,
          textBody: "The lake walk when it started pouring and we just kept going.",
          selectedUserID: nil,
          mediaAssetIDs: []
        )
      }
      return DailyChallengeQuestion(
        id: id,
        coupleDayID: coupleDayID,
        coupleID: coupleID,
        localDate: localDate,
        effectiveLocalDate: effectiveLocalDate,
        startsAt: startsAt,
        endsAt: endsAt,
        status: status,
        questionID: questionID,
        questionVersionID: questionVersionID,
        questionKey: questionKey,
        prompt: prompt,
        shortPrompt: shortPrompt,
        answerKinds: answerKinds,
        ownAnswer: DailyQuestionAnswerSummary(id: ownDetail.answerID, answeredAt: ownDetail.answeredAt),
        partnerAnswer: partnerAnswer,
        canViewPartnerAnswer: partnerDetail != nil,
        ownAnswerDetail: ownDetail,
        partnerAnswerDetail: partnerDetail,
        isCurrentDay: isCurrentDay,
        hasSharedRound: partnerDetail != nil
      )
    }
  }
#endif
