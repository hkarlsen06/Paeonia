#if DEBUG
  import SwiftUI

  /// The inviter's path before their partner joins: the start date step before
  /// sign-in, and the invite screen with the first question answered. `Pairing invite ·
  /// ready` shows it unanswered. The rest of the path runs in `Local flow · fresh
  /// install` and `Local flow · onboarding`.
  nonisolated extension DeveloperScenario {
    static let inviter: [DeveloperScenario] = [
      welcomeStartDate, pairingInviteFirstDayDone, pairingInviteFirstDrawing,
    ]

    static let welcomeStartDate = DeveloperScenario(
      "welcome-start-date", "Welcome · start date",
      "When did you get together, then the days count-up", .launchAndAuth
    ) { _ in DeveloperStartDateScenarioView() }
    static let pairingInviteFirstDayDone = DeveloperScenario(
      "pairing-invite-first-day-done", "Pairing invite · first question answered",
      "First answer saved", .pairing
    ) { _ in DeveloperInviterScenarioView() }
    static let pairingInviteFirstDrawing = DeveloperScenario(
      "pairing-invite-first-drawing", "Pairing invite · first drawing made",
      "The first drawing is saved, so the share text names a gift", .pairing
    ) { _ in DeveloperInviterScenarioView(answered: false, drawing: true) }
  }

  /// The start date step on its own. Continue plays the count-up, and the step stays.
  private struct DeveloperStartDateScenarioView: View {
    var body: some View {
      PaeoniaScreenFrame {
        WelcomeStartDateStep(onBack: {}, onSave: { _ in }, onSkip: {}, onFinish: {})
      }
    }
  }

  /// The invite screen with a local invite and a local first day draft.
  private struct DeveloperInviterScenarioView: View {
    var answered = true
    var drawing = false

    var body: some View {
      PaeoniaScreenFrame {
        PairingInviteView(
          session: DeveloperScenarioFixture.completeSession,
          viewModel: PairingInviteViewModel(
            userID: DeveloperScenarioFixture.currentUserID.uuidString,
            pairingService: DeveloperScenarioPairingService(mode: .ready),
            operationProvider: DeveloperScenarioOperationProvider(),
            inviteStore: DeveloperScenarioInviteStore(invite: nil),
            now: { DeveloperScenarioFixture.now }
          ),
          firstDayModel: DeveloperInviterFixture.firstDayModel(answered: answered, drawing: drawing),
          showsManageSubscription: true,
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
    /// widget, so a drawing made before sign-in in a local flow is sent locally too.
    @MainActor
    static func firstDayModel(
      answered: Bool,
      drawing: Bool = false,
      canvas: DeveloperWidgetCanvasService = DeveloperWidgetCanvasService(),
      pendingUploads: WidgetPendingUploadStore? = nil
    ) -> InviterFirstDayModel {
      let pendingUploads = pendingUploads ?? {
        let store = WidgetPendingUploadStore(defaults: defaults)
        store.clearAll()
        return store
      }()
      let gateway = DeveloperFirstDayGateway(answered: answered, drawing: drawing)
      return InviterFirstDayModel(
        ownerUserID: DeveloperScenarioFixture.currentUserID,
        authorName: "Alex",
        gateway: gateway,
        uploader: FirstDayDrawingUploadService(
          gateway: gateway,
          pendingStore: pendingUploads,
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

    init(answered: Bool, drawing: Bool = false) {
      draft = FirstDayDraft(
        startedOn: nil,
        question: FirstDayQuestion(
          questionVersionID: UUID(uuidString: "F1F1F1F1-0000-0000-0000-000000000001") ?? UUID(),
          promptEN: "What is one small thing your partner did recently that stayed with you?",
          promptNB: "Hva er en liten ting partneren din gjorde nylig som har blitt værende hos deg?",
          answerText: answered ? "The voice note they sent from the train." : nil
        ),
        drawing: drawing ? FirstDayDrawingReference(mediaAssetID: UUID(), revisionID: UUID()) : nil
      )
    }

    func startDraft() -> FirstDayDraft {
      draft
    }

    func setStartedOn(_: String?, operation _: SyncClientOperation) {}

    func saveAnswer(questionVersionID: UUID, text: String, operation _: SyncClientOperation) async throws {
      try await Task.sleep(for: .milliseconds(500))
      if draft.question?.id == questionVersionID {
        draft.question?.answerText = text
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

    func saveDrawing(_: WidgetDrawingUploadPayload, mediaAssetID: UUID, operation _: SyncClientOperation) {
      draft = FirstDayDraft(
        startedOn: draft.startedOn,
        question: draft.question,
        drawing: FirstDayDrawingReference(mediaAssetID: mediaAssetID, revisionID: UUID())
      )
    }

    func signedDrawingURL(mediaAssetID _: UUID) -> URL? {
      nil
    }
  }
#endif
