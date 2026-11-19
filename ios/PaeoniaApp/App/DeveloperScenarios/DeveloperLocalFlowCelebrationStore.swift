#if DEBUG
  import Foundation

  @MainActor
  final class DeveloperLocalFlowCelebrationStore: PairingCelebrationStoring {
    private var seenCoupleIDs = Set<UUID>()

    /// With `firstSteps`, the couple starts in the tabs, past the celebration and the first
    /// day, with that saved "Things to try together" card. The local flow has no games or
    /// topics to read, so the card shows only when `firstSteps` has those rows ticked.
    init(firstSteps: HomeFirstStepsProgress? = nil) {
      guard let firstSteps else { return }
      seenCoupleIDs.insert(DeveloperScenarioFixture.coupleID)
      progressByCoupleID[DeveloperScenarioFixture.coupleID] = PostPairingProgress(isFinished: true)
      firstStepsByCoupleID[DeveloperScenarioFixture.coupleID] = firstSteps
    }

    func hasSeenCelebration(forCoupleID coupleID: UUID) -> Bool { seenCoupleIDs.contains(coupleID) }
    func markCelebrationSeen(forCoupleID coupleID: UUID) { seenCoupleIDs.insert(coupleID) }
    private var seenReunions = Set<ReunionCelebration>()
    func hasSeenReunionCelebration(_ reunion: ReunionCelebration) -> Bool { seenReunions.contains(reunion) }
    func markReunionCelebrationSeen(_ reunion: ReunionCelebration) { seenReunions.insert(reunion) }
    private var progressByCoupleID: [UUID: PostPairingProgress] = [:]
    func postPairingProgress(forCoupleID coupleID: UUID) -> PostPairingProgress? { progressByCoupleID[coupleID] }
    func savePostPairingProgress(_ progress: PostPairingProgress, forCoupleID coupleID: UUID) {
      progressByCoupleID[coupleID] = progress
    }
    private var firstStepsByCoupleID: [UUID: HomeFirstStepsProgress] = [:]
    func homeFirstSteps(forCoupleID coupleID: UUID) -> HomeFirstStepsProgress {
      firstStepsByCoupleID[coupleID] ?? HomeFirstStepsProgress()
    }
    func saveHomeFirstSteps(_ progress: HomeFirstStepsProgress, forCoupleID coupleID: UUID) {
      firstStepsByCoupleID[coupleID] = progress
    }
  }
#endif
