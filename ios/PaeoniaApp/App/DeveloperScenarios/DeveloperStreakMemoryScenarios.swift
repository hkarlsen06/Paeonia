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

    private var brokenStreak: CoupleStreak {
      CoupleStreak(
        currentCount: 0,
        longestCount: 42,
        lastQualifiedDate: "2026-07-13",
        restoreAvailable: true,
        restorableCount: 18,
        restoreDeadline: Date().addingTimeInterval(18 * 3_600)
      )
    }

    var body: some View {
      switch scenario {
      case .streakBroken:
        StreakRestoreView(
          viewModel: StreakRestoreViewModel(
            streak: brokenStreak,
            userID: DeveloperScenarioFixture.currentUserID.uuidString,
            storeKitService: DeveloperScenarioStoreKitService()
          )
        )
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
        onSave: { _, _, _, _, _ in false }
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
