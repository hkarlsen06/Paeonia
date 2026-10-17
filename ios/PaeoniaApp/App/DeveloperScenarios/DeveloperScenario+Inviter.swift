#if DEBUG
  import PencilKit
  import SwiftUI

  /// The inviter's path before their partner joins: the start date page of profile
  /// setup, and the invite screen's "while you wait" items with nothing, half, or
  /// everything made. The rest of the path runs in `Local flow · onboarding`.
  nonisolated extension DeveloperScenario {
    static let inviter: [DeveloperScenario] = [
      onboardingStartDate, pairingInviteFirstDayHalf, pairingInviteFirstDayDone,
    ]

    static let onboardingStartDate = DeveloperScenario(
      "onboarding-start-date", "Onboarding · start date",
      "When did you get together, then the days count-up", .launchAndAuth
    ) { _ in DeveloperStartDateScenarioView() }
    static let pairingInviteFirstDayHalf = DeveloperScenario(
      "pairing-invite-first-day-half", "Pairing invite · while you wait, half done",
      "One of two first answers saved, no drawing yet", .pairing
    ) { _ in DeveloperInviterScenarioView(answered: 1, hasDrawing: false) }
    static let pairingInviteFirstDayDone = DeveloperScenario(
      "pairing-invite-first-day-done", "Pairing invite · while you wait, all done",
      "Both first answers saved and a drawing on the widget", .pairing
    ) { _ in DeveloperInviterScenarioView(answered: 2, hasDrawing: true) }
  }

  /// The start date page on its own. Continue plays the count-up, and the page stays.
  private struct DeveloperStartDateScenarioView: View {
    var body: some View {
      RootBrandedFrame {
        AuthOnboardingStartDatePage(
          isSaving: false,
          onBack: {},
          onSaveDate: { _ in true },
          onFinish: {}
        )
      }
    }
  }

  /// The invite screen with a local invite and a local first day draft.
  private struct DeveloperInviterScenarioView: View {
    let answered: Int
    let hasDrawing: Bool

    var body: some View {
      RootBrandedFrame {
        PairingInviteView(
          session: DeveloperScenarioFixture.completeSession,
          viewModel: PairingInviteViewModel(
            userID: DeveloperScenarioFixture.currentUserID.uuidString,
            pairingService: DeveloperScenarioPairingService(mode: .ready),
            operationProvider: DeveloperScenarioOperationProvider(),
            inviteStore: DeveloperScenarioInviteStore(invite: nil),
            now: { DeveloperScenarioFixture.now }
          ),
          firstDayModel: DeveloperInviterFixture.firstDayModel(answered: answered, hasDrawing: hasDrawing),
          onSubmitJoinCode: { _ in true },
          onRefreshAccess: {}
        )
      }
    }
  }

  enum DeveloperInviterFixture {
    /// Keeps the scenarios' "not sent yet" state and widget names out of the app's own.
    static let defaults = UserDefaults(suiteName: "DeveloperInviterScenarios") ?? .standard

    /// A first day model that never leaves this phone. `canvas` stands in for the
    /// widget, so a drawing made in the scenario stays local too.
    @MainActor
    static func firstDayModel(
      answered: Int,
      hasDrawing: Bool,
      canvas: DeveloperWidgetCanvasService? = nil
    ) -> InviterFirstDayModel {
      let drawing = DeveloperGamesFixture.umbrella().dataRepresentation()
      WidgetPendingUploadStore(defaults: defaults).clearAll()
      let canvas = canvas ?? DeveloperWidgetCanvasService(
        snapshot: hasDrawing
          ? WidgetCanvasSnapshot(drawingData: drawing, authorName: "Alex", createdAt: DeveloperScenarioFixture.now)
          : nil
      )
      let gateway = DeveloperFirstDayGateway(answered: answered, hasDrawing: hasDrawing)
      return InviterFirstDayModel(
        ownerUserID: DeveloperScenarioFixture.currentUserID,
        authorName: "Alex",
        gateway: gateway,
        uploader: FirstDayDrawingUploadService(
          gateway: gateway,
          pendingStore: WidgetPendingUploadStore(defaults: defaults),
          localStore: canvas
        ),
        canvas: canvas,
        pushAuthorization: DeveloperScenarioPushAuthorization(denied: false),
        identityStore: WidgetSyncIdentityStore(defaults: defaults),
        questionPreferences: DeveloperNotificationPreferences()
      )
    }
  }

  /// A first day draft kept in memory. Saves take a moment, so the spinners show.
  actor DeveloperFirstDayGateway: FirstDayGateway {
    private var draft: FirstDayDraft

    init(answered: Int, hasDrawing: Bool = false) {
      let questions = [
        FirstDayQuestion(
          slotNumber: 1,
          questionVersionID: UUID(uuidString: "F1F1F1F1-0000-0000-0000-000000000001") ?? UUID(),
          promptEN: "What is one small thing your partner did recently that stayed with you?",
          promptNB: "Hva er en liten ting partneren din gjorde nylig som har blitt værende hos deg?",
          answerText: answered >= 1 ? "The voice note they sent from the train." : nil
        ),
        FirstDayQuestion(
          slotNumber: 2,
          questionVersionID: UUID(uuidString: "F1F1F1F1-0000-0000-0000-000000000002") ?? UUID(),
          promptEN: "What is one place you would like to show them?",
          promptNB: "Hvilket sted har du lyst til å vise dem?",
          answerText: answered >= 2 ? "The bakery by the harbour." : nil
        ),
      ]
      draft = FirstDayDraft(
        startedOn: nil,
        questions: questions,
        drawing: hasDrawing ? FirstDayDrawingReference(mediaAssetID: UUID(), revisionID: UUID()) : nil
      )
    }

    func startDraft() -> FirstDayDraft {
      draft
    }

    func setStartedOn(_: String?, operation _: SyncClientOperation) {}

    func saveAnswer(questionVersionID: UUID, text: String, operation _: SyncClientOperation) async throws {
      try await Task.sleep(for: .milliseconds(500))
      if let index = draft.questions.firstIndex(where: { $0.id == questionVersionID }) {
        draft.questions[index].answerText = text
      }
    }

    func reserveDrawingUpload(revisionID _: UUID, operation _: SyncClientOperation) -> MediaUploadReservation {
      MediaUploadReservation(
        mediaAssetID: UUID(),
        bucket: "widget-drawings",
        storagePath: "local",
        uploadURL: URL(fileURLWithPath: "/")
      )
    }

    func uploadDrawingPayload(reservation _: MediaUploadReservation, data _: Data) -> String {
      "local"
    }

    func finalizeDrawingUpload(_: WidgetDrawingFinalizeInput, operation _: SyncClientOperation) {}

    func saveDrawing(_: WidgetDrawingUploadPayload, mediaAssetID _: UUID, operation _: SyncClientOperation) {}

    func signedDrawingURL(mediaAssetID _: UUID) -> URL? {
      nil
    }
  }
#endif
