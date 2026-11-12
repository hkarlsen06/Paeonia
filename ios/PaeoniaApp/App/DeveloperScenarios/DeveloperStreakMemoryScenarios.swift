#if DEBUG
  import SwiftUI

  @MainActor
  struct DeveloperStreakScenarioView: View {
    let scenario: DeveloperScenario

    private let people = StreakPeople(currentName: "Alex", partnerName: "Robin")

    /// Both partners have done something today.
    private var healthyStreak: CoupleStreak {
      CoupleStreak(
        currentCount: 18,
        longestCount: 42,
        lastQualifiedDate: "2026-07-15",
        restoreAvailable: false,
        restorableCount: 0,
        restoreDeadline: nil,
        currentUserContributedToday: true,
        partnerContributedToday: true
      )
    }

    /// An 18-day streak that broke. `saveEndsIn` is how long its free save day still
    /// runs (negative once it is over), and the two restore days follow it.
    nonisolated static func brokenStreak(saveEndsIn: TimeInterval, userContributedToday: Bool = false) -> CoupleStreak {
      CoupleStreak(
        currentCount: 0,
        longestCount: 42,
        lastQualifiedDate: "2026-07-13",
        restoreAvailable: saveEndsIn <= 0,
        restorableCount: 18,
        restoreDeadline: Date().addingTimeInterval(saveEndsIn + 48 * 3_600),
        currentUserContributedToday: userContributedToday,
        saveDeadline: Date().addingTimeInterval(saveEndsIn)
      )
    }

    private var statusStreak: CoupleStreak {
      var streak = healthyStreak
      streak.endsAt = .now.addingTimeInterval(5 * 3_600)
      streak.freezeSavedStreak = scenario == .streakFrozen
      if scenario == .streakAtRisk {
        streak.partnerContributedToday = false
      }
      if scenario == .streakFrozen {
        streak.currentUserContributedToday = false
      }
      if scenario == .streakOneDay {
        // Far enough from the end that the pill shows no hourglass yet.
        streak.currentCount = 1
        streak.endsAt = .now.addingTimeInterval(14 * 3_600)
        streak.currentUserContributedToday = false
        streak.partnerContributedToday = false
      }
      if scenario == .visitStreakSheet {
        // Together from yesterday to tomorrow, so the streak needs both partners again the day after.
        let today = Calendar.current.startOfDay(for: .now)
        streak.endsAt = today.addingTimeInterval(3 * 86_400)
        streak.rest = today.addingTimeInterval(-86_400)..<today.addingTimeInterval(2 * 86_400)
      }
      return streak
    }

    private func restoreView(for streak: CoupleStreak) -> some View {
      StreakRestoreView(
        viewModel: StreakRestoreViewModel(
          streak: streak,
          userID: DeveloperScenarioFixture.currentUserID.uuidString,
          storeKitService: DeveloperScenarioStoreKitService()
        )
      )
    }

    var body: some View {
      switch scenario {
      case .streakSaveDay:
        StreakDetailView(streak: Self.brokenStreak(saveEndsIn: 6 * 3_600, userContributedToday: true), people: people)
      case .streakSaved:
        StreakMilestoneView(days: 19, isSave: true)
      case .streakBroken:
        // The second day after the missed one: the save day ended 18 hours ago.
        restoreView(for: Self.brokenStreak(saveEndsIn: -18 * 3_600))
      case .streakRestoreExpired:
        restoreView(for: Self.brokenStreak(saveEndsIn: -48 * 3_600 - 60))
      case .streakRestored:
        StreakDetailView(
          streak: healthyStreak,
          title: .streakRestoreSuccessTitle,
          message: .streakRestoreSuccessMessage,
          playsCelebration: true,
          ambientMotion: false
        )
      case .streakOneDay, .streakAtRisk, .streakFrozen, .visitStreakSheet:
        let streak = statusStreak
        Color.paeoniaBackgroundPrimary
          .overlay(alignment: .topTrailing) {
            DailyStreakToolbarLabel(state: StreakPillState(streak))
          }
          .sheet(isPresented: .constant(true)) {
            StreakDetailView(streak: streak, people: people)
              .presentationDetents([.large])
              .presentationBackground(.paeoniaSurfacePrimary)
          }
      default:
        StreakDetailView(streak: healthyStreak, people: people)
      }
    }
  }

  struct DeveloperMemoryEditorScenarioView: View {
    @State private var draft = MemoryDraft(
      title: "A Sunday worth keeping",
      date: DeveloperScenarioFixture.now,
      note: "Coffee, rain, and nowhere we needed to be."
    )

    var body: some View {
      MemoryEditorView(
        draft: $draft,
        allowsPhotos: false,
        onSave: { _, _, _, _, _, _ in .failed }
      )
      .environment(PaeoniaBannerCenter())
    }
  }

  @MainActor
  struct DeveloperMemoryDetailScenarioView: View {
    private let memoryID: UUID
    @State private var viewModel: MemoriesViewModel
    @State private var mediaImageProvider: DeveloperMemoryGalleryImageProvider

    /// `celebrates` opens the memory the way a save from the Us tab's visit photo card does.
    init(celebrates: Bool = false) {
      let records = DeveloperMemoryGalleryFixture.records()
      _mediaImageProvider = State(initialValue: DeveloperMemoryGalleryImageProvider(
        failsFirstFullImageLoad: UserDefaults.standard.bool(forKey: "paeonia-scenario-gallery-retry")
      ))
      let memoryID = UUID(uuidString: "aaaaaaa1-aaaa-aaaa-aaaa-aaaaaaaaaaaa") ?? UUID()
      self.memoryID = memoryID
      let viewModel = MemoriesViewModel(
        memoryService: DeveloperScenarioMemoryDataService(records: records),
        operationProvider: DeveloperScenarioOperationProvider(),
        mediaUploader: nil,
        mediaImageCache: nil
      )
      if celebrates { viewModel.celebrationRequestedMemoryID = memoryID }
      _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
      NavigationStack {
        MemoryDetailView(
          memoryID: memoryID,
          currentUserID: DeveloperScenarioFixture.currentUserID,
          viewModel: viewModel,
          mediaImageProvider: mediaImageProvider
        )
      }
      .task {
        await viewModel.configure(
          currentUserID: DeveloperScenarioFixture.currentUserID,
          coupleID: DeveloperScenarioFixture.coupleID
        )
      }
    }
  }

  nonisolated extension DeveloperScenario {
    static let memoryCelebration = DeveloperScenario(
      "memory-celebration", "Memory · saved from the Us tab",
      "The memory's screen right after a save from the visit photo card: a haptic and petals", .memories
    ) { _ in DeveloperMemoryDetailScenarioView(celebrates: true) }
  }
#endif
