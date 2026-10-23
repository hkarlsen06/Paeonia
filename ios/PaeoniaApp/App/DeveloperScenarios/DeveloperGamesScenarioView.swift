#if DEBUG
  import Foundation
  import PencilKit
  import SwiftUI

  /// A Draw & Guess phase on its own screen.
  @MainActor
  struct DeveloperGamesScenarioView: View {
    let scenario: DeveloperScenario
    @State private var viewModel: DrawAndGuessViewModel
    @State private var isReady = false

    init(scenario: DeveloperScenario) {
      self.scenario = scenario
      let viewModel = DrawAndGuessViewModel(
        dependencies: DeveloperGamesScenarioFactory.dependencies(for: scenario),
        participants: DeveloperGamesFixture.participants
      )
      // The scenario host lets the viewer see the replay play once.
      _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
      NavigationStack {
        if isReady {
          DrawAndGuessScreen(viewModel: viewModel)
        } else {
          Color.paeoniaBackgroundPrimary
        }
      }
      .task {
        await seed()
        isReady = true
      }
    }

    /// Puts the scenario's unsent move in the queue before the screen reads it.
    private func seed() async {
      guard scenario == .drawSavedOffline else { return }
      let drawing = DeveloperGamesFixture.umbrella()
      let payload = GameSubmitDrawingPayload(
        gameID: DeveloperGamesFixture.gameID,
        roundID: DeveloperGamesFixture.roundID,
        coupleID: DeveloperScenarioFixture.coupleID,
        drawingData: drawing.dataRepresentation(),
        reserveOperation: SyncClientOperation(clientID: UUID(), clientSequence: 1),
        finalizeOperation: SyncClientOperation(clientID: UUID(), clientSequence: 2)
      )
      guard let data = try? JSONEncoder().encode(payload) else { return }
      try? await viewModel.dependencies.pendingOperationStore.enqueue(
        PendingSyncOperationRequest(
          ownerUserID: DeveloperGamesFixture.me,
          operation: SyncClientOperation(clientID: UUID(), clientSequence: 3),
          operationKind: .submitGameDrawing,
          idempotencyScope: "game-drawing:developer",
          requestData: data
        )
      )
    }
  }
#endif
