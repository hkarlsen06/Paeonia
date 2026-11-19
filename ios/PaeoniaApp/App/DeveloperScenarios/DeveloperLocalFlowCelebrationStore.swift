#if DEBUG
  import Foundation

  @MainActor
  final class DeveloperLocalFlowCelebrationStore: PairingCelebrationStoring {
    private var seenPairIDs = Set<UUID>()

    /// With `firstSteps`, the pair starts in the tabs, past the celebration and the first
    /// day, with that saved "Things to try together" card. The local flow has no games or
    /// topics to read, so the card shows only when `firstSteps` has those rows ticked.
    init(firstSteps: HomeFirstStepsProgress? = nil) {
      guard let firstSteps else { return }
      seenPairIDs.insert(DeveloperLocalFlowIDs.pairID)
      progressByPairID[DeveloperLocalFlowIDs.pairID] = PostPairingProgress(isFinished: true)
      firstStepsByPairID[DeveloperLocalFlowIDs.pairID] = firstSteps
    }

    func hasSeenCelebration(forPairID pairID: UUID) -> Bool { seenPairIDs.contains(pairID) }
    func markCelebrationSeen(forPairID pairID: UUID) { seenPairIDs.insert(pairID) }
    private var seenReunions = Set<ReunionCelebration>()
    func hasSeenReunionCelebration(_ reunion: ReunionCelebration) -> Bool { seenReunions.contains(reunion) }
    func markReunionCelebrationSeen(_ reunion: ReunionCelebration) { seenReunions.insert(reunion) }
    private var progressByPairID: [UUID: PostPairingProgress] = [:]
    func postPairingProgress(forPairID pairID: UUID) -> PostPairingProgress? { progressByPairID[pairID] }
    func savePostPairingProgress(_ progress: PostPairingProgress, forPairID pairID: UUID) {
      progressByPairID[pairID] = progress
    }
    private var firstStepsByPairID: [UUID: HomeFirstStepsProgress] = [:]
    func homeFirstSteps(forPairID pairID: UUID) -> HomeFirstStepsProgress {
      firstStepsByPairID[pairID] ?? HomeFirstStepsProgress()
    }
    func saveHomeFirstSteps(_ progress: HomeFirstStepsProgress, forPairID pairID: UUID) {
      firstStepsByPairID[pairID] = progress
    }
  }
#endif
