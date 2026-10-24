#if DEBUG
  import SwiftUI

  @MainActor
  struct DeveloperStreakScenarioView: View {
    let scenario: DeveloperScenario

    private var healthyStreak: CoupleStreak {
      CoupleStreak(
        currentCount: 18,
        longestCount: 42,
        lastQualifiedDate: "2026-07-15",
        restoreAvailable: false,
        restorableCount: 0,
        restoreDeadline: nil
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
        StreakDetailView(streak: Self.brokenStreak(saveEndsIn: 6 * 3_600, userContributedToday: true))
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
      default:
        StreakDetailView(streak: healthyStreak)
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
        onSave: { _, _, _, _, _, _ in false }
      )
      .environment(PaeoniaBannerCenter())
    }
  }

  @MainActor
  struct DeveloperMemoryDetailScenarioView: View {
    private let memoryID: UUID
    @State private var viewModel: MemoriesViewModel

    init() {
      let records = DeveloperScenarioFixture.memoryRecords()
      memoryID = UUID(uuidString: "aaaaaaa1-aaaa-aaaa-aaaa-aaaaaaaaaaaa") ?? UUID()
      _viewModel = State(
        initialValue: MemoriesViewModel(
          memoryService: DeveloperScenarioMemoryDataService(records: records),
          operationProvider: DeveloperScenarioOperationProvider(),
          mediaUploader: nil,
          mediaImageCache: nil
        )
      )
    }

    var body: some View {
      NavigationStack {
        MemoryDetailView(
          memoryID: memoryID,
          currentUserID: DeveloperScenarioFixture.currentUserID,
          viewModel: viewModel
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
#endif
